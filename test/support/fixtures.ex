defmodule WhoThere.Fixtures do
  @moduledoc """
  Test fixtures for WhoThere.
  """

  @doc """
  Sample user agents for testing.
  """
  def user_agents do
    %{
      chrome:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
      firefox: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
      safari:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
      mobile_chrome:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1",
      googlebot: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      bingbot: "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
      facebookbot: "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
      curl: "curl/7.68.0"
    }
  end

  @doc """
  Sample IP addresses for testing.
  """
  def ip_addresses do
    %{
      local: {127, 0, 0, 1},
      private_192: {192, 168, 1, 100},
      private_10: {10, 0, 0, 50},
      cloudflare: {104, 16, 0, 1},
      google: {8, 8, 8, 8},
      ipv6_local: {0, 0, 0, 0, 0, 0, 0, 1},
      ipv6_public: {8193, 11, 8454, 0, 0, 0, 0, 1}
    }
  end

  @doc """
  Sample Cloudflare headers for testing.
  """
  def cloudflare_headers do
    %{
      us_california: [
        {"cf-ipcountry", "US"},
        {"cf-ipcity", "San Francisco"},
        {"cf-ipcontinent", "NA"},
        {"cf-visitor", "{\"scheme\":\"https\"}"},
        {"cf-ray", "123456789abcdef-SFO"}
      ],
      uk_london: [
        {"cf-ipcountry", "GB"},
        {"cf-ipcity", "London"},
        {"cf-ipcontinent", "EU"},
        {"cf-visitor", "{\"scheme\":\"https\"}"},
        {"cf-ray", "987654321fedcba-LHR"}
      ],
      jp_tokyo: [
        {"cf-ipcountry", "JP"},
        {"cf-ipcity", "Tokyo"},
        {"cf-ipcontinent", "AS"},
        {"cf-visitor", "{\"scheme\":\"https\"}"},
        {"cf-ray", "abcdef123456789-NRT"}
      ]
    }
  end

  @doc """
  Sample proxy headers for testing.
  """
  def proxy_headers do
    %{
      x_forwarded_for: [
        {"x-forwarded-for", "203.0.113.195, 70.41.3.18, 150.172.238.178"}
      ],
      x_real_ip: [
        {"x-real-ip", "203.0.113.195"}
      ],
      aws_alb: [
        {"x-forwarded-for", "203.0.113.195"},
        {"x-forwarded-proto", "https"},
        {"x-forwarded-port", "443"}
      ]
    }
  end

  @doc """
  Sample paths for testing route filtering.
  """
  def sample_paths do
    %{
      public: [
        "/",
        "/about",
        "/contact",
        "/blog",
        "/blog/post-1",
        "/products",
        "/products/item-123"
      ],
      admin: [
        "/admin",
        "/admin/dashboard",
        "/admin/users",
        "/admin/settings"
      ],
      api: [
        "/api/health",
        "/api/_health",
        "/api/v1/users",
        "/api/v1/posts",
        "/api/internal/metrics"
      ],
      assets: [
        "/css/app.css",
        "/js/app.js",
        "/images/logo.png",
        "/favicon.ico",
        "/robots.txt"
      ]
    }
  end

  @doc """
  Sample fingerprint data for testing.
  """
  def fingerprint_data do
    %{
      chrome_desktop: %{
        screen: "1920x1080",
        timezone: "America/New_York",
        language: "en-US",
        platform: "Win32",
        cookies_enabled: true,
        do_not_track: false
      },
      mobile_safari: %{
        screen: "375x667",
        timezone: "America/Los_Angeles",
        language: "en-US",
        platform: "iPhone",
        cookies_enabled: true,
        do_not_track: false
      },
      privacy_focused: %{
        screen: "1024x768",
        timezone: "UTC",
        language: "en",
        platform: "Linux x86_64",
        cookies_enabled: false,
        do_not_track: true
      }
    }
  end

  @doc """
  Creates sample event data for testing.
  """
  def sample_events(tenant_id, count \\ 10) do
    paths = sample_paths().public
    user_agents = Map.values(user_agents())
    ips = Map.values(ip_addresses())

    for i <- 1..count do
      %{
        tenant_id: tenant_id,
        session_id: "session_#{i}",
        event_type: "page_view",
        path: Enum.random(paths),
        user_agent: Enum.random(user_agents),
        ip_hash: "hash_#{Enum.random(ips) |> :erlang.phash2()}",
        country: Enum.random(["US", "GB", "JP", "DE", "FR"]),
        city: Enum.random(["San Francisco", "London", "Tokyo", "Berlin", "Paris"]),
        is_bot: Enum.random([true, false]),
        occurred_at: DateTime.utc_now() |> DateTime.add(-i * 3600, :second)
      }
    end
  end

  @doc """
  Creates sample bot traffic for testing.
  """
  def bot_traffic_events(tenant_id, count \\ 5) do
    bot_agents = [
      user_agents().googlebot,
      user_agents().bingbot,
      user_agents().facebookbot
    ]

    for i <- 1..count do
      %{
        tenant_id: tenant_id,
        session_id: "bot_session_#{i}",
        event_type: "page_view",
        path: Enum.random(["/", "/about", "/products"]),
        user_agent: Enum.random(bot_agents),
        ip_hash: "bot_hash_#{i}",
        country: "US",
        city: "Mountain View",
        is_bot: true,
        occurred_at: DateTime.utc_now() |> DateTime.add(-i * 1800, :second)
      }
    end
  end
end
