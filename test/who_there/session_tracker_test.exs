defmodule WhoThere.SessionTrackerTest do
  use ExUnit.Case, async: true
  import WhoThere.TestHelpers

  alias WhoThere.SessionTracker

  describe "generate_fingerprint/1" do
    test "generates consistent fingerprints for same data" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        accept_language: "en-US,en;q=0.9",
        accept_encoding: "gzip, deflate, br",
        screen_resolution: "1920x1080",
        timezone: "America/New_York"
      }

      fingerprint1 = SessionTracker.generate_fingerprint(conn_data)
      fingerprint2 = SessionTracker.generate_fingerprint(conn_data)

      assert fingerprint1 == fingerprint2
      assert String.starts_with?(fingerprint1, "fp_")
      # "fp_" + 16 chars
      assert String.length(fingerprint1) == 19
    end

    test "generates different fingerprints for different data" do
      conn_data1 = %{
        user_agent: "Mozilla/5.0 Chrome",
        accept_language: "en-US"
      }

      conn_data2 = %{
        user_agent: "Mozilla/5.0 Firefox",
        accept_language: "en-GB"
      }

      fingerprint1 = SessionTracker.generate_fingerprint(conn_data1)
      fingerprint2 = SessionTracker.generate_fingerprint(conn_data2)

      assert fingerprint1 != fingerprint2
    end

    test "handles missing data gracefully" do
      conn_data = %{user_agent: "Mozilla/5.0"}

      fingerprint = SessionTracker.generate_fingerprint(conn_data)

      assert is_binary(fingerprint)
      assert String.starts_with?(fingerprint, "fp_")
    end

    test "handles empty data" do
      fingerprint = SessionTracker.generate_fingerprint(%{})

      assert is_binary(fingerprint)
      assert String.starts_with?(fingerprint, "fp_")
    end

    test "normalizes user agent versions" do
      conn_data1 = %{user_agent: "Chrome/91.0.4472.124"}
      conn_data2 = %{user_agent: "Chrome/92.0.4515.107"}

      fingerprint1 = SessionTracker.generate_fingerprint(conn_data1)
      fingerprint2 = SessionTracker.generate_fingerprint(conn_data2)

      # Should be same due to version normalization
      assert fingerprint1 == fingerprint2
    end
  end

  describe "track_session/2" do
    test "creates new session for unknown fingerprint" do
      conn_data = %{
        user_agent: "Mozilla/5.0 Chrome",
        remote_ip: {192, 168, 1, 100},
        accept_language: "en-US"
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.fingerprint == SessionTracker.generate_fingerprint(conn_data)
      assert session.user_agent == "Mozilla/5.0 Chrome"
      assert session.page_count == 1
      assert session.is_bounce == true
      assert session.device_type == "desktop"
      assert session.platform == "Unknown"
    end

    test "detects mobile devices" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) Mobile",
        remote_ip: {192, 168, 1, 100}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.device_type == "mobile"
      assert session.platform == "iOS"
    end

    test "detects Android devices" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (Linux; Android 11) Mobile",
        remote_ip: {192, 168, 1, 100}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.device_type == "mobile"
      assert session.platform == "Android"
    end

    test "detects tablets" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (iPad; CPU OS 14_6 like Mac OS X)",
        remote_ip: {192, 168, 1, 100}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.device_type == "tablet"
      assert session.platform == "iOS"
    end

    test "detects Windows platform" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        remote_ip: {192, 168, 1, 100}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.platform == "Windows"
    end

    test "detects macOS platform" do
      conn_data = %{
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        remote_ip: {192, 168, 1, 100}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.platform == "macOS"
    end
  end

  describe "is_bounce?/2" do
    test "identifies bounce sessions with single page view" do
      session = %{
        page_count: 1,
        started_at: DateTime.utc_now() |> DateTime.add(-15, :second),
        last_seen_at: DateTime.utc_now()
      }

      assert SessionTracker.is_bounce?(session) == true
    end

    test "identifies non-bounce with multiple page views" do
      session = %{
        page_count: 3,
        started_at: DateTime.utc_now() |> DateTime.add(-15, :second),
        last_seen_at: DateTime.utc_now()
      }

      assert SessionTracker.is_bounce?(session) == false
    end

    test "identifies non-bounce with long single page session" do
      session = %{
        page_count: 1,
        started_at: DateTime.utc_now() |> DateTime.add(-60, :second),
        last_seen_at: DateTime.utc_now()
      }

      assert SessionTracker.is_bounce?(session, 30) == false
    end

    test "uses custom threshold" do
      session = %{
        page_count: 1,
        started_at: DateTime.utc_now() |> DateTime.add(-45, :second),
        last_seen_at: DateTime.utc_now()
      }

      assert SessionTracker.is_bounce?(session, 30) == false
      assert SessionTracker.is_bounce?(session, 60) == true
    end
  end

  describe "session_duration/1" do
    test "calculates duration correctly" do
      started = DateTime.utc_now() |> DateTime.add(-120, :second)
      last_seen = DateTime.utc_now()

      session = %{
        started_at: started,
        last_seen_at: last_seen
      }

      duration = SessionTracker.session_duration(session)
      # Allow for small timing differences
      assert duration >= 115 and duration <= 125
    end

    test "returns 0 for invalid session data" do
      assert SessionTracker.session_duration(%{}) == 0
      assert SessionTracker.session_duration(nil) == 0
    end
  end

  describe "update_session_activity/3" do
    test "returns error for non-existent session" do
      assert {:error, :session_not_found} =
               SessionTracker.update_session_activity("invalid_id", "test_tenant")
    end

    # Note: Full testing would require the Session resource to be available
    # These are placeholder tests for the current implementation
  end

  describe "expire_sessions/2" do
    test "returns success with count" do
      assert {:ok, expired_count: count} = SessionTracker.expire_sessions("test_tenant")
      assert is_integer(count)
    end

    test "uses custom timeout" do
      assert {:ok, expired_count: count} = SessionTracker.expire_sessions("test_tenant", 60)
      assert is_integer(count)
    end
  end

  describe "presence_data/1" do
    test "creates presence data from session" do
      session = %{
        session_id: "session_123",
        fingerprint: "fp_abc123",
        device_type: "mobile",
        platform: "iOS",
        last_seen_at: DateTime.utc_now()
      }

      presence_data = SessionTracker.presence_data(session)

      assert presence_data.session_id == "session_123"
      assert presence_data.fingerprint == "fp_abc123"
      assert presence_data.device_type == "mobile"
      assert presence_data.platform == "iOS"
      assert %DateTime{} = presence_data.joined_at
      assert presence_data.last_seen == session.last_seen_at
    end
  end

  describe "detect_related_sessions/3" do
    test "returns empty list for now" do
      session = %{fingerprint: "fp_test"}

      assert {:ok, related} =
               SessionTracker.detect_related_sessions(session, "test_tenant")

      assert related == []
    end

    test "accepts custom time window" do
      session = %{fingerprint: "fp_test"}

      assert {:ok, related} =
               SessionTracker.detect_related_sessions(session, "test_tenant",
                 time_window_hours: 48
               )

      assert related == []
    end
  end

  describe "validate_session_privacy/1" do
    test "passes validation for clean session data" do
      session_data = %{
        user_agent: "Mozilla/5.0 (clean user agent)",
        fingerprint: "fp_clean123"
      }

      assert SessionTracker.validate_session_privacy(session_data) == :ok
    end

    test "detects PII in user agent" do
      session_data = %{
        user_agent: "Mozilla/5.0 (contains email@example.com)"
      }

      assert {:error, violations} = SessionTracker.validate_session_privacy(session_data)
      assert :pii_in_user_agent in violations
    end

    test "detects tracking identifiers" do
      session_data = %{
        user_agent: "Mozilla/5.0 FBAV/123.0 Mobile"
      }

      assert {:error, violations} = SessionTracker.validate_session_privacy(session_data)
      assert :tracking_identifiers in violations
    end

    test "detects Instagram app" do
      session_data = %{
        user_agent: "Instagram 123.0 (iPhone)"
      }

      assert {:error, violations} = SessionTracker.validate_session_privacy(session_data)
      assert :tracking_identifiers in violations
    end

    test "detects multiple violations" do
      session_data = %{
        user_agent: "Instagram app with user@email.com"
      }

      assert {:error, violations} = SessionTracker.validate_session_privacy(session_data)
      assert :pii_in_user_agent in violations
      assert :tracking_identifiers in violations
    end
  end

  describe "platform and device detection edge cases" do
    test "handles empty user agent" do
      conn_data = %{user_agent: "", remote_ip: {127, 0, 0, 1}}

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.platform == "Unknown"
      assert session.device_type == "unknown"
    end

    test "handles nil user agent" do
      conn_data = %{remote_ip: {127, 0, 0, 1}}

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.platform == "Unknown"
      assert session.device_type == "unknown"
    end

    test "handles complex user agent strings" do
      conn_data = %{
        user_agent:
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        remote_ip: {127, 0, 0, 1}
      }

      assert {:ok, session} = SessionTracker.track_session(conn_data, tenant: "test_tenant")

      assert session.platform == "Linux"
      assert session.device_type == "desktop"
    end
  end

  describe "fingerprint consistency" do
    test "fingerprint remains consistent with varying optional fields" do
      base_data = %{
        user_agent: "Mozilla/5.0 Chrome",
        accept_language: "en-US"
      }

      data_with_extras =
        Map.merge(base_data, %{
          custom_field: "value",
          another_field: 123
        })

      fp1 = SessionTracker.generate_fingerprint(base_data)
      fp2 = SessionTracker.generate_fingerprint(data_with_extras)

      assert fp1 == fp2
    end
  end
end
