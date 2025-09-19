defmodule WhoThere.BotDetectorTest do
  use ExUnit.Case, async: true

  alias WhoThere.BotDetector

  describe "is_bot?/1" do
    test "detects common bots by user agent" do
      bot_user_agents = [
        "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
        "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
        "Twitterbot/1.0",
        "LinkedInBot/1.0 (compatible; Mozilla/5.0; Apache-HttpClient +http://www.linkedin.com/)"
      ]

      for user_agent <- bot_user_agents do
        assert BotDetector.is_bot?(%{user_agent: user_agent}),
               "Expected #{user_agent} to be detected as a bot"
      end
    end

    test "does not detect legitimate browsers as bots" do
      legitimate_user_agents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Mobile/15E148 Safari/604.1"
      ]

      for user_agent <- legitimate_user_agents do
        refute BotDetector.is_bot?(%{user_agent: user_agent}),
               "Expected #{user_agent} to NOT be detected as a bot"
      end
    end

    test "detects bots by IP range" do
      # Example bot IP ranges (these would be real ranges in production)
      bot_ips = [
        # Google
        "66.249.64.1",
        # Bing
        "207.46.13.1",
        # Facebook
        "69.63.176.1"
      ]

      for ip <- bot_ips do
        assert BotDetector.is_bot?(%{ip_address: ip, user_agent: "test"}),
               "Expected IP #{ip} to be detected as a bot"
      end
    end

    test "handles behavioral analysis" do
      # High request rate from same IP
      high_frequency_request = %{
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0 (compatible; test)",
        # requests per minute
        request_frequency: 100
      }

      assert BotDetector.is_bot?(high_frequency_request)

      # Normal request rate
      normal_request = %{
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0 (compatible; test)",
        # requests per minute
        request_frequency: 5
      }

      refute BotDetector.is_bot?(normal_request)
    end

    test "handles missing or malformed user agents" do
      refute BotDetector.is_bot?(%{user_agent: nil})
      refute BotDetector.is_bot?(%{user_agent: ""})
      refute BotDetector.is_bot?(%{})
    end

    test "case insensitive detection" do
      user_agents = [
        "GOOGLEBOT/2.1",
        "googlebot/2.1",
        "GoogleBot/2.1"
      ]

      for user_agent <- user_agents do
        assert BotDetector.is_bot?(%{user_agent: user_agent})
      end
    end
  end

  describe "get_bot_type/1" do
    test "identifies specific bot types" do
      assert BotDetector.get_bot_type(%{user_agent: "Googlebot/2.1"}) == :search_engine
      assert BotDetector.get_bot_type(%{user_agent: "facebookexternalhit/1.1"}) == :social_media
      assert BotDetector.get_bot_type(%{user_agent: "Slackbot-LinkExpanding"}) == :social_media
      assert BotDetector.get_bot_type(%{user_agent: "Chrome/91.0"}) == :human
    end

    test "handles unknown bots" do
      assert BotDetector.get_bot_type(%{user_agent: "UnknownBot/1.0"}) == :unknown_bot
    end
  end

  describe "get_bot_info/1" do
    test "returns detailed bot information" do
      request = %{
        user_agent: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
      }

      info = BotDetector.get_bot_info(request)

      assert info.is_bot == true
      assert info.bot_type == :search_engine
      assert info.bot_name == "Googlebot"
      assert info.confidence >= 0.8
    end

    test "returns human information for non-bots" do
      request = %{user_agent: "Mozilla/5.0 (Windows NT 10.0) Chrome/91.0"}

      info = BotDetector.get_bot_info(request)

      assert info.is_bot == false
      assert info.bot_type == :human
      assert info.bot_name == nil
      assert info.confidence >= 0.8
    end
  end

  describe "performance" do
    test "detection is fast for large volumes" do
      requests =
        for i <- 1..1000 do
          %{
            user_agent: "Mozilla/5.0 (compatible; test#{i})",
            ip_address: "192.168.1.#{rem(i, 255)}"
          }
        end

      start_time = System.monotonic_time(:microsecond)

      for request <- requests do
        BotDetector.is_bot?(request)
      end

      end_time = System.monotonic_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000

      # Should process 1000 requests in under 100ms
      assert duration_ms < 100
    end
  end
end
