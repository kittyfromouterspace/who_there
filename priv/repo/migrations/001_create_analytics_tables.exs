defmodule WhoThere.Repo.Migrations.CreateAnalyticsTables do
  @moduledoc """
  Creates all analytics tables for WhoThere analytics system.

  This migration creates:
  - analytics_configurations: Tenant-specific analytics settings
  - analytics_events: Individual event tracking
  - analytics_sessions: Session tracking without cookies
  - daily_analytics: Pre-computed daily summaries
  """

  use Ecto.Migration

  def up do
    # Create analytics_configurations table
    create table(:analytics_configurations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false

      # Core Analytics Settings
      add :enabled, :boolean, default: true, null: false

      # Data Collection Settings
      add :collect_user_agents, :boolean, default: true, null: false
      add :collect_referrers, :boolean, default: true, null: false
      add :collect_geolocation, :boolean, default: true, null: false
      add :anonymize_ips, :boolean, default: true, null: false

      # Route Filtering Settings
      add :exclude_admin_routes, :boolean, default: true, null: false
      add :exclude_patterns, {:array, :string}, default: [], null: false

      # Session and Retention Settings
      add :session_timeout_minutes, :integer, default: 30, null: false
      add :data_retention_days, :integer, default: 365, null: false

      # Advanced Features
      add :bot_detection_enabled, :boolean, default: true, null: false
      add :presence_integration, :boolean, default: false, null: false
      add :dashboard_enabled, :boolean, default: true, null: false
      add :d3_visualizations_enabled, :boolean, default: true, null: false
      add :proxy_header_detection, :boolean, default: true, null: false
      add :live_view_deduplication, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create unique index for tenant_id in analytics_configurations
    create unique_index(:analytics_configurations, [:tenant_id])

    # Create analytics_sessions table
    create table(:analytics_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :session_fingerprint, :string, size: 255, null: false
      add :user_id, :string, size: 255
      add :started_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :duration_seconds, :integer, default: 0, null: false
      add :page_views, :integer, default: 1, null: false
      add :entry_path, :string, size: 2000
      add :exit_path, :string, size: 2000
      add :referrer, :string, size: 2000
      add :country_code, :string, size: 2
      add :city, :string, size: 100
      add :device_type, :string, size: 20
      add :is_bot, :boolean, default: false, null: false
      add :is_bounce, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for analytics_sessions
    create index(:analytics_sessions, [:tenant_id, :started_at])
    create unique_index(:analytics_sessions, [:tenant_id, :session_fingerprint])
    create index(:analytics_sessions, [:tenant_id, :is_bot])
    create index(:analytics_sessions, [:tenant_id, :user_id], where: "user_id IS NOT NULL")
    create index(:analytics_sessions, [:tenant_id, :last_seen_at])

    # Create analytics_events table
    create table(:analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :event_type, :string, size: 50, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :session_id, :binary_id
      add :user_id, :string, size: 255
      add :path, :string, size: 2000, null: false
      add :method, :string, size: 10
      add :status_code, :integer
      add :duration_ms, :integer
      add :user_agent, :string, size: 1000
      add :device_type, :string, size: 20
      add :ip_address, :string, size: 45
      add :country_code, :string, size: 2
      add :city, :string, size: 100
      add :referrer, :string, size: 2000
      add :bot_name, :string, size: 100
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for analytics_events (optimized for queries)
    create index(:analytics_events, [:tenant_id, :timestamp])
    create index(:analytics_events, [:tenant_id, :event_type, :timestamp])
    create index(:analytics_events, [:tenant_id, :path, :timestamp])
    create index(:analytics_events, [:session_id], where: "session_id IS NOT NULL")
    create index(:analytics_events, [:tenant_id, :bot_name], where: "event_type = 'bot_traffic'")

    # Create daily_analytics table
    create table(:daily_analytics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :date, :date, null: false

      # Core metrics
      add :unique_visitors, :integer, default: 0, null: false
      add :page_views, :integer, default: 0, null: false
      add :sessions, :integer, default: 0, null: false
      add :bounced_sessions, :integer, default: 0, null: false
      add :total_duration_seconds, :integer, default: 0, null: false
      add :bot_requests, :integer, default: 0, null: false
      add :human_requests, :integer, default: 0, null: false

      # JSON data fields for detailed breakdowns
      add :top_pages, :map, default: %{}, null: false
      add :top_referrers, :map, default: %{}, null: false
      add :countries, :map, default: %{}, null: false
      add :devices, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for daily_analytics
    create unique_index(:daily_analytics, [:tenant_id, :date])
    create index(:daily_analytics, [:tenant_id, :date, :unique_visitors])
    create index(:daily_analytics, [:tenant_id, :date, :page_views])

    # Add foreign key constraint from analytics_events to analytics_sessions
    alter table(:analytics_events) do
      modify :session_id, references(:analytics_sessions, type: :binary_id, on_delete: :nilify_all)
    end

    # Create constraint to ensure event_type is valid
    create constraint(:analytics_events, :valid_event_type,
      check: "event_type IN ('page_view', 'api_call', 'liveview_event', 'bot_traffic')")

    # Create constraint to ensure country_code is exactly 2 chars when present
    create constraint(:analytics_events, :valid_country_code,
      check: "country_code IS NULL OR char_length(country_code) = 2")

    create constraint(:analytics_sessions, :valid_country_code,
      check: "country_code IS NULL OR char_length(country_code) = 2")

    # Create constraint to ensure positive numeric values
    create constraint(:analytics_events, :positive_duration,
      check: "duration_ms IS NULL OR duration_ms >= 0")

    create constraint(:analytics_events, :valid_status_code,
      check: "status_code IS NULL OR (status_code >= 100 AND status_code <= 599)")

    create constraint(:analytics_sessions, :positive_page_views,
      check: "page_views >= 0")

    create constraint(:analytics_sessions, :positive_duration,
      check: "duration_seconds >= 0")

    create constraint(:daily_analytics, :positive_metrics,
      check: "unique_visitors >= 0 AND page_views >= 0 AND sessions >= 0 AND bounced_sessions >= 0 AND total_duration_seconds >= 0 AND bot_requests >= 0 AND human_requests >= 0")

    create constraint(:daily_analytics, :bounced_sessions_logical,
      check: "bounced_sessions <= sessions")

    # Create constraint to ensure paths start with /
    create constraint(:analytics_events, :valid_path,
      check: "path ~ '^/'")

    create constraint(:analytics_sessions, :valid_entry_path,
      check: "entry_path IS NULL OR entry_path ~ '^/'")

    create constraint(:analytics_sessions, :valid_exit_path,
      check: "exit_path IS NULL OR exit_path ~ '^/'")

    # Create constraint to ensure last_seen_at >= started_at in sessions
    create constraint(:analytics_sessions, :valid_session_times,
      check: "last_seen_at >= started_at")

    # Create constraint to ensure session_timeout_minutes and data_retention_days are in valid ranges
    create constraint(:analytics_configurations, :valid_session_timeout,
      check: "session_timeout_minutes > 0 AND session_timeout_minutes <= 1440")

    create constraint(:analytics_configurations, :valid_data_retention,
      check: "data_retention_days > 0 AND data_retention_days <= 3650")
  end

  def down do
    # Drop tables in reverse order to handle foreign key dependencies
    drop table(:daily_analytics)
    drop table(:analytics_events)
    drop table(:analytics_sessions)
    drop table(:analytics_configurations)
  end
end