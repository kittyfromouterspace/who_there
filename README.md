# WhoThere

**Privacy-first analytics for Phoenix applications with Ash Framework integration**

WhoThere is a comprehensive analytics library built specifically for Phoenix applications using the Ash Framework. It provides invisible request tracking, bot detection, session management, and geographic data parsing while maintaining strong privacy protections and multi-tenant isolation.

## Features

- 🔒 **Privacy-First**: IP anonymization, GDPR compliance, configurable privacy modes
- 🏢 **Multi-Tenant**: Built-in tenant isolation with flexible tenant resolution
- 🤖 **Bot Detection**: Comprehensive bot identification with configurable patterns
- 🌍 **Geographic Data**: Extract location data from proxy headers and IP geolocation
- 📊 **Rich Analytics**: Page views, sessions, performance metrics, and traffic analysis
- ⚡ **Performance**: Async processing with minimal request overhead
- 🔧 **Phoenix Integration**: Seamless Plug and LiveView integration
- 📈 **Real-time**: Live dashboard metrics and real-time analytics queries

## Installation

### Automatic Installation (Recommended)

Add `who_there` to your dependencies and run the installation task:

```elixir
def deps do
  [
    {:who_there, "~> 0.1.0"}
  ]
end
```

```bash
mix deps.get
mix who_there.install
```

This will:
- Generate configuration files
- Create database migrations
- Add routing examples
- Set up tenant resolver functions

### Manual Installation

1. **Add to dependencies:**

```elixir
def deps do
  [
    {:who_there, "~> 0.1.0"},
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:phoenix, "~> 1.8"}
  ]
end
```

2. **Configure your application:**

```elixir
# config/config.exs
config :who_there, WhoThere.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "your_app_repo",
  pool_size: 10

config :who_there,
  privacy_mode: false,
  bot_detection: true,
  geographic_data: true,
  session_tracking: true
```

3. **Run migrations:**

```bash
mix ecto.migrate
```

## Usage

### Basic Phoenix Integration

Add the WhoThere plug to your router:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :analytics do
    plug WhoThere.Plug,
      tenant_resolver: &MyApp.Analytics.get_tenant/1,
      track_page_views: true,
      track_api_calls: false,
      exclude_paths: [~r/^\/api\/health/]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MyAppWeb do
    pipe_through [:browser, :analytics]  # Add analytics here

    get "/", PageController, :home
    # ... other routes
  end
end
```

### Tenant Resolution

Implement a tenant resolver function:

```elixir
# lib/my_app/analytics.ex
defmodule MyApp.Analytics do
  def get_tenant(conn) do
    # Option 1: From subdomain
    case String.split(conn.host, ".") do
      [tenant | _] when tenant != "www" -> tenant
      _ -> "default"
    end

    # Option 2: From session
    # Plug.Conn.get_session(conn, :current_tenant)

    # Option 3: From path
    # case conn.path_info do
    #   [tenant | _] -> tenant
    #   _ -> "default"
    # end
  end
end
```

### Analytics Queries

Query your analytics data:

```elixir
# Get page view analytics
{:ok, data} = WhoThere.AnalyticsQuery.page_views(
  tenant: "my-tenant",
  start_date: ~U[2023-01-01 00:00:00Z],
  end_date: ~U[2023-01-31 23:59:59Z],
  group_by: :day
)

# Get real-time metrics
{:ok, metrics} = WhoThere.AnalyticsQuery.real_time_metrics(
  tenant: "my-tenant",
  window_minutes: 60
)

# Get bot traffic analysis
{:ok, bot_data} = WhoThere.AnalyticsQuery.bot_traffic_analysis(
  tenant: "my-tenant",
  start_date: ~U[2023-01-01 00:00:00Z],
  end_date: ~U[2023-01-31 23:59:59Z]
)
```

## Configuration

### Privacy Settings

```elixir
config :who_there,
  privacy_mode: true,  # Enable privacy-first mode
  ip_anonymization: :full,  # :none, :partial, :full
  geographic_precision: :country,  # :country, :region, :city
  data_retention_days: 30
```

### Route Filtering

```elixir
config :who_there, :route_filters,
  exclude_paths: [
    ~r/^\/assets\//,
    ~r/^\/images\//,
    "/health",
    "/metrics"
  ],
  include_only: [
    ~r/^\/dashboard\//
  ]
```

### Bot Detection

```elixir
config :who_there, :bot_detection,
  enabled: true,
  user_agent_patterns: [
    ~r/googlebot/i,
    ~r/bingbot/i,
    "custom-crawler"
  ],
  ip_ranges: [
    "66.249.64.0/19"  # Google bot IP range
  ]
```

## Development Status

### ✅ Completed Tasks

- [x] Project foundation and dependencies
- [x] Core Ash resources (AnalyticsEvent, Session, DailyAnalytics, AnalyticsConfiguration)
- [x] Database migrations and indexes
- [x] Bot detection system with pattern matching
- [x] Privacy utilities with IP anonymization  
- [x] Proxy header parsing (Cloudflare, AWS, etc.)
- [x] Geographic data extraction
- [x] Session tracking utilities with comprehensive tests
- [x] Analytics query module with pre-defined actions
- [x] Phoenix Plug integration
- [x] Telemetry handlers for LiveView events
- [x] Route filtering system
- [x] Igniter installation task (`mix who_there.install`)
- [x] Multi-tenant support with policies
- [x] Compilation error fixes and stability
- [x] Resource policy integration tests
- [x] Phoenix integration with telemetry and monitoring
- [x] LiveDashboard integration with real-time analytics
- [x] Comprehensive integration guide and documentation

### 🚧 In Progress

- [ ] Advanced analytics features (comparative analysis, retention)
- [ ] Performance optimization benchmarks

### 📋 Planned Features

- [ ] D3.js chart integration
- [ ] Circuit breaker protection
- [ ] Data export functionality (CSV, JSON, PDF)
- [ ] GDPR compliance tools
- [ ] Cache layer for query optimization
- [ ] Alert system for traffic anomalies
- [ ] Advanced bot analytics and machine learning detection

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

Documentation can be found at [HexDocs](https://hexdocs.pm/who_there).

