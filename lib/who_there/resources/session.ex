defmodule WhoThere.Resources.Session do
  @moduledoc """
  Session resource for tracking user sessions without cookies
  (based on fingerprinting + time window) with tenant isolation.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("analytics_sessions")
    repo(WhoThere.Repo)

    custom_indexes do
      # Primary query patterns for performance
      index([:tenant_id, :started_at])
      index([:tenant_id, :session_fingerprint], unique: true)
      index([:tenant_id, :is_bot])
      index([:tenant_id, :user_id], where: "user_id IS NOT NULL")
      index([:tenant_id, :last_seen_at])
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
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
      ])

      # Set started_at if not provided
      change(fn changeset, _opts ->
        case Ash.Changeset.get_attribute(changeset, :started_at) do
          nil -> Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
          _ -> changeset
        end
      end)

      # Set last_seen_at to started_at if not provided
      change(fn changeset, _opts ->
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
      end)

      # Compute is_bounce based on page_views
      change(fn changeset, _opts ->
        page_views = Ash.Changeset.get_attribute(changeset, :page_views) || 1
        is_bounce = page_views <= 1
        Ash.Changeset.change_attribute(changeset, :is_bounce, is_bounce)
      end)

      # Compute duration_seconds
      change(fn changeset, _opts ->
        started_at = Ash.Changeset.get_attribute(changeset, :started_at)
        last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)

        if started_at && last_seen_at do
          duration_seconds = DateTime.diff(last_seen_at, started_at, :second)
          Ash.Changeset.change_attribute(changeset, :duration_seconds, max(duration_seconds, 0))
        else
          changeset
        end
      end)
    end

    update :update do
      require_atomic?(false)

      accept([
        :last_seen_at,
        :page_views,
        :exit_path,
        :user_id
      ])

      # Recompute is_bounce when page_views change
      change(fn changeset, _opts ->
        page_views = Ash.Changeset.get_attribute(changeset, :page_views)

        if page_views do
          is_bounce = page_views <= 1
          Ash.Changeset.change_attribute(changeset, :is_bounce, is_bounce)
        else
          changeset
        end
      end)

      # Recompute duration_seconds when last_seen_at changes
      change(fn changeset, _opts ->
        last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)

        if last_seen_at do
          started_at = Ash.Changeset.get_data(changeset, :started_at)

          if started_at do
            duration_seconds = DateTime.diff(last_seen_at, started_at, :second)
            Ash.Changeset.change_attribute(changeset, :duration_seconds, max(duration_seconds, 0))
          else
            changeset
          end
        else
          changeset
        end
      end)
    end

    read :by_fingerprint do
      argument(:session_fingerprint, :string, allow_nil?: false)

      filter(expr(session_fingerprint == arg(:session_fingerprint)))
    end

    read :active_sessions do
      argument(:timeout_minutes, :integer, allow_nil?: false)

      prepare(fn query, _context ->
        timeout_minutes = Ash.Query.get_argument(query, :timeout_minutes)
        cutoff_time = DateTime.utc_now() |> DateTime.add(-timeout_minutes * 60, :second)

        Ash.Query.filter(query, expr(last_seen_at >= ^cutoff_time))
      end)
    end

    read :by_date_range do
      argument(:start_date, :utc_datetime, allow_nil?: false)
      argument(:end_date, :utc_datetime, allow_nil?: false)

      filter(expr(started_at >= arg(:start_date) and started_at <= arg(:end_date)))
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
    validate(present(:session_fingerprint), message: "Session fingerprint is required")

    # Fingerprint length validation
    validate(string_length(:session_fingerprint, min: 8, max: 255),
      message: "Session fingerprint must be between 8 and 255 characters"
    )

    # Page views validation
    validate(numericality(:page_views, greater_than_or_equal_to: 0),
      where: present(:page_views),
      message: "Page views must be non-negative"
    )

    # Duration validation
    validate(numericality(:duration_seconds, greater_than_or_equal_to: 0),
      where: present(:duration_seconds),
      message: "Duration must be non-negative"
    )

    # Country code validation if present
    validate(string_length(:country_code, exact: 2),
      where: present(:country_code),
      message: "Country code must be exactly 2 characters"
    )

    # Path format validation
    validate(match(:entry_path, ~r/^\/.*$/),
      where: present(:entry_path),
      message: "Entry path must start with '/'"
    )

    validate(match(:exit_path, ~r/^\/.*$/),
      where: present(:exit_path),
      message: "Exit path must start with '/'"
    )

    # Time validation - last_seen_at cannot be before started_at
    validate(fn changeset, _context ->
      started_at = Ash.Changeset.get_attribute(changeset, :started_at)
      last_seen_at = Ash.Changeset.get_attribute(changeset, :last_seen_at)

      if started_at && last_seen_at && DateTime.compare(last_seen_at, started_at) == :lt do
        {:error, field: :last_seen_at, message: "Last seen cannot be before session start"}
      else
        :ok
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

    attribute :session_fingerprint, :string do
      description("Unique session identifier (fingerprint)")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :user_id, :string do
      description("User identifier from Phoenix Presence or authentication")
      constraints(max_length: 255)
    end

    attribute :started_at, :utc_datetime_usec do
      description("When the session started")
      allow_nil?(false)
    end

    attribute :last_seen_at, :utc_datetime_usec do
      description("Last activity timestamp")
      allow_nil?(false)
    end

    attribute :duration_seconds, :integer do
      description("Session duration in seconds")
      default(0)
    end

    attribute :page_views, :integer do
      description("Number of page views in session")
      default(1)
    end

    attribute :entry_path, :string do
      description("First page visited in session")
      constraints(max_length: 2000)
    end

    attribute :exit_path, :string do
      description("Last page visited in session")
      constraints(max_length: 2000)
    end

    attribute :referrer, :string do
      description("Session referrer")
      constraints(max_length: 2000)
    end

    attribute :country_code, :string do
      description("Country code from IP geolocation")
      constraints(min_length: 2, max_length: 2)
    end

    attribute :city, :string do
      description("City from IP geolocation")
      constraints(max_length: 100)
    end

    attribute :device_type, :string do
      description("Device type: desktop, mobile, tablet, bot")
      constraints(max_length: 20)
    end

    attribute :is_bot, :boolean do
      description("Whether this session is from a bot")
      default(false)
    end

    attribute :is_bounce, :boolean do
      description("Whether this session is a bounce (single page view)")
      default(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :events, WhoThere.Resources.AnalyticsEvent do
      source_attribute(:id)
      destination_attribute(:session_id)
    end
  end

  calculations do
    calculate :is_active, :boolean do
      description("Whether this session is currently active (within timeout)")

      calculation(fn records, opts ->
        timeout_minutes = Keyword.get(opts, :timeout_minutes, 30)
        cutoff_time = DateTime.utc_now() |> DateTime.add(-timeout_minutes * 60, :second)

        Enum.map(records, fn record ->
          DateTime.compare(record.last_seen_at, cutoff_time) != :lt
        end)
      end)
    end

    calculate :geographic_label, :string do
      description("Human-readable geographic location")

      calculation(fn records, _opts ->
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
      end)
    end
  end

  identities do
    identity(:unique_session_per_tenant, [:tenant_id, :session_fingerprint])
  end
end
