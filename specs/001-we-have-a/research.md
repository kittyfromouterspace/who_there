# Research: WhoThere Analytics Library

## Overview
Research findings for implementing a privacy-first, multi-tenant Phoenix analytics library with advanced visualizations and bot detection capabilities.

## D3.js Integration with Phoenix LiveView

### Decision: D3.js v7 with LiveView Hooks
**Rationale**:
- D3.js provides unmatched data visualization capabilities for creating interactive, animated charts
- LiveView hooks enable seamless integration while maintaining server-side state management
- Allows for real-time data updates through LiveView streams while leveraging D3's client-side rendering power

**Implementation Approach**:
- Use LiveView hooks to mount D3.js components on specific DOM elements
- Pass data from LiveView assigns to JavaScript via phx-hook data attributes
- Handle real-time updates through LiveView streams and update D3 charts accordingly
- Implement chart types: time series, geographic maps, flow diagrams, heatmaps

**Dependencies**:
- D3.js v7 (latest stable)
- Phoenix LiveView 0.20+ for hooks support
- Custom JavaScript modules for chart components

**Alternatives Considered**:
- Server-side SVG generation: Limited interactivity, poor performance for complex charts
- Chart.js: Less flexible than D3, limited customization options
- Phoenix built-in charting: Too basic for advanced analytics visualizations

## Proxy Header Detection Strategy

### Decision: Multi-tier Header Priority System
**Rationale**:
- Different CDNs and load balancers use different header conventions
- Need robust fallback chain for maximum compatibility
- Geographic accuracy depends on proper header parsing

**Header Priority Order**:
1. **Cloudflare Headers** (highest priority):
   - `cf-connecting-ip`: Original client IP
   - `cf-ipcountry`: Country code
   - `cf-ipcity`: City name
   - `cf-region`: Region/state
   - `cf-timezone`: Client timezone

2. **AWS Application Load Balancer**:
   - `x-forwarded-for`: Client IP chain
   - `x-forwarded-proto`: Protocol
   - `x-amzn-trace-id`: Request tracing

3. **Standard Proxy Headers**:
   - `x-real-ip`: Direct client IP (nginx)
   - `x-forwarded-for`: IP chain (standard)
   - `x-forwarded-proto`: Protocol

4. **Connection-level Fallback**:
   - `conn.remote_ip`: Direct connection IP

**Implementation**:
- Create `ProxyHeaderParser` module with priority-based parsing
- Validate and sanitize all header values
- Cache parsed results to avoid repeated processing
- Log header parsing decisions for debugging

## Bot Traffic Detection and Segregation

### Decision: Multi-layered Bot Detection System
**Rationale**:
- Bot traffic significantly skews analytics if not properly identified
- Different bot types require different detection strategies
- Separate analytics streams provide cleaner user metrics

**Detection Layers**:

1. **User-Agent Pattern Matching**:
   - Known bot patterns: googlebot, bingbot, facebookexternalhit, twitterbot
   - Generic patterns: crawler, spider, scraper, bot
   - Legitimate browser patterns (whitelist approach)

2. **Behavioral Analysis**:
   - Request frequency patterns
   - Navigation patterns (missing typical user flows)
   - JavaScript execution capabilities

3. **IP Range Detection**:
   - Known bot IP ranges (Google, Bing, Facebook, etc.)
   - Data center IP ranges
   - Residential vs commercial IP classification

4. **Request Pattern Analysis**:
   - Rapid sequential requests
   - Missing common headers (Accept-Language, etc.)
   - Unusual HTTP method usage

**Storage Strategy**:
- Separate `bot_events` table or event_type categorization
- Bot analytics dashboard showing per-bot breakdown
- Regular bot pattern updates via configurable rules

**Bot Categories**:
- Search engine crawlers
- Social media bots
- Monitoring/uptime bots
- Malicious bots/scrapers
- Unknown automated traffic

## Phoenix Presence Integration

### Decision: Optional Presence Integration with Graceful Fallback
**Rationale**:
- Phoenix Presence provides accurate user tracking when available
- Not all applications use Presence, need fallback strategy
- Logged-in users can be tracked more accurately

**Integration Strategy**:

1. **Presence Detection**:
   - Check if Presence is configured and available
   - Detect presence topic patterns
   - Handle presence join/leave events

2. **User Identity Hierarchy**:
   - Presence ID (highest accuracy): Active users in LiveView
   - User authentication: Logged-in users via `conn.assigns.current_user`
   - Session fingerprinting: Anonymous users via IP + User-Agent

3. **Implementation**:
   - Optional Presence module integration
   - Track presence state changes in analytics
   - Merge presence data with session tracking
   - Handle presence disconnections gracefully

**Benefits**:
- Accurate concurrent user counts
- Real user session tracking across devices
- Better understanding of user engagement patterns

## LiveView Dead Render Deduplication

### Decision: Connected Socket Tracking Only
**Rationale**:
- LiveView renders both dead (initial HTTP) and live (WebSocket) versions
- Dead renders are essentially HTTP requests and shouldn't be double-counted
- Only connected LiveView interactions represent true LiveView usage

**Implementation Strategy**:

1. **Telemetry Handler Logic**:
   ```elixir
   def handle_lv_mount_stop(_event, _measurements, metadata, _config) do
     %{socket: socket} = metadata

     # Only track connected mounts
     if connected?(socket) do
       track_liveview_event("mount", socket, metadata)
     end
   end

   defp connected?(socket) do
     Map.get(socket, :connected?, false)
   end
   ```

2. **Event Classification**:
   - Dead renders: Tracked as regular HTTP page views
   - Connected mounts: Tracked as LiveView initializations
   - LiveView events: Only tracked for connected sockets

3. **Coordination with HTTP Tracking**:
   - HTTP plug skips LiveView routes
   - Telemetry handlers handle LiveView-specific tracking
   - Avoid double-counting initial page loads

**Benefits**:
- Accurate LiveView usage metrics
- Clear distinction between HTTP and WebSocket interactions
- Proper attribution of user engagement

## Multi-tenant Data Architecture

### Decision: Ash Framework Multitenancy with Configurable Strategies
**Rationale**:
- Support both shared database and separate schema approaches
- Ash provides robust tenant isolation guarantees
- Configurable based on deployment requirements

**Tenancy Strategies**:

1. **Attribute-based (Shared Database)**:
   - All resources include `tenant_id` attribute
   - Database-level row filtering
   - Single database, multiple tenants

2. **Schema-based (Separate Schemas)**:
   - Each tenant gets dedicated schema
   - Complete data isolation
   - Better for compliance requirements

**Implementation**:
- All Ash resources configured with multitenancy
- Tenant context propagated through all operations
- Automatic tenant scoping in queries
- Tenant-specific configuration inheritance

## Performance and Scalability Considerations

### Decision: Asynchronous Processing with Circuit Breakers
**Rationale**:
- Analytics must never impact application performance
- High-traffic applications need robust failure handling
- Background processing enables complex analytics computations

**Architecture Components**:

1. **Async Event Processing**:
   - Phoenix telemetry for data collection
   - Background job processing for aggregations
   - Stream processing for real-time updates

2. **Circuit Breaker Protection**:
   - Protect against analytics system failures
   - Graceful degradation when analytics unavailable
   - Fast failure to prevent cascade effects

3. **Caching Strategy**:
   - Redis/ETS for frequently accessed analytics
   - Pre-computed aggregations for dashboard performance
   - Intelligent cache invalidation

**Performance Targets**:
- <1ms overhead for request tracking
- <100ms for dashboard page loads
- Zero user-visible impact during failures

## Privacy and Compliance Framework

### Decision: Privacy-by-Design with Configurable Data Retention
**Rationale**:
- GDPR and CCPA compliance requirements
- User privacy as competitive advantage
- Configurable to meet different regulatory needs

**Privacy Features**:

1. **Data Minimization**:
   - Collect only necessary operational data
   - No PII storage in analytics data
   - Automatic IP address anonymization

2. **Retention Policies**:
   - Configurable data retention periods
   - Automatic data purging
   - Summary table generation before deletion

3. **User Rights**:
   - Data export capabilities
   - Data deletion on request
   - Audit trails for data operations

**Implementation**:
- Built-in anonymization functions
- Scheduled cleanup jobs
- GDPR-compliant data handling procedures

## Testing Strategy

### Decision: Multi-layered Testing with Performance Validation
**Rationale**:
- Analytics library must be rock-solid reliable
- Performance impact testing critical
- Multi-tenant isolation must be verified

**Testing Layers**:

1. **Unit Tests**:
   - Individual module functionality
   - Ash resource validations
   - Data transformation logic

2. **Integration Tests**:
   - Phoenix plug integration
   - Telemetry event handling
   - Multi-tenant data isolation

3. **Performance Tests**:
   - Load testing with analytics enabled
   - Memory and CPU impact measurement
   - Failure scenario testing

4. **Privacy Tests**:
   - PII detection in stored data
   - Anonymization verification
   - Cross-tenant data isolation

**Tools**:
- ExUnit for Elixir testing
- Phoenix.ConnTest for plug testing
- Phoenix.LiveViewTest for LiveView components
- Custom performance benchmarking

## Igniter Integration Strategy

### Decision: Igniter as Primary Installation Mechanism
**Rationale**:
- Igniter provides automated, intelligent code modification for Phoenix/Elixir projects
- Eliminates manual configuration errors and setup complexity
- Ensures consistent installation across different Phoenix application structures
- Supports configuration options for different deployment scenarios

**Implementation Approach**:

1. **Igniter Tasks**:
   - `mix igniter.install who_there` - Main installation task
   - Automatic dependency management and version resolution
   - Intelligent detection of existing Ash/Phoenix patterns
   - Configuration file generation with sensible defaults

2. **Installation Features**:
   - Automatic supervision tree integration
   - Phoenix router plug injection with proper pipeline detection
   - Database migration generation and execution
   - Multi-tenancy strategy configuration
   - Default analytics configuration creation

3. **Configuration Options**:
   - `--tenant-strategy`: attribute (default) or schema
   - `--enable-bot-detection`: true (default) or false
   - `--enable-presence-integration`: false (default) or true
   - `--enable-d3-visualizations`: true (default) or false
   - `--anonymize-ips`: true (default) or false
   - `--data-retention-days`: 365 (default) or custom value

4. **Smart Detection**:
   - Detect existing Ash Framework usage and integrate accordingly
   - Identify Phoenix router structure and add plugs to appropriate pipelines
   - Check for existing Presence configuration
   - Detect multi-tenant patterns in the application

**Benefits**:
- Zero-configuration installation for most use cases
- Consistent setup across different Phoenix applications
- Reduces onboarding friction for new users
- Ensures best practices are followed automatically

**Igniter Task Structure**:
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
    # Implementation details for automated setup
  end
end
```

## Summary

All research findings support a comprehensive, privacy-first analytics library that integrates seamlessly with Phoenix applications while providing advanced visualization capabilities and robust bot detection. The architecture ensures zero performance impact, complete tenant isolation, and regulatory compliance while delivering powerful analytics insights.

**Igniter Integration**: The addition of Igniter as the primary installation mechanism significantly reduces setup complexity and ensures consistent, error-free installations across different Phoenix application architectures, making WhoThere accessible to developers of all experience levels.