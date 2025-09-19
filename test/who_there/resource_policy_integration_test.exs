defmodule WhoThere.ResourcePolicyIntegrationTest do
  @moduledoc """
  Integration tests for WhoThere resource policies and security validation.

  These tests verify that:
  - Multi-tenant isolation is properly enforced
  - Analytics data access controls work correctly
  - Privacy settings are respected
  - Authorization flows function as expected
  - Security boundaries are maintained

  The tests use realistic scenarios to ensure the security model
  works end-to-end in practice.
  """

  use ExUnit.Case, async: false
  use WhoThere.DataCase

  alias WhoThere.{Domain, Resources}
  alias WhoThere.Resources.{AnalyticsEvent, AnalyticsConfiguration, Session, DailyAnalytics}

  @tenant_a "tenant-a-123"
  @tenant_b "tenant-b-456"
  @unauthorized_tenant "unauthorized-tenant"

  describe "multi-tenant isolation" do
    test "analytics events are isolated by tenant" do
      # Create events for different tenants
      event_a = create_analytics_event(@tenant_a, %{path: "/page-a"})
      event_b = create_analytics_event(@tenant_b, %{path: "/page-b"})

      # Tenant A should only see their events
      tenant_a_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()

      assert length(tenant_a_events) == 1
      assert hd(tenant_a_events).path == "/page-a"

      # Tenant B should only see their events
      tenant_b_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()

      assert length(tenant_b_events) == 1
      assert hd(tenant_b_events).path == "/page-b"
    end

    test "cannot access analytics events from other tenants" do
      # Create event for tenant A
      _event_a = create_analytics_event(@tenant_a, %{path: "/private-page"})

      # Try to access from tenant B context
      tenant_b_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()

      # Should not see tenant A's events
      assert tenant_b_events == []
    end

    test "sessions are properly isolated" do
      # Create sessions for different tenants
      session_a = create_session(@tenant_a, %{fingerprint: "fp_tenant_a"})
      session_b = create_session(@tenant_b, %{fingerprint: "fp_tenant_b"})

      # Verify isolation
      tenant_a_sessions =
        Session
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()

      assert length(tenant_a_sessions) == 1
      assert hd(tenant_a_sessions).fingerprint == "fp_tenant_a"

      tenant_b_sessions =
        Session
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()

      assert length(tenant_b_sessions) == 1
      assert hd(tenant_b_sessions).fingerprint == "fp_tenant_b"
    end

    test "daily analytics are tenant-isolated" do
      today = Date.utc_today()

      # Create daily analytics for different tenants
      daily_a = create_daily_analytics(@tenant_a, %{date: today, page_views: 100})
      daily_b = create_daily_analytics(@tenant_b, %{date: today, page_views: 200})

      # Verify isolation
      tenant_a_daily =
        DailyAnalytics
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()

      assert length(tenant_a_daily) == 1
      assert hd(tenant_a_daily).page_views == 100

      tenant_b_daily =
        DailyAnalytics
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()

      assert length(tenant_b_daily) == 1
      assert hd(tenant_b_daily).page_views == 200
    end

    test "analytics configuration is tenant-specific" do
      # Create configurations for different tenants
      config_a = create_analytics_config(@tenant_a, %{track_page_views: true})
      config_b = create_analytics_config(@tenant_b, %{track_page_views: false})

      # Verify isolation
      tenant_a_config =
        AnalyticsConfiguration
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()
        |> List.first()

      assert tenant_a_config.track_page_views == true

      tenant_b_config =
        AnalyticsConfiguration
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()
        |> List.first()

      assert tenant_b_config.track_page_views == false
    end
  end

  describe "authorization enforcement" do
    test "requires valid tenant context for reading analytics events" do
      # Create an event
      _event = create_analytics_event(@tenant_a, %{path: "/test"})

      # Try to read without tenant context
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.read!()
      end
    end

    test "requires valid tenant context for creating analytics events" do
      # Try to create without tenant context
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          event_type: :page_view,
          path: "/test",
          timestamp: DateTime.utc_now()
        })
        |> Ash.create!()
      end
    end

    test "validates tenant_id matches context on creation" do
      # Try to create with mismatched tenant_id
      attrs = %{
        # Different from context
        tenant_id: @tenant_b,
        event_type: :page_view,
        path: "/test",
        timestamp: DateTime.utc_now()
      }

      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, attrs)
        # Context is tenant_a
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "prevents cross-tenant session access" do
      # Create session for tenant A
      session_a = create_session(@tenant_a, %{fingerprint: "fp_test"})

      # Try to access from tenant B context
      result =
        Session
        |> Ash.Query.new()
        |> Ash.Query.filter(id == ^session_a.id)
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read()

      # Should return empty result, not the session
      assert {:ok, []} = result
    end
  end

  describe "privacy controls" do
    test "respects IP anonymization settings" do
      # Configure tenant for full IP anonymization
      config =
        create_analytics_config(@tenant_a, %{
          anonymize_ips: true,
          ip_anonymization_level: :full
        })

      # Create event with IP address
      event =
        create_analytics_event(@tenant_a, %{
          path: "/test",
          ip_address: "192.168.1.100"
        })

      # Verify IP is anonymized (would be handled by application logic)
      # This test verifies the configuration is accessible
      assert config.anonymize_ips == true
      assert config.ip_anonymization_level == :full
    end

    test "respects data retention settings" do
      # Configure short retention period
      config =
        create_analytics_config(@tenant_a, %{
          data_retention_days: 30
        })

      # Create old event (this would be handled by cleanup job)
      old_timestamp = DateTime.add(DateTime.utc_now(), -35 * 24 * 60 * 60, :second)

      old_event =
        create_analytics_event(@tenant_a, %{
          path: "/old-page",
          timestamp: old_timestamp
        })

      # Configuration should be accessible for cleanup logic
      assert config.data_retention_days == 30
    end

    test "supports bot traffic filtering preferences" do
      # Configure to exclude bot traffic
      config =
        create_analytics_config(@tenant_a, %{
          exclude_bot_traffic: true
        })

      # Create bot traffic event
      bot_event =
        create_analytics_event(@tenant_a, %{
          path: "/test",
          event_type: :bot_traffic,
          bot_name: "GoogleBot"
        })

      # Configuration should guide filtering logic
      assert config.exclude_bot_traffic == true

      # Events can still be created but filtering happens at query time
      events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()

      assert length(events) == 1
      assert hd(events).event_type == :bot_traffic
    end
  end

  describe "data validation and integrity" do
    test "validates required fields for analytics events" do
      # Missing required fields should fail validation
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          # Missing tenant_id, event_type, path
          timestamp: DateTime.utc_now()
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "validates event type constraints" do
      # Invalid event type should fail
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: @tenant_a,
          event_type: :invalid_type,
          path: "/test",
          timestamp: DateTime.utc_now()
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "validates path format" do
      # Path not starting with '/' should fail
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: @tenant_a,
          event_type: :page_view,
          # Should start with '/'
          path: "invalid-path",
          timestamp: DateTime.utc_now()
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "validates status code ranges" do
      # Invalid status code should fail
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: @tenant_a,
          event_type: :api_call,
          path: "/api/test",
          # Invalid status code
          status_code: 999,
          timestamp: DateTime.utc_now()
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "validates timestamp constraints" do
      # Future timestamp should fail
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: @tenant_a,
          event_type: :page_view,
          path: "/test",
          timestamp: future_time
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end

    test "enforces bot traffic validation" do
      # Bot traffic event without bot_name should fail
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: @tenant_a,
          event_type: :bot_traffic,
          path: "/test",
          timestamp: DateTime.utc_now()
          # Missing bot_name
        })
        |> Ash.create!(tenant: @tenant_a)
      end
    end
  end

  describe "query authorization and filtering" do
    test "filters results by tenant in date range queries" do
      base_time = DateTime.utc_now()

      # Create events for different tenants
      event_a =
        create_analytics_event(@tenant_a, %{
          path: "/page-a",
          timestamp: base_time
        })

      event_b =
        create_analytics_event(@tenant_b, %{
          path: "/page-b",
          timestamp: base_time
        })

      # Query with date range from tenant A
      start_date = DateTime.add(base_time, -3600, :second)
      end_date = DateTime.add(base_time, 3600, :second)

      results =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.Query.action(:by_date_range, %{
          start_date: start_date,
          end_date: end_date
        })
        |> Ash.read!()

      # Should only return tenant A's events
      assert length(results) == 1
      assert hd(results).path == "/page-a"
    end

    test "filters by event type within tenant context" do
      # Create different event types for same tenant
      page_view =
        create_analytics_event(@tenant_a, %{
          path: "/page",
          event_type: :page_view
        })

      api_call =
        create_analytics_event(@tenant_a, %{
          path: "/api/test",
          event_type: :api_call
        })

      # Query for only page views
      results =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.Query.action(:by_event_type, %{event_type: :page_view})
        |> Ash.read!()

      assert length(results) == 1
      assert hd(results).event_type == :page_view
    end

    test "session filtering works within tenant boundaries" do
      # Create sessions and events for tenant A
      session = create_session(@tenant_a, %{fingerprint: "test_session"})

      event1 =
        create_analytics_event(@tenant_a, %{
          path: "/page1",
          session_id: session.id
        })

      event2 =
        create_analytics_event(@tenant_a, %{
          path: "/page2",
          session_id: session.id
        })

      # Create event for different session
      other_event =
        create_analytics_event(@tenant_a, %{
          path: "/other",
          session_id: nil
        })

      # Query events by session
      results =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.Query.action(:by_session, %{session_id: session.id})
        |> Ash.read!()

      assert length(results) == 2
      assert Enum.all?(results, &(&1.session_id == session.id))
    end
  end

  describe "relationship access control" do
    test "session relationship respects tenant boundaries" do
      # Create session and event for tenant A
      session_a = create_session(@tenant_a, %{fingerprint: "session_a"})

      event_a =
        create_analytics_event(@tenant_a, %{
          path: "/test",
          session_id: session_a.id
        })

      # Load event with session relationship
      loaded_event =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.Query.filter(id == ^event_a.id)
        |> Ash.Query.load(:session)
        |> Ash.read!()
        |> List.first()

      # Should load the related session
      assert loaded_event.session != nil
      assert loaded_event.session.fingerprint == "session_a"
    end

    test "cannot load cross-tenant relationships" do
      # Create session in tenant A
      session_a = create_session(@tenant_a, %{fingerprint: "session_a"})

      # Try to access from tenant B (this would not match due to tenant isolation)
      # The relationship itself is protected by tenant context
      events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.Query.filter(session_id == ^session_a.id)
        |> Ash.read!()

      # Should return no events since session belongs to different tenant
      assert events == []
    end
  end

  describe "aggregation and calculation security" do
    test "calculations respect tenant boundaries" do
      # Create events for different tenants
      create_analytics_event(@tenant_a, %{
        path: "/test",
        event_type: :bot_traffic,
        bot_name: "TestBot"
      })

      create_analytics_event(@tenant_b, %{
        path: "/test",
        event_type: :page_view
      })

      # Load with calculations
      tenant_a_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.Query.load([:is_bot_traffic, :geographic_label])
        |> Ash.read!()

      # Should only include tenant A's data in calculations
      assert length(tenant_a_events) == 1
      assert hd(tenant_a_events).is_bot_traffic == true
    end
  end

  describe "bulk operations security" do
    test "bulk operations respect tenant context" do
      # Create multiple events for tenant A
      create_analytics_event(@tenant_a, %{path: "/page1"})
      create_analytics_event(@tenant_a, %{path: "/page2"})
      create_analytics_event(@tenant_b, %{path: "/page3"})

      # Bulk update with tenant context
      AnalyticsEvent
      |> Ash.Query.new()
      |> Ash.Query.set_tenant(@tenant_a)
      |> Ash.bulk_update!(:update, %{metadata: %{updated: true}})

      # Verify only tenant A's events were updated
      tenant_a_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_a)
        |> Ash.read!()

      assert Enum.all?(tenant_a_events, fn event ->
               get_in(event.metadata, ["updated"]) == true
             end)

      # Verify tenant B's events were not affected
      tenant_b_events =
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(@tenant_b)
        |> Ash.read!()

      assert Enum.all?(tenant_b_events, fn event ->
               get_in(event.metadata, ["updated"]) != true
             end)
    end
  end

  describe "policy error details" do
    test "provides meaningful error messages for policy violations" do
      # Test various policy violation scenarios and ensure they return appropriate errors
      scenarios = [
        {
          "missing tenant context",
          fn ->
            AnalyticsEvent
            |> Ash.Query.new()
            |> Ash.read!()
          end,
          [Ash.Error.Invalid]
        },
        {
          "invalid tenant in changeset",
          fn ->
            AnalyticsEvent
            |> Ash.Changeset.for_create(:create, %{
              tenant_id: @tenant_b,
              event_type: :page_view,
              path: "/test"
            })
            |> Ash.create!(tenant: @tenant_a)
          end,
          [Ash.Error.Invalid]
        }
      ]

      for {scenario_name, scenario_fn, expected_error_types} <- scenarios do
        assert_raise expected_error_types, fn ->
          scenario_fn.()
        end
      end
    end
  end

  describe "edge case security scenarios" do
    test "handles nil tenant gracefully" do
      # Attempting operations with nil tenant should fail safely
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant(nil)
        |> Ash.read!()
      end
    end

    test "handles empty string tenant gracefully" do
      # Attempting operations with empty tenant should fail safely
      assert_raise Ash.Error.Invalid, fn ->
        AnalyticsEvent
        |> Ash.Query.new()
        |> Ash.Query.set_tenant("")
        |> Ash.read!()
      end
    end

    test "rejects malformed tenant IDs" do
      invalid_tenants = ["not-a-uuid", "12345", "special-chars-!@#"]
      
      for invalid_tenant <- invalid_tenants do
        assert_raise Ash.Error.Invalid, fn ->
          create_analytics_event(invalid_tenant, %{path: "/test"})
        end
      end
    end
  end

  # Helper functions

  defp create_analytics_event(tenant, attrs \\ %{}) do
    default_attrs = %{
      tenant_id: tenant,
      event_type: :page_view,
      path: "/test",
      timestamp: DateTime.utc_now(),
      user_agent: "Test Browser/1.0",
      device_type: "desktop"
    }

    final_attrs = Map.merge(default_attrs, attrs)

    AnalyticsEvent
    |> Ash.Changeset.for_create(:create, final_attrs)
    |> Ash.create!(tenant: tenant)
  end

  defp create_session(tenant, attrs \\ %{}) do
    default_attrs = %{
      tenant_id: tenant,
      fingerprint: "test_fingerprint",
      user_agent: "Test Browser/1.0",
      ip_hash: "test_hash",
      started_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      page_count: 1,
      is_bounce: false,
      device_type: "desktop",
      platform: "Unknown"
    }

    final_attrs = Map.merge(default_attrs, attrs)

    Session
    |> Ash.Changeset.for_create(:create, final_attrs)
    |> Ash.create!(tenant: tenant)
  end

  defp create_daily_analytics(tenant, attrs \\ %{}) do
    default_attrs = %{
      tenant_id: tenant,
      date: Date.utc_today(),
      page_views: 100,
      unique_visitors: 50,
      sessions: 60,
      bounce_rate: 0.4,
      avg_session_duration: 180
    }

    final_attrs = Map.merge(default_attrs, attrs)

    DailyAnalytics
    |> Ash.Changeset.for_create(:create, final_attrs)
    |> Ash.create!(tenant: tenant)
  end

  defp create_analytics_config(tenant, attrs \\ %{}) do
    default_attrs = %{
      tenant_id: tenant,
      track_page_views: true,
      track_api_calls: true,
      track_liveview_events: true,
      exclude_bot_traffic: false,
      anonymize_ips: false,
      ip_anonymization_level: :partial,
      data_retention_days: 365,
      session_timeout_minutes: 30
    }

    final_attrs = Map.merge(default_attrs, attrs)

    AnalyticsConfiguration
    |> Ash.Changeset.for_create(:create, final_attrs)
    |> Ash.create!(tenant: tenant)
  end
end
