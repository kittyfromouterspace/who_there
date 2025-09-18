defmodule WhoThere.Session do
  @moduledoc """
  Session resource for tracking user sessions without cookies
  (based on fingerprinting + time window) with tenant isolation.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "analytics_sessions"
    repo WhoThere.Repo

    custom_indexes do
      # Primary query patterns for performance
      index [:tenant_id, :started_at]
      index [:tenant_id, :session_fingerprint], unique: true
      index [:tenant_id, :is_bot]
      index [:tenant_id, :user_id], where: "user_id IS NOT NULL"
      index [:tenant_id, :last_seen_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tenant_id,
        :session_fingerprint,
        :user_id,
        :started_at,
        :last_seen_at,
        :page_views,
        :entry_path,
        :exit_path,
        :referrer,
        :country_code,
        :city,
        :device_type,
        :is_bot
      ]

      # Set started_at if not provided
      change fn changeset, _opts ->
        case Ash.Changeset.get_attribute(changeset, :started_at) do
          nil -> Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
          _ -> changeset
        end
      end

      # Set last_seen_at to started_at if not provided
      change fn changeset, _opts ->
        case Ash.Changeset.get_attribute(changeset, :last_seen_at) do
          nil ->
            started_at = Ash.Changeset.get_attribute(changeset, :started_at)
            if started_at do
              Ash.Changeset.change_attribute(changeset, :last_seen_at, started_at)
            else
              changeset
            end
          _ ->
            changeset
        end
      end

      # Compute is_bounce based on page_views
      change fn changeset, _opts ->
        page_views = Ash.Changeset.get_attribute(changeset, :page_views) || 1
        is_bounce = page_views <= 1
        Ash.Changeset.change_attribute(changeset, :is_bounce, is_bounce)
      end

      # Compute duration_seconds
      change fn changeset, _opts ->
        started_at = Ash.Changeset.get_attribute(changeset, :started_at)
        last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)

        if started_at && last_seen_at do
          duration_seconds = DateTime.diff(last_seen_at, started_at, :second)
          Ash.Changeset.change_attribute(changeset, :duration_seconds, max(duration_seconds, 0))
        else
          changeset
        end
      end
    end

    update :update do
      accept [
        :last_seen_at,
        :page_views,
        :exit_path,
        :user_id
      ]

      # Function-based changes can't be atomic
      require_atomic? false

      # Recompute is_bounce and duration when updated
      change fn changeset, _opts ->
        page_views = Ash.Changeset.get_attribute(changeset, :page_views)

        changeset =
          if page_views do
            is_bounce = page_views <= 1
            Ash.Changeset.change_attribute(changeset, :is_bounce, is_bounce)
          else
            changeset
          end

        # Recompute duration if last_seen_at changed
        last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)

        if last_seen_at do
          started_at = Ash.Changeset.get_data(changeset, :started_at)
          duration_seconds = DateTime.diff(last_seen_at, started_at, :second)
          Ash.Changeset.change_attribute(changeset, :duration_seconds, max(duration_seconds, 0))
        else
          changeset
        end
      end
    end

    update :end_session do
      # Custom action to end/expire a session
      accept [:exit_path, :last_seen_at, :ended_at]

      # Function-based changes can't be atomic
      require_atomic? false

      change fn changeset, _opts ->
        now = DateTime.utc_now()

        # Set ended_at and last_seen_at to now if not provided
        changeset =
          case Ash.Changeset.get_attribute(changeset, :ended_at) do
            nil -> Ash.Changeset.change_attribute(changeset, :ended_at, now)
            _ -> changeset
          end

        changeset =
          case Ash.Changeset.get_attribute(changeset, :last_seen_at) do
            nil -> Ash.Changeset.change_attribute(changeset, :last_seen_at, now)
            _ -> changeset
          end

        # Recompute duration
        started_at = Ash.Changeset.get_data(changeset, :started_at)
        last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)
        duration_seconds = DateTime.diff(last_seen_at, started_at, :second)
        Ash.Changeset.change_attribute(changeset, :duration_seconds, max(duration_seconds, 0))
      end
    end

    read :by_fingerprint do
      argument :fingerprint, :string, allow_nil?: false

      prepare fn query, _context ->
        fingerprint = Ash.Query.get_argument(query, :fingerprint)
        Ash.Query.filter(query, session_fingerprint == ^fingerprint)
      end
    end

    read :active_sessions do
      argument :timeout_minutes, :integer, default_value: 30

      prepare fn query, _context ->
        timeout_minutes = Ash.Query.get_argument(query, :timeout_minutes)
        cutoff_time = DateTime.add(DateTime.utc_now(), -timeout_minutes * 60, :second)

        query
        |> Ash.Query.filter(
          last_seen_at >= ^cutoff_time and
          (is_nil(ended_at) or ended_at >= ^cutoff_time)
        )
        |> Ash.Query.sort(last_seen_at: :desc)
      end
    end

    read :by_date_range do
      argument :start_date, :utc_datetime, allow_nil?: false
      argument :end_date, :utc_datetime, allow_nil?: false

      prepare fn query, _context ->
        start_date = Ash.Query.get_argument(query, :start_date)
        end_date = Ash.Query.get_argument(query, :end_date)

        Ash.Query.filter(query,
          started_at >= ^start_date and started_at <= ^end_date
        )
      end
    end

    read :by_user do
      argument :user_id, :string, allow_nil?: false

      prepare fn query, _context ->
        user_id = Ash.Query.get_argument(query, :user_id)
        Ash.Query.filter(query, user_id == ^user_id)
      end
    end

    read :session_summary do
      argument :start_date, :utc_datetime, allow_nil?: false
      argument :end_date, :utc_datetime, allow_nil?: false

      prepare fn query, _context ->
        start_date = Ash.Query.get_argument(query, :start_date)
        end_date = Ash.Query.get_argument(query, :end_date)

        query
        |> Ash.Query.filter(
          started_at >= ^start_date and
          started_at <= ^end_date and
          is_bot == false
        )
        |> Ash.Query.aggregate(:count, :total_sessions)
        |> Ash.Query.aggregate(:avg, :avg_duration, field: :duration_seconds)
        |> Ash.Query.aggregate(:sum, :total_page_views, field: :page_views)
        |> Ash.Query.aggregate(:count, :bounce_sessions, filter: [is_bounce: true])
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
    validate present(:session_fingerprint), message: "Session fingerprint is required"
    validate present(:started_at), message: "Start time is required"
    validate present(:entry_path), message: "Entry path is required"

    # Entry path format validation - must start with /
    validate match(:entry_path, ~r/^\/.*$/),
      message: "Entry path must start with '/'"

    # Exit path format validation if present
    validate match(:exit_path, ~r/^\/.*$/),
      where: present(:exit_path),
      message: "Exit path must start with '/'"

    # Page views validation
    validate numericality(:page_views, greater_than_or_equal_to: 0),
      message: "Page views must be non-negative"

    # Duration validation
    validate numericality(:duration_seconds, greater_than_or_equal_to: 0),
      where: present(:duration_seconds),
      message: "Duration must be non-negative"

    # Timestamp validation - started_at <= last_seen_at <= ended_at
    validate fn changeset, _context ->
      started_at =
        Ash.Changeset.get_attribute(changeset, :started_at) ||
          Ash.Changeset.get_data(changeset, :started_at)

      last_seen_at =
        Ash.Changeset.get_attribute(changeset, :last_seen_at) ||
          Ash.Changeset.get_data(changeset, :last_seen_at)

      ended_at =
        Ash.Changeset.get_attribute(changeset, :ended_at) ||
          Ash.Changeset.get_data(changeset, :ended_at)

      cond do
        started_at && last_seen_at && DateTime.compare(started_at, last_seen_at) == :gt ->
          {:error, field: :last_seen_at, message: "Last seen time must be after start time"}

        last_seen_at && ended_at && DateTime.compare(last_seen_at, ended_at) == :gt ->
          {:error, field: :ended_at, message: "End time must be after last seen time"}

        true ->
          :ok
      end
    end

    # Country code validation if present
    validate string_length(:country_code, exact: 2),
      where: present(:country_code),
      message: "Country code must be exactly 2 characters"
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

    attribute :session_fingerprint, :string do
      description "Hash of IP + User Agent + time window"
      allow_nil? false
      constraints max_length: 255
    end

    attribute :user_id, :string do
      description "User identifier from Phoenix Presence or authentication"
      constraints max_length: 255
    end

    attribute :started_at, :utc_datetime_usec do
      description "Session start time"
      allow_nil? false
    end

    attribute :last_seen_at, :utc_datetime_usec do
      description "Most recent activity"
      allow_nil? false
    end

    attribute :ended_at, :utc_datetime_usec do
      description "Session end time (explicit or timeout)"
    end

    attribute :page_views, :integer do
      description "Number of page views in session"
      default 1
      constraints min: 0
    end

    attribute :duration_seconds, :integer do
      description "Session duration in seconds (computed)"
      default 0
      # Computed field but needs to be writable for internal changes
    end

    attribute :entry_path, :string do
      description "First page visited"
      allow_nil? false
      constraints max_length: 2000
    end

    attribute :exit_path, :string do
      description "Last page visited"
      constraints max_length: 2000
    end

    attribute :referrer, :string do
      description "Session referrer"
      constraints max_length: 2000
    end

    attribute :country_code, :string do
      description "Country code from proxy headers or IP geolocation"
      constraints min_length: 2, max_length: 2
    end

    attribute :city, :string do
      description "City from proxy headers or IP geolocation"
      constraints max_length: 100
    end

    attribute :device_type, :string do
      description "Device type: desktop, mobile, tablet, bot"
      constraints max_length: 20
    end

    attribute :is_bot, :boolean do
      description "Bot session flag"
      default false
    end

    attribute :is_bounce, :boolean do
      description "Single page session (computed)"
      default true
      # Computed field but needs to be writable for internal changes
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :events, WhoThere.AnalyticsEvent do
      source_attribute :id
      destination_attribute :session_id
    end
  end

  identities do
    identity :unique_session_per_tenant, [:tenant_id, :session_fingerprint]
  end

  aggregates do
    count :event_count, :events do
      description "Total number of events in this session"
    end

    first :first_event_timestamp, :events, :timestamp do
      description "Timestamp of first event in session"
      sort [:timestamp]
    end

    last :last_event_timestamp, :events, :timestamp do
      description "Timestamp of last event in session"
      sort [:timestamp]
    end
  end

  calculations do
    calculate :is_active, :boolean do
      description "Whether session is currently active"
      argument :timeout_minutes, :integer, default_value: 30

      calculation fn records, %{timeout_minutes: timeout_minutes} ->
        cutoff_time = DateTime.add(DateTime.utc_now(), -timeout_minutes * 60, :second)

        Enum.map(records, fn record ->
          is_nil(record.ended_at) and
            DateTime.compare(record.last_seen_at, cutoff_time) == :gt
        end)
      end
    end

    calculate :bounce_rate, :float do
      description "Bounce rate as decimal (0.0 to 1.0)"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          if record.is_bounce, do: 1.0, else: 0.0
        end)
      end
    end

    calculate :pages_per_session, :float do
      description "Average pages per session"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          Float.round(record.page_views / 1, 2)
        end)
      end
    end

    calculate :geographic_label, :string do
      description "Human-readable geographic location"
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case {record.city, record.country_code} do
            {city, country} when not is_nil(city) and not is_nil(country) ->
              "#{city}, #{country}"
            {nil, country} when not is_nil(country) ->
              country
            _ ->
              "Unknown"
          end
        end)
      end
    end
  end
end