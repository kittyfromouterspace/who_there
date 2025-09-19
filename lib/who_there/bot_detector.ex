defmodule WhoThere.BotDetector do
  @moduledoc """
  Multi-layered bot detection system with pattern matching and behavior analysis.

  This module provides comprehensive bot detection capabilities including:
  - User-agent pattern matching
  - IP range detection
  - Behavioral analysis (request frequency, patterns)
  - Bot type classification
  - Confidence scoring

  ## Examples

      iex> WhoThere.BotDetector.is_bot?(%{user_agent: "Googlebot/2.1"})
      true

      iex> WhoThere.BotDetector.is_bot?(%{user_agent: "Chrome/91.0"})
      false

      iex> WhoThere.BotDetector.get_bot_info(%{user_agent: "Googlebot/2.1"})
      %{is_bot: true, bot_type: :search_engine, bot_name: "Googlebot", confidence: 0.95}
  """

  @type bot_type ::
          :search_engine | :social_media | :security | :seo | :monitoring | :unknown_bot | :human

  @type bot_info :: %{
          is_bot: boolean(),
          bot_type: bot_type(),
          bot_name: String.t() | nil,
          confidence: float()
        }

  # Known bot user agent patterns
  @bot_patterns [
    # Search engines
    {~r/googlebot/i, :search_engine, "Googlebot"},
    {~r/bingbot/i, :search_engine, "Bingbot"},
    {~r/slurp/i, :search_engine, "Yahoo Slurp"},
    {~r/duckduckbot/i, :search_engine, "DuckDuckBot"},
    {~r/baiduspider/i, :search_engine, "Baiduspider"},
    {~r/yandexbot/i, :search_engine, "YandexBot"},

    # Social media
    {~r/facebookexternalhit/i, :social_media, "Facebook"},
    {~r/twitterbot/i, :social_media, "Twitter"},
    {~r/linkedinbot/i, :social_media, "LinkedIn"},
    {~r/slackbot/i, :social_media, "Slack"},
    {~r/discordbot/i, :social_media, "Discord"},
    {~r/telegrambot/i, :social_media, "Telegram"},

    # SEO and monitoring
    {~r/ahrefsbot/i, :seo, "AhrefsBot"},
    {~r/semrushbot/i, :seo, "SemrushBot"},
    {~r/mj12bot/i, :seo, "MJ12bot"},
    {~r/dotbot/i, :seo, "DotBot"},
    {~r/uptimerobot/i, :monitoring, "UptimeRobot"},
    {~r/pingdom/i, :monitoring, "Pingdom"},

    # Security scanners
    {~r/nessus/i, :security, "Nessus"},
    {~r/nmap/i, :security, "Nmap"},
    {~r/masscan/i, :security, "Masscan"},

    # Generic bot patterns
    {~r/bot\b/i, :unknown_bot, "Generic Bot"},
    {~r/crawler/i, :unknown_bot, "Crawler"},
    {~r/spider/i, :unknown_bot, "Spider"},
    {~r/scraper/i, :unknown_bot, "Scraper"}
  ]

  # Known bot IP ranges would be loaded from configuration in production

  @doc """
  Determines if a request is from a bot.

  ## Parameters

  - `request_data` - Map containing request information:
    - `:user_agent` - The User-Agent header (required)
    - `:ip_address` - The client IP address (optional)
    - `:request_frequency` - Requests per minute from this IP (optional)

  ## Examples

      iex> WhoThere.BotDetector.is_bot?(%{user_agent: "Googlebot/2.1"})
      true

      iex> WhoThere.BotDetector.is_bot?(%{user_agent: "Chrome/91.0"})
      false
  """
  @spec is_bot?(map()) :: boolean()
  def is_bot?(request_data) when is_map(request_data) do
    user_agent = Map.get(request_data, :user_agent, "")
    ip_address = Map.get(request_data, :ip_address)
    request_frequency = Map.get(request_data, :request_frequency, 0)

    cond do
      is_bot_by_user_agent?(user_agent) -> true
      is_bot_by_ip?(ip_address) -> true
      is_bot_by_behavior?(request_frequency) -> true
      true -> false
    end
  end

  @doc """
  Gets the type of bot for a request.

  Returns `:human` if not a bot, or the specific bot type if it is a bot.
  """
  @spec get_bot_type(map()) :: bot_type()
  def get_bot_type(request_data) when is_map(request_data) do
    user_agent = Map.get(request_data, :user_agent, "")

    case find_bot_pattern(user_agent) do
      {_pattern, bot_type, _name} -> bot_type
      nil -> if is_bot?(request_data), do: :unknown_bot, else: :human
    end
  end

  @doc """
  Gets detailed information about bot detection for a request.

  Returns a map with bot detection details including confidence score.
  """
  @spec get_bot_info(map()) :: bot_info()
  def get_bot_info(request_data) when is_map(request_data) do
    user_agent = Map.get(request_data, :user_agent, "")
    is_bot = is_bot?(request_data)

    case find_bot_pattern(user_agent) do
      {_pattern, bot_type, bot_name} ->
        %{
          is_bot: true,
          bot_type: bot_type,
          bot_name: bot_name,
          confidence: calculate_confidence(request_data, true)
        }

      nil ->
        if is_bot do
          %{
            is_bot: true,
            bot_type: :unknown_bot,
            bot_name: nil,
            confidence: calculate_confidence(request_data, true)
          }
        else
          %{
            is_bot: false,
            bot_type: :human,
            bot_name: nil,
            confidence: calculate_confidence(request_data, false)
          }
        end
    end
  end

  # Private functions

  @spec is_bot_by_user_agent?(String.t() | nil) :: boolean()
  defp is_bot_by_user_agent?(user_agent) when is_binary(user_agent) and user_agent != "" do
    find_bot_pattern(user_agent) != nil
  end

  defp is_bot_by_user_agent?(_), do: false

  @spec find_bot_pattern(String.t()) :: {Regex.t(), bot_type(), String.t()} | nil
  defp find_bot_pattern(user_agent) when is_binary(user_agent) do
    Enum.find_value(@bot_patterns, fn {pattern, bot_type, name} ->
      if Regex.match?(pattern, user_agent) do
        {pattern, bot_type, name}
      end
    end)
  end

  @spec is_bot_by_ip?(String.t() | nil) :: boolean()
  defp is_bot_by_ip?(ip_address) when is_binary(ip_address) do
    # Simple implementation - in production this would use a proper CIDR library
    # For now, we'll do basic string matching for known bot IPs
    known_bot_ip_prefixes = [
      # Google
      "66.249.",
      # Microsoft
      "207.46.",
      # Facebook
      "69.63.176.",
      # Facebook
      "69.171."
    ]

    Enum.any?(known_bot_ip_prefixes, &String.starts_with?(ip_address, &1))
  end

  defp is_bot_by_ip?(_), do: false

  @spec is_bot_by_behavior?(number()) :: boolean()
  defp is_bot_by_behavior?(request_frequency) when is_number(request_frequency) do
    # Consider anything over 60 requests per minute as potentially bot behavior
    request_frequency > 60
  end

  defp is_bot_by_behavior?(_), do: false

  @spec calculate_confidence(map(), boolean()) :: float()
  defp calculate_confidence(request_data, is_bot) do
    user_agent = Map.get(request_data, :user_agent, "")
    ip_address = Map.get(request_data, :ip_address)
    request_frequency = Map.get(request_data, :request_frequency, 0)

    base_confidence = if is_bot, do: 0.6, else: 0.8

    # Increase confidence based on multiple indicators
    confidence = base_confidence
    confidence = if is_bot_by_user_agent?(user_agent), do: confidence + 0.3, else: confidence
    confidence = if is_bot_by_ip?(ip_address), do: confidence + 0.2, else: confidence
    confidence = if is_bot_by_behavior?(request_frequency), do: confidence + 0.1, else: confidence

    # Cap at 0.99
    min(confidence, 0.99)
  end
end
