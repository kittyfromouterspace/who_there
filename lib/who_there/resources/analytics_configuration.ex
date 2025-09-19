defmodule WhoThere.Resources.AnalyticsConfiguration do
  @moduledoc """
  AnalyticsConfiguration resource for tenant-specific analytics settings
  and privacy controls with comprehensive configuration options.
  """

  use Ash.Resource,
    otp_app: :who_there,
    domain: WhoThere.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("analytics_configurations")
    repo(WhoThere.Repo)

    custom_indexes do
      index([:tenant_id], unique: true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :tenant_id,
        :enabled,
        :collect_user_agents,
        :collect_referrers,
        :collect_geolocation,
        :anonymize_ips,
        :exclude_admin_routes,
        :exclude_patterns,
        :session_timeout_minutes,
        :data_retention_days,
        :bot_detection_enabled,
        :presence_integration,
        :dashboard_enabled,
        :d3_visualizations_enabled,
        :proxy_header_detection,
        :live_view_deduplication
      ])

      # Validate exclude patterns on creation
      change(fn changeset, _opts ->
        patterns = Ash.Changeset.get_attribute(changeset, :exclude_patterns) || []

        case validate_exclude_patterns(patterns) do
          :ok ->
            changeset

          {:error, invalid_pattern} ->
            Ash.Changeset.add_error(
              changeset,
              :exclude_patterns,
              "Invalid exclude pattern: #{invalid_pattern}"
            )
        end
      end)
    end

    update :update do
      accept([
        :enabled,
        :collect_user_agents,
        :collect_referrers,
        :collect_geolocation,
        :anonymize_ips,
        :exclude_admin_routes,
        :exclude_patterns,
        :session_timeout_minutes,
        :data_retention_days,
        :bot_detection_enabled,
        :presence_integration,
        :dashboard_enabled,
        :d3_visualizations_enabled,
        :proxy_header_detection,
        :live_view_deduplication
      ])

      require_atomic?(false)

      # Validate exclude patterns on update
      change(fn changeset, _opts ->
        patterns = Ash.Changeset.get_attribute(changeset, :exclude_patterns)

        if patterns do
          case validate_exclude_patterns(patterns) do
            :ok ->
              changeset

            {:error, invalid_pattern} ->
              Ash.Changeset.add_error(
                changeset,
                :exclude_patterns,
                "Invalid exclude pattern: #{invalid_pattern}"
              )
          end
        else
          changeset
        end
      end)
    end

    read :by_tenant do
      argument(:tenant_id, :uuid, allow_nil?: false)

      filter(expr(tenant_id == arg(:tenant_id)))
    end

    update :bulk_update do
      # Custom action for updating multiple settings atomically
      accept([
        :enabled,
        :collect_user_agents,
        :collect_referrers,
        :collect_geolocation,
        :anonymize_ips,
        :exclude_admin_routes,
        :exclude_patterns,
        :session_timeout_minutes,
        :data_retention_days,
        :bot_detection_enabled,
        :presence_integration,
        :dashboard_enabled,
        :d3_visualizations_enabled,
        :proxy_header_detection,
        :live_view_deduplication
      ])

      require_atomic?(false)

      change(fn changeset, _opts ->
        # Validate all changes as a group
        patterns = Ash.Changeset.get_attribute(changeset, :exclude_patterns)

        if patterns do
          case validate_exclude_patterns(patterns) do
            :ok ->
              changeset

            {:error, invalid_pattern} ->
              Ash.Changeset.add_error(
                changeset,
                :exclude_patterns,
                "Invalid exclude pattern: #{invalid_pattern}"
              )
          end
        else
          changeset
        end
      end)
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

    # Session timeout validation
    validate(
      numericality(:session_timeout_minutes,
        greater_than: 0,
        less_than_or_equal_to: 1440
      ),
      message: "Session timeout must be between 1 and 1440 minutes (24 hours)"
    )

    # Data retention validation
    validate(
      numericality(:data_retention_days,
        greater_than: 0,
        less_than_or_equal_to: 3650
      ),
      message: "Data retention must be between 1 and 3650 days (10 years)"
    )

    # Custom validation for exclude patterns
    validate(fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :exclude_patterns) do
        nil ->
          :ok

        patterns when is_list(patterns) ->
          case validate_exclude_patterns(patterns) do
            :ok ->
              :ok

            {:error, invalid_pattern} ->
              {:error, field: :exclude_patterns, message: "Invalid pattern: #{invalid_pattern}"}
          end

        _ ->
          {:error, field: :exclude_patterns, message: "Exclude patterns must be a list"}
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

    # Core Analytics Settings
    attribute :enabled, :boolean do
      description("Analytics collection enabled")
      default(true)
    end

    # Data Collection Settings
    attribute :collect_user_agents, :boolean do
      description("Store user agent strings")
      default(true)
    end

    attribute :collect_referrers, :boolean do
      description("Store referrer information")
      default(true)
    end

    attribute :collect_geolocation, :boolean do
      description("Store geographic data (country, city)")
      default(true)
    end

    attribute :anonymize_ips, :boolean do
      description("Anonymize IP addresses before storage")
      default(true)
    end

    # Route Filtering Settings
    attribute :exclude_admin_routes, :boolean do
      description("Skip tracking admin panel routes")
      default(true)
    end

    attribute :exclude_patterns, {:array, :string} do
      description("Custom exclusion patterns (regex or string)")
      default([])
      constraints(items: [max_length: 200])
    end

    # Session and Retention Settings
    attribute :session_timeout_minutes, :integer do
      description("Session expiry timeout in minutes")
      default(30)
      constraints(min: 1, max: 1440)
    end

    attribute :data_retention_days, :integer do
      description("Data retention period in days")
      default(365)
      constraints(min: 1, max: 3650)
    end

    # Advanced Features
    attribute :bot_detection_enabled, :boolean do
      description("Enable bot traffic detection and segregation")
      default(true)
    end

    attribute :presence_integration, :boolean do
      description("Use Phoenix Presence for user tracking when available")
      default(false)
    end

    attribute :dashboard_enabled, :boolean do
      description("Enable analytics dashboard access")
      default(true)
    end

    attribute :d3_visualizations_enabled, :boolean do
      description("Enable D3.js visualizations in dashboard")
      default(true)
    end

    attribute :proxy_header_detection, :boolean do
      description("Automatically detect popular proxy headers (Cloudflare, AWS ALB, etc.)")
      default(true)
    end

    attribute :live_view_deduplication, :boolean do
      description("Only count connected LiveView renders, not dead renders")
      default(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_config_per_tenant, [:tenant_id])
  end

  calculations do
    calculate :privacy_score, :integer do
      description("Privacy protection score (0-100) based on configuration")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          score = 0

          score = if record.anonymize_ips, do: score + 25, else: score
          score = if not record.collect_user_agents, do: score + 20, else: score
          score = if not record.collect_referrers, do: score + 15, else: score
          score = if not record.collect_geolocation, do: score + 15, else: score
          score = if record.data_retention_days <= 90, do: score + 25, else: score

          min(score, 100)
        end)
      end)
    end

    calculate :compliance_level, :string do
      description("Data protection compliance level assessment")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          cond do
            record.anonymize_ips and not record.collect_user_agents and
                record.data_retention_days <= 30 ->
              "Strict"

            record.anonymize_ips and record.data_retention_days <= 365 ->
              "Standard"

            record.anonymize_ips ->
              "Basic"

            true ->
              "Minimal"
          end
        end)
      end)
    end

    calculate :feature_summary, :map do
      description("Summary of enabled features")

      calculation(fn records, _opts ->
        Enum.map(records, fn record ->
          %{
            analytics_enabled: record.enabled,
            bot_detection: record.bot_detection_enabled,
            presence_tracking: record.presence_integration,
            dashboard_access: record.dashboard_enabled,
            d3_visualizations: record.d3_visualizations_enabled,
            proxy_detection: record.proxy_header_detection,
            liveview_dedup: record.live_view_deduplication,
            privacy_features: %{
              ip_anonymization: record.anonymize_ips,
              data_retention_days: record.data_retention_days,
              user_agent_collection: record.collect_user_agents,
              referrer_collection: record.collect_referrers,
              geolocation_collection: record.collect_geolocation
            }
          }
        end)
      end)
    end
  end

  # Private helper function for pattern validation
  defp validate_exclude_patterns(patterns) when is_list(patterns) do
    patterns
    |> Enum.find(fn pattern ->
      not valid_pattern?(pattern)
    end)
    |> case do
      nil -> :ok
      invalid_pattern -> {:error, invalid_pattern}
    end
  end

  defp validate_exclude_patterns(_), do: {:error, "must be a list"}

  defp valid_pattern?(pattern) when is_binary(pattern) do
    cond do
      String.length(pattern) == 0 ->
        false

      String.length(pattern) > 200 ->
        false

      not String.starts_with?(pattern, "/") ->
        false

      String.contains?(pattern, "**") ->
        false

      true ->
        # Try to compile as regex
        test_regex =
          pattern
          |> Regex.escape()
          |> String.replace("\\*", ".*")
          |> then(&("^" <> &1 <> "$"))

        case Regex.compile(test_regex) do
          {:ok, _} -> true
          {:error, _} -> false
        end
    end
  end

  defp valid_pattern?(_), do: false
end
