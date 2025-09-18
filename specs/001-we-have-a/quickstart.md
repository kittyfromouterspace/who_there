# Quickstart Guide: WhoThere Analytics

This guide will get you up and running with WhoThere analytics in your Phoenix application in under 10 minutes.

## Prerequisites

- Phoenix 1.8+ application
- PostgreSQL database
- Elixir 1.18+

## 1. Installation

### Option A: Using Igniter (Recommended)

WhoThere uses [Igniter](https://hexdocs.pm/igniter/readme.html) for automated installation and configuration:

```bash
# Install WhoThere with automatic setup
mix igniter.install who_there

# Or install with specific options
mix igniter.install who_there --tenant-strategy=attribute --enable-bot-detection=true
```

This automatically:
- Adds WhoThere and dependencies to `mix.exs`
- Generates database migrations
- Configures your application supervision tree
- Sets up basic Phoenix plug integration
- Creates default analytics configuration

### Option B: Manual Installation

If you prefer manual setup, add WhoThere to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:who_there, "~> 0.1.0"},
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:igniter, "~> 0.3", only: [:dev]}
  ]
end
```

Run the installation:

```bash
mix deps.get
mix who_there.install
```

## 2. Database Setup

### If Using Igniter Installation

Database setup is automatic! The Igniter installer handles migration generation and application. Skip to step 3.

### If Using Manual Installation

Generate and run the analytics database migrations:

```bash
mix ash.codegen analytics_setup
mix ash.migrate
```

This creates the required tables:
- `analytics_events` - Individual tracking events
- `analytics_sessions` - User sessions
- `analytics_configurations` - Tenant settings
- `daily_analytics` - Pre-computed summaries
- `geographic_data` - Geographic reference data

## 3. Basic Configuration

### If Using Igniter Installation

Configuration is automatic! Igniter has already:
- Added WhoThere to your supervision tree
- Configured your repository settings
- Set up default analytics configuration

You can customize settings by editing the generated configuration in `config/config.exs`.

### Igniter Installation Options

The Igniter installer supports several configuration options:

```bash
# Multi-tenancy strategy
mix igniter.install who_there --tenant-strategy=attribute  # or schema

# Enable/disable features
mix igniter.install who_there --enable-bot-detection=true
mix igniter.install who_there --enable-presence-integration=true
mix igniter.install who_there --enable-d3-visualizations=true

# Privacy settings
mix igniter.install who_there --anonymize-ips=true
mix igniter.install who_there --data-retention-days=365

# Combined example
mix igniter.install who_there \
  --tenant-strategy=attribute \
  --enable-bot-detection=true \
  --enable-d3-visualizations=true \
  --anonymize-ips=true \
  --data-retention-days=90
```

### If Using Manual Installation

Add WhoThere to your application supervision tree in `lib/your_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... your existing children
    {WhoThere, [repo: YourApp.Repo]}
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Configure your repository in `config/config.exs`:

```elixir
config :who_there,
  repo: YourApp.Repo,
  # Enable for multi-tenant applications
  multitenancy: :attribute, # or :schema
  # Default analytics configuration
  default_config: %{
    enabled: true,
    anonymize_ips: true,
    bot_detection_enabled: true,
    data_retention_days: 365
  }
```

## 4. Add Analytics Tracking

### For Single-Tenant Applications

Add the request tracker plug to your router in `lib/your_app_web/router.ex`:

```elixir
defmodule YourAppWeb.Router do
  use YourAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YourAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Add WhoThere tracking
    plug WhoThere.Plugs.RequestTracker
  end

  # ... rest of your router
end
```

### For Multi-Tenant Applications

Add tenant context to the request tracker:

```elixir
pipeline :browser do
  # ... existing plugs
  plug :assign_tenant
  plug WhoThere.Plugs.RequestTracker
end

defp assign_tenant(conn, _opts) do
  # Your tenant detection logic
  tenant_id = get_tenant_from_subdomain(conn) # or however you determine tenant
  assign(conn, :tenant_id, tenant_id)
end
```

## 5. Enable Telemetry Tracking

Add telemetry handlers to your application startup:

```elixir
# In lib/your_app/application.ex start/2 function
def start(_type, _args) do
  children = [
    # ... existing children
    {WhoThere, [repo: YourApp.Repo]}
  ]

  # Attach telemetry handlers
  WhoThere.Telemetry.attach_handlers()

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## 6. Create Analytics Configuration

For single-tenant applications:

```elixir
# In iex -S mix or a migration
WhoThere.create_config(%{
  enabled: true,
  collect_user_agents: true,
  collect_geolocation: true,
  anonymize_ips: true,
  exclude_admin_routes: true,
  bot_detection_enabled: true
})
```

For multi-tenant applications:

```elixir
# Create configuration for each tenant
WhoThere.create_config(%{
  enabled: true,
  collect_user_agents: true,
  collect_geolocation: true,
  anonymize_ips: true,
  exclude_admin_routes: true,
  bot_detection_enabled: true
}, tenant: tenant_id)
```

## 7. Add Analytics Dashboard (Optional)

Add analytics routes to your router:

```elixir
# In lib/your_app_web/router.ex
scope "/analytics", YourAppWeb do
  pipe_through [:browser, :require_admin] # Add your auth pipeline

  live "/", WhoThere.Live.Dashboard
  live "/events", WhoThere.Live.Events
  live "/sessions", WhoThere.Live.Sessions
  live "/bots", WhoThere.Live.BotTraffic
end
```

## 8. Verification

Start your application and visit a few pages:

```bash
mix phx.server
```

Check that analytics are being collected:

```elixir
# In iex -S mix phx.server
WhoThere.get_events_by_date_range(
  Date.add(Date.utc_today(), -1),
  Date.utc_today()
)
```

You should see events being tracked!

## 9. Advanced Configuration

### Enable Phoenix Presence Integration

If your application uses Phoenix Presence:

```elixir
# In your analytics configuration
config = %{
  presence_integration: true,
  # ... other settings
}

WhoThere.update_config(config, tenant: tenant_id)
```

### Configure Bot Detection

Customize bot detection patterns:

```elixir
config = %{
  bot_detection_enabled: true,
  exclude_patterns: [
    "/api/health",
    "/metrics",
    "/favicon.ico",
    ".*\\.css$",
    ".*\\.js$"
  ]
}

WhoThere.update_config(config, tenant: tenant_id)
```

### Enable D3.js Visualizations

Add D3.js to your assets in `assets/js/app.js`:

```javascript
import * as d3 from "d3"

// Make D3 available globally for WhoThere charts
window.d3 = d3

// Import WhoThere chart hooks
import { Charts } from "who_there"
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...Charts },
  params: {_csrf_token: csrfToken}
})
```

Update your analytics configuration:

```elixir
WhoThere.update_config(%{
  d3_visualizations_enabled: true
}, tenant: tenant_id)
```

## 10. Privacy Compliance

For GDPR/CCPA compliance, configure strict privacy settings:

```elixir
config = %{
  anonymize_ips: true,
  collect_user_agents: false,
  collect_referrers: false,
  collect_geolocation: false,
  data_retention_days: 30
}

WhoThere.update_config(config, tenant: tenant_id)
```

## Testing Your Integration

### 1. Generate Test Traffic

Visit various pages in your application to generate analytics data.

### 2. Check Event Collection

```elixir
# View recent events
events = WhoThere.get_events_by_date_range(
  Date.add(Date.utc_today(), -1),
  Date.utc_today(),
  tenant: tenant_id
)

IO.inspect(events, limit: :infinity)
```

### 3. Check Session Tracking

```elixir
# View recent sessions
sessions = WhoThere.Session
|> Ash.Query.for_read(:by_date_range, %{
  start_date: DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second),
  end_date: DateTime.utc_now()
})
|> Ash.read!(tenant: tenant_id)

IO.inspect(sessions)
```

### 4. Check Bot Detection

```elixir
# View bot traffic
bot_events = WhoThere.get_events_by_date_range(
  Date.add(Date.utc_today(), -1),
  Date.utc_today(),
  event_type: :bot_traffic,
  tenant: tenant_id
)

IO.inspect(bot_events)
```

### 5. View Daily Summaries

```elixir
# Check daily analytics summary
summary = WhoThere.DailyAnalytics
|> Ash.Query.for_read(:latest_summary)
|> Ash.read_one!(tenant: tenant_id)

IO.inspect(summary)
```

## Troubleshooting

### No Events Being Tracked

1. **Check configuration**: Ensure analytics are enabled
   ```elixir
   config = WhoThere.get_config_by_tenant(tenant: tenant_id)
   IO.inspect(config.enabled)
   ```

2. **Check tenant context**: For multi-tenant apps, ensure tenant is properly assigned
   ```elixir
   # In your controller or LiveView
   IO.inspect(assigns[:tenant_id])
   ```

3. **Check exclude patterns**: Verify your routes aren't being excluded
   ```elixir
   config = WhoThere.get_config_by_tenant(tenant: tenant_id)
   IO.inspect(config.exclude_patterns)
   ```

### High Bot Traffic

1. **Review bot detection patterns**: Check if legitimate traffic is being classified as bots
2. **Add custom exclusion rules**: Use exclude_patterns to filter unwanted traffic
3. **Monitor bot breakdown**: Use the analytics dashboard to identify bot sources

### Performance Issues

1. **Check async processing**: Ensure analytics processing isn't blocking requests
2. **Review indexes**: Database queries should use proper indexes
3. **Configure retention**: Reduce data retention period if needed

### Privacy Concerns

1. **Enable IP anonymization**: Set `anonymize_ips: true`
2. **Disable user agent collection**: Set `collect_user_agents: false`
3. **Reduce retention period**: Set `data_retention_days` to a lower value
4. **Review geographic data**: Disable `collect_geolocation` if not needed

## Next Steps

- [Configure advanced analytics features](./advanced-config.md)
- [Set up custom dashboards](./dashboards.md)
- [Integrate with monitoring systems](./monitoring.md)
- [Optimize for high-traffic applications](./performance.md)

## Support

- [Documentation](https://hexdocs.pm/who_there)
- [GitHub Issues](https://github.com/your-org/who_there/issues)
- [Community Forum](https://example.com/forum)

Congratulations! You now have privacy-first analytics running in your Phoenix application. 🎉