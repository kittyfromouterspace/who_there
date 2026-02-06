defmodule WhoThere.Resources.AnalyticsEvent do
  @moduledoc """
  AnalyticsEvent resource for tracking individual analytics events
  (page views, API calls, LiveView interactions, bot traffic) with tenant isolation.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("analytics_events")
    repo(WhoThere.Repo)

    identity_wheres_to_sql unique_event: "session_id IS NOT NULL"

    custom_indexes do
      # Primary query patterns for performance
      index([:tenant_id, :timestamp])
      index([:tenant_id, :event_type, :timestamp])
      index([:tenant_id, :path, :timestamp])
      index([:session_id], where: "session_id IS NOT NULL")
      index([:tenant_id, :bot_name], where: "event_type = 'bot_traffic'")
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :tenant_id,
        :event_type,
        :timestamp,
        :session_id,
        :user_id,
        :path,
        :method,
        :status_code,
        :duration_ms,
        :user_agent,
        :device_type,
        :ip_address,
        :country_code,
        :city,
        :referrer,
        :bot_name,
        :metadata
      ])

      # Set timestamp if not provided
      change(fn changeset, _opts ->
        case Ash.Changeset.get_attribute(changeset, :timestamp) do
          nil -> Ash.Changeset.change_attribute(changeset, :timestamp, DateTime.utc_now())
          _ -> changeset
        end
      end)

      # Set device_type from user_agent if not provided
      change(fn changeset, _opts ->
        device_type = Ash.Changeset.get_attribute(changeset, :device_type)
        user_agent = Ash.Changeset.get_attribute(changeset, :user_agent)

        if is_nil(device_type) and not is_nil(user_agent) do
          detected_type = detect_device_type(user_agent)
          Ash.Changeset.change_attribute(changeset, :device_type, detected_type)
        else
          changeset
        end
      end)

      # Detect bot traffic and set event_type accordingly
      change(fn changeset, _opts ->
        user_agent = Ash.Changeset.get_attribute(changeset, :user_agent)
        ip_address = Ash.Changeset.get_attribute(changeset, :ip_address)

        if not is_nil(user_agent) do
          request_data = %{user_agent: user_agent, ip_address: ip_address}

          if WhoThere.BotDetector.is_bot?(request_data) do
            bot_info = WhoThere.BotDetector.get_bot_info(request_data)

            changeset
            |> Ash.Changeset.change_attribute(:event_type, :bot_traffic)
            |> Ash.Changeset.change_attribute(:bot_name, bot_info.bot_name)
          else
            changeset
          end
        else
          changeset
        end
      end)
    end

    read :by_date_range do
      argument(:start_date, :utc_datetime, allow_nil?: false)
      argument(:end_date, :utc_datetime, allow_nil?: false)

      filter(expr(timestamp >= arg(:start_date) and timestamp <= arg(:end_date)))
    end

    read :by_event_type do
      argument(:event_type, :atom, allow_nil?: false)

      filter(expr(event_type == arg(:event_type)))
    end

    read :by_session do
      argument(:session_id, :uuid, allow_nil?: false)

      filter(expr(session_id == arg(:session_id)))
    end

    read :bot_traffic_summary do
      argument(:start_date, :utc_datetime, allow_nil?: false)
      argument(:end_date, :utc_datetime, allow_nil?: false)

      filter(
        expr(
          event_type == :bot_traffic and
            timestamp >= arg(:start_date) and
            timestamp <= arg(:end_date)
        )
      )
    end

    read :page_analytics do
      argument(:start_date, :utc_datetime, allow_nil?: false)
      argument(:end_date, :utc_datetime, allow_nil?: false)
      argument(:path_pattern, :string, allow_nil?: true)

      filter(
        expr(
          event_type in [:page_view, :liveview_event] and
            timestamp >= arg(:start_date) and
            timestamp <= arg(:end_date)
        )
      )

      prepare(fn query, _context ->
        path_pattern = Ash.Query.get_argument(query, :path_pattern)

        if path_pattern do
          Ash.Query.filter(query, expr(contains(path, ^path_pattern)))
        else
          query
        end
      end)
    end
  end

  policies do
    # Analytics resources require proper tenant context
    # The multitenancy block automatically filters records by tenant_id
    policy action_type([:read, :create, :destroy]) do
      authorize_if(always())
    end
  end

  validations do
    # Required field validations
    validate(present(:tenant_id), message: "Tenant ID is required")
    validate(present(:event_type), message: "Event type is required")
    validate(present(:path), message: "Path is required")

    # Event type validation
    validate(one_of(:event_type, [:page_view, :api_call, :liveview_event, :bot_traffic]),
      message: "Event type must be one of: page_view, api_call, liveview_event, bot_traffic"
    )

    # Path format validation - must start with /
    validate(match(:path, ~r/^\/.*$/),
      message: "Path must start with '/'"
    )

    # Status code validation if present
    validate(
      numericality(:status_code, greater_than_or_equal_to: 100, less_than_or_equal_to: 599),
      where: present(:status_code),
      message: "Status code must be between 100-599"
    )

    # Duration validation if present
    validate(numericality(:duration_ms, greater_than_or_equal_to: 0),
      where: present(:duration_ms),
      message: "Duration must be non-negative"
    )

    # Country code validation if present
    validate(string_length(:country_code, exact: 2),
      where: present(:country_code),
      message: "Country code must be exactly 2 characters"
    )

    # Timestamp validation - cannot be in the future
    validate(fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :timestamp) do
        nil ->
          :ok

        timestamp ->
          if DateTime.compare(timestamp, DateTime.utc_now()) == :gt do
            {:error, field: :timestamp, message: "Timestamp cannot be in the future"}
          else
            :ok
          end
      end
    end)

    # Bot traffic validation - bot_name required for bot events
    validate(fn changeset, _context ->
      event_type = Ash.Changeset.get_attribute(changeset, :event_type)
      bot_name = Ash.Changeset.get_attribute(changeset, :bot_name)

      if event_type == :bot_traffic and is_nil(bot_name) do
        {:error, field: :bot_name, message: "Bot name is required for bot traffic events"}
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

    attribute :event_type, :atom do
      description("Type of event: page_view, api_call, liveview_event, bot_traffic")
      allow_nil?(false)
      constraints(one_of: [:page_view, :api_call, :liveview_event, :bot_traffic])
    end

    attribute :timestamp, :utc_datetime_usec do
      description("When the event occurred")
      allow_nil?(false)
    end

    attribute :session_id, :uuid do
      description("Session identifier (without cookies)")
    end

    attribute :user_id, :string do
      description("User identifier from Phoenix Presence or authentication")
      constraints(max_length: 255)
    end

    attribute :path, :string do
      description("Request path")
      allow_nil?(false)
      constraints(max_length: 2000)
    end

    attribute :method, :string do
      description("HTTP method for API calls")
      constraints(max_length: 10)
    end

    attribute :status_code, :integer do
      description("HTTP response status code")
    end

    attribute :duration_ms, :integer do
      description("Request duration in milliseconds")
    end

    attribute :user_agent, :string do
      description("Full user agent string")
      constraints(max_length: 1000)
    end

    attribute :device_type, :string do
      description("Device type: desktop, mobile, tablet, bot")
      constraints(max_length: 20)
    end

    attribute :ip_address, :string do
      description("Client IP address (anonymized for privacy)")
      # IPv6 max length
      constraints(max_length: 45)
    end

    attribute :country_code, :string do
      description("Country code from proxy headers or IP geolocation")
      constraints(min_length: 2, max_length: 2)
    end

    attribute :city, :string do
      description("City from proxy headers or IP geolocation")
      constraints(max_length: 100)
    end

    attribute :referrer, :string do
      description("HTTP referrer")
      constraints(max_length: 2000)
    end

    attribute :bot_name, :string do
      description("Identified bot name for bot traffic events")
      constraints(max_length: 100)
    end

    attribute :metadata, :map do
      description("Additional event-specific data")
      default(%{})
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :session, WhoThere.Resources.Session do
      source_attribute(:session_id)
      destination_attribute(:id)
      allow_nil?(true)
    end
  end

  calculations do
    calculate :is_bot_traffic, :boolean do
      description("Whether this event represents bot traffic")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          record.event_type == :bot_traffic
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
    # Ensure events are unique per tenant for deduplication if needed
    identity(:unique_event, [:tenant_id, :timestamp, :path, :session_id],
      where: "session_id IS NOT NULL"
    )
  end

  # Private helper function for device detection (simplified)
  defp detect_device_type(user_agent) when is_binary(user_agent) do
    user_agent_lower = String.downcase(user_agent)

    cond do
      String.contains?(user_agent_lower, "mobile") -> "mobile"
      String.contains?(user_agent_lower, "tablet") -> "tablet"
      String.contains?(user_agent_lower, "bot") -> "bot"
      true -> "desktop"
    end
  end

  defp detect_device_type(_), do: "desktop"
end
