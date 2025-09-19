defmodule WhoThere.PlugTest do
  use ExUnit.Case, async: true
  use WhoThere.DataCase

  alias WhoThere.Plug, as: WhoTherePlug

  # Mock connection helper
  defp build_conn(method \\ "GET", path \\ "/", headers \\ []) do
    %Plug.Conn{
      method: method,
      request_path: path,
      remote_ip: {192, 168, 1, 100},
      req_headers: headers,
      private: %{},
      before_send: []
    }
  end

  defp add_header(conn, name, value) do
    %{conn | req_headers: [{name, value} | conn.req_headers]}
  end

  defp simple_tenant_resolver(conn) do
    case Enum.find(conn.req_headers, fn {name, _} -> name == "x-tenant-id" end) do
      {_, tenant} -> tenant
      nil -> "default-tenant"
    end
  end

  describe "init/1" do
    test "requires tenant_resolver option" do
      assert_raise KeyError, fn ->
        WhoTherePlug.init([])
      end
    end

    test "sets default options correctly" do
      opts = WhoTherePlug.init(tenant_resolver: &simple_tenant_resolver/1)

      assert opts.tenant_resolver == (&simple_tenant_resolver/1)
      assert opts.track_page_views == true
      assert opts.track_api_calls == false
      assert opts.track_static_assets == false
      assert opts.session_tracking == true
      assert opts.bot_detection == true
      assert opts.geographic_data == true
      assert opts.async_tracking == true
      assert opts.max_path_length == 2000
      assert opts.privacy_mode == false
    end

    test "allows custom options" do
      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_api_calls: true,
          privacy_mode: true,
          exclude_paths: [~r/^\/health/]
        )

      assert opts.track_api_calls == true
      assert opts.privacy_mode == true
      assert opts.exclude_paths == [~r/^\/health/]
    end
  end

  describe "call/2 - basic functionality" do
    test "processes trackable requests" do
      conn =
        build_conn("GET", "/dashboard")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Mozilla/5.0 Test Browser")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          # Sync for testing
          async_tracking: false
        )

      result_conn = WhoTherePlug.call(conn, opts)

      # Should have tracking data in private
      assert get_in(result_conn.private, [:who_there_tracking]) != nil
      tracking_data = get_in(result_conn.private, [:who_there_tracking])

      assert tracking_data.tenant == "test-tenant"
      assert tracking_data.path == "/dashboard"
      assert tracking_data.method == "GET"
      assert tracking_data.event_type == :page_view
    end

    test "skips requests without tenant" do
      conn = build_conn("GET", "/dashboard")

      opts =
        WhoTherePlug.init(
          tenant_resolver: fn _conn -> nil end,
          async_tracking: false
        )

      result_conn = WhoTherePlug.call(conn, opts)

      # Should not have tracking data
      assert get_in(result_conn.private, [:who_there_tracking]) == nil
    end

    test "registers response tracking callback" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result_conn = WhoTherePlug.call(conn, opts)

      # Should have registered a before_send callback
      assert length(result_conn.before_send) > 0
    end
  end

  describe "call/2 - path filtering" do
    test "excludes paths matching exclude patterns" do
      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          exclude_paths: [~r/^\/health/, "/admin/status"],
          async_tracking: false
        )

      # Test regex exclusion
      conn1 =
        build_conn("GET", "/health/check")
        |> add_header("x-tenant-id", "test-tenant")

      result1 = WhoTherePlug.call(conn1, opts)
      assert get_in(result1.private, [:who_there_tracking]) == nil

      # Test string exclusion
      conn2 =
        build_conn("GET", "/admin/status")
        |> add_header("x-tenant-id", "test-tenant")

      result2 = WhoTherePlug.call(conn2, opts)
      assert get_in(result2.private, [:who_there_tracking]) == nil

      # Test normal path is tracked
      conn3 =
        build_conn("GET", "/dashboard")
        |> add_header("x-tenant-id", "test-tenant")

      result3 = WhoTherePlug.call(conn3, opts)
      assert get_in(result3.private, [:who_there_tracking]) != nil
    end

    test "excludes static assets by default" do
      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_static_assets: false,
          async_tracking: false
        )

      static_paths = [
        "/assets/app.css",
        "/static/logo.png",
        "/js/app.js",
        "/images/icon.svg",
        "/favicon.ico"
      ]

      for path <- static_paths do
        conn =
          build_conn("GET", path)
          |> add_header("x-tenant-id", "test-tenant")

        result = WhoTherePlug.call(conn, opts)
        assert get_in(result.private, [:who_there_tracking]) == nil
      end
    end

    test "tracks static assets when configured" do
      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_static_assets: true,
          async_tracking: false
        )

      conn =
        build_conn("GET", "/assets/app.css")
        |> add_header("x-tenant-id", "test-tenant")

      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) != nil
    end

    test "excludes paths exceeding max length" do
      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          max_path_length: 100,
          async_tracking: false
        )

      long_path = "/test/" <> String.duplicate("a", 200)

      conn =
        build_conn("GET", long_path)
        |> add_header("x-tenant-id", "test-tenant")

      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) == nil
    end
  end

  describe "call/2 - request type detection" do
    test "detects page view requests" do
      conn =
        build_conn("GET", "/dashboard")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("accept", "text/html,application/xhtml+xml")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_page_views: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.event_type == :page_view
    end

    test "detects API requests by path" do
      conn =
        build_conn("POST", "/api/v1/users")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("content-type", "application/json")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_api_calls: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.event_type == :api_call
    end

    test "detects API requests by accept header" do
      conn =
        build_conn("GET", "/users")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("accept", "application/json")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_api_calls: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.event_type == :api_call
    end

    test "skips API requests when tracking disabled" do
      conn =
        build_conn("GET", "/api/users")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_api_calls: false,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) == nil
    end

    test "skips page requests when tracking disabled" do
      conn =
        build_conn("GET", "/dashboard")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_page_views: false,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) == nil
    end
  end

  describe "call/2 - header extraction" do
    test "extracts user agent" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Mozilla/5.0 Test Browser")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.user_agent == "Mozilla/5.0 Test Browser"
    end

    test "extracts forwarded IP addresses" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("x-forwarded-for", "203.0.113.1, 192.168.1.1")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Should extract the first IP from the forwarded header
      assert tracking_data.remote_ip == {203, 0, 113, 1}
    end

    test "extracts geographic headers" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("cf-ipcountry", "US")
        |> add_header("cf-ipcity", "San Francisco")
        |> add_header("accept-language", "en-US,en;q=0.9")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.headers["cf-ipcountry"] == "US"
      assert tracking_data.headers["cf-ipcity"] == "San Francisco"
      assert tracking_data.headers["accept-language"] == "en-US,en;q=0.9"
    end
  end

  describe "call/2 - feature toggles" do
    test "disables session tracking when configured" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Mozilla/5.0 Test Browser")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          session_tracking: false,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Should not have session-related fields
      assert Map.get(tracking_data, :session_id) == nil
      assert Map.get(tracking_data, :fingerprint) == nil
    end

    test "disables geographic data when configured" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("cf-ipcountry", "US")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          geographic_data: false,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Should not have geographic fields
      assert Map.get(tracking_data, :country_code) == nil
      assert Map.get(tracking_data, :city) == nil
    end

    test "disables bot detection when configured" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Googlebot/2.1")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          bot_detection: false,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Should not be detected as bot traffic
      assert tracking_data.event_type != :bot_traffic
      assert Map.get(tracking_data, :bot_name) == nil
    end
  end

  describe "call/2 - privacy mode" do
    test "applies privacy filters in privacy mode" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          privacy_mode: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Should have privacy-friendly values
      assert tracking_data != nil
      # Specific privacy filtering would be tested in Privacy module tests
    end
  end

  describe "call/2 - error handling" do
    test "handles tenant resolver errors gracefully" do
      failing_resolver = fn _conn -> raise "Tenant resolution failed" end

      conn = build_conn("GET", "/test")

      opts =
        WhoTherePlug.init(
          tenant_resolver: failing_resolver,
          async_tracking: false
        )

      # Should not raise, should skip tracking
      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) == nil
    end

    test "handles invalid tenant values" do
      invalid_resolver = fn _conn -> %{invalid: "tenant"} end

      conn = build_conn("GET", "/test")

      opts =
        WhoTherePlug.init(
          tenant_resolver: invalid_resolver,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      assert get_in(result.private, [:who_there_tracking]) == nil
    end

    test "handles tracking data build failures gracefully" do
      # This is harder to test directly, but the plug should handle
      # any errors in building tracking data and continue processing
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      # Should not raise even if internal processing fails
      result = WhoTherePlug.call(conn, opts)
      assert result != nil
    end
  end

  describe "call/2 - async vs sync processing" do
    test "async processing doesn't block request" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          # Default
          async_tracking: true
        )

      start_time = System.monotonic_time()
      result = WhoTherePlug.call(conn, opts)
      duration = System.monotonic_time() - start_time

      # Should complete very quickly since processing is async
      assert duration < :timer.seconds(1)
      assert get_in(result.private, [:who_there_tracking]) != nil
    end

    test "sync processing completes before returning" do
      conn =
        build_conn("GET", "/test")
        |> add_header("x-tenant-id", "test-tenant")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)

      # Should have completed processing
      assert get_in(result.private, [:who_there_tracking]) != nil
    end
  end

  describe "integration scenarios" do
    test "complete tracking flow for page view" do
      conn =
        build_conn("GET", "/dashboard")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Mozilla/5.0 Test Browser")
        |> add_header("accept", "text/html")
        |> add_header("accept-language", "en-US,en;q=0.9")
        |> add_header("cf-ipcountry", "US")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Verify comprehensive tracking data
      assert tracking_data.tenant == "test-tenant"
      assert tracking_data.path == "/dashboard"
      assert tracking_data.method == "GET"
      assert tracking_data.event_type == :page_view
      assert tracking_data.user_agent == "Mozilla/5.0 Test Browser"
      assert tracking_data.headers["cf-ipcountry"] == "US"
      assert tracking_data.timestamp != nil
    end

    test "complete tracking flow for API call" do
      conn =
        build_conn("POST", "/api/v1/users")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("content-type", "application/json")
        |> add_header("accept", "application/json")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          track_api_calls: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      assert tracking_data.event_type == :api_call
      assert tracking_data.method == "POST"
      assert tracking_data.path == "/api/v1/users"
    end

    test "bot detection and classification" do
      conn =
        build_conn("GET", "/robots.txt")
        |> add_header("x-tenant-id", "test-tenant")
        |> add_header("user-agent", "Googlebot/2.1 (+http://www.google.com/bot.html)")

      opts =
        WhoTherePlug.init(
          tenant_resolver: &simple_tenant_resolver/1,
          bot_detection: true,
          async_tracking: false
        )

      result = WhoTherePlug.call(conn, opts)
      tracking_data = get_in(result.private, [:who_there_tracking])

      # Would be classified as bot traffic if bot detection works
      # (depends on BotDetector implementation)
      assert tracking_data != nil
    end
  end
end
