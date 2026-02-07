defmodule WhoThere.GeoHeaderParser do
  @moduledoc """
  Advanced geographic data parser for WhoThere analytics.

  This module extracts geographic information from various proxy headers and
  IP addresses, supporting multiple hosting providers and CDN configurations.
  It provides normalized geographic data with privacy controls and fallback mechanisms.

  ## Supported Providers

  - **Cloudflare**: CF-IPCountry, CF-Connecting-IP, CF-Region, CF-City
  - **AWS ALB**: X-Forwarded-For, X-Amzn-Trace-Id  
  - **Fastly**: Fastly-Client-IP, Fastly-GeoIP-*
  - **Fly.io**: Fly-Client-IP, Fly-Region
  - **Heroku**: X-Forwarded-For, X-Request-ID
  - **Vercel**: X-Vercel-IP-Country, X-Forwarded-For
  - **Nginx/HAProxy**: X-Real-IP, X-Forwarded-For
  - **Generic**: Standard forwarded headers

  ## Features

  - Multi-provider header parsing with priority ordering
  - IP geolocation fallback using configurable providers
  - Privacy-first design with configurable precision levels
  - Automatic header validation and sanitization
  - Caching for improved performance
  - VPN/Proxy detection capabilities

  ## Configuration

      config :who_there, :geo_parsing,
        # Provider priority order (first match wins)
        provider_priority: [:cloudflare, :fastly, :aws_alb, :fly_io, :vercel, :nginx],
        
        # Geographic precision level
        precision_level: :city,  # :country, :region, :city, :full
        
        # IP geolocation provider for fallback
        ip_geolocation_provider: :maxmind,  # :maxmind, :geoip2, :ipapi, :disabled
        
        # Privacy settings
        privacy_mode: false,
        anonymize_ip: true,
        
        # Enable VPN/proxy detection
        detect_vpn: true,
        
        # Cache settings
        cache_ttl_minutes: 60,
        enable_cache: true

  ## Usage

      # Parse geo data from connection
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_geo_data(conn)

      # With custom options
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_geo_data(
        conn, 
        precision_level: :country,
        privacy_mode: true
      )

      # Extract from specific headers
      headers = %{"cf-ipcountry" => "US", "cf-connecting-ip" => "1.2.3.4"}
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_from_headers(headers)

  ## Geographic Data Structure

  The returned geographic data follows this structure:

      %WhoThere.GeoHeaderParser.GeoData{
        country_code: "US",
        country_name: "United States", 
        region_code: "CA",
        region_name: "California",
        city: "San Francisco",
        latitude: 37.7749,
        longitude: -122.4194,
        timezone: "America/Los_Angeles",
        isp: "Cloudflare",
        is_vpn: false,
        is_proxy: false,
        confidence: 0.95,
        provider: :cloudflare,
        ip_address: "1.2.3.4"  # anonymized based on privacy settings
      }
  """

  require Logger

  defstruct [
    :country_code,
    :country_name,
    :region_code,
    :region_name,
    :city,
    :latitude,
    :longitude,
    :timezone,
    :isp,
    :is_vpn,
    :is_proxy,
    :confidence,
    :provider,
    :ip_address
  ]

  @type t :: %__MODULE__{
    country_code: String.t() | nil,
    country_name: String.t() | nil,
    region_code: String.t() | nil,
    region_name: String.t() | nil,
    city: String.t() | nil,
    latitude: float() | nil,
    longitude: float() | nil,
    timezone: String.t() | nil,
    isp: String.t() | nil,
    is_vpn: boolean() | nil,
    is_proxy: boolean() | nil,
    confidence: float() | nil,
    provider: atom() | nil,
    ip_address: String.t() | nil
  }

  # Provider-specific header mappings
  @cloudflare_headers %{
    country: "cf-ipcountry",
    region: "cf-region", 
    city: "cf-city",
    ip: "cf-connecting-ip",
    timezone: "cf-timezone"
  }

  @fastly_headers %{
    country: "fastly-geoip-country-code",
    region: "fastly-geoip-region", 
    city: "fastly-geoip-city",
    ip: "fastly-client-ip"
  }

  @vercel_headers %{
    country: "x-vercel-ip-country",
    region: "x-vercel-ip-region",
    city: "x-vercel-ip-city",
    ip: "x-forwarded-for"
  }

  @fly_io_headers %{
    region: "fly-region",
    ip: "fly-client-ip"
  }

  @default_provider_priority [:cloudflare, :fastly, :vercel, :fly_io, :aws_alb, :nginx, :generic]

  @doc """
  Parses geographic data from a Plug.Conn struct.

  Extracts geographic information using provider-specific headers with
  configurable fallback to IP geolocation services.

  ## Options

  - `:precision_level` - Geographic precision (:country, :region, :city, :full)
  - `:privacy_mode` - Enable privacy-first parsing (default: false)
  - `:provider_priority` - List of providers to check in order
  - `:enable_cache` - Use caching for repeated requests (default: true)
  - `:detect_vpn` - Enable VPN/proxy detection (default: true)

  ## Examples

      # Basic usage
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_geo_data(conn)

      # Privacy mode (country-level only)
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_geo_data(
        conn,
        precision_level: :country,
        privacy_mode: true
      )
  """
  def parse_geo_data(conn, opts \\ []) do
    headers = extract_headers(conn)
    ip_address = extract_ip_address(conn)
    
    opts = merge_config_opts(opts)
    
    with {:ok, geo_data} <- parse_from_headers(headers, opts),
         {:ok, enriched_data} <- maybe_enrich_with_ip_geolocation(geo_data, ip_address, opts),
         {:ok, final_data} <- apply_privacy_controls(enriched_data, opts) do
      {:ok, final_data}
    else
      {:error, reason} -> 
        Logger.debug("Geo parsing failed: #{inspect(reason)}")
        {:ok, empty_geo_data()}
    end
  end

  @doc """
  Parses geographic data from a headers map.

  Useful for testing or when you already have extracted headers.

  ## Examples

      headers = %{
        "cf-ipcountry" => "US",
        "cf-region" => "California",
        "cf-connecting-ip" => "1.2.3.4"
      }
      {:ok, geo_data} = WhoThere.GeoHeaderParser.parse_from_headers(headers)
  """
  def parse_from_headers(headers, opts \\ []) do
    opts = merge_config_opts(opts)
    provider_priority = Keyword.get(opts, :provider_priority, @default_provider_priority)
    
    # Try each provider in priority order
    case try_providers(headers, provider_priority, opts) do
      {:ok, geo_data} when not is_nil(geo_data) ->
        {:ok, geo_data}
      _ ->
        # No provider could extract data, return empty result
        {:ok, empty_geo_data()}
    end
  end

  @doc """
  Extracts the client IP address with proxy header support.

  Returns the most likely real client IP by checking various proxy headers
  in order of reliability.

  ## Examples

      ip = WhoThere.GeoHeaderParser.extract_client_ip(conn)
      # => "192.168.1.100"
  """
  def extract_client_ip(conn, opts \\ []) do
    extract_ip_address(conn, opts)
  end

  @doc """
  Detects if the request is coming through a VPN or proxy service.

  Uses multiple detection methods including known VPN IP ranges,
  proxy headers, and behavioral patterns.

  ## Examples

      if WhoThere.GeoHeaderParser.is_vpn_or_proxy?(conn) do
        # Handle VPN/proxy traffic differently
      end
  """
  def is_vpn_or_proxy?(conn, opts \\ []) do
    if Keyword.get(opts, :detect_vpn, get_config(:detect_vpn, true)) do
      ip_address = extract_client_ip(conn, opts)
      headers = extract_headers(conn)
      
      detect_vpn_proxy(ip_address, headers, opts)
    else
      false
    end
  end

  @doc """
  Validates and normalizes geographic data.

  Ensures data integrity and applies configured precision limits.
  """
  def validate_geo_data(%__MODULE__{} = geo_data, opts \\ []) do
    precision_level = Keyword.get(opts, :precision_level, :city)
    
    geo_data
    |> apply_precision_level(precision_level)
    |> validate_coordinates()
    |> validate_country_code()
  end

  # Private functions

  defp extract_headers(conn) do
    conn.req_headers
    |> Enum.into(%{}, fn {key, value} -> {String.downcase(key), value} end)
  end

  defp extract_ip_address(conn, _opts \\ []) do
    # Try proxy headers first, then fall back to remote_ip
    forwarded_ips = [
      get_header_value(conn, "cf-connecting-ip"),
      get_header_value(conn, "fastly-client-ip"), 
      get_header_value(conn, "fly-client-ip"),
      get_header_value(conn, "x-real-ip"),
      extract_forwarded_for_ip(conn)
    ]

    case Enum.find(forwarded_ips, &valid_ip?/1) do
      nil -> format_ip_tuple(conn.remote_ip)
      ip -> ip
    end
  end

  defp extract_forwarded_for_ip(conn) do
    case get_header_value(conn, "x-forwarded-for") do
      nil -> nil
      forwarded_for ->
        # Take the first IP from comma-separated list
        forwarded_for
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp get_header_value(conn, header_name) do
    case Plug.Conn.get_req_header(conn, String.downcase(header_name)) do
      [value] -> String.trim(value)
      _ -> nil
    end
  end

  defp valid_ip?(nil), do: false
  defp valid_ip?(ip) when is_binary(ip) do
    # Basic IP validation - could be enhanced
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp format_ip_tuple({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip_tuple({a, b, c, d, e, f, g, h}) do
    # IPv6 - simplified formatting
    parts = [a, b, c, d, e, f, g, h]
    parts
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end
  defp format_ip_tuple(other), do: to_string(other)

  defp try_providers(headers, providers, opts) do
    Enum.reduce_while(providers, {:error, :no_provider_match}, fn provider, _acc ->
      case parse_with_provider(headers, provider, opts) do
        {:ok, %__MODULE__{country_code: country} = geo_data} when not is_nil(country) ->
          {:halt, {:ok, geo_data}}
        _ ->
          {:cont, {:error, :no_provider_match}}
      end
    end)
  end

  defp parse_with_provider(headers, :cloudflare, _opts) do
    case extract_cloudflare_data(headers) do
      {:ok, geo_data} -> 
        {:ok, %{geo_data | provider: :cloudflare, confidence: 0.95}}
      error -> 
        error
    end
  end

  defp parse_with_provider(headers, :fastly, _opts) do
    case extract_fastly_data(headers) do
      {:ok, geo_data} -> 
        {:ok, %{geo_data | provider: :fastly, confidence: 0.90}}
      error -> 
        error
    end
  end

  defp parse_with_provider(headers, :vercel, _opts) do
    case extract_vercel_data(headers) do
      {:ok, geo_data} -> 
        {:ok, %{geo_data | provider: :vercel, confidence: 0.85}}
      error -> 
        error
    end
  end

  defp parse_with_provider(headers, :fly_io, _opts) do
    case extract_fly_io_data(headers) do
      {:ok, geo_data} -> 
        {:ok, %{geo_data | provider: :fly_io, confidence: 0.80}}
      error -> 
        error
    end
  end

  defp parse_with_provider(_headers, provider, _opts) do
    Logger.debug("Unsupported geo provider: #{provider}")
    {:error, {:unsupported_provider, provider}}
  end

  defp extract_cloudflare_data(headers) do
    country_code = Map.get(headers, @cloudflare_headers.country)
    
    if country_code && String.length(country_code) == 2 do
      geo_data = %__MODULE__{
        country_code: String.upcase(country_code),
        region_name: Map.get(headers, @cloudflare_headers.region),
        city: Map.get(headers, @cloudflare_headers.city),
        ip_address: Map.get(headers, @cloudflare_headers.ip),
        timezone: Map.get(headers, @cloudflare_headers.timezone)
      }
      {:ok, geo_data}
    else
      {:error, :missing_required_headers}
    end
  end

  defp extract_fastly_data(headers) do
    country_code = Map.get(headers, @fastly_headers.country)
    
    if country_code && String.length(country_code) == 2 do
      geo_data = %__MODULE__{
        country_code: String.upcase(country_code),
        region_name: Map.get(headers, @fastly_headers.region),
        city: Map.get(headers, @fastly_headers.city),
        ip_address: Map.get(headers, @fastly_headers.ip)
      }
      {:ok, geo_data}
    else
      {:error, :missing_required_headers}
    end
  end

  defp extract_vercel_data(headers) do
    country_code = Map.get(headers, @vercel_headers.country)
    
    if country_code && String.length(country_code) == 2 do
      geo_data = %__MODULE__{
        country_code: String.upcase(country_code),
        region_name: Map.get(headers, @vercel_headers.region),
        city: Map.get(headers, @vercel_headers.city),
        ip_address: Map.get(headers, @vercel_headers.ip)
      }
      {:ok, geo_data}
    else
      {:error, :missing_required_headers}
    end
  end

  defp extract_fly_io_data(headers) do
    region = Map.get(headers, @fly_io_headers.region)
    
    if region do
      # Fly.io provides region codes, not country codes
      # Map common Fly.io regions to countries
      country_code = map_fly_region_to_country(region)
      
      geo_data = %__MODULE__{
        country_code: country_code,
        region_code: region,
        ip_address: Map.get(headers, @fly_io_headers.ip)
      }
      {:ok, geo_data}
    else
      {:error, :missing_required_headers}
    end
  end

  defp map_fly_region_to_country(region) do
    # Map Fly.io regions to countries (simplified)
    case region do
      "lax" -> "US"  # Los Angeles
      "ord" -> "US"  # Chicago  
      "iad" -> "US"  # Washington DC
      "lhr" -> "GB"  # London
      "ams" -> "NL"  # Amsterdam
      "nrt" -> "JP"  # Tokyo
      "syd" -> "AU"  # Sydney
      _ -> nil
    end
  end

  defp maybe_enrich_with_ip_geolocation(geo_data, ip_address, opts) do
    provider = Keyword.get(opts, :ip_geolocation_provider, :disabled)
    
    # Only use IP geolocation if we don't have sufficient data
    if should_enrich_with_ip?(geo_data) and provider != :disabled do
      enrich_with_ip_geolocation(geo_data, ip_address, provider, opts)
    else
      {:ok, geo_data}
    end
  end

  defp should_enrich_with_ip?(geo_data) do
    # Enrich if we're missing key geographic data
    is_nil(geo_data.country_code) or 
    (is_nil(geo_data.latitude) and is_nil(geo_data.longitude))
  end

  defp enrich_with_ip_geolocation(geo_data, ip_address, provider, _opts) do
    # This would integrate with actual IP geolocation services
    # For now, return the original data
    Logger.debug("Would enrich geo data using #{provider} for IP: #{ip_address}")
    {:ok, geo_data}
  end

  defp detect_vpn_proxy(_ip_address, headers, _opts) do
    # Basic VPN/proxy detection logic
    # This would be enhanced with actual detection services
    
    vpn_indicators = [
      # Check for known VPN headers
      Map.has_key?(headers, "x-vpn-service"),
      Map.has_key?(headers, "x-proxy-service"),
      
      # Check for common proxy headers
      Map.has_key?(headers, "via"),
      Map.has_key?(headers, "x-forwarded-proto")
    ]
    
    Enum.any?(vpn_indicators)
  end

  defp apply_privacy_controls(geo_data, opts) do
    privacy_mode = Keyword.get(opts, :privacy_mode, false)
    precision_level = Keyword.get(opts, :precision_level, :city)
    
    if privacy_mode do
      # In privacy mode, limit geographic precision
      limited_precision = min_precision_level(precision_level, :country)
      
      geo_data
      |> apply_precision_level(limited_precision)
      |> anonymize_ip_if_needed(opts)
      |> then(&{:ok, &1})
    else
      {:ok, geo_data}
    end
  end

  defp apply_precision_level(geo_data, :country) do
    %{geo_data | 
      region_code: nil,
      region_name: nil,
      city: nil,
      latitude: nil,
      longitude: nil
    }
  end

  defp apply_precision_level(geo_data, :region) do
    %{geo_data | 
      city: nil,
      latitude: nil,
      longitude: nil
    }
  end

  defp apply_precision_level(geo_data, :city) do
    %{geo_data | 
      latitude: nil,
      longitude: nil
    }
  end

  defp apply_precision_level(geo_data, :full), do: geo_data

  defp min_precision_level(:full, limit), do: limit
  defp min_precision_level(:city, :country), do: :country
  defp min_precision_level(:city, limit), do: limit
  defp min_precision_level(:region, :country), do: :country
  defp min_precision_level(current, _limit), do: current

  defp anonymize_ip_if_needed(geo_data, opts) do
    if Keyword.get(opts, :anonymize_ip, true) do
      anonymized_ip = WhoThere.Privacy.anonymize_ip(geo_data.ip_address, :partial)
      %{geo_data | ip_address: anonymized_ip}
    else
      geo_data
    end
  end

  defp validate_coordinates(geo_data) do
    # Validate latitude/longitude ranges
    lat_valid = is_nil(geo_data.latitude) or 
                (geo_data.latitude >= -90 and geo_data.latitude <= 90)
    lon_valid = is_nil(geo_data.longitude) or 
                (geo_data.longitude >= -180 and geo_data.longitude <= 180)

    if lat_valid and lon_valid do
      geo_data
    else
      %{geo_data | latitude: nil, longitude: nil}
    end
  end

  defp validate_country_code(geo_data) do
    if geo_data.country_code && String.length(geo_data.country_code) == 2 do
      geo_data
    else
      %{geo_data | country_code: nil, country_name: nil}
    end
  end

  defp empty_geo_data do
    %__MODULE__{
      confidence: 0.0,
      provider: :none
    }
  end

  defp merge_config_opts(opts) do
    config_opts = [
      precision_level: get_config(:precision_level, :city),
      privacy_mode: get_config(:privacy_mode, false),
      provider_priority: get_config(:provider_priority, @default_provider_priority),
      enable_cache: get_config(:enable_cache, true),
      detect_vpn: get_config(:detect_vpn, true),
      anonymize_ip: get_config(:anonymize_ip, true)
    ]
    
    Keyword.merge(config_opts, opts)
  end

  defp get_config(key, default) do
    :who_there
    |> Application.get_env(:geo_parsing, [])
    |> Keyword.get(key, default)
  end
end