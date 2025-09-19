defmodule WhoThere.PrivacyTest do
  use ExUnit.Case, async: true
  doctest WhoThere.Privacy

  alias WhoThere.Privacy

  describe "anonymize_ip/1" do
    test "anonymizes IPv4 addresses" do
      assert Privacy.anonymize_ip({192, 168, 1, 100}) == {192, 168, 1, 0}
      assert Privacy.anonymize_ip({10, 0, 0, 50}) == {10, 0, 0, 0}
      assert Privacy.anonymize_ip({203, 0, 113, 195}) == {203, 0, 113, 0}
    end

    test "anonymizes IPv6 addresses" do
      assert Privacy.anonymize_ip({8193, 11, 8454, 0, 0, 0, 0, 1}) ==
               {8193, 11, 8454, 0, 0, 0, 0, 0}

      assert Privacy.anonymize_ip({0xFE80, 0, 0, 0, 0x200, 0x5EFF, 0xFE00, 0x5301}) ==
               {0xFE80, 0, 0, 0, 0, 0, 0, 0}
    end

    test "anonymizes string IP addresses" do
      assert Privacy.anonymize_ip("192.168.1.100") == "192.168.1.0"
      assert Privacy.anonymize_ip("10.0.0.50") == "10.0.0.0"
    end

    test "handles invalid IP addresses gracefully" do
      assert Privacy.anonymize_ip("not-an-ip") == "not-an-ip"
      assert Privacy.anonymize_ip(nil) == nil
      assert Privacy.anonymize_ip({1, 2}) == {1, 2}
    end
  end

  describe "hash_ip/2" do
    test "creates consistent hashes for same IP" do
      ip = {192, 168, 1, 100}
      salt = "test_salt"

      hash1 = Privacy.hash_ip(ip, salt)
      hash2 = Privacy.hash_ip(ip, salt)

      assert hash1 == hash2
      assert is_binary(hash1)
      assert String.length(hash1) == 16
    end

    test "creates different hashes for different IPs" do
      salt = "test_salt"
      hash1 = Privacy.hash_ip({192, 168, 1, 100}, salt)
      hash2 = Privacy.hash_ip({192, 168, 1, 101}, salt)

      assert hash1 != hash2
    end

    test "creates different hashes with different salts" do
      ip = {192, 168, 1, 100}
      hash1 = Privacy.hash_ip(ip, "salt1")
      hash2 = Privacy.hash_ip(ip, "salt2")

      assert hash1 != hash2
    end

    test "works with string IP addresses" do
      hash = Privacy.hash_ip("192.168.1.100", "test_salt")
      assert is_binary(hash)
      assert String.length(hash) == 16
    end

    test "generates salt when not provided" do
      ip = {192, 168, 1, 100}
      hash = Privacy.hash_ip(ip)
      assert is_binary(hash)
      assert String.length(hash) == 16
    end
  end

  describe "detect_pii/1" do
    test "detects email addresses" do
      assert Privacy.detect_pii("Contact me at john@example.com") == [:email]
      assert Privacy.detect_pii("Multiple emails: alice@test.org, bob@demo.net") == [:email]
    end

    test "detects phone numbers" do
      assert Privacy.detect_pii("Call (555) 123-4567") == [:phone]
      assert Privacy.detect_pii("Phone: +1 555-123-4567") == [:phone]
      assert Privacy.detect_pii("My number is 555.123.4567") == [:phone]
    end

    test "detects SSNs" do
      assert Privacy.detect_pii("SSN: 123-45-6789") == [:ssn]
    end

    test "detects credit cards" do
      assert Privacy.detect_pii("Card: 4532 1234 5678 9012") == [:credit_card]
      assert Privacy.detect_pii("CC: 4532-1234-5678-9012") == [:credit_card]
    end

    test "detects IP addresses" do
      assert Privacy.detect_pii("From IP 192.168.1.100") == [:ip_address]
    end

    test "detects multiple PII types" do
      text = "Email: john@example.com, Phone: (555) 123-4567, IP: 192.168.1.1"
      pii_types = Privacy.detect_pii(text)

      assert :email in pii_types
      assert :phone in pii_types
      assert :ip_address in pii_types
    end

    test "returns empty list for clean text" do
      assert Privacy.detect_pii("Just some normal text") == []
      assert Privacy.detect_pii("") == []
    end

    test "handles non-string input" do
      assert Privacy.detect_pii(nil) == []
      assert Privacy.detect_pii(123) == []
    end
  end

  describe "sanitize_pii/2" do
    test "sanitizes email addresses" do
      result = Privacy.sanitize_pii("Email: john@example.com")
      assert result == "Email: *****************"
    end

    test "preserves domain when option is set" do
      result = Privacy.sanitize_pii("Email: john@example.com", preserve_domain: true)
      assert result == "Email: ****@example.com"
    end

    test "sanitizes phone numbers" do
      result = Privacy.sanitize_pii("Call (555) 123-4567")
      assert result == "Call **************"
    end

    test "sanitizes multiple PII types" do
      text = "Email: john@example.com, Phone: (555) 123-4567"
      result = Privacy.sanitize_pii(text)
      assert result == "Email: *****************, Phone: **************"
    end

    test "uses custom mask character" do
      result = Privacy.sanitize_pii("Email: john@example.com", mask_char: "X")
      assert result == "Email: XXXXXXXXXXXXXXXXX"
    end

    test "handles non-string input" do
      assert Privacy.sanitize_pii(nil) == nil
      assert Privacy.sanitize_pii(123) == 123
    end
  end

  describe "validate_privacy_compliance/1" do
    test "returns :ok for compliant data" do
      data = %{
        ip_hash: "hashed_ip",
        user_agent: "Mozilla/5.0 (clean user agent)",
        path: "/normal/path"
      }

      assert Privacy.validate_privacy_compliance(data) == :ok
    end

    test "detects raw IP violations" do
      data = %{ip_address: "192.168.1.100"}
      assert {:error, violations} = Privacy.validate_privacy_compliance(data)
      assert :raw_ip in violations
    end

    test "detects PII in user agent" do
      data = %{user_agent: "Mozilla/5.0 (email: john@example.com)"}
      assert {:error, violations} = Privacy.validate_privacy_compliance(data)
      assert :pii_in_user_agent in violations
    end

    test "detects tracking pixels" do
      data = %{path: "/track/pixel.gif"}
      assert {:error, violations} = Privacy.validate_privacy_compliance(data)
      assert :tracking_pixels in violations
    end

    test "handles non-map input" do
      assert Privacy.validate_privacy_compliance("not a map") == :ok
      assert Privacy.validate_privacy_compliance(nil) == :ok
    end
  end

  describe "generate_salt/1" do
    test "generates salt of default length" do
      salt = Privacy.generate_salt()
      assert is_binary(salt)
      assert String.length(salt) == 32
    end

    test "generates salt of custom length" do
      salt = Privacy.generate_salt(16)
      assert is_binary(salt)
      assert String.length(salt) == 16
    end

    test "generates different salts on each call" do
      salt1 = Privacy.generate_salt()
      salt2 = Privacy.generate_salt()
      assert salt1 != salt2
    end
  end

  describe "private_ip?/1" do
    test "identifies private IPv4 addresses" do
      assert Privacy.private_ip?({10, 0, 0, 1}) == true
      assert Privacy.private_ip?({172, 16, 0, 1}) == true
      assert Privacy.private_ip?({192, 168, 1, 1}) == true
      assert Privacy.private_ip?({127, 0, 0, 1}) == true
    end

    test "identifies public IPv4 addresses" do
      assert Privacy.private_ip?({8, 8, 8, 8}) == false
      assert Privacy.private_ip?({203, 0, 113, 1}) == false
    end

    test "identifies private IPv6 addresses" do
      assert Privacy.private_ip?({0xFE80, 0, 0, 0, 0, 0, 0, 1}) == true
      assert Privacy.private_ip?({0xFC00, 0, 0, 0, 0, 0, 0, 1}) == true
      assert Privacy.private_ip?({0, 0, 0, 0, 0, 0, 0, 1}) == true
    end

    test "works with string IP addresses" do
      assert Privacy.private_ip?("192.168.1.1") == true
      assert Privacy.private_ip?("8.8.8.8") == false
    end

    test "handles invalid input" do
      assert Privacy.private_ip?("not-an-ip") == false
      assert Privacy.private_ip?(nil) == false
    end
  end

  describe "should_exclude?/1" do
    test "excludes requests with do not track flag" do
      data = %{do_not_track: true}
      assert Privacy.should_exclude?(data) == true
    end

    test "excludes admin requests" do
      data = %{path: "/admin/dashboard"}
      assert Privacy.should_exclude?(data) == true
    end

    test "excludes health check requests" do
      data = %{path: "/health"}
      assert Privacy.should_exclude?(data) == true

      data = %{path: "/api/_health"}
      assert Privacy.should_exclude?(data) == true
    end

    test "excludes requests with privacy flag" do
      data = %{exclude_analytics: true}
      assert Privacy.should_exclude?(data) == true
    end

    test "includes bot requests for separate tracking" do
      data = %{is_bot: true}
      assert Privacy.should_exclude?(data) == false
    end

    test "includes normal requests" do
      data = %{path: "/normal/page", is_bot: false}
      assert Privacy.should_exclude?(data) == false
    end

    test "handles empty or invalid data" do
      assert Privacy.should_exclude?(%{}) == false
      assert Privacy.should_exclude?(nil) == false
    end
  end

  describe "edge cases and performance" do
    test "handles very long text efficiently" do
      long_text = String.duplicate("normal text ", 10000)
      result = Privacy.detect_pii(long_text)
      assert result == []
    end

    test "handles text with many PII instances" do
      emails = for i <- 1..100, do: "user#{i}@example.com"
      text = Enum.join(emails, ", ")

      result = Privacy.detect_pii(text)
      assert :email in result
    end

    test "sanitization preserves text structure" do
      text = "Before email@example.com after"
      result = Privacy.sanitize_pii(text)
      assert String.starts_with?(result, "Before")
      assert String.ends_with?(result, "after")
    end
  end
end
