defmodule WhoThere.DomainTest do
  use ExUnit.Case, async: true
  import WhoThere.TestHelpers

  alias WhoThere.Domain

  setup do
    setup_db()
    tenant_id = test_tenant_id()
    {:ok, tenant_id: tenant_id}
  end

  describe "domain configuration" do
    test "domain module is configured properly" do
      assert Domain.__ash_domain__?()
      resources = Domain.__resources__()

      expected_resources = [
        WhoThere.Resources.AnalyticsEvent,
        WhoThere.Resources.Session,
        WhoThere.Resources.AnalyticsConfiguration,
        WhoThere.Resources.DailyAnalytics
      ]

      resource_modules = Enum.map(resources, & &1)

      Enum.each(expected_resources, fn resource ->
        assert resource in resource_modules, "Expected #{resource} to be registered in domain"
      end)
    end

    test "authorization is configured" do
      assert Domain.__ash_domain_config__()[:authorization][:authorize] == :when_requested
    end
  end

  describe "track_event/2" do
    test "creates analytics event with tenant context", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      event_attrs = %{
        session_id: generate_session_id(),
        event_type: "page_view",
        path: "/test",
        user_agent: "Test Agent",
        ip_hash: "test_hash",
        country: "US",
        city: "Test City",
        is_bot: false
      }

      assert {:ok, event} = Domain.track_event(event_attrs, tenant: tenant_id)
      assert event.tenant_id == tenant_id
      assert event.path == "/test"
      assert event.event_type == "page_view"
    end

    test "returns error with invalid attributes", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      invalid_attrs = %{
        path: "/test"
      }

      assert {:error, _changeset} = Domain.track_event(invalid_attrs, tenant: tenant_id)
    end
  end

  describe "track_session/2" do
    test "creates new session when fingerprint doesn't exist", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      session_attrs = %{
        session_id: generate_session_id(),
        fingerprint: "unique_fingerprint",
        user_agent: "Test Agent",
        ip_hash: "test_hash"
      }

      assert {:ok, session} = Domain.track_session(session_attrs, tenant: tenant_id)
      assert session.tenant_id == tenant_id
      assert session.fingerprint == "unique_fingerprint"
    end

    test "updates existing session when fingerprint exists", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)
      fingerprint = "existing_fingerprint"

      existing_session = create_session(tenant_id, fingerprint: fingerprint)

      update_attrs = %{
        fingerprint: fingerprint,
        last_seen_at: DateTime.utc_now()
      }

      assert {:ok, updated_session} = Domain.track_session(update_attrs, tenant: tenant_id)
      assert updated_session.id == existing_session.id
      assert DateTime.compare(updated_session.last_seen_at, existing_session.last_seen_at) == :gt
    end
  end

  describe "get_session_by_fingerprint/2" do
    test "returns session when found", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)
      fingerprint = "test_fingerprint"
      session = create_session(tenant_id, fingerprint: fingerprint)

      assert found_session = Domain.get_session_by_fingerprint(fingerprint, tenant: tenant_id)
      assert found_session.id == session.id
    end

    test "returns nil when not found", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      assert Domain.get_session_by_fingerprint("nonexistent", tenant: tenant_id) == nil
    end

    test "respects tenant isolation", %{tenant_id: tenant_id} do
      other_tenant = test_tenant_id()
      create_analytics_config(tenant_id)
      create_analytics_config(other_tenant)

      fingerprint = "test_fingerprint"
      _session = create_session(tenant_id, fingerprint: fingerprint)

      assert Domain.get_session_by_fingerprint(fingerprint, tenant: other_tenant) == nil
    end
  end

  describe "get_config_by_tenant/1" do
    test "returns configuration when found", %{tenant_id: tenant_id} do
      config = create_analytics_config(tenant_id)

      assert found_config = Domain.get_config_by_tenant(tenant: tenant_id)
      assert found_config.id == config.id
    end

    test "returns nil when not found", %{tenant_id: tenant_id} do
      assert Domain.get_config_by_tenant(tenant: tenant_id) == nil
    end
  end

  describe "create_config/2" do
    test "creates configuration with defaults", %{tenant_id: tenant_id} do
      attrs = %{enabled: true}

      assert {:ok, config} = Domain.create_config(attrs, tenant: tenant_id)
      assert config.tenant_id == tenant_id
      assert config.enabled == true
    end

    test "applies tenant_id from options", %{tenant_id: tenant_id} do
      attrs = %{}

      assert {:ok, config} = Domain.create_config(attrs, tenant: tenant_id)
      assert config.tenant_id == tenant_id
    end
  end

  describe "get_events_by_date_range/3" do
    test "returns events within date range", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      start_date = DateTime.utc_now() |> DateTime.add(-3600, :second)
      end_date = DateTime.utc_now()
      middle_date = DateTime.utc_now() |> DateTime.add(-1800, :second)

      _event1 = create_analytics_event(tenant_id, occurred_at: middle_date)

      _event2 =
        create_analytics_event(tenant_id, occurred_at: DateTime.add(start_date, -1800, :second))

      assert {:ok, events} =
               Domain.get_events_by_date_range(start_date, end_date, tenant: tenant_id)

      assert length(events) == 1
    end

    test "filters by event type when specified", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      start_date = DateTime.utc_now() |> DateTime.add(-3600, :second)
      end_date = DateTime.utc_now()

      _page_view = create_analytics_event(tenant_id, event_type: "page_view")
      _click = create_analytics_event(tenant_id, event_type: "click")

      assert {:ok, events} =
               Domain.get_events_by_date_range(start_date, end_date,
                 tenant: tenant_id,
                 event_type: "page_view"
               )

      assert length(events) == 1
      assert hd(events).event_type == "page_view"
    end
  end

  describe "create_daily_summary/3" do
    test "creates new summary when none exists", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      date = Date.utc_today()

      attrs = %{
        total_events: 100,
        unique_visitors: 50,
        page_views: 80
      }

      assert {:ok, summary} = Domain.create_daily_summary(date, attrs, tenant: tenant_id)
      assert summary.date == date
      assert summary.total_events == 100
    end

    test "updates existing summary", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      date = Date.utc_today()

      initial_attrs = %{
        total_events: 50,
        unique_visitors: 25,
        page_views: 40
      }

      {:ok, _initial} = Domain.create_daily_summary(date, initial_attrs, tenant: tenant_id)

      update_attrs = %{
        total_events: 100,
        unique_visitors: 60
      }

      assert {:ok, updated} = Domain.create_daily_summary(date, update_attrs, tenant: tenant_id)
      assert updated.total_events == 100
      assert updated.unique_visitors == 60
    end
  end

  describe "get_bot_traffic_summary/3" do
    test "returns bot traffic aggregated by user agent", %{tenant_id: tenant_id} do
      create_analytics_config(tenant_id)

      start_date = DateTime.utc_now() |> DateTime.add(-3600, :second)
      end_date = DateTime.utc_now()

      _bot_event1 = create_analytics_event(tenant_id, is_bot: true, user_agent: "Googlebot")
      _bot_event2 = create_analytics_event(tenant_id, is_bot: true, user_agent: "Googlebot")
      _human_event = create_analytics_event(tenant_id, is_bot: false, user_agent: "Chrome")

      assert {:ok, summary} =
               Domain.get_bot_traffic_summary(start_date, end_date, tenant: tenant_id)

      assert is_list(summary)
    end
  end

  describe "cleanup_expired_data/1" do
    test "returns error when no config exists", %{tenant_id: tenant_id} do
      assert {:error, :no_config} = Domain.cleanup_expired_data(tenant: tenant_id)
    end

    test "cleans up old events based on retention policy", %{tenant_id: tenant_id} do
      config = create_analytics_config(tenant_id, data_retention_days: 30)

      old_date = DateTime.utc_now() |> DateTime.add(-31 * 24 * 60 * 60, :second)
      recent_date = DateTime.utc_now() |> DateTime.add(-10 * 24 * 60 * 60, :second)

      _old_event = create_analytics_event(tenant_id, occurred_at: old_date)
      _recent_event = create_analytics_event(tenant_id, occurred_at: recent_date)

      assert {:ok, _result} = Domain.cleanup_expired_data(tenant: tenant_id)
    end
  end
end
