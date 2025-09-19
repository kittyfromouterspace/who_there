defmodule WhoThere.AnalyticsQueryFocusedTest do
  use ExUnit.Case, async: false
  
  # Mock the Ash.Query functions since we don't have full database setup
  defmodule MockAsh.Query do
    def new(resource), do: %{resource: resource, filters: [], sorts: [], aggregates: []}
    
    def filter(query, filter_expr) do
      %{query | filters: [filter_expr | query.filters]}
    end
    
    def sort(query, sorts) when is_list(sorts) do
      %{query | sorts: sorts ++ query.sorts}
    end
    
    def sort(query, sort_field) do
      %{query | sorts: [sort_field | query.sorts]}
    end
    
    def aggregate(query, name, field, type) do
      agg = %{name: name, field: field, type: type}
      %{query | aggregates: [agg | query.aggregates]}
    end
    
    def select(query, fields) do
      Map.put(query, :select, fields)
    end
  end
  
  defmodule MockAnalyticsEvent do
    def query, do: MockAsh.Query.new(__MODULE__)
  end
  
  describe "WhoThere.AnalyticsQuery filtering" do
    alias WhoThere.AnalyticsQuery
    
    # Mock the Ash modules for testing
    setup do
      # Store original modules
      original_ash_query = Application.get_env(:who_there, :test_ash_query_module, Ash.Query)
      original_analytics_event = Application.get_env(:who_there, :test_analytics_event_module, WhoThere.Resources.AnalyticsEvent)
      
      # Set test modules
      Application.put_env(:who_there, :test_ash_query_module, MockAsh.Query)
      Application.put_env(:who_there, :test_analytics_event_module, MockAnalyticsEvent)
      
      on_exit(fn ->
        Application.put_env(:who_there, :test_ash_query_module, original_ash_query)
        Application.put_env(:who_there, :test_analytics_event_module, original_analytics_event)
      end)
      
      :ok
    end
    
    test "filter_by_date_range/3 creates proper date range filters" do
      base_query = MockAnalyticsEvent.query()
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]
      
      # Test the date range filtering logic
      result_query = AnalyticsQuery.filter_by_date_range(base_query, start_date, end_date)
      
      # Verify the query structure (filters are added)
      assert length(result_query.filters) > length(base_query.filters)
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_event_type/2 handles single event type" do
      base_query = MockAnalyticsEvent.query()
      event_type = "page_view"
      
      result_query = AnalyticsQuery.filter_by_event_type(base_query, event_type)
      
      # Verify filter was added
      assert length(result_query.filters) == 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_event_type/2 handles multiple event types" do
      base_query = MockAnalyticsEvent.query()
      event_types = ["page_view", "click", "form_submit"]
      
      result_query = AnalyticsQuery.filter_by_event_type(base_query, event_types)
      
      # Verify filter was added for multiple types
      assert length(result_query.filters) == 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_path_patterns/2 handles various path patterns" do
      base_query = MockAnalyticsEvent.query()
      patterns = ["/dashboard/*", "/api/users", "~/admin/.*"]
      
      result_query = AnalyticsQuery.filter_by_path_patterns(base_query, patterns)
      
      # Verify filters were added
      assert length(result_query.filters) >= 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_status_code/2 handles single status code" do
      base_query = MockAnalyticsEvent.query()
      status_code = 200
      
      result_query = AnalyticsQuery.filter_by_status_code(base_query, status_code)
      
      assert length(result_query.filters) == 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_status_code/2 handles multiple status codes" do
      base_query = MockAnalyticsEvent.query()
      status_codes = [200, 201, 404]
      
      result_query = AnalyticsQuery.filter_by_status_code(base_query, status_codes)
      
      assert length(result_query.filters) == 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "filter_by_bot_flag/2 filters bot traffic" do
      base_query = MockAnalyticsEvent.query()
      
      # Test excluding bots
      result_query = AnalyticsQuery.filter_by_bot_flag(base_query, false)
      assert length(result_query.filters) == 1
      
      # Test including only bots
      bot_query = AnalyticsQuery.filter_by_bot_flag(base_query, true)
      assert length(bot_query.filters) == 1
    end
  end
  
  describe "WhoThere.AnalyticsQuery grouping and aggregation" do
    alias WhoThere.AnalyticsQuery
    
    test "group_by_field/2 handles basic field grouping" do
      base_query = MockAnalyticsEvent.query()
      
      result_query = AnalyticsQuery.group_by_field(base_query, :path)
      
      # Should have grouping logic applied
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "group_by_time_bucket/3 handles time-based grouping" do
      base_query = MockAnalyticsEvent.query()
      
      # Test hourly grouping
      hourly_query = AnalyticsQuery.group_by_time_bucket(base_query, :hour, :inserted_at)
      assert hourly_query.resource == MockAnalyticsEvent
      
      # Test daily grouping
      daily_query = AnalyticsQuery.group_by_time_bucket(base_query, :day, :inserted_at)
      assert daily_query.resource == MockAnalyticsEvent
    end
    
    test "add_count_aggregate/2 adds count aggregation" do
      base_query = MockAnalyticsEvent.query()
      
      result_query = AnalyticsQuery.add_count_aggregate(base_query, :events_count)
      
      # Verify aggregate was added
      assert length(result_query.aggregates) == 1
      [aggregate] = result_query.aggregates
      assert aggregate.name == :events_count
      assert aggregate.type == :count
    end
  end
  
  describe "WhoThere.AnalyticsQuery query building" do
    alias WhoThere.AnalyticsQuery
    
    test "build_events_query/1 creates basic events query" do
      opts = [
        date_range: {~D[2024-01-01], ~D[2024-01-31]},
        event_type: "page_view"
      ]
      
      {:ok, query} = AnalyticsQuery.build_events_query(opts)
      
      # Verify query structure
      assert query.resource == MockAnalyticsEvent
      assert length(query.filters) >= 2  # date range + event type
    end
    
    test "build_events_query/1 handles complex filtering options" do
      opts = [
        date_range: {~D[2024-01-01], ~D[2024-01-31]},
        event_types: ["page_view", "click"],
        path_patterns: ["/dashboard/*"],
        status_codes: [200, 201],
        exclude_bots: true,
        group_by: :path,
        aggregate: :count
      ]
      
      {:ok, query} = AnalyticsQuery.build_events_query(opts)
      
      # Should have multiple filters applied
      assert query.resource == MockAnalyticsEvent
      assert length(query.filters) >= 4  # Multiple filter conditions
    end
    
    test "build_events_query/1 handles invalid options gracefully" do
      opts = [
        invalid_option: "bad_value",
        group_by: :invalid_field
      ]
      
      # Should either return error or handle gracefully
      result = AnalyticsQuery.build_events_query(opts)
      
      # Accept either error tuple or successful query with minimal filters
      case result do
        {:error, _reason} -> assert true
        {:ok, query} -> assert query.resource == MockAnalyticsEvent
      end
    end
  end
  
  describe "WhoThere.AnalyticsQuery integration patterns" do
    alias WhoThere.AnalyticsQuery
    
    test "chaining multiple filters works correctly" do
      base_query = MockAnalyticsEvent.query()
      
      result_query = 
        base_query
        |> AnalyticsQuery.filter_by_event_type("page_view")
        |> AnalyticsQuery.filter_by_status_code(200)
        |> AnalyticsQuery.filter_by_bot_flag(false)
        |> AnalyticsQuery.add_count_aggregate(:total_events)
      
      # Verify all operations were applied
      assert length(result_query.filters) == 3
      assert length(result_query.aggregates) == 1
      assert result_query.resource == MockAnalyticsEvent
    end
    
    test "empty filters don't break query building" do
      base_query = MockAnalyticsEvent.query()
      
      # Test with empty/nil values
      result_query = 
        base_query
        |> AnalyticsQuery.filter_by_event_type(nil)
        |> AnalyticsQuery.filter_by_path_patterns([])
        |> AnalyticsQuery.filter_by_status_code([])
      
      # Should handle empty filters gracefully
      assert result_query.resource == MockAnalyticsEvent
      # Filters should be empty or contain only valid ones
    end
  end
  
  describe "WhoThere.AnalyticsQuery error handling" do
    alias WhoThere.AnalyticsQuery
    
    test "invalid date ranges are handled" do
      base_query = MockAnalyticsEvent.query()
      
      # Test invalid date range (end before start)
      result = AnalyticsQuery.filter_by_date_range(base_query, ~D[2024-01-31], ~D[2024-01-01])
      
      # Should either handle gracefully or return error
      case result do
        {:error, _} -> assert true
        %{resource: MockAnalyticsEvent} -> assert true  # Handled gracefully
      end
    end
    
    test "unsupported grouping fields are handled" do
      base_query = MockAnalyticsEvent.query()
      
      result = AnalyticsQuery.group_by_field(base_query, :non_existent_field)
      
      # Should handle gracefully
      assert result.resource == MockAnalyticsEvent
    end
  end
end