defmodule WhoThere.Domain do
  @moduledoc """
  WhoThere Analytics Domain - Ash Framework domain for analytics resources.

  This domain manages all analytics-related resources with multi-tenant isolation,
  privacy-first data handling, and Phoenix application integration.
  """

  use Ash.Domain

  resources do
    resource WhoThere.AnalyticsEvent
    resource WhoThere.Session
    resource WhoThere.AnalyticsConfiguration
    resource WhoThere.DailyAnalytics
    resource WhoThere.GeographicData
  end

  authorization do
    # All resources require proper tenant context
    # Multitenancy provides automatic tenant isolation
    authorize :when_requested
  end

  # Domain functions for external API

  @doc """
  Tracks an analytics event with tenant context.

  ## Parameters
  - `event_attrs`: Map of event attributes
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, event}` on success
  - `{:error, changeset}` on validation failure
  """
  def track_event(event_attrs, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    event_attrs
    |> Map.put(:tenant_id, tenant)
    |> then(&WhoThere.AnalyticsEvent.create(&1, tenant: tenant))
  end

  @doc """
  Creates or updates a session with tenant context.

  ## Parameters
  - `session_attrs`: Map of session attributes
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, session}` on success
  - `{:error, changeset}` on validation failure
  """
  def track_session(session_attrs, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    fingerprint = Map.get(session_attrs, :session_fingerprint)

    case get_session_by_fingerprint(fingerprint, opts) do
      nil ->
        session_attrs
        |> Map.put(:tenant_id, tenant)
        |> then(&WhoThere.Session.create(&1, tenant: tenant))

      session ->
        WhoThere.Session.update(session, session_attrs, tenant: tenant)
    end
  end

  @doc """
  Retrieves session by fingerprint with tenant context.

  ## Parameters
  - `fingerprint`: Session fingerprint string
  - `opts`: Options including tenant context

  ## Returns
  - `%Session{}` if found
  - `nil` if not found
  """
  def get_session_by_fingerprint(fingerprint, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    WhoThere.Session
    |> Ash.Query.for_read(:read, %{}, tenant: tenant)
    |> Ash.Query.filter(session_fingerprint == ^fingerprint)
    |> Ash.read_one(tenant: tenant)
    |> case do
      {:ok, session} -> session
      {:error, _} -> nil
    end
  end

  @doc """
  Retrieves analytics configuration for tenant.

  ## Parameters
  - `opts`: Options including tenant context

  ## Returns
  - `%AnalyticsConfiguration{}` if found
  - `nil` if not found
  """
  def get_config_by_tenant(opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    WhoThere.AnalyticsConfiguration
    |> Ash.Query.for_read(:read, %{}, tenant: tenant)
    |> Ash.Query.filter(tenant_id == ^tenant)
    |> Ash.read_one(tenant: tenant)
    |> case do
      {:ok, config} -> config
      {:error, _} -> nil
    end
  end

  @doc """
  Creates analytics configuration for tenant with defaults.

  ## Parameters
  - `config_attrs`: Configuration attributes (optional)
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, config}` on success
  - `{:error, changeset}` on failure
  """
  def create_config(config_attrs \\ %{}, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    config_attrs
    |> Map.put(:tenant_id, tenant)
    |> then(&WhoThere.AnalyticsConfiguration.create(&1, tenant: tenant))
  end

  @doc """
  Retrieves analytics events for date range with tenant context.

  ## Parameters
  - `start_date`: Start date for query
  - `end_date`: End date for query
  - `opts`: Options including tenant context and filters

  ## Returns
  - `{:ok, [events]}` on success
  - `{:error, reason}` on failure
  """
  def get_events_by_date_range(start_date, end_date, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    event_type = Keyword.get(opts, :event_type)

    query =
      WhoThere.AnalyticsEvent
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.filter(timestamp >= ^start_date and timestamp <= ^end_date)

    query =
      if event_type do
        Ash.Query.filter(query, event_type == ^event_type)
      else
        query
      end

    Ash.read(query, tenant: tenant)
  end

  @doc """
  Creates or updates daily analytics summary.

  ## Parameters
  - `date`: Date for summary
  - `summary_attrs`: Summary attributes
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, summary}` on success
  - `{:error, changeset}` on failure
  """
  def create_daily_summary(date, summary_attrs, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    # Check if summary already exists
    existing_query =
      WhoThere.DailyAnalytics
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.filter(date == ^date)

    case Ash.read_one(existing_query, tenant: tenant) do
      {:ok, nil} ->
        # Create new summary
        summary_attrs
        |> Map.put(:tenant_id, tenant)
        |> Map.put(:date, date)
        |> then(&WhoThere.DailyAnalytics.create(&1, tenant: tenant))

      {:ok, existing} ->
        # Update existing summary
        WhoThere.DailyAnalytics.update(existing, summary_attrs, tenant: tenant)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves bot traffic summary for date range.

  ## Parameters
  - `start_date`: Start date for query
  - `end_date`: End date for query
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, bot_summary}` on success
  - `{:error, reason}` on failure
  """
  def get_bot_traffic_summary(start_date, end_date, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    WhoThere.AnalyticsEvent
    |> Ash.Query.for_read(:read, %{}, tenant: tenant)
    |> Ash.Query.filter(
      event_type == :bot_traffic and
      timestamp >= ^start_date and
      timestamp <= ^end_date
    )
    |> Ash.Query.aggregate(:count, :total_bot_events)
    |> Ash.Query.group_by([:bot_name])
    |> Ash.read(tenant: tenant)
  end

  @doc """
  Cleans up expired analytics data based on retention policies.

  ## Parameters
  - `opts`: Options including tenant context

  ## Returns
  - `{:ok, deleted_count}` on success
  - `{:error, reason}` on failure
  """
  def cleanup_expired_data(opts \\ []) do
    tenant = Keyword.get(opts, :tenant)

    # Get retention policy
    case get_config_by_tenant(opts) do
      nil ->
        {:error, :no_config}

      config ->
        cutoff_date =
          DateTime.utc_now()
          |> DateTime.add(-config.data_retention_days * 24 * 60 * 60, :second)

        # Delete old events
        WhoThere.AnalyticsEvent
        |> Ash.Query.for_read(:read, %{}, tenant: tenant)
        |> Ash.Query.filter(timestamp < ^cutoff_date)
        |> Ash.bulk_destroy(:destroy, tenant: tenant)
    end
  end
end