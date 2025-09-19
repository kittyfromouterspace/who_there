# WhoThere Phoenix Integration Guide

This guide covers how to integrate WhoThere analytics into your Phoenix application.

## Table of Contents

1. [Quick Setup](#quick-setup)
2. [Basic Integration](#basic-integration)
3. [Advanced Configuration](#advanced-configuration)
4. [LiveView Integration](#liveview-integration)
5. [LiveDashboard Integration](#livedashboard-integration)
6. [Telemetry and Monitoring](#telemetry-and-monitoring)
7. [API Endpoints](#api-endpoints)
8. [Troubleshooting](#troubleshooting)

## Quick Setup

### 1. Add WhoThere to Your Dependencies

```elixir
# mix.exs
def deps do
  [
    {:who_there, "~> 0.1.0"}
  ]
end
```

### 2. Basic Plug Integration

Add the WhoThere plug to your endpoint or router:

```elixir
# lib/your_app_web/endpoint.ex
defmodule YourAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :your_app

  plug WhoThere.Plug
  
  # ... rest of your plugs
end
```

### 3. Configuration

```elixir
# config/config.exs
config :who_there,
  tenant: "your_app",
  database_url: System.get_env("DATABASE_URL"),
  
  # Analytics configuration
  session_cookie_name: "_your_app_session_analytics",
  session_ttl: :timer.hours(2),
  privacy_mode_ttl: :timer.minutes(30),
  
  # Bot detection
  enable_bot_detection: true,
  custom_bot_patterns: [],
  
  # Privacy and security
  anonymize_ips: true,
  respect_dnt: true,
  enable_privacy_mode: true
```

That's it! WhoThere will now track analytics for your Phoenix application.

## Basic Integration

### Adding the Plug with Options

```elixir
# lib/your_app_web/router.ex
defmodule YourAppWeb.Router do
  use YourAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {YourAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    
    # Add WhoThere tracking
    plug WhoThere.Plug, [
      tenant: "your_app",
      track_sessions: true,
      track_page_views: true,
      async_processing: true
    ]
  end
  
  # ... rest of your routes
end
```

### Selective Route Tracking

You can enable tracking only for specific routes:

```elixir
defmodule YourAppWeb.Router do
  use YourAppWeb, :router

  pipeline :tracked_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug WhoThere.Plug, tenant: "your_app"
  end

  pipeline :untracked_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    # No WhoThere plug
  end

  scope "/", YourAppWeb do
    pipe_through :tracked_browser
    
    get "/", PageController, :index
    get "/dashboard", DashboardController, :show
  end

  scope "/admin", YourAppWeb do
    pipe_through :untracked_browser
    
    get "/", AdminController, :index
  end
end
```

## Advanced Configuration

### Complete Configuration Options

```elixir
# config/config.exs
config :who_there,
  # Required - Your application identifier
  tenant: "your_app",
  
  # Database configuration
  database_url: System.get_env("DATABASE_URL"),
  
  # Session tracking
  session_cookie_name: "_your_app_analytics",
  session_ttl: :timer.hours(2),
  privacy_mode_ttl: :timer.minutes(30),
  secure_cookie: true,
  same_site: "Lax",
  
  # Event processing
  async_processing: true,
  event_batch_size: 100,
  event_flush_interval: :timer.seconds(30),
  
  # Bot detection
  enable_bot_detection: true,
  custom_bot_patterns: [
    ~r/MyCustomBot/i,
    ~r/InternalMonitor/i
  ],
  
  # Privacy and GDPR compliance
  anonymize_ips: true,
  respect_dnt: true,
  enable_privacy_mode: true,
  data_retention_days: 365,
  
  # Geographic data
  enable_geo_lookup: false,
  geoip_database_path: nil,
  
  # Performance
  track_performance_metrics: true,
  slow_request_threshold_ms: 1000,
  
  # Filtering
  exclude_paths: ["/health", "/metrics", "/favicon.ico"],
  exclude_user_agents: [],
  exclude_ips: ["127.0.0.1", "::1"],
  
  # Custom event handlers
  custom_event_handlers: []
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :who_there,
  async_processing: false,  # Synchronous for easier debugging
  anonymize_ips: false,     # See real IPs in development
  enable_bot_detection: false

# config/prod.exs  
config :who_there,
  async_processing: true,
  anonymize_ips: true,
  enable_bot_detection: true,
  secure_cookie: true

# config/test.exs
config :who_there,
  async_processing: false,  # Synchronous for tests
  session_ttl: :timer.minutes(5),  # Shorter for tests
  enable_bot_detection: false
```

## LiveView Integration

### Automatic LiveView Tracking

WhoThere automatically tracks LiveView events when the Phoenix integration is enabled:

```elixir
# config/config.exs
config :who_there, :phoenix_integration,
  telemetry_enabled: true,
  track_live_view: true
```

### Manual LiveView Event Tracking

```elixir
defmodule YourAppWeb.DashboardLive do
  use YourAppWeb, :live_view
  
  def handle_event("user_action", params, socket) do
    # Custom analytics event
    WhoThere.PhoenixIntegration.emit_analytics_event(:user_dashboard_action, %{
      action: params["action"],
      user_id: socket.assigns.current_user.id,
      timestamp: System.system_time(:millisecond)
    })
    
    {:noreply, socket}
  end
  
  def handle_info(:track_page_view, socket) do
    # Track LiveView "page view"
    WhoThere.PhoenixIntegration.emit_analytics_event(:liveview_navigation, %{
      live_view: __MODULE__,
      path: socket.assigns.current_path
    })
    
    {:noreply, socket}
  end
end
```

### LiveView Session Persistence

```elixir
defmodule YourAppWeb.SessionLive do
  use YourAppWeb, :live_view
  
  def mount(_params, session, socket) do
    # Access WhoThere session data
    analytics_session_id = session["_who_there_session_id"]
    
    socket = assign(socket, :analytics_session_id, analytics_session_id)
    
    {:ok, socket}
  end
end
```

## LiveDashboard Integration

### Setup LiveDashboard with WhoThere

```elixir
# lib/your_app/application.ex
defmodule YourApp.Application do
  def start(_type, _args) do
    children = [
      # ... other children
      {WhoThere.PhoenixIntegration, []}
    ]
    
    WhoThere.PhoenixIntegration.attach_telemetry_handlers()
    
    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

```elixir
# lib/your_app_web/router.ex
defmodule YourAppWeb.Router do
  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through :browser
    
    live_dashboard "/dashboard",
      metrics: YourAppWeb.Telemetry,
      additional_pages: [
        analytics: {WhoThere.PhoenixIntegration.LiveDashboardPage, [
          tenant: "your_app"
        ]}
      ]
  end
end
```

### Custom Dashboard Metrics

```elixir
# lib/your_app_web/telemetry.ex
defmodule YourAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # WhoThere Analytics Metrics
      counter("who_there.analytics.event_tracked.count",
        tags: [:event_type, :tenant]
      ),
      summary("who_there.analytics.session_duration",
        unit: {:native, :second}
      ),
      counter("who_there.analytics.bot_requests.count",
        tags: [:bot_type]
      )
    ]
  end

  defp periodic_measurements do
    []
  end
end
```

## Telemetry and Monitoring

### Built-in Telemetry Events

WhoThere emits the following telemetry events:

```elixir
# Analytics events
[:who_there, :analytics, :event_tracked]   # When an event is successfully tracked
[:who_there, :analytics, :error]           # When tracking fails
[:who_there, :analytics, :session_created] # New session created  
[:who_there, :analytics, :session_updated] # Session updated
[:who_there, :analytics, :bot_detected]    # Bot request detected

# Performance events  
[:who_there, :performance, :slow_request]  # Request exceeded threshold
[:who_there, :performance, :database_slow] # Database query was slow
```

### Custom Telemetry Handlers

```elixir
# lib/your_app/telemetry.ex
defmodule YourApp.Telemetry do
  def attach_handlers do
    :telemetry.attach(
      "who-there-analytics-handler",
      [:who_there, :analytics, :event_tracked],
      &handle_analytics_event/4,
      %{}
    )
    
    :telemetry.attach(
      "who-there-error-handler", 
      [:who_there, :analytics, :error],
      &handle_analytics_error/4,
      %{}
    )
  end

  def handle_analytics_event(event, measurements, metadata, config) do
    # Send to external monitoring
    YourApp.Monitoring.increment("analytics.events", 1, [
      tenant: metadata.tenant,
      event_type: metadata.event_type
    ])
  end

  def handle_analytics_error(event, measurements, metadata, config) do
    # Send error to error tracking service
    YourApp.ErrorReporting.report(metadata.error, %{
      context: "who_there_analytics",
      tenant: metadata.tenant
    })
  end
end
```

### Integration with External Monitoring

```elixir
# config/config.exs
config :who_there, :phoenix_integration,
  telemetry_enabled: true,
  emit_metrics: true,
  emit_error_metrics: true,
  custom_handlers: [
    {[:who_there, :analytics, :custom], &YourApp.Telemetry.handle_custom_event/4}
  ]
```

## API Endpoints

### Optional JSON API

Add API endpoints for accessing analytics data:

```elixir
# lib/your_app_web/controllers/analytics_controller.ex
defmodule YourAppWeb.AnalyticsController do
  use YourAppWeb, :controller
  
  alias WhoThere.Analytics

  def daily_stats(conn, %{"date" => date_string}) do
    tenant = get_tenant(conn)
    date = Date.from_iso8601!(date_string)
    
    case Analytics.get_daily_analytics(tenant, date) do
      nil -> 
        conn
        |> put_status(:not_found)
        |> json(%{error: "No data found for date"})
        
      stats ->
        json(conn, %{
          date: date,
          unique_visitors: stats.unique_visitors,
          page_views: stats.page_views,
          avg_session_duration: stats.avg_session_duration,
          bounce_rate: stats.bounce_rate
        })
    end
  end

  def session_stats(conn, params) do
    tenant = get_tenant(conn)
    
    sessions = Analytics.get_recent_sessions(tenant, limit: 50)
    
    json(conn, %{
      sessions: Enum.map(sessions, fn session ->
        %{
          id: session.id,
          started_at: session.inserted_at,
          duration: session.duration,
          page_count: session.page_count,
          user_agent: session.user_agent,
          country: session.country
        }
      end)
    })
  end

  defp get_tenant(conn) do
    # Extract tenant from authentication, subdomain, etc.
    "your_app"
  end
end
```

```elixir
# lib/your_app_web/router.ex
scope "/api/v1", YourAppWeb do
  pipe_through :api
  
  get "/analytics/daily/:date", AnalyticsController, :daily_stats
  get "/analytics/sessions", AnalyticsController, :session_stats
end
```

### GraphQL Integration

```elixir
# lib/your_app_web/schema.ex
defmodule YourAppWeb.Schema do
  use Absinthe.Schema
  alias WhoThere.Analytics

  object :daily_analytics do
    field :date, :date
    field :unique_visitors, :integer
    field :page_views, :integer
    field :avg_session_duration, :integer
    field :bounce_rate, :float
  end

  query do
    field :daily_analytics, :daily_analytics do
      arg :date, non_null(:date)
      arg :tenant, non_null(:string)
      
      resolve fn %{date: date, tenant: tenant}, _ ->
        case Analytics.get_daily_analytics(tenant, date) do
          nil -> {:error, "No analytics data found"}
          data -> {:ok, data}
        end
      end
    end
  end
end
```

## Troubleshooting

### Common Issues

**1. Analytics events not being tracked**

Check that the plug is properly configured:

```elixir
# Verify plug order - WhoThere.Plug should be early in the pipeline
plug :fetch_session  # Required before WhoThere.Plug
plug WhoThere.Plug
```

**2. Sessions not persisting**

Ensure session configuration is correct:

```elixir
config :who_there,
  session_cookie_name: "_your_app_analytics",  # Must be unique
  secure_cookie: false  # Set to false for local development
```

**3. Database connection issues**

Verify database configuration:

```elixir
config :who_there,
  database_url: "postgresql://user:pass@localhost/who_there_dev"
```

**4. Telemetry events not firing**

Ensure handlers are attached:

```elixir
# In application.ex
WhoThere.PhoenixIntegration.attach_telemetry_handlers()
```

### Debug Mode

Enable debug logging:

```elixir
# config/dev.exs
config :logger, level: :debug

config :who_there,
  debug_mode: true,
  async_processing: false  # Makes debugging easier
```

### Performance Troubleshooting

**1. Slow request processing**

```elixir
config :who_there,
  async_processing: true,      # Process events asynchronously
  event_batch_size: 50,       # Reduce batch size
  event_flush_interval: 10_000 # Increase flush interval
```

**2. High memory usage**

```elixir
config :who_there,
  event_batch_size: 25,       # Smaller batches
  session_ttl: :timer.hours(1), # Shorter session TTL
  data_retention_days: 30     # Clean up old data more frequently
```

### Testing

```elixir
# test/test_helper.exs
ExUnit.start()

# Configure WhoThere for testing
Application.put_env(:who_there, :async_processing, false)
Application.put_env(:who_there, :session_ttl, :timer.minutes(1))
```

```elixir
# In your tests
defmodule YourAppWeb.AnalyticsTest do
  use YourAppWeb.ConnCase
  
  test "tracks page view", %{conn: conn} do
    conn = get(conn, "/")
    
    # Verify event was tracked
    assert_receive {:telemetry, [:who_there, :analytics, :event_tracked], _, _}
  end
  
  test "respects privacy mode", %{conn: conn} do
    conn = 
      conn
      |> put_req_header("dnt", "1")
      |> get("/")
    
    # Should not track when DNT header is present
    refute_receive {:telemetry, [:who_there, :analytics, :event_tracked], _, _}
  end
end
```

## Next Steps

- Review the [API Documentation](API.md) for detailed function references
- Check out [Advanced Features](ADVANCED.md) for custom event handlers
- See [Deployment Guide](DEPLOYMENT.md) for production considerations
- Read [Privacy & GDPR](PRIVACY.md) for compliance guidance