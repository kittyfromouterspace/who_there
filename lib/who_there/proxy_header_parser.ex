defmodule WhoThere.ProxyHeaderParser do
  @moduledoc """
  Multi-tier header detection for accurate geographic and IP data extraction.

  This module provides functions to parse various proxy headers from different
  providers like Cloudflare, AWS ALB, nginx, and other common proxy setups
  with proper priority fallbacks for accurate data extraction.
  """

  @doc """
  Extracts the real client IP address from proxy headers with priority fallbacks.

  Returns the most reliable IP address found, falling back through various
  headers in order of trustworthiness.

  ## Priority Order:
  1. CF-Connecting-IP (Cloudflare)
  2. True-Client-IP (Cloudflare Enterprise)
  3. X-Real-IP (nginx)
  4. X-Forwarded-For (first IP, if trusted)
  5. X-Client-IP
  6. Remote IP from connection

  ## Examples

      iex> headers = [{"cf-connecting-ip", "203.0.113.195"}]
      iex> WhoThere.ProxyHeaderParser.extract_real_ip(headers, {127, 0, 0, 1})
      "203.0.113.195"

  """
  def extract_real_ip(headers, remote_ip \\ nil) do
    headers_map = normalize_headers(headers)

    cond do
      cloudflare_ip = get_cloudflare_ip(headers_map) ->
        cloudflare_ip

      real_ip = get_real_ip(headers_map) ->
        real_ip

      forwarded_ip = get_forwarded_ip(headers_map) ->
        forwarded_ip

      client_ip = get_client_ip(headers_map) ->
        client_ip

      remote_ip ->
        format_ip(remote_ip)

      true ->
        nil
    end
  end

  @doc """
  Extracts geographic information from Cloudflare headers.

  Returns a map with country, city, continent, and other geographic data
  when available from Cloudflare headers.

  ## Examples

      iex> headers = [
      ...>   {"cf-ipcountry", "US"},
      ...>   {"cf-ipcity", "San Francisco"},
      ...>   {"cf-ipcontinent", "NA"}
      ...> ]
      iex> WhoThere.ProxyHeaderParser.extract_cloudflare_geo(headers)
      %{country: "US", city: "San Francisco", continent: "NA"}

  """
  def extract_cloudflare_geo(headers) do
    headers_map = normalize_headers(headers)

    %{}
    |> maybe_put(:country, Map.get(headers_map, "cf-ipcountry"))
    |> maybe_put(:city, Map.get(headers_map, "cf-ipcity"))
    |> maybe_put(:continent, Map.get(headers_map, "cf-ipcontinent"))
    |> maybe_put(:region, Map.get(headers_map, "cf-region"))
    |> maybe_put(:metro_code, Map.get(headers_map, "cf-metro-code"))
    |> maybe_put(:postal_code, Map.get(headers_map, "cf-postal-code"))
    |> maybe_put(:timezone, Map.get(headers_map, "cf-timezone"))
    |> maybe_put(:latitude, Map.get(headers_map, "cf-iplatitude"))
    |> maybe_put(:longitude, Map.get(headers_map, "cf-iplongitude"))
  end

  @doc """
  Extracts AWS ALB geographic information from headers.

  Returns geographic data when available from AWS Application Load Balancer headers.
  """
  def extract_aws_geo(headers) do
    headers_map = normalize_headers(headers)

    %{}
    |> maybe_put(:country, Map.get(headers_map, "cloudfront-viewer-country"))
    |> maybe_put(:country_name, Map.get(headers_map, "cloudfront-viewer-country-name"))
    |> maybe_put(:region, Map.get(headers_map, "cloudfront-viewer-country-region"))
    |> maybe_put(:city, Map.get(headers_map, "cloudfront-viewer-city"))
    |> maybe_put(:postal_code, Map.get(headers_map, "cloudfront-viewer-postal-code"))
    |> maybe_put(:timezone, Map.get(headers_map, "cloudfront-viewer-time-zone"))
    |> maybe_put(:latitude, Map.get(headers_map, "cloudfront-viewer-latitude"))
    |> maybe_put(:longitude, Map.get(headers_map, "cloudfront-viewer-longitude"))
  end

  @doc """
  Detects the proxy type based on available headers.

  Returns an atom indicating the proxy type: :cloudflare, :aws_alb, :nginx, :apache, etc.
  """
  def detect_proxy_type(headers) do
    headers_map = normalize_headers(headers)

    cond do
      Map.has_key?(headers_map, "cf-ray") or Map.has_key?(headers_map, "cf-connecting-ip") ->
        :cloudflare

      Map.has_key?(headers_map, "cloudfront-viewer-country") ->
        :aws_cloudfront

      Map.has_key?(headers_map, "x-forwarded-for") and
          Map.has_key?(headers_map, "x-forwarded-proto") ->
        :aws_alb

      Map.has_key?(headers_map, "x-real-ip") ->
        :nginx

      Map.has_key?(headers_map, "x-forwarded-for") ->
        :generic_proxy

      true ->
        :direct
    end
  end

  @doc """
  Extracts connection information like protocol and port.

  Returns connection metadata including HTTPS detection, port information, etc.
  """
  def extract_connection_info(headers) do
    headers_map = normalize_headers(headers)

    %{}
    |> maybe_put(:protocol, detect_protocol(headers_map))
    |> maybe_put(:port, detect_port(headers_map))
    |> maybe_put(:scheme, detect_scheme(headers_map))
    |> maybe_put(:host, Map.get(headers_map, "host"))
    |> maybe_put(:user_agent, Map.get(headers_map, "user-agent"))
  end

  @doc """
  Validates that proxy headers are trustworthy and not forged.

  Returns `:ok` if headers appear legitimate, `{:error, reason}` otherwise.
  """
  def validate_headers(headers, opts \\ []) do
    headers_map = normalize_headers(headers)
    trusted_proxies = Keyword.get(opts, :trusted_proxies, [])

    with :ok <- validate_cloudflare_headers(headers_map),
         :ok <- validate_forwarded_headers(headers_map, trusted_proxies),
         :ok <- validate_consistency(headers_map) do
      :ok
    end
  end

  @doc """
  Extracts all available information from proxy headers.

  Returns a comprehensive map with IP, geographic, and connection information.
  """
  def parse_all(headers, remote_ip \\ nil, opts \\ []) do
    %{
      real_ip: extract_real_ip(headers, remote_ip),
      geo: extract_all_geo(headers),
      connection: extract_connection_info(headers),
      proxy_type: detect_proxy_type(headers),
      headers_valid: validate_headers(headers, opts) == :ok
    }
  end

  # Private functions

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
    |> Enum.into(%{})
  end

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
    |> Enum.into(%{})
  end

  defp normalize_headers(_), do: %{}

  defp get_cloudflare_ip(headers) do
    cond do
      ip = Map.get(headers, "cf-connecting-ip") -> validate_and_return_ip(ip)
      ip = Map.get(headers, "true-client-ip") -> validate_and_return_ip(ip)
      true -> nil
    end
  end

  defp get_real_ip(headers) do
    case Map.get(headers, "x-real-ip") do
      nil -> nil
      ip -> validate_and_return_ip(ip)
    end
  end

  defp get_forwarded_ip(headers) do
    case Map.get(headers, "x-forwarded-for") do
      nil ->
        nil

      forwarded ->
        forwarded
        |> String.split(",", parts: 2)
        |> List.first()
        |> String.trim()
        |> validate_and_return_ip()
    end
  end

  defp get_client_ip(headers) do
    case Map.get(headers, "x-client-ip") do
      nil -> nil
      ip -> validate_and_return_ip(ip)
    end
  end

  defp validate_and_return_ip(ip_string) when is_binary(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, _parsed_ip} -> ip_string
      {:error, _} -> nil
    end
  end

  defp validate_and_return_ip(_), do: nil

  defp format_ip(ip) when is_tuple(ip) do
    :inet.ntoa(ip) |> to_string()
  end

  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp detect_protocol(headers) do
    cond do
      Map.get(headers, "x-forwarded-proto") == "https" -> "https"
      Map.get(headers, "x-forwarded-ssl") == "on" -> "https"
      cf_visitor = Map.get(headers, "cf-visitor") -> parse_cf_visitor_scheme(cf_visitor)
      true -> "http"
    end
  end

  defp detect_port(headers) do
    case Map.get(headers, "x-forwarded-port") do
      nil -> nil
      port -> String.to_integer(port)
    end
  rescue
    _ -> nil
  end

  defp detect_scheme(headers) do
    case detect_protocol(headers) do
      "https" -> "https"
      _ -> "http"
    end
  end

  defp parse_cf_visitor_scheme(cf_visitor) do
    case Jason.decode(cf_visitor) do
      {:ok, %{"scheme" => scheme}} -> scheme
      _ -> "http"
    end
  rescue
    _ -> "http"
  end

  defp extract_all_geo(headers) do
    cloudflare_geo = extract_cloudflare_geo(headers)
    aws_geo = extract_aws_geo(headers)

    Map.merge(aws_geo, cloudflare_geo)
  end

  defp validate_cloudflare_headers(headers) do
    case {Map.get(headers, "cf-ray"), Map.get(headers, "cf-connecting-ip")} do
      {nil, nil} ->
        :ok

      {ray, ip} when is_binary(ray) and is_binary(ip) ->
        if valid_cf_ray?(ray) and valid_ip?(ip), do: :ok, else: {:error, :invalid_cf_headers}

      _ ->
        {:error, :invalid_cf_headers}
    end
  end

  defp validate_forwarded_headers(headers, trusted_proxies) do
    case Map.get(headers, "x-forwarded-for") do
      nil ->
        :ok

      forwarded ->
        ips = String.split(forwarded, ",") |> Enum.map(&String.trim/1)

        if Enum.all?(ips, &valid_ip?/1) and
             (trusted_proxies == [] or Enum.any?(ips, &(&1 in trusted_proxies))) do
          :ok
        else
          {:error, :untrusted_forwarded_headers}
        end
    end
  end

  defp validate_consistency(headers) do
    protocol_consistency = check_protocol_consistency(headers)
    ip_consistency = check_ip_consistency(headers)

    if protocol_consistency and ip_consistency do
      :ok
    else
      {:error, :inconsistent_headers}
    end
  end

  defp check_protocol_consistency(headers) do
    proto = Map.get(headers, "x-forwarded-proto")
    ssl = Map.get(headers, "x-forwarded-ssl")
    cf_visitor = Map.get(headers, "cf-visitor")

    case {proto, ssl, cf_visitor} do
      {nil, nil, nil} -> true
      {"https", "on", _} -> true
      {"http", nil, _} -> true
      {"https", nil, visitor} when is_binary(visitor) -> String.contains?(visitor, "https")
      _ -> false
    end
  end

  defp check_ip_consistency(headers) do
    cf_ip = Map.get(headers, "cf-connecting-ip")
    real_ip = Map.get(headers, "x-real-ip")
    forwarded = Map.get(headers, "x-forwarded-for")

    ips = [cf_ip, real_ip, forwarded] |> Enum.filter(&(&1 != nil))

    case ips do
      [] -> true
      [_single] -> true
      multiple -> length(Enum.uniq(multiple)) <= 2
    end
  end

  defp valid_cf_ray?(ray) do
    String.match?(ray, ~r/^[a-f0-9]+-[A-Z]{3}$/)
  end

  defp valid_ip?(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end
