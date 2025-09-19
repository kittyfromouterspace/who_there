defmodule WhoThere.ProxyHeaderParserTest do
  use ExUnit.Case, async: true
  doctest WhoThere.ProxyHeaderParser

  alias WhoThere.ProxyHeaderParser
  import WhoThere.Fixtures

  describe "extract_real_ip/2" do
    test "extracts Cloudflare connecting IP with highest priority" do
      headers = [
        {"cf-connecting-ip", "203.0.113.195"},
        {"x-real-ip", "198.51.100.1"},
        {"x-forwarded-for", "192.0.2.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "falls back to True-Client-IP for Cloudflare Enterprise" do
      headers = [
        {"true-client-ip", "203.0.113.195"},
        {"x-real-ip", "198.51.100.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "uses X-Real-IP when Cloudflare headers not present" do
      headers = [
        {"x-real-ip", "198.51.100.1"},
        {"x-forwarded-for", "192.0.2.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "198.51.100.1"
    end

    test "parses first IP from X-Forwarded-For chain" do
      headers = [
        {"x-forwarded-for", "203.0.113.195, 198.51.100.1, 192.0.2.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "uses X-Client-IP as fallback" do
      headers = [
        {"x-client-ip", "203.0.113.195"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "falls back to remote IP when no proxy headers" do
      headers = []
      remote_ip = {192, 168, 1, 100}

      assert ProxyHeaderParser.extract_real_ip(headers, remote_ip) == "192.168.1.100"
    end

    test "handles invalid IP addresses gracefully" do
      headers = [
        {"cf-connecting-ip", "invalid-ip"},
        {"x-real-ip", "also-invalid"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == nil
    end

    test "handles empty and malformed headers" do
      assert ProxyHeaderParser.extract_real_ip([]) == nil
      assert ProxyHeaderParser.extract_real_ip([{"", ""}]) == nil
      assert ProxyHeaderParser.extract_real_ip(nil) == nil
    end
  end

  describe "extract_cloudflare_geo/1" do
    test "extracts complete Cloudflare geographic information" do
      headers = cloudflare_headers().us_california

      result = ProxyHeaderParser.extract_cloudflare_geo(headers)

      assert result.country == "US"
      assert result.city == "San Francisco"
      assert result.continent == "NA"
    end

    test "handles partial geographic information" do
      headers = [
        {"cf-ipcountry", "GB"},
        {"cf-ipcity", "London"}
      ]

      result = ProxyHeaderParser.extract_cloudflare_geo(headers)

      assert result.country == "GB"
      assert result.city == "London"
      assert Map.get(result, :continent) == nil
    end

    test "returns empty map when no Cloudflare headers present" do
      headers = [{"x-real-ip", "192.168.1.1"}]

      result = ProxyHeaderParser.extract_cloudflare_geo(headers)

      assert result == %{}
    end

    test "ignores empty or nil values" do
      headers = [
        {"cf-ipcountry", "US"},
        {"cf-ipcity", ""},
        {"cf-ipcontinent", nil}
      ]

      result = ProxyHeaderParser.extract_cloudflare_geo(headers)

      assert result == %{country: "US"}
    end
  end

  describe "extract_aws_geo/1" do
    test "extracts AWS CloudFront geographic information" do
      headers = [
        {"cloudfront-viewer-country", "US"},
        {"cloudfront-viewer-country-name", "United States"},
        {"cloudfront-viewer-city", "Seattle"},
        {"cloudfront-viewer-postal-code", "98101"}
      ]

      result = ProxyHeaderParser.extract_aws_geo(headers)

      assert result.country == "US"
      assert result.country_name == "United States"
      assert result.city == "Seattle"
      assert result.postal_code == "98101"
    end

    test "returns empty map when no AWS headers present" do
      headers = [{"cf-ipcountry", "US"}]

      result = ProxyHeaderParser.extract_aws_geo(headers)

      assert result == %{}
    end
  end

  describe "detect_proxy_type/1" do
    test "detects Cloudflare proxy" do
      headers = [{"cf-ray", "123456789abcdef-SFO"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :cloudflare

      headers = [{"cf-connecting-ip", "203.0.113.195"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :cloudflare
    end

    test "detects AWS CloudFront" do
      headers = [{"cloudfront-viewer-country", "US"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :aws_cloudfront
    end

    test "detects AWS ALB" do
      headers = [
        {"x-forwarded-for", "203.0.113.195"},
        {"x-forwarded-proto", "https"}
      ]

      assert ProxyHeaderParser.detect_proxy_type(headers) == :aws_alb
    end

    test "detects nginx proxy" do
      headers = [{"x-real-ip", "203.0.113.195"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :nginx
    end

    test "detects generic proxy" do
      headers = [{"x-forwarded-for", "203.0.113.195"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :generic_proxy
    end

    test "detects direct connection" do
      headers = [{"user-agent", "Mozilla/5.0"}]
      assert ProxyHeaderParser.detect_proxy_type(headers) == :direct
    end
  end

  describe "extract_connection_info/1" do
    test "extracts protocol from X-Forwarded-Proto" do
      headers = [{"x-forwarded-proto", "https"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.protocol == "https"
      assert result.scheme == "https"
    end

    test "detects HTTPS from X-Forwarded-SSL" do
      headers = [{"x-forwarded-ssl", "on"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.protocol == "https"
    end

    test "parses Cloudflare visitor scheme" do
      headers = [{"cf-visitor", "{\"scheme\":\"https\"}"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.protocol == "https"
    end

    test "extracts port information" do
      headers = [{"x-forwarded-port", "8080"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.port == 8080
    end

    test "extracts host and user agent" do
      headers = [
        {"host", "example.com"},
        {"user-agent", "Mozilla/5.0 Chrome/91.0"}
      ]

      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.host == "example.com"
      assert result.user_agent == "Mozilla/5.0 Chrome/91.0"
    end

    test "handles malformed port gracefully" do
      headers = [{"x-forwarded-port", "not-a-number"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.port == nil
    end
  end

  describe "validate_headers/2" do
    test "validates legitimate Cloudflare headers" do
      headers = [
        {"cf-ray", "123456789abcdef-SFO"},
        {"cf-connecting-ip", "203.0.113.195"}
      ]

      assert ProxyHeaderParser.validate_headers(headers) == :ok
    end

    test "detects invalid Cloudflare Ray ID" do
      headers = [
        {"cf-ray", "invalid-ray-id"},
        {"cf-connecting-ip", "203.0.113.195"}
      ]

      assert {:error, :invalid_cf_headers} = ProxyHeaderParser.validate_headers(headers)
    end

    test "validates X-Forwarded-For with trusted proxies" do
      headers = [{"x-forwarded-for", "203.0.113.195, 198.51.100.1"}]
      opts = [trusted_proxies: ["198.51.100.1"]]

      assert ProxyHeaderParser.validate_headers(headers, opts) == :ok
    end

    test "rejects untrusted forwarded headers" do
      headers = [{"x-forwarded-for", "203.0.113.195, 192.168.1.1"}]
      opts = [trusted_proxies: ["198.51.100.1"]]

      assert {:error, :untrusted_forwarded_headers} =
               ProxyHeaderParser.validate_headers(headers, opts)
    end

    test "detects inconsistent protocol headers" do
      headers = [
        {"x-forwarded-proto", "https"},
        {"x-forwarded-ssl", "off"}
      ]

      assert {:error, :inconsistent_headers} = ProxyHeaderParser.validate_headers(headers)
    end

    test "validates when no proxy headers present" do
      headers = [{"user-agent", "Mozilla/5.0"}]
      assert ProxyHeaderParser.validate_headers(headers) == :ok
    end
  end

  describe "parse_all/3" do
    test "extracts comprehensive information from all headers" do
      headers = [
        {"cf-connecting-ip", "203.0.113.195"},
        {"cf-ipcountry", "US"},
        {"cf-ipcity", "San Francisco"},
        {"cf-ray", "123456789abcdef-SFO"},
        {"x-forwarded-proto", "https"},
        {"host", "example.com"}
      ]

      result = ProxyHeaderParser.parse_all(headers)

      assert result.real_ip == "203.0.113.195"
      assert result.geo.country == "US"
      assert result.geo.city == "San Francisco"
      assert result.connection.protocol == "https"
      assert result.connection.host == "example.com"
      assert result.proxy_type == :cloudflare
      assert result.headers_valid == true
    end

    test "handles mixed proxy environments" do
      headers = [
        {"x-forwarded-for", "203.0.113.195, 198.51.100.1"},
        {"cloudfront-viewer-country", "US"},
        {"x-forwarded-proto", "https"}
      ]

      result = ProxyHeaderParser.parse_all(headers)

      assert result.real_ip == "203.0.113.195"
      assert result.geo.country == "US"
      assert result.proxy_type == :aws_cloudfront
    end

    test "provides fallback when no proxy headers present" do
      headers = [{"user-agent", "Mozilla/5.0"}]
      remote_ip = {192, 168, 1, 100}

      result = ProxyHeaderParser.parse_all(headers, remote_ip)

      assert result.real_ip == "192.168.1.100"
      assert result.geo == %{}
      assert result.proxy_type == :direct
      assert result.headers_valid == true
    end
  end

  describe "edge cases and malformed input" do
    test "handles case-insensitive headers" do
      headers = [
        {"CF-Connecting-IP", "203.0.113.195"},
        {"X-Real-IP", "198.51.100.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "handles atom keys in headers" do
      headers = [
        {:cf_connecting_ip, "203.0.113.195"},
        {:x_real_ip, "198.51.100.1"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "handles map-style headers" do
      headers = %{
        "cf-connecting-ip" => "203.0.113.195",
        "x-real-ip" => "198.51.100.1"
      }

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end

    test "handles malformed JSON in CF visitor" do
      headers = [{"cf-visitor", "invalid-json"}]
      result = ProxyHeaderParser.extract_connection_info(headers)

      assert result.protocol == "http"
    end

    test "handles extremely long header values" do
      long_forwarded = String.duplicate("203.0.113.195,", 1000) <> "198.51.100.1"
      headers = [{"x-forwarded-for", long_forwarded}]

      result = ProxyHeaderParser.extract_real_ip(headers)
      assert result == "203.0.113.195"
    end

    test "handles special characters in headers" do
      headers = [
        {"cf-connecting-ip", "203.0.113.195"},
        {"x-custom-header", "special-chars-!@#$%^&*()"}
      ]

      assert ProxyHeaderParser.extract_real_ip(headers) == "203.0.113.195"
    end
  end

  describe "performance with large header sets" do
    test "processes many headers efficiently" do
      headers =
        for i <- 1..1000 do
          {"x-custom-header-#{i}", "value-#{i}"}
        end ++ [{"cf-connecting-ip", "203.0.113.195"}]

      start_time = System.monotonic_time()
      result = ProxyHeaderParser.extract_real_ip(headers)
      end_time = System.monotonic_time()

      assert result == "203.0.113.195"
      # Should complete in reasonable time (less than 10ms)
      assert System.convert_time_unit(end_time - start_time, :native, :millisecond) < 10
    end
  end
end
