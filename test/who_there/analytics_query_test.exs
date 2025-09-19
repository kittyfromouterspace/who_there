defmodule WhoThere.AnalyticsQueryTest do
  use ExUnit.Case, async: true
  use WhoThere.DataCase

  alias WhoThere.AnalyticsQuery
  alias WhoThere.Resources.AnalyticsEvent

  describe "page_views/1" do
    test "requires tenant parameter" do
      opts = [
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:error, :tenant_required} = AnalyticsQuery.page_views(opts)
    end

    test "requires date range parameters" do
      opts = [tenant: "test-tenant"]

      assert {:error, :date_range_required} = AnalyticsQuery.page_views(opts)
    end

    test "validates date range order" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-31 23:59:59Z],
        end_date: ~U[2023-01-01 00:00:00Z]
      ]

      assert {:error, :invalid_date_range} = AnalyticsQuery.page_views(opts)
    end

    test "returns page view analytics grouped by day" do
      tenant = "test-tenant"
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-03 23:59:59Z]

      # Create test events
      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/page1", "session1"},
        {~U[2023-01-01 11:00:00Z], "/page2", "session1"},
        {~U[2023-01-01 12:00:00Z], "/page1", "session2"},
        {~U[2023-01-02 10:00:00Z], "/page1", "session3"},
        {~U[2023-01-02 11:00:00Z], "/page3", "session3"}
      ])

      opts = [
        tenant: tenant,
        start_date: start_date,
        end_date: end_date,
        group_by: :day
      ]

      assert {:ok, results} = AnalyticsQuery.page_views(opts)
      assert length(results) == 2

      # Check first day
      day1 = Enum.find(results, &(&1.date == ~D[2023-01-01]))
      assert day1.views == 3
      assert day1.unique_sessions == 2

      # Check second day
      day2 = Enum.find(results, &(&1.date == ~D[2023-01-02]))
      assert day2.views == 2
      assert day2.unique_sessions == 1
    end

    test "filters by path pattern when provided" do
      tenant = "test-tenant"
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-01 23:59:59Z]

      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/admin/dashboard", "session1"},
        {~U[2023-01-01 11:00:00Z], "/admin/users", "session1"},
        {~U[2023-01-01 12:00:00Z], "/public/page", "session2"}
      ])

      opts = [
        tenant: tenant,
        start_date: start_date,
        end_date: end_date,
        path_pattern: "admin",
        group_by: :day
      ]

      assert {:ok, results} = AnalyticsQuery.page_views(opts)
      assert length(results) == 1

      day_result = List.first(results)
      assert day_result.views == 2
      assert day_result.unique_sessions == 1
    end

    test "excludes bot traffic by default" do
      tenant = "test-tenant"
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-01 23:59:59Z]

      # Create mixed traffic including bots
      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/page1", "session1", :page_view},
        {~U[2023-01-01 11:00:00Z], "/page2", "session2", :bot_traffic}
      ])

      opts = [
        tenant: tenant,
        start_date: start_date,
        end_date: end_date,
        group_by: :day
      ]

      assert {:ok, results} = AnalyticsQuery.page_views(opts)
      day_result = List.first(results)
      # Only human traffic
      assert day_result.views == 1
    end

    test "includes bot traffic when requested" do
      tenant = "test-tenant"
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-01 23:59:59Z]

      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/page1", "session1", :page_view},
        {~U[2023-01-01 11:00:00Z], "/page2", "session2", :bot_traffic}
      ])

      opts = [
        tenant: tenant,
        start_date: start_date,
        end_date: end_date,
        group_by: :day,
        include_bot_traffic: true
      ]

      assert {:ok, results} = AnalyticsQuery.page_views(opts)
      day_result = List.first(results)
      # Both human and bot traffic
      assert day_result.views == 2
    end

    test "groups by path when requested" do
      tenant = "test-tenant"
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-01 23:59:59Z]

      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/page1", "session1"},
        {~U[2023-01-01 11:00:00Z], "/page1", "session2"},
        {~U[2023-01-01 12:00:00Z], "/page2", "session3"}
      ])

      opts = [
        tenant: tenant,
        start_date: start_date,
        end_date: end_date,
        group_by: :path
      ]

      assert {:ok, results} = AnalyticsQuery.page_views(opts)
      assert length(results) == 2

      # Results should be sorted by views descending
      [first, second] = results
      assert first.path == "/page1"
      assert first.views == 2
      assert second.path == "/page2"
      assert second.views == 1
    end
  end

  describe "user_behavior/1" do
    test "returns comprehensive session analytics structure" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.user_behavior(opts)

      # Verify structure
      assert Map.has_key?(result, :total_sessions)
      assert Map.has_key?(result, :unique_visitors)
      assert Map.has_key?(result, :bounce_rate)
      assert Map.has_key?(result, :avg_session_duration)
      assert Map.has_key?(result, :avg_pages_per_session)
      assert Map.has_key?(result, :segments)

      # Verify types
      assert is_integer(result.total_sessions)
      assert is_integer(result.unique_visitors)
      assert is_float(result.bounce_rate)
      assert is_integer(result.avg_session_duration)
      assert is_float(result.avg_pages_per_session)
      assert is_list(result.segments)
    end
  end

  describe "traffic_sources/1" do
    test "returns traffic source analysis structure" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.traffic_sources(opts)

      # Verify structure
      assert Map.has_key?(result, :direct_traffic)
      assert Map.has_key?(result, :referrers)
      assert Map.has_key?(result, :classified_sources)

      # Verify direct traffic structure
      assert Map.has_key?(result.direct_traffic, :sessions)
      assert Map.has_key?(result.direct_traffic, :percentage)

      # Verify types
      assert is_list(result.referrers)
      assert is_map(result.classified_sources)
    end
  end

  describe "geographic_distribution/1" do
    test "validates required parameters" do
      opts = [
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:error, :tenant_required} = AnalyticsQuery.geographic_distribution(opts)
    end

    test "returns geographic analysis for valid parameters" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, _result} = AnalyticsQuery.geographic_distribution(opts)
    end
  end

  describe "device_analytics/1" do
    test "returns device analysis structure" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.device_analytics(opts)

      assert Map.has_key?(result, :devices)
      assert Map.has_key?(result, :platforms)
      assert Map.has_key?(result, :browsers)
    end
  end

  describe "bot_traffic_analysis/1" do
    test "returns bot analysis structure" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.bot_traffic_analysis(opts)

      assert Map.has_key?(result, :total_bot_requests)
      assert Map.has_key?(result, :bot_types)
      assert Map.has_key?(result, :detection_accuracy)
    end
  end

  describe "performance_metrics/1" do
    test "returns performance analysis structure" do
      opts = [
        tenant: "test-tenant",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.performance_metrics(opts)

      assert Map.has_key?(result, :avg_response_time)
      assert Map.has_key?(result, :response_time_percentiles)
      assert Map.has_key?(result, :status_code_distribution)
    end
  end

  describe "comparative_analysis/1" do
    test "validates comparative period parameters" do
      # Missing comparison period
      opts = [
        tenant: "test-tenant",
        current_start: ~U[2023-01-01 00:00:00Z],
        current_end: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:error, :invalid_comparative_period} = AnalyticsQuery.comparative_analysis(opts)
    end

    test "returns comparative analysis for valid periods" do
      opts = [
        tenant: "test-tenant",
        current_start: ~U[2023-02-01 00:00:00Z],
        current_end: ~U[2023-02-28 23:59:59Z],
        comparison_start: ~U[2023-01-01 00:00:00Z],
        comparison_end: ~U[2023-01-31 23:59:59Z]
      ]

      assert {:ok, result} = AnalyticsQuery.comparative_analysis(opts)

      assert Map.has_key?(result, :current)
      assert Map.has_key?(result, :comparison)
      assert Map.has_key?(result, :changes)
    end
  end

  describe "real_time_metrics/1" do
    test "returns real-time analytics" do
      tenant = "test-tenant"

      # Create recent events
      # 30 minutes ago
      recent_time = DateTime.add(DateTime.utc_now(), -30 * 60, :second)

      create_test_events(tenant, [
        {recent_time, "/page1", "session1"},
        {DateTime.add(recent_time, 5 * 60, :second), "/page2", "session1"},
        {DateTime.add(recent_time, 10 * 60, :second), "/page1", "session2"}
      ])

      opts = [tenant: tenant, window_minutes: 60]

      assert {:ok, result} = AnalyticsQuery.real_time_metrics(opts)

      assert Map.has_key?(result, :active_sessions)
      assert Map.has_key?(result, :page_views)
      assert Map.has_key?(result, :top_pages)
      assert Map.has_key?(result, :recent_activity)

      assert result.active_sessions == 2
      assert result.page_views == 3
      assert is_list(result.top_pages)
      assert is_list(result.recent_activity)
    end

    test "excludes bot traffic from real-time metrics" do
      tenant = "test-tenant"
      recent_time = DateTime.add(DateTime.utc_now(), -30 * 60, :second)

      create_test_events(tenant, [
        {recent_time, "/page1", "session1", :page_view},
        {DateTime.add(recent_time, 5 * 60, :second), "/page2", "session2", :bot_traffic}
      ])

      opts = [tenant: tenant, window_minutes: 60]

      assert {:ok, result} = AnalyticsQuery.real_time_metrics(opts)

      # Only human sessions
      assert result.active_sessions == 1
      # Only human page views
      assert result.page_views == 1
    end
  end

  describe "custom query building" do
    test "builds basic custom query" do
      query = AnalyticsQuery.build_custom_query()
      assert %Ash.Query{} = query
    end

    test "applies tenant filter" do
      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.filter_by_tenant("test-tenant")

      assert query.tenant == "test-tenant"
    end

    test "applies date range filter" do
      start_date = ~U[2023-01-01 00:00:00Z]
      end_date = ~U[2023-01-31 23:59:59Z]

      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.filter_by_date_range(start_date, end_date)

      # Verify filter is applied (exact structure may vary)
      assert query.filter != nil
    end

    test "applies event type filter" do
      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.filter_by_event_type(:page_view)

      assert query.filter != nil
    end

    test "applies path pattern filter" do
      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.filter_by_path_pattern("/admin")

      assert query.filter != nil
    end

    test "excludes bot traffic" do
      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.exclude_bot_traffic()

      assert query.filter != nil
    end

    test "executes custom query" do
      tenant = "test-tenant"

      create_test_events(tenant, [
        {~U[2023-01-01 10:00:00Z], "/page1", "session1"}
      ])

      query =
        AnalyticsQuery.build_custom_query()
        |> AnalyticsQuery.filter_by_tenant(tenant)
        |> AnalyticsQuery.filter_by_event_type(:page_view)

      assert {:ok, results} = AnalyticsQuery.execute_custom_query(query)
      assert is_list(results)
    end
  end

  # Helper functions

  defp create_test_events(tenant, event_specs) do
    Enum.each(event_specs, fn spec ->
      case spec do
        {timestamp, path, session_id} ->
          create_test_event(tenant, timestamp, path, session_id, :page_view)

        {timestamp, path, session_id, event_type} ->
          create_test_event(tenant, timestamp, path, session_id, event_type)
      end
    end)
  end

  defp create_test_event(tenant, timestamp, path, session_id, event_type) do
    attrs = %{
      tenant_id: tenant,
      event_type: event_type,
      timestamp: timestamp,
      session_id: session_id,
      path: path,
      user_agent: "Test Browser/1.0",
      device_type: "desktop"
    }

    case AnalyticsEvent
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, _event} ->
        :ok

      {:error, error} ->
        flunk("Failed to create test event: #{inspect(error)}")
    end
  end
end
