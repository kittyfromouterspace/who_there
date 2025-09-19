defmodule WhoThere.Resources.DailyAnalytics do
  @moduledoc """
  DailyAnalytics resource for pre-computed daily summaries
  with efficient aggregations and tenant isolation.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("daily_analytics")
    repo(WhoThere.Repo)

    custom_indexes do
      # Primary query patterns for performance
      index([:tenant_id, :date], unique: true)
      index([:tenant_id, :date, :unique_visitors])
      index([:tenant_id, :date, :page_views])
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :tenant_id,
        :date,
        :unique_visitors,
        :page_views,
        :sessions,
        :bounced_sessions,
        :total_duration_seconds,
        :bot_requests,
        :human_requests,
        :top_pages,
        :top_referrers,
        :countries,
        :devices
      ])
    end

    update :update do
      accept([
        :unique_visitors,
        :page_views,
        :sessions,
        :bounced_sessions,
        :total_duration_seconds,
        :bot_requests,
        :human_requests,
        :top_pages,
        :top_referrers,
        :countries,
        :devices
      ])
    end

    read :by_date_range do
      argument(:start_date, :date, allow_nil?: false)
      argument(:end_date, :date, allow_nil?: false)

      filter(expr(date >= arg(:start_date) and date <= arg(:end_date)))
    end

    read :by_date do
      argument(:date, :date, allow_nil?: false)

      filter(expr(date == arg(:date)))
    end

    create :upsert do
      # For upserting daily analytics data
      upsert?(true)
      upsert_identity(:unique_analytics_per_tenant_date)

      accept([
        :tenant_id,
        :date,
        :unique_visitors,
        :page_views,
        :sessions,
        :bounced_sessions,
        :total_duration_seconds,
        :bot_requests,
        :human_requests,
        :top_pages,
        :top_referrers,
        :countries,
        :devices
      ])
    end
  end

  policies do
    # Analytics resources require proper tenant context
    # The multitenancy block automatically filters records by tenant_id
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if(always())
    end
  end

  validations do
    # Required field validations
    validate(present(:tenant_id), message: "Tenant ID is required")
    validate(present(:date), message: "Date is required")

    # Numeric validations
    validate(numericality(:unique_visitors, greater_than_or_equal_to: 0),
      where: present(:unique_visitors),
      message: "Unique visitors must be non-negative"
    )

    validate(numericality(:page_views, greater_than_or_equal_to: 0),
      where: present(:page_views),
      message: "Page views must be non-negative"
    )

    validate(numericality(:sessions, greater_than_or_equal_to: 0),
      where: present(:sessions),
      message: "Sessions must be non-negative"
    )

    validate(numericality(:bounced_sessions, greater_than_or_equal_to: 0),
      where: present(:bounced_sessions),
      message: "Bounced sessions must be non-negative"
    )

    validate(numericality(:total_duration_seconds, greater_than_or_equal_to: 0),
      where: present(:total_duration_seconds),
      message: "Total duration must be non-negative"
    )

    validate(numericality(:bot_requests, greater_than_or_equal_to: 0),
      where: present(:bot_requests),
      message: "Bot requests must be non-negative"
    )

    validate(numericality(:human_requests, greater_than_or_equal_to: 0),
      where: present(:human_requests),
      message: "Human requests must be non-negative"
    )

    # Logical validations
    validate(fn changeset, _context ->
      sessions = Ash.Changeset.get_attribute(changeset, :sessions)
      bounced_sessions = Ash.Changeset.get_attribute(changeset, :bounced_sessions)

      if sessions && bounced_sessions && bounced_sessions > sessions do
        {:error,
         field: :bounced_sessions, message: "Bounced sessions cannot exceed total sessions"}
      else
        :ok
      end
    end)

    # Date validation - cannot be in the future
    validate(fn changeset, _context ->
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
    end)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :tenant_id, :uuid do
      description("References tenant ID for isolation")
      allow_nil?(false)
      public?(true)
    end

    attribute :date, :date do
      description("Analytics date")
      allow_nil?(false)
    end

    # Core metrics
    attribute :unique_visitors, :integer do
      description("Number of unique visitors")
      default(0)
    end

    attribute :page_views, :integer do
      description("Total page views")
      default(0)
    end

    attribute :sessions, :integer do
      description("Number of sessions")
      default(0)
    end

    attribute :bounced_sessions, :integer do
      description("Number of single-page sessions")
      default(0)
    end

    attribute :total_duration_seconds, :integer do
      description("Total session duration in seconds")
      default(0)
    end

    attribute :bot_requests, :integer do
      description("Number of bot requests")
      default(0)
    end

    attribute :human_requests, :integer do
      description("Number of human requests")
      default(0)
    end

    # JSON data fields for detailed breakdowns
    attribute :top_pages, :map do
      description("Top pages with view counts")
      default(%{})
    end

    attribute :top_referrers, :map do
      description("Top referrers with counts")
      default(%{})
    end

    attribute :countries, :map do
      description("Country breakdown with counts")
      default(%{})
    end

    attribute :devices, :map do
      description("Device type breakdown with counts")
      default(%{})
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  calculations do
    calculate :bounce_rate, :float do
      description("Bounce rate as a percentage (0-100)")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          if record.sessions > 0 do
            record.bounced_sessions / record.sessions * 100
          else
            0.0
          end
        end)
      end)
    end

    calculate :avg_session_duration, :float do
      description("Average session duration in seconds")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          if record.sessions > 0 do
            record.total_duration_seconds / record.sessions
          else
            0.0
          end
        end)
      end)
    end

    calculate :pages_per_session, :float do
      description("Average pages per session")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          if record.sessions > 0 do
            record.page_views / record.sessions
          else
            0.0
          end
        end)
      end)
    end

    calculate :bot_percentage, :float do
      description("Percentage of bot traffic (0-100)")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          total_requests = record.bot_requests + record.human_requests

          if total_requests > 0 do
            record.bot_requests / total_requests * 100
          else
            0.0
          end
        end)
      end)
    end

    calculate :total_requests, :integer do
      description("Total requests (bot + human)")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          record.bot_requests + record.human_requests
        end)
      end)
    end
  end

  identities do
    identity(:unique_analytics_per_tenant_date, [:tenant_id, :date])
  end
end
