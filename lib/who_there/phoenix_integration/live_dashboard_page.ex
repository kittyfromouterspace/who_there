if Code.ensure_loaded?(Phoenix.LiveDashboard.PageBuilder) do
  defmodule WhoThere.PhoenixIntegration.LiveDashboardPage do
    @moduledoc """
    Phoenix LiveDashboard integration for WhoThere analytics.
    
    Provides real-time analytics visualization within Phoenix LiveDashboard.
    
    ## Usage
    
    Add to your router:
    
        live_dashboard "/dashboard",
          additional_pages: [
            who_there: WhoThere.PhoenixIntegration.LiveDashboardPage
          ]
    
    Note: This requires `phoenix_live_dashboard` >= 0.8
    """
    
    use Phoenix.LiveDashboard.PageBuilder
    
    @impl true
    def menu_link(_, _) do
      {:ok, "WhoThere Analytics"}
    end
    
    @impl true
    def render(assigns) do
      ~H"""
      <div class="who-there-dashboard">
        <h2>WhoThere Analytics</h2>
        <p>Analytics dashboard coming soon.</p>
        <p>Current tenant: <%= @tenant %></p>
        
        <div class="stats-grid" style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-top: 1rem;">
          <div class="stat-card" style="padding: 1rem; background: #f5f5f5; border-radius: 8px;">
            <div style="font-size: 2rem; font-weight: bold;"><%= @stats.total_sessions %></div>
            <div style="color: #666;">Total Sessions</div>
          </div>
          <div class="stat-card" style="padding: 1rem; background: #f5f5f5; border-radius: 8px;">
            <div style="font-size: 2rem; font-weight: bold;"><%= @stats.total_events %></div>
            <div style="color: #666;">Total Events</div>
          </div>
          <div class="stat-card" style="padding: 1rem; background: #f5f5f5; border-radius: 8px;">
            <div style="font-size: 2rem; font-weight: bold;"><%= @stats.unique_visitors %></div>
            <div style="color: #666;">Unique Visitors</div>
          </div>
          <div class="stat-card" style="padding: 1rem; background: #f5f5f5; border-radius: 8px;">
            <div style="font-size: 2rem; font-weight: bold;"><%= @stats.page_views %></div>
            <div style="color: #666;">Page Views</div>
          </div>
        </div>
      </div>
      """
    end

    @impl true
    def mount(_params, _session, socket) do
      tenant = socket.assigns[:tenant] || "default"
      stats = get_stats(tenant)
      
      {:ok, assign(socket, tenant: tenant, stats: stats)}
    end
    
    @impl true
    def handle_refresh(socket) do
      stats = get_stats(socket.assigns.tenant)
      {:noreply, assign(socket, stats: stats)}
    end
    
    defp get_stats(tenant) do
      today = Date.utc_today()
      
      # Try to get actual stats, fall back to defaults
      case get_daily_analytics(tenant, today) do
        {:ok, analytics} ->
          %{
            total_sessions: analytics.unique_visitors || 0,
            total_events: analytics.page_views || 0,
            unique_visitors: analytics.unique_visitors || 0,
            page_views: analytics.page_views || 0
          }
        
        _ ->
          %{
            total_sessions: 0,
            total_events: 0,
            unique_visitors: 0,
            page_views: 0
          }
      end
    end
    
    defp get_daily_analytics(tenant, date) do
      # Query the daily analytics for the given tenant and date
      try do
        require Ash.Query
        
        WhoThere.Analytics.DailyAnalytics
        |> Ash.Query.filter(tenant_id == ^tenant and date == ^date)
        |> Ash.read_one(authorize?: false)
      rescue
        _ -> {:error, :not_available}
      end
    end
  end
else
  defmodule WhoThere.PhoenixIntegration.LiveDashboardPage do
    @moduledoc """
    LiveDashboard integration is not available.
    
    To enable LiveDashboard integration, add the following to your dependencies:
    
        {:phoenix_live_dashboard, "~> 0.8"}
    """
    
    def menu_link(_, _) do
      {:error, "LiveDashboard not available. Add phoenix_live_dashboard to your dependencies."}
    end
  end
end
