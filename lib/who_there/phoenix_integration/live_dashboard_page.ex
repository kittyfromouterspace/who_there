defmodule WhoThere.PhoenixIntegration.LiveDashboardPage do
  @moduledoc """
  Phoenix LiveDashboard integration for WhoThere analytics.
  
  Provides real-time analytics visualization within Phoenix LiveDashboard.
  """
  
  use Phoenix.LiveDashboard.PageBuilder
  import Phoenix.LiveView.Helpers
  alias WhoThere.Analytics
  alias WhoThere.Analytics.DailyAnalytics
  
  @impl true
  def menu_link(_, _) do
    {:ok, "WhoThere Analytics"}
  end

  @impl true
  def render_page(_assigns) do
    nav_bar = [
      {"Overview", "overview"},
      {"Sessions", "sessions"},
      {"Events", "events"},
      {"Performance", "performance"}
    ]

    row_template(
      title: "WhoThere Analytics Dashboard",
      nav_bar: nav_bar
    ) do
      [
        overview_section(),
        sessions_section(),
        events_section(),
        performance_section()
      ]
    end
  end

  @impl true
  def init(opts) do
    {:ok, opts, %{
      # Refresh every 30 seconds
      refresh: 30_000,
      tenant: Keyword.get(opts, :tenant, "default")
    }}
  end

  @impl true
  def handle_refresh(socket) do
    # Force refresh of metrics data
    {:noreply, socket}
  end

  defp overview_section do
    card(
      title: "Analytics Overview",
      hint: "Real-time overview of WhoThere analytics",
      inner_title: "Key Metrics",
      nav_id: "overview"
    ) do
      columns([
        column(
          size: 6,
          components: [overview_stats_component()]
        ),
        column(
          size: 6,
          components: [recent_activity_component()]
        )
      ])
    end
  end

  defp sessions_section do
    card(
      title: "Session Analytics",
      hint: "Session tracking and user behavior metrics",
      inner_title: "Sessions",
      nav_id: "sessions"
    ) do
      columns([
        column(
          size: 12,
          components: [session_metrics_component()]
        )
      ])
    end
  end

  defp events_section do
    card(
      title: "Event Analytics", 
      hint: "Analytics events and tracking data",
      inner_title: "Events",
      nav_id: "events"
    ) do
      columns([
        column(
          size: 6,
          components: [event_type_breakdown_component()]
        ),
        column(
          size: 6,
          components: [recent_events_component()]
        )
      ])
    end
  end

  defp performance_section do
    card(
      title: "Performance Metrics",
      hint: "Phoenix and LiveView performance data",
      inner_title: "Performance",
      nav_id: "performance"
    ) do
      columns([
        column(
          size: 12,
          components: [performance_metrics_component()]
        )
      ])
    end
  end

  defp overview_stats_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.OverviewStats, %{
      tenant: get_current_tenant()
    }}
  end

  defp recent_activity_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.RecentActivity, %{
      tenant: get_current_tenant(),
      limit: 10
    }}
  end

  defp session_metrics_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.SessionMetrics, %{
      tenant: get_current_tenant()
    }}
  end

  defp event_type_breakdown_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.EventTypeBreakdown, %{
      tenant: get_current_tenant()
    }}
  end

  defp recent_events_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.RecentEvents, %{
      tenant: get_current_tenant(),
      limit: 20
    }}
  end

  defp performance_metrics_component do
    {WhoThere.PhoenixIntegration.LiveDashboardComponents.PerformanceMetrics, %{
      tenant: get_current_tenant()
    }}
  end

  defp get_current_tenant do
    # This could be extracted from socket assigns or configuration
    "default"
  end
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.OverviewStats do
  use Phoenix.LiveDashboard.PageBuilder

  def render(assigns) do
    stats = get_overview_stats(assigns.tenant)
    
    ~H"""
    <div class="overview-stats">
      <div class="stat-grid">
        <div class="stat-item">
          <div class="stat-value"><%= stats.total_sessions %></div>
          <div class="stat-label">Total Sessions</div>
        </div>
        <div class="stat-item">
          <div class="stat-value"><%= stats.total_events %></div>
          <div class="stat-label">Total Events</div>
        </div>
        <div class="stat-item">
          <div class="stat-value"><%= stats.active_sessions %></div>
          <div class="stat-label">Active Sessions</div>
        </div>
        <div class="stat-item">
          <div class="stat-value"><%= format_duration(stats.avg_session_duration) %></div>
          <div class="stat-label">Avg Session Duration</div>
        </div>
      </div>
    </div>
    """
  end

  defp get_overview_stats(tenant) do
    today = Date.utc_today()
    
    # This would typically query your analytics data
    %{
      total_sessions: get_total_sessions(tenant, today),
      total_events: get_total_events(tenant, today),
      active_sessions: get_active_sessions(tenant),
      avg_session_duration: get_avg_session_duration(tenant, today)
    }
  end

  defp get_total_sessions(tenant, date) do
    # Mock data - replace with actual Analytics queries
    case Analytics.get_daily_analytics(tenant, date) do
      %DailyAnalytics{unique_visitors: count} -> count
      nil -> 0
    end
  end

  defp get_total_events(tenant, date) do
    # Mock data - replace with actual Analytics queries
    case Analytics.get_daily_analytics(tenant, date) do
      %DailyAnalytics{page_views: count} -> count
      nil -> 0
    end
  end

  defp get_active_sessions(tenant) do
    # Mock data - could query recent sessions within last hour
    42
  end

  defp get_avg_session_duration(tenant, date) do
    # Mock data - replace with actual calculation
    case Analytics.get_daily_analytics(tenant, date) do
      %DailyAnalytics{avg_session_duration: duration} when is_integer(duration) -> duration
      _ -> 0
    end
  end

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp format_duration(_), do: "0s"
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.RecentActivity do
  use Phoenix.LiveDashboard.PageBuilder
  alias WhoThere.Analytics

  def render(assigns) do
    events = get_recent_events(assigns.tenant, assigns.limit)
    
    ~H"""
    <div class="recent-activity">
      <h4>Recent Activity</h4>
      <div class="activity-list">
        <%= for event <- events do %>
          <div class="activity-item">
            <div class="activity-time"><%= format_timestamp(event.timestamp) %></div>
            <div class="activity-type"><%= event.event_type %></div>
            <div class="activity-details"><%= format_event_details(event) %></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_recent_events(tenant, limit) do
    # This would query recent analytics events
    # For now, return mock data
    []
  end

  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_event_details(event) do
    case event.event_type do
      "page_view" -> event.url || "Page view"
      "session_start" -> "New session started"
      _ -> String.capitalize(to_string(event.event_type))
    end
  end
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.SessionMetrics do
  use Phoenix.LiveDashboard.PageBuilder

  def render(assigns) do
    metrics = get_session_metrics(assigns.tenant)
    
    ~H"""
    <div class="session-metrics">
      <div class="metrics-grid">
        <div class="metric-card">
          <h5>Sessions Today</h5>
          <div class="metric-value"><%= metrics.sessions_today %></div>
        </div>
        <div class="metric-card">
          <h5>Bounce Rate</h5>
          <div class="metric-value"><%= metrics.bounce_rate %>%</div>
        </div>
        <div class="metric-card">
          <h5>Avg Pages/Session</h5>
          <div class="metric-value"><%= metrics.avg_pages_per_session %></div>
        </div>
        <div class="metric-card">
          <h5>Return Visitors</h5>
          <div class="metric-value"><%= metrics.return_visitors %>%</div>
        </div>
      </div>
    </div>
    """
  end

  defp get_session_metrics(tenant) do
    # Mock data - replace with actual analytics queries
    %{
      sessions_today: 156,
      bounce_rate: 34.5,
      avg_pages_per_session: 2.8,
      return_visitors: 23.1
    }
  end
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.EventTypeBreakdown do
  use Phoenix.LiveDashboard.PageBuilder

  def render(assigns) do
    breakdown = get_event_type_breakdown(assigns.tenant)
    
    ~H"""
    <div class="event-breakdown">
      <h4>Event Types</h4>
      <div class="breakdown-list">
        <%= for {event_type, count} <- breakdown do %>
          <div class="breakdown-item">
            <span class="event-type"><%= event_type %></span>
            <span class="event-count"><%= count %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_event_type_breakdown(tenant) do
    # Mock data - replace with actual event type queries
    [
      {"page_view", 1234},
      {"session_start", 156},
      {"click", 89},
      {"form_submit", 23}
    ]
  end
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.RecentEvents do
  use Phoenix.LiveDashboard.PageBuilder

  def render(assigns) do
    events = get_recent_events(assigns.tenant, assigns.limit)
    
    ~H"""
    <div class="recent-events">
      <h4>Recent Events</h4>
      <div class="events-table">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Type</th>
              <th>Details</th>
              <th>IP</th>
            </tr>
          </thead>
          <tbody>
            <%= for event <- events do %>
              <tr>
                <td><%= format_time(event.inserted_at) %></td>
                <td><%= event.event_type %></td>
                <td><%= truncate(inspect(event.event_data), 30) %></td>
                <td><%= event.ip_address || "N/A" %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp get_recent_events(tenant, limit) do
    # This would query recent analytics events from the database
    []
  end

  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end

  defp truncate(string, length) do
    if String.length(string) > length do
      String.slice(string, 0, length) <> "..."
    else
      string
    end
  end
end

defmodule WhoThere.PhoenixIntegration.LiveDashboardComponents.PerformanceMetrics do
  use Phoenix.LiveDashboard.PageBuilder

  def render(assigns) do
    metrics = get_performance_metrics(assigns.tenant)
    
    ~H"""
    <div class="performance-metrics">
      <h4>Performance Overview</h4>
      <div class="performance-grid">
        <div class="perf-card">
          <h5>Avg Response Time</h5>
          <div class="perf-value"><%= metrics.avg_response_time %>ms</div>
        </div>
        <div class="perf-card">
          <h5>Slow Requests</h5>
          <div class="perf-value"><%= metrics.slow_requests %></div>
        </div>
        <div class="perf-card">
          <h5>LiveView Mounts</h5>
          <div class="perf-value"><%= metrics.liveview_mounts %></div>
        </div>
        <div class="perf-card">
          <h5>Error Rate</h5>
          <div class="perf-value"><%= metrics.error_rate %>%</div>
        </div>
      </div>
    </div>
    """
  end

  defp get_performance_metrics(tenant) do
    # Mock data - this could integrate with telemetry metrics
    %{
      avg_response_time: 45,
      slow_requests: 3,
      liveview_mounts: 89,
      error_rate: 0.1
    }
  end
end