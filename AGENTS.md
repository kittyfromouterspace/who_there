# AGENTS.md

This file provides AI development guidance for the WhoThere Analytics library project.

## Project Overview
WhoThere is a privacy-first, multi-tenant Phoenix analytics library that provides invisible server-side tracking of page views, API calls, and LiveView interactions. Built with Elixir, Phoenix Framework 1.8+, and Ash Framework 3.x+.

## Core Technologies
- **Language**: Elixir 1.18+
- **Framework**: Phoenix 1.8+ with LiveView
- **Domain Layer**: Ash Framework 3.x+ for all business logic
- **Database**: PostgreSQL with Ash.Postgres
- **Frontend**: Phoenix Core Components + DaisyUI + D3.js
- **Installation**: Igniter for automated setup and configuration
- **Testing**: ExUnit, Phoenix.ConnTest, Phoenix.LiveViewTest

## Constitutional Requirements (NON-NEGOTIABLE)
1. **Privacy-First**: No PII storage, IP anonymization, no client-side tracking
2. **Multi-Tenant Isolation**: All resources use Ash multitenancy features
3. **Zero User Impact**: Completely invisible analytics collection
4. **Test-First Development**: TDD with comprehensive test coverage
5. **Ash Framework**: All business logic through Ash resources and domains
6. **Performance**: Asynchronous processing, circuit breakers, <1ms overhead

## Architecture Patterns

### Resource Definition Pattern
```elixir
use Ash.Resource,
  otp_app: :who_there,
  domain: WhoThere.Domain,
  data_layer: AshPostgres.DataLayer,
  authorizers: [Ash.Policy.Authorizer]

multitenancy do
  strategy :attribute
  attribute :tenant_id
end
```

### Phoenix Plug Integration Pattern
```elixir
def call(conn, opts) do
  # Always use register_before_send for production
  register_before_send(conn, fn conn ->
    track_request_async(conn, opts)
    conn
  end)
end
```

### Telemetry Handler Pattern
```elixir
def handle_lv_mount_stop(_event, measurements, metadata, _config) do
  %{socket: socket} = metadata

  # Only track connected LiveView renders
  if connected?(socket) do
    track_liveview_event("mount", socket, measurements, metadata)
  end
end
```

## Key Implementation Details

### Bot Detection
- Multi-tier detection: user-agent patterns, IP ranges, behavior analysis
- Separate analytics streams for bot traffic
- Per-bot breakdown in dashboards
- Exclude bot traffic from normal user metrics

### Proxy Header Detection
- Priority order: Cloudflare → AWS ALB → nginx → standard headers
- Headers: `cf-connecting-ip`, `x-forwarded-for`, `x-real-ip`
- Geographic data from `cf-ipcountry`, `cf-ipcity`, `cf-region`
- Fallback mechanisms for missing headers

### Phoenix Presence Integration
- Optional integration with graceful fallback
- Check Presence availability at runtime
- Use presence_id when available, fingerprinting otherwise
- Track presence state changes in analytics

### LiveView Deduplication
- Track only connected LiveView renders using `socket.connected?`
- Dead renders handled as regular HTTP requests
- Prevent double-counting initial page loads
- Coordinate between HTTP plug and telemetry handlers

### D3.js Integration
- Use LiveView hooks for chart mounting
- Pass data via phx-hook data attributes
- Real-time updates through LiveView streams
- Chart types: time series, geographic maps, heatmaps

## Database Schema Patterns

### Primary Indexes
```elixir
custom_indexes do
  index [:tenant_id, :timestamp]
  index [:tenant_id, :event_type, :timestamp]
  index [:session_id], where: "session_id IS NOT NULL"
end
```

### Multitenancy Configuration
```elixir
multitenancy do
  strategy :attribute  # or :schema for separate schemas
  attribute :tenant_id
end
```

### Validation Patterns
```elixir
validations do
  validate present(:tenant_id), message: "Tenant ID is required"
  validate one_of(:event_type, [:page_view, :api_call, :liveview_event, :bot_traffic])
  validate match(:path, ~r/^\/.*$/), message: "Path must start with '/'"
end
```

## Privacy Implementation

### IP Anonymization
```elixir
def anonymize_ip(ip_string) do
  case String.split(ip_string, ".") do
    [a, b, c, _d] -> "#{a}.#{b}.#{c}.0"  # IPv4
    _ -> hash_ip(ip_string)  # IPv6 or invalid
  end
end
```

### Data Retention
```elixir
def cleanup_expired_data(opts \\ []) do
  config = get_config_by_tenant(opts)
  cutoff_date = DateTime.add(DateTime.utc_now(), -config.data_retention_days * 24 * 60 * 60, :second)

  # Bulk delete with tenant isolation
  WhoThere.AnalyticsEvent
  |> Ash.Query.filter(timestamp < ^cutoff_date)
  |> Ash.bulk_destroy(:destroy, tenant: tenant)
end
```

## Common Development Commands

### Installation and Setup
```bash
# Primary installation method
mix igniter.install who_there

# With configuration options
mix igniter.install who_there --tenant-strategy=attribute --enable-bot-detection=true

# Manual installation fallback
mix deps.get
mix who_there.install
```

### Database Operations
```bash
mix ash.codegen analytics_migration
mix ash.migrate
mix ash.rollback
```

### Quality Checks
```bash
mix check          # Run all quality tools
mix format         # Format code
mix test           # Run test suite
mix credo --strict # Static analysis
```

### Development Server
```bash
iex -S mix phx.server
mix phx.server
```

## Testing Patterns

### Resource Testing
```elixir
describe "analytics event creation" do
  test "creates event with tenant isolation" do
    attrs = %{event_type: :page_view, path: "/test"}

    assert {:ok, event} = WhoThere.track_event(attrs, tenant: tenant_id)
    assert event.tenant_id == tenant_id
  end
end
```

### Integration Testing
```elixir
test "request tracking with Phoenix plug", %{conn: conn} do
  conn =
    conn
    |> assign(:tenant_id, tenant_id)
    |> get("/")

  # Verify event was created asynchronously
  Process.sleep(10)
  events = WhoThere.get_events_by_date_range(yesterday, tomorrow, tenant: tenant_id)
  assert length(events) == 1
end
```

### LiveView Testing
```elixir
test "LiveView mount tracking", %{conn: conn} do
  {:ok, _view, _html} = live(conn, "/live-page")

  # Verify only connected render was tracked
  events = get_liveview_events()
  assert length(events) == 1
  assert hd(events).metadata["source"] == "liveview_telemetry"
end
```

## Error Handling Patterns

### Graceful Degradation
```elixir
def track_event(attrs, opts) do
  try do
    # Analytics tracking logic
  rescue
    error ->
      Logger.error("Analytics tracking failed: #{inspect(error)}")
      # Never impact user experience
      :ok
  end
end
```

### Circuit Breaker Pattern
```elixir
def maybe_track_analytics(conn, config) do
  if analytics_healthy?() do
    track_analytics(conn, config)
  else
    Logger.warn("Analytics circuit breaker open, skipping tracking")
    :ok
  end
end
```

## Performance Considerations

### Async Processing
```elixir
# Use Task.async for non-blocking analytics
Task.start(fn ->
  track_analytics_event(event_attrs, tenant: tenant_id)
end)
```

### Efficient Queries
```elixir
# Use proper indexes and limit results
query =
  WhoThere.AnalyticsEvent
  |> Ash.Query.filter(tenant_id == ^tenant_id and timestamp >= ^start_date)
  |> Ash.Query.sort(timestamp: :desc)
  |> Ash.Query.limit(1000)
```

### Caching Strategy
```elixir
# Cache frequently accessed configurations
defp get_analytics_config_cached(tenant_id) do
  case Cachex.get(:analytics_cache, tenant_id) do
    {:ok, nil} ->
      config = get_analytics_config(tenant_id)
      Cachex.put(:analytics_cache, tenant_id, config, ttl: :timer.minutes(5))
      config
    {:ok, config} ->
      config
  end
end
```

## Debugging Tips

### Enable Debug Logging
```elixir
config :logger, level: :debug

# In modules
require Logger
Logger.debug("Analytics: tracking event #{inspect(event_attrs)}")
```

### Verify Tenant Isolation
```elixir
# Check tenant context in iex
WhoThere.AnalyticsEvent
|> Ash.Query.for_read(:read, %{}, tenant: tenant_id)
|> Ash.read!()
```

### Monitor Performance
```elixir
# Track processing time
start_time = System.monotonic_time(:microsecond)
result = track_analytics(attrs)
duration = System.monotonic_time(:microsecond) - start_time
Logger.info("Analytics processing took #{duration}µs")
```

## Igniter Development Patterns

### Igniter Task Implementation
```elixir
defmodule WhoThere.Igniter.Install do
  use Igniter.Mix.Task

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [],
      schema: [
        tenant_strategy: :string,
        enable_bot_detection: :boolean,
        enable_presence_integration: :boolean,
        enable_d3_visualizations: :boolean,
        anonymize_ips: :boolean,
        data_retention_days: :integer
      ]
    }
  end

  def igniter(igniter, argv) do
    options = options!(argv)

    igniter
    |> add_dependencies()
    |> configure_application(options)
    |> setup_router_plugs()
    |> generate_migrations()
    |> create_default_config(options)
  end
end
```

### Automated Configuration Patterns
```elixir
# Add to supervision tree
Igniter.Code.Module.find_and_update_module!(igniter, MyApp.Application, fn zipper ->
  # Modify supervision tree to include WhoThere
end)

# Add router plugs
Igniter.Code.Module.find_and_update_module!(igniter, MyAppWeb.Router, fn zipper ->
  # Add RequestTracker plug to appropriate pipeline
end)

# Generate configuration
Igniter.Project.Config.configure(igniter, "who_there.exs", [:who_there], config_values)
```

## Recent Changes
- Added Igniter as the primary installation mechanism for automated setup
- Implemented comprehensive Igniter task with configuration options
- Added D3.js visualization support with LiveView hooks
- Implemented comprehensive bot detection with per-bot analytics
- Enhanced proxy header detection for better geographic accuracy
- Added Phoenix Presence integration for user tracking
- Implemented LiveView dead render deduplication

This guidance ensures consistent, high-quality development following the project's constitutional principles and architectural patterns, with Igniter providing seamless installation and configuration automation.