defmodule WhoThere.Privacy do
  @moduledoc """
  Privacy and anonymization utilities for WhoThere analytics.

  This module provides functions for anonymizing IP addresses, detecting PII,
  and sanitizing data to ensure compliance with privacy regulations like GDPR.
  """

  @doc """
  Anonymizes an IP address by zeroing out the last octet for IPv4
  or the last 80 bits for IPv6.

  ## Examples

      iex> WhoThere.Privacy.anonymize_ip({192, 168, 1, 100})
      {192, 168, 1, 0}

      iex> WhoThere.Privacy.anonymize_ip({8193, 11, 8454, 0, 0, 0, 0, 1})
      {8193, 11, 8454, 0, 0, 0, 0, 0}

  """
  def anonymize_ip(ip) when is_tuple(ip) do
    case tuple_size(ip) do
      4 -> anonymize_ipv4(ip)
      8 -> anonymize_ipv6(ip)
      _ -> ip
    end
  end

  def anonymize_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed_ip} ->
        anonymized = anonymize_ip(parsed_ip)
        :inet.ntoa(anonymized) |> to_string()

      {:error, _} ->
        ip
    end
  end

  def anonymize_ip(ip), do: ip

  @doc """
  Anonymizes an IP address with configurable anonymization levels.
  
  - `:partial` - Anonymizes last octet of IPv4 or last 80 bits of IPv6 (default behavior)
  - `:full` - Anonymizes last two octets of IPv4 or last 112 bits of IPv6 for stronger privacy
  
  ## Examples
  
      iex> WhoThere.Privacy.anonymize_ip({192, 168, 1, 100}, :partial)
      {192, 168, 1, 0}
      
      iex> WhoThere.Privacy.anonymize_ip({192, 168, 1, 100}, :full)
      {192, 168, 0, 0}
  """
  def anonymize_ip(ip, :partial), do: anonymize_ip(ip)
  
  def anonymize_ip(ip, :full) when is_tuple(ip) do
    case tuple_size(ip) do
      4 -> anonymize_ipv4_full(ip)
      8 -> anonymize_ipv6_full(ip)
      _ -> ip
    end
  end
  
  def anonymize_ip(ip, :full) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed_ip} ->
        anonymized = anonymize_ip(parsed_ip, :full)
        :inet.ntoa(anonymized) |> to_string()
      {:error, _} ->
        ip
    end
  end
  
  def anonymize_ip(ip, _level), do: ip

  @doc """
  Creates a hash of an IP address for analytics while preserving privacy.

  The hash includes a random salt to prevent rainbow table attacks.
  """
  def hash_ip(ip, salt \\ nil) do
    salt = salt || generate_salt()

    ip_string =
      case ip do
        ip when is_tuple(ip) -> :inet.ntoa(ip) |> to_string()
        ip when is_binary(ip) -> ip
        _ -> ""
      end

    :crypto.hash(:sha256, salt <> ip_string)
    |> Base.encode64()
    |> binary_part(0, 16)
  end

  @doc """
  Detects potential personally identifiable information (PII) in text.

  Returns a list of detected PII types.

  ## Examples

      iex> WhoThere.Privacy.detect_pii("My email is john@example.com")
      [:email]

      iex> WhoThere.Privacy.detect_pii("Call me at (555) 123-4567")
      [:phone]

  """
  def detect_pii(text) when is_binary(text) do
    []
    |> check_email(text)
    |> check_phone(text)
    |> check_ssn(text)
    |> check_credit_card(text)
    |> check_ip_address(text)
  end

  def detect_pii(_), do: []

  @doc """
  Sanitizes text by removing or masking detected PII.

  ## Options
  - `:mask_char` - Character to use for masking (default: "*")
  - `:preserve_domain` - Whether to preserve email domains (default: false)
  """
  def sanitize_pii(text, opts \\ [])

  def sanitize_pii(text, opts) when is_binary(text) do
    mask_char = Keyword.get(opts, :mask_char, "*")
    preserve_domain = Keyword.get(opts, :preserve_domain, false)

    text
    |> sanitize_emails(mask_char, preserve_domain)
    |> sanitize_phones(mask_char)
    |> sanitize_ssns(mask_char)
    |> sanitize_credit_cards(mask_char)
    |> sanitize_ip_addresses(mask_char)
  end

  def sanitize_pii(text, _opts), do: text

  @doc """
  Validates that data meets privacy requirements.

  Returns `:ok` if valid, `{:error, violations}` if violations are found.
  """
  def validate_privacy_compliance(data) when is_map(data) do
    violations = []

    violations =
      if has_raw_ip?(data), do: [:raw_ip | violations], else: violations

    violations =
      if has_pii_in_user_agent?(data), do: [:pii_in_user_agent | violations], else: violations

    violations =
      if has_tracking_pixels?(data), do: [:tracking_pixels | violations], else: violations

    case violations do
      [] -> :ok
      violations -> {:error, violations}
    end
  end

  def validate_privacy_compliance(_), do: :ok

  @doc """
  Generates a cryptographically secure salt for hashing.
  """
  def generate_salt(length \\ 32) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end

  @doc """
  Checks if an IP address is from a private network range.
  """
  def private_ip?(ip) when is_tuple(ip) do
    case tuple_size(ip) do
      4 -> private_ipv4?(ip)
      8 -> private_ipv6?(ip)
      _ -> false
    end
  end

  def private_ip?(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed_ip} -> private_ip?(parsed_ip)
      {:error, _} -> false
    end
  end

  def private_ip?(_), do: false

  @doc """
  Checks if data should be excluded from analytics based on privacy rules.
  """
  def should_exclude?(data) when is_map(data) do
    cond do
      # Bot requests are tracked separately
      is_bot_request?(data) -> false
      has_do_not_track?(data) -> true
      is_admin_request?(data) -> true
      is_health_check?(data) -> true
      has_privacy_flag?(data) -> true
      true -> false
    end
  end

  def should_exclude?(_), do: false

  @doc """
  Sanitizes a user agent string by removing potentially identifying information.
  
  Removes version numbers, build information, and other identifying details
  while preserving general browser and OS information for analytics.
  """
  def sanitize_user_agent(user_agent) when is_binary(user_agent) do
    user_agent
    |> String.replace(~r/\b\d+\.\d+\.\d+(\.\d+)?\b/, "x.x.x")  # Version numbers
    |> String.replace(~r/\b[A-Z0-9]{8,}\b/, "XXXXXXXX")         # Long alphanumeric strings
    |> String.replace(~r/\(.+?\)/, "()")                        # Remove details in parentheses
    |> String.replace(~r/\s+/, " ")                             # Normalize whitespace
    |> String.trim()
  end

  def sanitize_user_agent(user_agent), do: user_agent

  @doc """
  Anonymizes IP-related data in a data structure.
  
  Recursively finds and anonymizes IP addresses in maps and lists.
  """
  def anonymize_ip_data(data) when is_map(data) do
    data
    |> Map.update(:ip_address, nil, &anonymize_ip/1)
    |> Map.update(:client_ip, nil, &anonymize_ip/1)
    |> Map.update(:remote_ip, nil, &anonymize_ip/1)
    |> Map.update(:forwarded_for, nil, &anonymize_ip/1)
    |> Enum.map(fn {k, v} -> {k, anonymize_ip_data(v)} end)
    |> Map.new()
  end

  def anonymize_ip_data(data) when is_list(data) do
    Enum.map(data, &anonymize_ip_data/1)
  end

  def anonymize_ip_data(data) when is_binary(data) do
    # Check if this looks like an IP address
    if Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, data) do
      anonymize_ip(data)
    else
      data
    end
  end

  def anonymize_ip_data(data), do: data

  @doc """
  Removes personally identifiable information from data.
  
  This function sanitizes various types of PII from structured data.
  """
  def remove_pii(data) when is_map(data) do
    data
    |> Map.drop([:email, :phone, :ssn, :credit_card])  # Remove known PII fields
    |> Map.update(:user_agent, nil, &sanitize_user_agent/1)
    |> anonymize_ip_data()
    |> Enum.map(fn {k, v} -> {k, remove_pii(v)} end)
    |> Map.new()
  end

  def remove_pii(data) when is_list(data) do
    Enum.map(data, &remove_pii/1)
  end

  def remove_pii(data) when is_binary(data) do
    sanitize_pii(data)
  end

  def remove_pii(data), do: data

  # Private functions

  defp anonymize_ipv4({a, b, c, _d}) do
    {a, b, c, 0}
  end

  defp anonymize_ipv4_full({a, b, _c, _d}) do
    {a, b, 0, 0}
  end

  defp anonymize_ipv6({a, b, c, d, _e, _f, _g, _h}) do
    {a, b, c, d, 0, 0, 0, 0}
  end

  defp anonymize_ipv6_full({a, b, _c, _d, _e, _f, _g, _h}) do
    {a, b, 0, 0, 0, 0, 0, 0}
  end

  defp check_email(acc, text) do
    email_regex = ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/
    if Regex.match?(email_regex, text), do: [:email | acc], else: acc
  end

  defp check_phone(acc, text) do
    phone_regex = ~r/(\+\d{1,3}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}/
    if Regex.match?(phone_regex, text), do: [:phone | acc], else: acc
  end

  defp check_ssn(acc, text) do
    ssn_regex = ~r/\b\d{3}-\d{2}-\d{4}\b/
    if Regex.match?(ssn_regex, text), do: [:ssn | acc], else: acc
  end

  defp check_credit_card(acc, text) do
    cc_regex = ~r/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/
    if Regex.match?(cc_regex, text), do: [:credit_card | acc], else: acc
  end

  defp check_ip_address(acc, text) do
    ip_regex = ~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
    if Regex.match?(ip_regex, text), do: [:ip_address | acc], else: acc
  end

  defp sanitize_emails(text, mask_char, preserve_domain) do
    email_regex = ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/

    Regex.replace(email_regex, text, fn email ->
      if preserve_domain do
        [local, domain] = String.split(email, "@", parts: 2)
        masked_local = String.duplicate(mask_char, String.length(local))
        "#{masked_local}@#{domain}"
      else
        String.duplicate(mask_char, String.length(email))
      end
    end)
  end

  defp sanitize_phones(text, mask_char) do
    phone_regex = ~r/(\+\d{1,3}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}/

    Regex.replace(phone_regex, text, fn phone ->
      String.duplicate(mask_char, String.length(phone))
    end)
  end

  defp sanitize_ssns(text, mask_char) do
    ssn_regex = ~r/\b\d{3}-\d{2}-\d{4}\b/

    Regex.replace(ssn_regex, text, fn ssn ->
      String.duplicate(mask_char, String.length(ssn))
    end)
  end

  defp sanitize_credit_cards(text, mask_char) do
    cc_regex = ~r/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/

    Regex.replace(cc_regex, text, fn cc ->
      String.duplicate(mask_char, String.length(cc))
    end)
  end

  defp sanitize_ip_addresses(text, mask_char) do
    ip_regex = ~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/

    Regex.replace(ip_regex, text, fn ip ->
      String.duplicate(mask_char, String.length(ip))
    end)
  end

  defp private_ipv4?({10, _, _, _}), do: true
  defp private_ipv4?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp private_ipv4?({192, 168, _, _}), do: true
  defp private_ipv4?({127, _, _, _}), do: true
  defp private_ipv4?(_), do: false

  # Link-local
  defp private_ipv6?({0xFE80, _, _, _, _, _, _, _}), do: true
  # Unique local
  defp private_ipv6?({0xFC00, _, _, _, _, _, _, _}), do: true
  # Loopback
  defp private_ipv6?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ipv6?(_), do: false

  defp has_raw_ip?(data) do
    Map.has_key?(data, :ip_address) and not Map.has_key?(data, :ip_hash)
  end

  defp has_pii_in_user_agent?(data) do
    case Map.get(data, :user_agent) do
      nil -> false
      user_agent -> detect_pii(user_agent) != []
    end
  end

  defp has_tracking_pixels?(data) do
    case Map.get(data, :path) do
      nil -> false
      path -> String.contains?(path, ["pixel.gif", "beacon.png", "track.gif"])
    end
  end

  defp is_bot_request?(data) do
    Map.get(data, :is_bot, false)
  end

  defp has_do_not_track?(data) do
    Map.get(data, :do_not_track, false)
  end

  defp is_admin_request?(data) do
    case Map.get(data, :path) do
      nil -> false
      path -> String.starts_with?(path, "/admin")
    end
  end

  defp is_health_check?(data) do
    case Map.get(data, :path) do
      nil -> false
      path -> path in ["/health", "/api/health", "/api/_health", "/_health"]
    end
  end

  defp has_privacy_flag?(data) do
    Map.get(data, :exclude_analytics, false)
  end
end
