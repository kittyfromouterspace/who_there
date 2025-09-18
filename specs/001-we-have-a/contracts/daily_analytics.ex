defmodule WhoThere.DailyAnalytics do
  @moduledoc """
  DailyAnalytics resource for pre-computed daily analytics summaries
  with efficient querying and aggregation capabilities.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "daily_analytics"
    repo WhoThere.Repo

    custom_indexes do
      # Primary query patterns for performance
      index [:tenant_id, :date], unique: true
      index [:tenant_id, :date], where: "date >= CURRENT_DATE - INTERVAL '30 days'"
      index [:date] # For cross-tenant analytics (admin use)
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tenant_id,
        :date,
        :total_events,
        :unique_sessions,
        :page_views,
        :api_calls,
        :liveview_events,
        :bot_events,
        :unique_visitors,
        :bounce_rate,
        :avg_session_duration,
        :top_pages,
        :top_referrers,
        :device_breakdown,
        :country_breakdown,
        :bot_breakdown,
        :performance_metrics
      ]

      # Validate and compute derived metrics
      change fn changeset, _opts ->
        # Compute bounce rate if not provided
        bounce_rate = Ash.Changeset.get_attribute(changeset, :bounce_rate)
        unique_sessions = Ash.Changeset.get_attribute(changeset, :unique_sessions)

        if is_nil(bounce_rate) and unique_sessions && unique_sessions > 0 do
          # Placeholder - would be computed from actual bounce sessions
          computed_bounce_rate = 0.0
          Ash.Changeset.change_attribute(changeset, :bounce_rate, computed_bounce_rate)
        else
          changeset
        end
      end

      # Validate top_pages and other JSON fields
      change fn changeset, _opts ->
        top_pages = Ash.Changeset.get_attribute(changeset, :top_pages) || %{}
        top_referrers = Ash.Changeset.get_attribute(changeset, :top_referrers) || %{}
        device_breakdown = Ash.Changeset.get_attribute(changeset, :device_breakdown) || %{}
        country_breakdown = Ash.Changeset.get_attribute(changeset, :country_breakdown) || %{}
        bot_breakdown = Ash.Changeset.get_attribute(changeset, :bot_breakdown) || %{}

        changeset
        |> Ash.Changeset.change_attribute(:top_pages, top_pages)
        |> Ash.Changeset.change_attribute(:top_referrers, top_referrers)
        |> Ash.Changeset.change_attribute(:device_breakdown, device_breakdown)
        |> Ash.Changeset.change_attribute(:country_breakdown, country_breakdown)
        |> Ash.Changeset.change_attribute(:bot_breakdown, bot_breakdown)
      end
    end

    update :update do
      accept [
        :total_events,
        :unique_sessions,
        :page_views,
        :api_calls,
        :liveview_events,
        :bot_events,
        :unique_visitors,
        :bounce_rate,
        :avg_session_duration,
        :top_pages,
        :top_referrers,
        :device_breakdown,
        :country_breakdown,
        :bot_breakdown,
        :performance_metrics
      ]
    end

    read :by_date_range do
      argument :start_date, :date, allow_nil?: false
      argument :end_date, :date, allow_nil?: false

      prepare fn query, _context ->
        start_date = Ash.Query.get_argument(query, :start_date)
        end_date = Ash.Query.get_argument(query, :end_date)

        query
        |> Ash.Query.filter(date >= ^start_date and date <= ^end_date)
        |> Ash.Query.sort(date: :desc)
      end
    end

    read :latest_summary do
      argument :days, :integer, default_value: 1

      prepare fn query, _context ->
        days = Ash.Query.get_argument(query, :days)
        start_date = Date.add(Date.utc_today(), -days)

        query
        |> Ash.Query.filter(date >= ^start_date)
        |> Ash.Query.sort(date: :desc)
        |> Ash.Query.limit(days)
      end
    end

    read :monthly_summary do
      argument :year, :integer, allow_nil?: false
      argument :month, :integer, allow_nil?: false

      prepare fn query, _context ->
        year = Ash.Query.get_argument(query, :year)
        month = Ash.Query.get_argument(query, :month)

        start_date = Date.new!(year, month, 1)
        end_date = Date.end_of_month(start_date)

        query
        |> Ash.Query.filter(date >= ^start_date and date <= ^end_date)
        |> Ash.Query.sort(date: :asc)
      end
    end

    read :aggregate_period do
      argument :start_date, :date, allow_nil?: false
      argument :end_date, :date, allow_nil?: false
      argument :period, :atom, allow_nil?: false # :daily, :weekly, :monthly

      prepare fn query, _context ->
        start_date = Ash.Query.get_argument(query, :start_date)
        end_date = Ash.Query.get_argument(query, :end_date)
        period = Ash.Query.get_argument(query, :period)

        base_query =
          query
          |> Ash.Query.filter(date >= ^start_date and date <= ^end_date)

        case period do
          :daily ->
            Ash.Query.sort(base_query, date: :asc)

          :weekly ->
            base_query
            |> Ash.Query.aggregate(:sum, :weekly_total_events, field: :total_events)
            |> Ash.Query.aggregate(:sum, :weekly_unique_sessions, field: :unique_sessions)
            |> Ash.Query.aggregate(:avg, :weekly_avg_bounce_rate, field: :bounce_rate)

          :monthly ->
            base_query
            |> Ash.Query.aggregate(:sum, :monthly_total_events, field: :total_events)
            |> Ash.Query.aggregate(:sum, :monthly_unique_sessions, field: :unique_sessions)
            |> Ash.Query.aggregate(:avg, :monthly_avg_bounce_rate, field: :bounce_rate)

          _ ->
            base_query
        end
      end
    end

    read :top_performing_days do
      argument :metric, :atom, allow_nil?: false # :page_views, :unique_sessions, etc.
      argument :limit, :integer, default_value: 10
      argument :days_back, :integer, default_value: 30

      prepare fn query, _context ->
        metric = Ash.Query.get_argument(query, :metric)
        limit = Ash.Query.get_argument(query, :limit)
        days_back = Ash.Query.get_argument(query, :days_back)

        start_date = Date.add(Date.utc_today(), -days_back)

        sort_field = case metric do
          :page_views -> [page_views: :desc]
          :unique_sessions -> [unique_sessions: :desc]
          :unique_visitors -> [unique_visitors: :desc]
          :total_events -> [total_events: :desc]
          _ -> [total_events: :desc]
        end

        query
        |> Ash.Query.filter(date >= ^start_date)
        |> Ash.Query.sort(sort_field)
        |> Ash.Query.limit(limit)
      end
    end
  end

  policies do
    # Analytics resources require proper tenant context
    # The multitenancy block automatically filters records by tenant_id
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if always()
    end
  end

  validations do
    # Required field validations
    validate present(:tenant_id), message: "Tenant ID is required"
    validate present(:date), message: "Date is required"

    # All count fields must be non-negative
    validate numericality(:total_events, greater_than_or_equal_to: 0),
      message: "Total events must be non-negative"

    validate numericality(:unique_sessions, greater_than_or_equal_to: 0),
      message: "Unique sessions must be non-negative"

    validate numericality(:page_views, greater_than_or_equal_to: 0),
      message: "Page views must be non-negative"

    validate numericality(:api_calls, greater_than_or_equal_to: 0),
      message: "API calls must be non-negative"

    validate numericality(:liveview_events, greater_than_or_equal_to: 0),
      message: "LiveView events must be non-negative"

    validate numericality(:bot_events, greater_than_or_equal_to: 0),
      message: "Bot events must be non-negative"

    validate numericality(:unique_visitors, greater_than_or_equal_to: 0),
      message: "Unique visitors must be non-negative"

    # Bounce rate validation
    validate numericality(:bounce_rate, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0),
      where: present(:bounce_rate),
      message: "Bounce rate must be between 0.0 and 1.0"

    # Average session duration validation
    validate numericality(:avg_session_duration, greater_than_or_equal_to: 0.0),
      where: present(:avg_session_duration),
      message: "Average session duration must be non-negative"

    # Date validation - cannot be in the future
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :date) do
        nil ->
          :ok

        date ->
          if Date.compare(date, Date.utc_today()) == :gt do
            {:error, field: :date, message: "Date cannot be in the future"}
          else
            :ok
          end
      end
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
  end

  attributes do
    uuid_primary_key :id

    attribute :tenant_id, :uuid do
      description "References tenant ID for isolation"
      allow_nil? false
      public? true
    end

    attribute :date, :date do
      description "Analytics date"
      allow_nil? false
    end

    # Core Metrics
    attribute :total_events, :integer do
      description "Total events count"
      default 0
      constraints min: 0
    end

    attribute :unique_sessions, :integer do
      description "Unique sessions count"
      default 0
      constraints min: 0
    end

    attribute :page_views, :integer do
      description "Page view events"
      default 0
      constraints min: 0
    end

    attribute :api_calls, :integer do
      description "API call events"
      default 0
      constraints min: 0
    end

    attribute :liveview_events, :integer do
      description "LiveView interaction events"
      default 0
      constraints min: 0
    end

    attribute :bot_events, :integer do
      description "Bot traffic events"
      default 0
      constraints min: 0
    end

    attribute :unique_visitors, :integer do
      description "Estimated unique visitors"
      default 0
      constraints min: 0
    end

    # Computed Metrics
    attribute :bounce_rate, :float do
      description "Bounce rate as decimal (0.0 to 1.0)"
      default 0.0
      constraints min: 0.0, max: 1.0
    end

    attribute :avg_session_duration, :float do
      description "Average session length in seconds"
      default 0.0
      constraints min: 0.0
    end

    # Breakdown Data (JSON fields)
    attribute :top_pages, :map do
      description "Most visited pages with counts"
      default %{}
    end

    attribute :top_referrers, :map do
      description "Top referrer sources with counts"
      default %{}
    end

    attribute :device_breakdown, :map do
      description "Device type distribution"
      default %{}
    end

    attribute :country_breakdown, :map do
      description "Geographic distribution by country"
      default %{}
    end

    attribute :bot_breakdown, :map do
      description "Bot traffic breakdown by bot type"
      default %{}
    end

    attribute :performance_metrics, :map do
      description "Performance-related metrics (avg response time, etc.)"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_daily_summary, [:tenant_id, :date]
  end

  calculations do
    calculate :human_traffic_events, :integer do
      description "Total events excluding bot traffic"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          record.total_events - record.bot_events
        end)
      end
    end

    calculate :bounce_rate_percentage, :float do
      description "Bounce rate as percentage (0-100)"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          Float.round((record.bounce_rate || 0.0) * 100, 1)
        end)
      end
    end

    calculate :avg_session_duration_minutes, :float do
      description "Average session duration in minutes"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          Float.round((record.avg_session_duration || 0.0) / 60, 1)
        end)
      end
    end

    calculate :events_per_session, :float do
      description "Average events per session"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          if record.unique_sessions > 0 do
            Float.round(record.total_events / record.unique_sessions, 2)
          else
            0.0
          end
        end)
      end
    end

    calculate :pages_per_session, :float do
      description "Average page views per session"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          if record.unique_sessions > 0 do
            Float.round(record.page_views / record.unique_sessions, 2)
          else
            0.0
          end
        end)
      end
    end

    calculate :bot_traffic_percentage, :float do
      description "Percentage of traffic that is bot traffic"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          if record.total_events > 0 do
            Float.round((record.bot_events / record.total_events) * 100, 1)
          else
            0.0
          end
        end)
      end
    end

    calculate :top_page, :string do
      description "Most visited page for the day"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.top_pages do
            pages when is_map(pages) and map_size(pages) > 0 ->
              {page, _count} =
                pages
                |> Enum.max_by(fn {_page, count} -> count end, fn -> {nil, 0} end)
              page || "N/A"
            _ ->
              "N/A"
          end
        end)
      end
    end

    calculate :top_referrer, :string do
      description "Top referrer source for the day"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.top_referrers do
            referrers when is_map(referrers) and map_size(referrers) > 0 ->
              {referrer, _count} =
                referrers
                |> Enum.max_by(fn {_ref, count} -> count end, fn -> {nil, 0} end)
              referrer || "Direct"
            _ ->
              "Direct"
          end
        end)
      end
    end

    calculate :primary_device_type, :string do
      description "Most common device type for the day"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.device_breakdown do
            devices when is_map(devices) and map_size(devices) > 0 ->
              {device, _count} =
                devices
                |> Enum.max_by(fn {_device, count} -> count end, fn -> {nil, 0} end)
              device || "Unknown"
            _ ->
              "Unknown"
          end
        end)
      end
    end

    calculate :top_country, :string do
      description "Country with most traffic for the day"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.country_breakdown do
            countries when is_map(countries) and map_size(countries) > 0 ->
              {country, _count} =
                countries
                |> Enum.max_by(fn {_country, count} -> count end, fn -> {nil, 0} end)
              country || "Unknown"
            _ ->
              "Unknown"
          end
        end)
      end
    end
  end

  aggregates do
    # Useful for period summaries
    sum :period_total_events, :total_events
    sum :period_unique_sessions, :unique_sessions
    sum :period_page_views, :page_views
    sum :period_api_calls, :api_calls
    sum :period_liveview_events, :liveview_events
    sum :period_bot_events, :bot_events
    avg :period_avg_bounce_rate, :bounce_rate
    avg :period_avg_session_duration, :avg_session_duration
  end
end