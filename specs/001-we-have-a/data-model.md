# Data Model: WhoThere Analytics Library

## Domain Overview
The WhoThere analytics domain manages privacy-first, multi-tenant analytics data through Ash Framework resources. All entities support tenant isolation and follow strict privacy guidelines.

## Core Entities

### AnalyticsEvent
**Purpose**: Individual tracking events for page views, API calls, and LiveView interactions

**Ash Resource Configuration**:
- **Domain**: `WhoThere.Domain`
- **Data Layer**: `AshPostgres.DataLayer`
- **Multitenancy**: Attribute-based with `tenant_id`
- **Table**: `analytics_events`

**Attributes**:
- `id`: UUID primary key
- `tenant_id`: UUID (required) - References tenant for isolation
- `event_type`: Atom (required) - `:page_view`, `:api_call`, `:liveview_event`, `:bot_traffic`
- `timestamp`: UTCDateTime (required) - When event occurred
- `session_id`: UUID (optional) - Links to Session
- `user_id`: String (optional) - From Phoenix Presence or auth
- `path`: String (required) - Request path, max 2000 chars
- `method`: String (optional) - HTTP method, max 10 chars
- `status_code`: Integer (optional) - HTTP response code
- `duration_ms`: Integer (optional) - Request duration in milliseconds
- `user_agent`: String (optional) - Full user agent, max 1000 chars
- `device_type`: String (optional) - `:desktop`, `:mobile`, `:tablet`, `:bot`
- `ip_address`: String (optional) - Anonymized IP, max 45 chars
- `country_code`: String (optional) - ISO country code, 2 chars
- `city`: String (optional) - City name, max 100 chars
- `referrer`: String (optional) - HTTP referrer, max 2000 chars
- `bot_name`: String (optional) - Identified bot name for bot traffic
- `metadata`: Map (default: %{}) - Additional event data

**Indexes**:
- `[:tenant_id, :timestamp]` - Primary query pattern
- `[:tenant_id, :event_type, :timestamp]` - Event type filtering
- `[:tenant_id, :path, :timestamp]` - Path analytics
- `[:session_id]` where session_id IS NOT NULL - Session analytics
- `[:tenant_id, :bot_name]` where event_type = :bot_traffic - Bot analytics

**Validations**:
- `tenant_id` must be present
- `event_type` must be one of allowed values
- `path` must start with '/'
- `status_code` must be 100-599 if present
- `duration_ms` must be non-negative if present
- `country_code` must be 2 characters if present

**Actions**:
- `create` - Create new event with automatic timestamp
- `read` - Read events with tenant filtering
- `by_date_range` - Query events within date range
- `by_event_type` - Filter by specific event types
- `bot_traffic_summary` - Aggregate bot traffic statistics

### Session
**Purpose**: User session tracking based on fingerprinting without cookies

**Ash Resource Configuration**:
- **Domain**: `WhoThere.Domain`
- **Data Layer**: `AshPostgres.DataLayer`
- **Multitenancy**: Attribute-based with `tenant_id`
- **Table**: `analytics_sessions`

**Attributes**:
- `id`: UUID primary key
- `tenant_id`: UUID (required) - References tenant for isolation
- `session_fingerprint`: String (required) - Hash of IP + User Agent, max 255 chars
- `user_id`: String (optional) - From Phoenix Presence or auth
- `started_at`: UTCDateTime (required) - Session start time
- `last_seen_at`: UTCDateTime (required) - Most recent activity
- `ended_at`: UTCDateTime (optional) - Explicit session end
- `page_views`: Integer (default: 0) - Number of page views
- `duration_seconds`: Integer (default: 0) - Computed session duration
- `entry_path`: String (required) - First page visited, max 2000 chars
- `exit_path`: String (optional) - Last page visited, max 2000 chars
- `referrer`: String (optional) - Session referrer, max 2000 chars
- `country_code`: String (optional) - ISO country code, 2 chars
- `city`: String (optional) - City name, max 100 chars
- `device_type`: String (optional) - Device classification
- `is_bot`: Boolean (default: false) - Bot session flag
- `is_bounce`: Boolean (default: true) - Single page session flag

**Indexes**:
- `[:tenant_id, :session_fingerprint]` unique - Session lookup
- `[:tenant_id, :started_at]` - Time-based queries
- `[:tenant_id, :is_bot]` - Bot session filtering
- `[:tenant_id, :user_id]` where user_id IS NOT NULL - User sessions

**Validations**:
- `tenant_id` must be present
- `session_fingerprint` must be present and unique per tenant
- `started_at` must be present
- `last_seen_at` must be >= `started_at`
- `entry_path` must start with '/'
- `exit_path` must start with '/' if present
- `page_views` must be non-negative

**Actions**:
- `create` - Create new session with computed fields
- `update` - Update session activity
- `end_session` - Mark session as ended
- `find_by_fingerprint` - Locate session by fingerprint
- `active_sessions` - Get currently active sessions
- `session_summary` - Generate session analytics

**Computed Fields**:
- `duration_seconds` - Computed from started_at and last_seen_at
- `is_bounce` - True if page_views <= 1

### AnalyticsConfiguration
**Purpose**: Tenant-specific analytics settings and privacy controls

**Ash Resource Configuration**:
- **Domain**: `WhoThere.Domain`
- **Data Layer**: `AshPostgres.DataLayer`
- **Multitenancy**: Attribute-based with `tenant_id`
- **Table**: `analytics_configurations`

**Attributes**:
- `id`: UUID primary key
- `tenant_id`: UUID (required) - References tenant for isolation
- `enabled`: Boolean (default: true) - Analytics collection enabled
- `collect_user_agents`: Boolean (default: true) - Store user agent strings
- `collect_referrers`: Boolean (default: true) - Store referrer information
- `collect_geolocation`: Boolean (default: true) - Store geographic data
- `anonymize_ips`: Boolean (default: true) - Anonymize IP addresses
- `exclude_admin_routes`: Boolean (default: true) - Skip admin panel tracking
- `exclude_patterns`: Array of String (default: []) - Custom exclusion patterns
- `session_timeout_minutes`: Integer (default: 30) - Session expiry timeout
- `data_retention_days`: Integer (default: 365) - Data retention period
- `bot_detection_enabled`: Boolean (default: true) - Enable bot detection
- `presence_integration`: Boolean (default: false) - Use Phoenix Presence
- `dashboard_enabled`: Boolean (default: true) - Enable analytics dashboard

**Indexes**:
- `[:tenant_id]` unique - One configuration per tenant

**Validations**:
- `tenant_id` must be present and unique
- `session_timeout_minutes` must be > 0 and <= 1440 (24 hours)
- `data_retention_days` must be > 0 and <= 3650 (10 years)
- Each pattern in `exclude_patterns` must be valid regex or string

**Actions**:
- `create` - Create tenant configuration with defaults
- `update` - Update configuration settings
- `get_by_tenant` - Retrieve configuration for tenant
- `bulk_update` - Update multiple settings atomically

### DailyAnalytics
**Purpose**: Pre-computed daily analytics summaries for efficient querying

**Ash Resource Configuration**:
- **Domain**: `WhoThere.Domain`
- **Data Layer**: `AshPostgres.DataLayer`
- **Multitenancy**: Attribute-based with `tenant_id`
- **Table**: `daily_analytics`

**Attributes**:
- `id`: UUID primary key
- `tenant_id`: UUID (required) - References tenant for isolation
- `date`: Date (required) - Analytics date
- `total_events`: Integer (default: 0) - Total events count
- `unique_sessions`: Integer (default: 0) - Unique sessions count
- `page_views`: Integer (default: 0) - Page view events
- `api_calls`: Integer (default: 0) - API call events
- `liveview_events`: Integer (default: 0) - LiveView interaction events
- `bot_events`: Integer (default: 0) - Bot traffic events
- `unique_visitors`: Integer (default: 0) - Estimated unique visitors
- `bounce_rate`: Float (default: 0.0) - Bounce rate percentage
- `avg_session_duration`: Float (default: 0.0) - Average session length in seconds
- `top_pages`: Map (default: %{}) - Most visited pages with counts
- `top_referrers`: Map (default: %{}) - Top referrer sources
- `device_breakdown`: Map (default: %{}) - Device type distribution
- `country_breakdown`: Map (default: %{}) - Geographic distribution
- `bot_breakdown`: Map (default: %{}) - Bot traffic by type

**Indexes**:
- `[:tenant_id, :date]` unique - Daily aggregations
- `[:tenant_id, :date]` DESC - Recent analytics queries

**Validations**:
- `tenant_id` must be present
- `date` must be present and unique per tenant
- All count fields must be non-negative
- `bounce_rate` must be between 0.0 and 1.0
- `avg_session_duration` must be non-negative

**Actions**:
- `create` - Create daily summary
- `update` - Update existing summary
- `get_by_date_range` - Retrieve summaries for date range
- `latest_summary` - Get most recent daily summary
- `aggregate_period` - Generate period aggregations (weekly, monthly)

### GeographicData
**Purpose**: Geographic reference data for analytics enrichment

**Ash Resource Configuration**:
- **Domain**: `WhoThere.Domain`
- **Data Layer**: `AshPostgres.DataLayer`
- **Table**: `geographic_data` (not tenant-specific - reference data)

**Attributes**:
- `id`: UUID primary key
- `country_code`: String (required) - ISO 3166-1 alpha-2 code
- `country_name`: String (required) - Full country name
- `region`: String (optional) - Continental region
- `timezone`: String (optional) - Representative timezone
- `currency`: String (optional) - Primary currency code
- `languages`: Array of String (default: []) - Primary languages

**Indexes**:
- `[:country_code]` unique - Country code lookup

**Actions**:
- `read` - Read geographic data
- `by_country_code` - Find by country code
- `by_region` - Filter by continental region

## Relationships

### AnalyticsEvent Relationships
- `belongs_to :session` - Links to Session via session_id
- `belongs_to :tenant` - References tenant entity

### Session Relationships
- `has_many :events` - All events in this session
- `belongs_to :tenant` - References tenant entity

### AnalyticsConfiguration Relationships
- `belongs_to :tenant` - References tenant entity

### DailyAnalytics Relationships
- `belongs_to :tenant` - References tenant entity

## Domain Policies

### Multi-tenant Isolation
All resources automatically filter by tenant_id through Ash multitenancy configuration. No cross-tenant data access is possible.

### Privacy Policies
- No PII storage in any analytics entities
- IP addresses are anonymized before storage
- User agents are optionally stored based on configuration
- Geographic data limited to country/city level

### Data Retention
- Configurable retention periods per tenant
- Automatic cleanup jobs for expired data
- Preservation of aggregated summaries after detail deletion

## State Transitions

### Session Lifecycle
1. **Created** - New session fingerprint detected
2. **Active** - Ongoing user activity, updating last_seen_at
3. **Expired** - No activity within timeout period
4. **Ended** - Explicitly closed (optional)

### Event Processing
1. **Collected** - Raw event from telemetry/plug
2. **Enriched** - Geographic and device data added
3. **Classified** - Bot detection and categorization
4. **Stored** - Persisted to AnalyticsEvent
5. **Aggregated** - Included in daily summaries

## Performance Considerations

### Indexing Strategy
- Primary indexes on tenant_id + timestamp for time-series queries
- Specialized indexes for bot traffic and session analytics
- Covering indexes to avoid table lookups for common queries

### Partitioning Strategy
- Consider table partitioning by date for large datasets
- Separate bot traffic for improved query performance
- Archive old data to separate tables/storage

### Caching Strategy
- Cache analytics configurations per tenant
- Pre-compute common aggregations
- Use ETS/Redis for frequently accessed summaries

## Data Migration Strategy

### Version 1.0 Schema
- Initial tables with core analytics functionality
- Basic multitenancy support
- Privacy-compliant data structure

### Future Migrations
- Additional analytics dimensions
- Enhanced bot detection fields
- Performance optimization indexes
- Data archival strategies

This data model provides a robust foundation for privacy-first, multi-tenant analytics while supporting advanced features like bot detection, geographic analysis, and real-time dashboards.