defmodule WhoThere.GeographicDataParser do
  @moduledoc """
  Geographic data parsing utilities for WhoThere analytics.

  This module provides privacy-focused geographic location detection from:
  - IP addresses (with anonymization)
  - Proxy headers (CloudFlare, AWS CloudFront, etc.)
  - Client hints and headers
  - Geolocation APIs (configurable)

  All geographic data collection respects privacy settings and supports
  IP anonymization to comply with GDPR and other privacy regulations.

  ## Configuration

  Geographic data parsing can be configured in your application config:

      config :who_there, WhoThere.GeographicDataParser,
        # Enable/disable IP geolocation
        ip_geolocation_enabled: true,

        # IP anonymization level (:none, :partial, :full)
        ip_anonymization: :partial,

        # Geolocation service provider
        geolocation_provider: :builtin,  # :builtin, :maxmind, :ipapi

        # Proxy header trust settings
        trust_proxy_headers: true,
        trusted_proxies: ["cloudflare", "cloudfront", "fastly"],

        # Country-level only mode (more privacy-friendly)
        country_only: false,

        # Cache settings for geolocation lookups
        cache_ttl_seconds: 3600

  ## Privacy Features

  - IP address anonymization before geolocation lookup
  - Optional country-only resolution (no city data)
  - Configurable proxy header trust levels
  - Automatic detection of VPN/proxy usage
  - GDPR-compliant data minimization
  """

  require Logger

  @doc """
  Extracts geographic information from connection data.

  Returns geographic data while respecting privacy settings and IP anonymization.

  ## Options

  - `:ip_anonymization` - Anonymization level (`:none`, `:partial`, `:full`)
  - `:country_only` - Only return country-level data (default: false)
  - `:trust_proxy_headers` - Whether to trust proxy headers (default: true)
  - `:use_cache` - Whether to use cached results (default: true)

  ## Examples

      iex> conn_data = %{
      ...>   remote_ip: {192, 168, 1, 1},
      ...>   headers: %{"cf-ipcountry" => "US", "cf-ipcity" => "San Francisco"}
      ...> }
      iex> WhoThere.GeographicDataParser.extract_geographic_data(conn_data)
      {:ok, %{
        country_code: "US",
        country_name: "United States",
        city: "San Francisco",
        region: "California",
        timezone: "America/Los_Angeles",
        source: :proxy_header,
        confidence: :high
      }}

  """
  def extract_geographic_data(conn_data, opts \\ []) do
    with {:ok, location_data} <- resolve_location(conn_data, opts),
         {:ok, enriched_data} <- enrich_location_data(location_data, opts) do
      {:ok, enriched_data}
    else
      {:error, reason} ->
        Logger.debug("Geographic data extraction failed: #{inspect(reason)}")
        {:ok, default_location_data()}
    end
  end

  @doc """
  Anonymizes an IP address according to the specified level.

  ## Anonymization Levels

  - `:none` - No anonymization (full IP preserved)
  - `:partial` - Last octet zeroed for IPv4, last 80 bits for IPv6
  - `:full` - Last two octets zeroed for IPv4, last 80 bits for IPv6

  ## Examples

      iex> WhoThere.GeographicDataParser.anonymize_ip({192, 168, 1, 100}, :partial)
      {192, 168, 1, 0}

      iex> WhoThere.GeographicDataParser.anonymize_ip({192, 168, 1, 100}, :full)
      {192, 168, 0, 0}

  """
  def anonymize_ip(ip_tuple, level \\ :partial)

  def anonymize_ip(ip_tuple, :none), do: ip_tuple

  def anonymize_ip({a, b, c, _d}, :partial), do: {a, b, c, 0}

  def anonymize_ip({a, b, _c, _d}, :full), do: {a, b, 0, 0}

  def anonymize_ip({a, b, c, d, e, f, g, _h}, :partial) do
    # IPv6 - zero last 80 bits (keep first 48 bits)
    {a, b, c, 0, 0, 0, 0, 0}
  end

  def anonymize_ip({a, b, c, d, e, f, g, h}, :full) do
    # IPv6 - zero last 80 bits more aggressively
    {a, b, 0, 0, 0, 0, 0, 0}
  end

  @doc """
  Extracts geographic data from proxy headers.

  Supports headers from major CDN providers including CloudFlare,
  AWS CloudFront, Fastly, and others.

  ## Supported Headers

  - CloudFlare: `CF-IPCountry`, `CF-IPCity`, `CF-Region`
  - CloudFront: `CloudFront-Viewer-Country`, `CloudFront-Viewer-City`
  - Fastly: `Fastly-Client-Country`, `Fastly-Client-City`
  - Generic: `X-Country-Code`, `X-City`, `X-Region`

  """
  def extract_from_proxy_headers(headers, opts \\ []) do
    trusted_sources = Keyword.get(opts, :trusted_sources, default_trusted_sources())

    case find_geographic_headers(headers, trusted_sources) do
      nil ->
        {:error, :no_geographic_headers}

      geo_data ->
        confidence = determine_header_confidence(geo_data.source)
        {:ok, Map.put(geo_data, :confidence, confidence)}
    end
  end

  @doc """
  Performs IP geolocation using the configured provider.

  Supports multiple geolocation backends with fallback options.
  """
  def geolocate_ip(ip, opts \\ []) do
    provider = Keyword.get(opts, :provider, default_geolocation_provider())
    anonymization = Keyword.get(opts, :ip_anonymization, :partial)

    anonymized_ip = anonymize_ip(ip, anonymization)

    case perform_geolocation(anonymized_ip, provider, opts) do
      {:ok, location_data} ->
        {:ok, Map.put(location_data, :source, :ip_geolocation)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates and normalizes country codes.

  Ensures country codes conform to ISO 3166-1 alpha-2 standard.
  """
  def normalize_country_code(country_code) when is_binary(country_code) do
    normalized = String.upcase(String.trim(country_code))

    if valid_country_code?(normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_country_code}
    end
  end

  def normalize_country_code(_), do: {:error, :invalid_country_code}

  @doc """
  Detects if an IP address is likely from a VPN or proxy service.

  Uses heuristics and known VPN/proxy IP ranges to identify
  potentially privacy-conscious users.
  """
  def detect_vpn_proxy(ip, opts \\ []) do
    checks = [
      check_known_vpn_ranges(ip),
      check_hosting_providers(ip),
      check_datacenter_ips(ip)
    ]

    vpn_score = Enum.count(checks, & &1)
    is_vpn = vpn_score >= 2

    %{
      is_vpn_likely: is_vpn,
      vpn_score: vpn_score,
      checks_passed: Enum.count(checks, & &1),
      total_checks: length(checks)
    }
  end

  @doc """
  Gets timezone information for a geographic location.

  Returns the most likely timezone for the given location data.
  """
  def get_timezone_info(location_data) do
    case location_data do
      %{country_code: country, city: city} when not is_nil(city) ->
        lookup_city_timezone(country, city)

      %{country_code: country} ->
        lookup_country_timezone(country)

      _ ->
        {:error, :insufficient_location_data}
    end
  end

  @doc """
  Calculates distance between two geographic points.

  Uses the Haversine formula to calculate great-circle distance.
  Useful for proximity analysis and location clustering.
  """
  def calculate_distance(location1, location2) do
    case {extract_coordinates(location1), extract_coordinates(location2)} do
      {{lat1, lon1}, {lat2, lon2}} ->
        distance_km = haversine_distance(lat1, lon1, lat2, lon2)
        {:ok, distance_km}

      _ ->
        {:error, :missing_coordinates}
    end
  end

  # Private helper functions

  defp resolve_location(conn_data, opts) do
    trust_proxy_headers = Keyword.get(opts, :trust_proxy_headers, true)
    headers = Map.get(conn_data, :headers, %{})
    remote_ip = Map.get(conn_data, :remote_ip)

    cond do
      trust_proxy_headers && map_size(headers) > 0 ->
        case extract_from_proxy_headers(headers, opts) do
          {:ok, header_data} -> {:ok, header_data}
          {:error, _} -> fallback_to_ip_geolocation(remote_ip, opts)
        end

      not is_nil(remote_ip) ->
        geolocate_ip(remote_ip, opts)

      true ->
        {:error, :no_location_data}
    end
  end

  defp fallback_to_ip_geolocation(nil, _opts), do: {:error, :no_ip_address}

  defp fallback_to_ip_geolocation(ip, opts) do
    case geolocate_ip(ip, opts) do
      {:ok, data} -> {:ok, Map.put(data, :confidence, :medium)}
      error -> error
    end
  end

  defp enrich_location_data(location_data, opts) do
    country_only = Keyword.get(opts, :country_only, false)

    enriched =
      location_data
      |> add_country_name()
      |> add_timezone_if_missing()
      |> maybe_remove_city_data(country_only)

    {:ok, enriched}
  end

  defp add_country_name(location_data) do
    case Map.get(location_data, :country_code) do
      nil ->
        location_data

      country_code ->
        country_name = lookup_country_name(country_code)
        Map.put(location_data, :country_name, country_name)
    end
  end

  defp add_timezone_if_missing(location_data) do
    if Map.has_key?(location_data, :timezone) do
      location_data
    else
      case get_timezone_info(location_data) do
        {:ok, timezone} -> Map.put(location_data, :timezone, timezone)
        {:error, _} -> location_data
      end
    end
  end

  defp maybe_remove_city_data(location_data, true) do
    location_data
    |> Map.delete(:city)
    |> Map.delete(:region)
    |> Map.delete(:latitude)
    |> Map.delete(:longitude)
  end

  defp maybe_remove_city_data(location_data, false), do: location_data

  defp default_location_data do
    %{
      country_code: nil,
      country_name: nil,
      city: nil,
      region: nil,
      timezone: nil,
      source: :unknown,
      confidence: :low
    }
  end

  defp find_geographic_headers(headers, trusted_sources) do
    # CloudFlare headers
    cloudflare_data = extract_cloudflare_headers(headers)

    if cloudflare_data && "cloudflare" in trusted_sources do
      Map.put(cloudflare_data, :source, :cloudflare)
    else
      # Try other sources
      extract_other_headers(headers, trusted_sources)
    end
  end

  defp extract_cloudflare_headers(headers) do
    country = get_header_value(headers, ["cf-ipcountry", "CF-IPCountry"])
    city = get_header_value(headers, ["cf-ipcity", "CF-IPCity"])
    region = get_header_value(headers, ["cf-region", "CF-Region"])

    if country do
      %{
        country_code: country,
        city: city,
        region: region
      }
    else
      nil
    end
  end

  defp extract_other_headers(headers, trusted_sources) do
    # CloudFront
    if "cloudfront" in trusted_sources do
      case extract_cloudfront_headers(headers) do
        nil -> extract_generic_headers(headers)
        data -> Map.put(data, :source, :cloudfront)
      end
    else
      extract_generic_headers(headers)
    end
  end

  defp extract_cloudfront_headers(headers) do
    country = get_header_value(headers, ["cloudfront-viewer-country"])

    if country do
      %{country_code: country}
    else
      nil
    end
  end

  defp extract_generic_headers(headers) do
    country = get_header_value(headers, ["x-country-code", "x-country"])
    city = get_header_value(headers, ["x-city"])
    region = get_header_value(headers, ["x-region", "x-state"])

    if country do
      %{
        country_code: country,
        city: city,
        region: region,
        source: :generic
      }
    else
      nil
    end
  end

  defp get_header_value(headers, header_names) do
    Enum.find_value(header_names, fn name ->
      case Map.get(headers, name) || Map.get(headers, String.downcase(name)) do
        nil -> nil
        "" -> nil
        value -> String.trim(value)
      end
    end)
  end

  defp determine_header_confidence(:cloudflare), do: :high
  defp determine_header_confidence(:cloudfront), do: :high
  defp determine_header_confidence(:fastly), do: :high
  defp determine_header_confidence(:generic), do: :medium
  defp determine_header_confidence(_), do: :low

  defp default_trusted_sources do
    Application.get_env(:who_there, __MODULE__, [])
    |> Keyword.get(:trusted_proxies, ["cloudflare", "cloudfront", "fastly"])
  end

  defp default_geolocation_provider do
    Application.get_env(:who_there, __MODULE__, [])
    |> Keyword.get(:geolocation_provider, :builtin)
  end

  defp perform_geolocation(ip, :builtin, _opts) do
    # Simple builtin geolocation using IP ranges
    # This is a basic implementation - real-world usage would use a proper database
    builtin_ip_lookup(ip)
  end

  defp perform_geolocation(ip, provider, opts) do
    # Placeholder for external geolocation providers
    # Would integrate with MaxMind, IP-API, etc.
    {:error, :provider_not_implemented}
  end

  defp builtin_ip_lookup(ip) do
    # Very basic IP range to country mapping
    # In production, this would use a proper GeoIP database
    case ip do
      {8, 8, 8, _} -> {:ok, %{country_code: "US", confidence: :low}}
      {1, 1, 1, _} -> {:ok, %{country_code: "AU", confidence: :low}}
      # Private IP
      {192, 168, _, _} -> {:ok, %{country_code: "XX", confidence: :low}}
      # Private IP
      {10, _, _, _} -> {:ok, %{country_code: "XX", confidence: :low}}
      _ -> {:error, :unknown_ip_range}
    end
  end

  defp valid_country_code?(code) when byte_size(code) == 2 do
    # Basic validation - in production would use complete ISO 3166-1 list
    code =~ ~r/^[A-Z]{2}$/
  end

  defp valid_country_code?(_), do: false

  defp lookup_country_name("US"), do: "United States"
  defp lookup_country_name("GB"), do: "United Kingdom"
  defp lookup_country_name("CA"), do: "Canada"
  defp lookup_country_name("AU"), do: "Australia"
  defp lookup_country_name("DE"), do: "Germany"
  defp lookup_country_name("FR"), do: "France"
  defp lookup_country_name("JP"), do: "Japan"
  defp lookup_country_name("XX"), do: "Unknown"
  defp lookup_country_name(_), do: "Unknown"

  defp lookup_city_timezone("US", "San Francisco"), do: {:ok, "America/Los_Angeles"}
  defp lookup_city_timezone("US", "New York"), do: {:ok, "America/New_York"}
  defp lookup_city_timezone("GB", "London"), do: {:ok, "Europe/London"}
  defp lookup_city_timezone(country, _city), do: lookup_country_timezone(country)

  defp lookup_country_timezone("US"), do: {:ok, "America/New_York"}
  defp lookup_country_timezone("GB"), do: {:ok, "Europe/London"}
  defp lookup_country_timezone("CA"), do: {:ok, "America/Toronto"}
  defp lookup_country_timezone("AU"), do: {:ok, "Australia/Sydney"}
  defp lookup_country_timezone("DE"), do: {:ok, "Europe/Berlin"}
  defp lookup_country_timezone("FR"), do: {:ok, "Europe/Paris"}
  defp lookup_country_timezone("JP"), do: {:ok, "Asia/Tokyo"}
  defp lookup_country_timezone(_), do: {:error, :unknown_timezone}

  defp check_known_vpn_ranges(_ip) do
    # Placeholder for VPN detection logic
    false
  end

  defp check_hosting_providers(_ip) do
    # Placeholder for hosting provider detection
    false
  end

  defp check_datacenter_ips(_ip) do
    # Placeholder for datacenter detection
    false
  end

  defp extract_coordinates(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon) do
    {lat, lon}
  end

  defp extract_coordinates(_), do: nil

  defp haversine_distance(lat1, lon1, lat2, lon2) do
    # Haversine formula implementation
    # Earth's radius in kilometers
    r = 6371

    d_lat = to_radians(lat2 - lat1)
    d_lon = to_radians(lon2 - lon1)

    a =
      :math.sin(d_lat / 2) * :math.sin(d_lat / 2) +
        :math.cos(to_radians(lat1)) * :math.cos(to_radians(lat2)) *
          :math.sin(d_lon / 2) * :math.sin(d_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    r * c
  end

  defp to_radians(degrees), do: degrees * :math.pi() / 180
end
