defmodule WhoThere.GeographicDataParserTest do
  use ExUnit.Case, async: true

  alias WhoThere.GeographicDataParser

  describe "extract_geographic_data/2" do
    test "extracts data from CloudFlare headers when trusted" do
      conn_data = %{
        headers: %{
          "cf-ipcountry" => "US",
          "cf-ipcity" => "San Francisco",
          "cf-region" => "California"
        }
      }

      opts = [trust_proxy_headers: true]

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data, opts)
      assert result.country_code == "US"
      assert result.city == "San Francisco"
      assert result.region == "California"
      assert result.source == :cloudflare
      assert result.confidence == :high
    end

    test "falls back to IP geolocation when headers not trusted" do
      conn_data = %{
        headers: %{"cf-ipcountry" => "US"},
        remote_ip: {8, 8, 8, 8}
      }

      opts = [trust_proxy_headers: false]

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data, opts)
      assert result.source == :ip_geolocation
    end

    test "returns default data when no location information available" do
      conn_data = %{}

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data)
      assert result.country_code == nil
      assert result.source == :unknown
      assert result.confidence == :low
    end

    test "respects country_only option" do
      conn_data = %{
        headers: %{
          "cf-ipcountry" => "US",
          "cf-ipcity" => "San Francisco"
        }
      }

      opts = [country_only: true]

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data, opts)
      assert result.country_code == "US"
      # Removed for privacy
      assert result.city == nil
    end
  end

  describe "anonymize_ip/2" do
    test "partial anonymization of IPv4" do
      ip = {192, 168, 1, 100}
      result = GeographicDataParser.anonymize_ip(ip, :partial)
      assert result == {192, 168, 1, 0}
    end

    test "full anonymization of IPv4" do
      ip = {192, 168, 1, 100}
      result = GeographicDataParser.anonymize_ip(ip, :full)
      assert result == {192, 168, 0, 0}
    end

    test "no anonymization preserves original IP" do
      ip = {192, 168, 1, 100}
      result = GeographicDataParser.anonymize_ip(ip, :none)
      assert result == ip
    end

    test "partial anonymization of IPv6" do
      ip = {0x2001, 0x0DB8, 0x85A3, 0x0000, 0x0000, 0x8A2E, 0x0370, 0x7334}
      result = GeographicDataParser.anonymize_ip(ip, :partial)
      assert result == {0x2001, 0x0DB8, 0x85A3, 0, 0, 0, 0, 0}
    end

    test "full anonymization of IPv6" do
      ip = {0x2001, 0x0DB8, 0x85A3, 0x0000, 0x0000, 0x8A2E, 0x0370, 0x7334}
      result = GeographicDataParser.anonymize_ip(ip, :full)
      assert result == {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}
    end
  end

  describe "extract_from_proxy_headers/2" do
    test "extracts CloudFlare headers" do
      headers = %{
        "cf-ipcountry" => "US",
        "cf-ipcity" => "San Francisco",
        "cf-region" => "California"
      }

      opts = [trusted_sources: ["cloudflare"]]

      assert {:ok, result} = GeographicDataParser.extract_from_proxy_headers(headers, opts)
      assert result.country_code == "US"
      assert result.city == "San Francisco"
      assert result.region == "California"
      assert result.source == :cloudflare
      assert result.confidence == :high
    end

    test "extracts CloudFront headers" do
      headers = %{
        "cloudfront-viewer-country" => "GB"
      }

      opts = [trusted_sources: ["cloudfront"]]

      assert {:ok, result} = GeographicDataParser.extract_from_proxy_headers(headers, opts)
      assert result.country_code == "GB"
      assert result.source == :cloudfront
      assert result.confidence == :high
    end

    test "extracts generic headers" do
      headers = %{
        "x-country-code" => "CA",
        "x-city" => "Toronto",
        "x-region" => "Ontario"
      }

      assert {:ok, result} = GeographicDataParser.extract_from_proxy_headers(headers)
      assert result.country_code == "CA"
      assert result.city == "Toronto"
      assert result.region == "Ontario"
      assert result.source == :generic
      assert result.confidence == :medium
    end

    test "handles case-insensitive headers" do
      headers = %{
        "CF-IPCOUNTRY" => "DE",
        "cf-ipcity" => "Berlin"
      }

      assert {:ok, result} = GeographicDataParser.extract_from_proxy_headers(headers)
      assert result.country_code == "DE"
      assert result.city == "Berlin"
    end

    test "returns error when no geographic headers found" do
      headers = %{"user-agent" => "Mozilla/5.0"}

      assert {:error, :no_geographic_headers} =
               GeographicDataParser.extract_from_proxy_headers(headers)
    end

    test "ignores empty header values" do
      headers = %{
        "cf-ipcountry" => "",
        "cf-ipcity" => "   ",
        "x-country-code" => "FR"
      }

      assert {:ok, result} = GeographicDataParser.extract_from_proxy_headers(headers)
      assert result.country_code == "FR"
    end
  end

  describe "geolocate_ip/2" do
    test "performs basic IP geolocation" do
      # Google DNS
      ip = {8, 8, 8, 8}

      assert {:ok, result} = GeographicDataParser.geolocate_ip(ip)
      assert result.country_code == "US"
      assert result.source == :ip_geolocation
    end

    test "handles private IP addresses" do
      ip = {192, 168, 1, 1}

      assert {:ok, result} = GeographicDataParser.geolocate_ip(ip)
      # Unknown/private
      assert result.country_code == "XX"
    end

    test "applies IP anonymization before lookup" do
      ip = {8, 8, 8, 100}

      # Should still match the 8.8.8.x range after anonymization
      assert {:ok, result} = GeographicDataParser.geolocate_ip(ip, ip_anonymization: :partial)
      assert result.country_code == "US"
    end

    test "returns error for unknown IP ranges" do
      # Invalid IP
      ip = {999, 999, 999, 999}

      assert {:error, :unknown_ip_range} = GeographicDataParser.geolocate_ip(ip)
    end
  end

  describe "normalize_country_code/1" do
    test "normalizes valid country codes" do
      assert {:ok, "US"} = GeographicDataParser.normalize_country_code("us")
      assert {:ok, "GB"} = GeographicDataParser.normalize_country_code("gb")
      assert {:ok, "CA"} = GeographicDataParser.normalize_country_code("  ca  ")
    end

    test "validates country code format" do
      assert {:error, :invalid_country_code} = GeographicDataParser.normalize_country_code("USA")
      assert {:error, :invalid_country_code} = GeographicDataParser.normalize_country_code("1")
      assert {:error, :invalid_country_code} = GeographicDataParser.normalize_country_code("")
      assert {:error, :invalid_country_code} = GeographicDataParser.normalize_country_code(nil)
    end

    test "handles numeric input" do
      assert {:error, :invalid_country_code} = GeographicDataParser.normalize_country_code(123)
    end
  end

  describe "detect_vpn_proxy/2" do
    test "returns VPN detection analysis" do
      ip = {192, 168, 1, 1}

      result = GeographicDataParser.detect_vpn_proxy(ip)

      assert Map.has_key?(result, :is_vpn_likely)
      assert Map.has_key?(result, :vpn_score)
      assert Map.has_key?(result, :checks_passed)
      assert Map.has_key?(result, :total_checks)

      assert is_boolean(result.is_vpn_likely)
      assert is_integer(result.vpn_score)
      assert is_integer(result.checks_passed)
      assert is_integer(result.total_checks)
    end

    test "VPN detection logic is consistent" do
      ip = {8, 8, 8, 8}

      result1 = GeographicDataParser.detect_vpn_proxy(ip)
      result2 = GeographicDataParser.detect_vpn_proxy(ip)

      assert result1 == result2
    end
  end

  describe "get_timezone_info/1" do
    test "returns timezone for city and country" do
      location_data = %{
        country_code: "US",
        city: "San Francisco"
      }

      assert {:ok, "America/Los_Angeles"} = GeographicDataParser.get_timezone_info(location_data)
    end

    test "returns country timezone when city not available" do
      location_data = %{country_code: "GB"}

      assert {:ok, "Europe/London"} = GeographicDataParser.get_timezone_info(location_data)
    end

    test "returns error for unknown locations" do
      location_data = %{country_code: "XX"}

      assert {:error, :unknown_timezone} = GeographicDataParser.get_timezone_info(location_data)
    end

    test "returns error for insufficient data" do
      location_data = %{}

      assert {:error, :insufficient_location_data} =
               GeographicDataParser.get_timezone_info(location_data)
    end
  end

  describe "calculate_distance/2" do
    test "calculates distance between two locations with coordinates" do
      # San Francisco
      location1 = %{latitude: 37.7749, longitude: -122.4194}
      # New York
      location2 = %{latitude: 40.7128, longitude: -74.0060}

      assert {:ok, distance} = GeographicDataParser.calculate_distance(location1, location2)
      assert is_float(distance)
      assert distance > 0
      # Distance should be approximately 4135 km (San Francisco to New York)
      assert distance > 4000 && distance < 5000
    end

    test "returns error when coordinates missing" do
      location1 = %{country_code: "US"}
      location2 = %{country_code: "GB"}

      assert {:error, :missing_coordinates} =
               GeographicDataParser.calculate_distance(location1, location2)
    end

    test "calculates zero distance for same location" do
      location = %{latitude: 37.7749, longitude: -122.4194}

      assert {:ok, distance} = GeographicDataParser.calculate_distance(location, location)
      assert distance == 0.0
    end

    test "handles partial coordinate data" do
      location1 = %{latitude: 37.7749, longitude: -122.4194}
      # Missing longitude
      location2 = %{latitude: 40.7128}

      assert {:error, :missing_coordinates} =
               GeographicDataParser.calculate_distance(location1, location2)
    end
  end

  describe "integration scenarios" do
    test "complete flow with CloudFlare headers" do
      conn_data = %{
        # Fallback IP
        remote_ip: {203, 0, 113, 1},
        headers: %{
          "cf-ipcountry" => "us",
          "cf-ipcity" => "San Francisco"
        }
      }

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data)

      # Should use CloudFlare headers (trusted by default)
      # Normalized to uppercase
      assert result.country_code == "US"
      assert result.country_name == "United States"
      assert result.city == "San Francisco"
      assert result.source == :cloudflare
      assert result.confidence == :high
      assert result.timezone == "America/Los_Angeles"
    end

    test "fallback to IP geolocation when headers unavailable" do
      conn_data = %{
        remote_ip: {8, 8, 8, 8},
        headers: %{}
      }

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data)

      assert result.country_code == "US"
      assert result.source == :ip_geolocation
      # Reduced confidence for fallback
      assert result.confidence == :medium
    end

    test "privacy-first configuration" do
      conn_data = %{
        remote_ip: {203, 0, 113, 100},
        headers: %{
          "cf-ipcountry" => "DE",
          "cf-ipcity" => "Berlin"
        }
      }

      opts = [
        country_only: true,
        ip_anonymization: :full
      ]

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data, opts)

      # Should have country but no city data for privacy
      assert result.country_code == "DE"
      assert result.city == nil
      assert result.region == nil
      assert Map.has_key?(result, :latitude) == false
      assert Map.has_key?(result, :longitude) == false
    end

    test "untrusted proxy headers scenario" do
      conn_data = %{
        remote_ip: {8, 8, 8, 8},
        headers: %{
          # Potentially spoofed
          "cf-ipcountry" => "FAKE",
          "cf-ipcity" => "Nowhere"
        }
      }

      opts = [trust_proxy_headers: false]

      assert {:ok, result} = GeographicDataParser.extract_geographic_data(conn_data, opts)

      # Should ignore headers and use IP geolocation
      # From IP lookup
      assert result.country_code == "US"
      assert result.source == :ip_geolocation
    end
  end
end
