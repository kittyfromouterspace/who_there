defmodule WhoThere.Domain do
  @moduledoc """
  WhoThere Analytics Domain - Ash Framework domain for analytics resources.

  This domain manages all analytics-related resources with multi-tenant isolation,
  privacy-first data handling, and Phoenix application integration.
  """

  use Ash.Domain

  resources do
    resource(WhoThere.Resources.AnalyticsConfiguration)
    resource(WhoThere.Resources.AnalyticsEvent)
    resource(WhoThere.Resources.Session)
    resource(WhoThere.Resources.DailyAnalytics)
  end

  authorization do
    authorize(:when_requested)
  end

  # API functions will be implemented once resources are created

  @doc """
  Tracks an analytics event with tenant context.
  
  ## Options
  - `:tenant` - Required tenant identifier
  - `:actor` - Optional actor for authorization
  
  ## Examples
  
      iex> WhoThere.Domain.track_event(%{event_type: "page_view", path: "/"}, tenant: "my_app")
      {:ok, %WhoThere.Resources.AnalyticsEvent{}}
  """
  def track_event(event_attrs, opts \\ []) when is_map(event_attrs) do
    tenant = Keyword.get(opts, :tenant)
    _actor = Keyword.get(opts, :actor)
    
    unless tenant do
      {:error, "Tenant is required for tracking events"}
    else
      try do
        WhoThere.Resources.AnalyticsEvent
        |> Ash.Changeset.for_create(:create, event_attrs)
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.create()
      rescue
        error ->
          {:error, error}
      end
    end
  end

  @doc """
  Creates or updates a session with tenant context.
  
  ## Options
  - `:tenant` - Required tenant identifier
  - `:actor` - Optional actor for authorization
  
  ## Examples
  
      iex> WhoThere.Domain.track_session(%{fingerprint: "abc123"}, tenant: "my_app")
      {:ok, %WhoThere.Resources.Session{}}
  """
  def track_session(session_attrs, opts \\ []) when is_map(session_attrs) do
    tenant = Keyword.get(opts, :tenant)
    _actor = Keyword.get(opts, :actor)
    
    unless tenant do
      {:error, "Tenant is required for tracking sessions"}
    else
      try do
        WhoThere.Resources.Session
        |> Ash.Changeset.for_create(:create, session_attrs)
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.create()
      rescue
        error ->
          {:error, error}
      end
    end
  end

  @doc """
  Gets analytics configuration for tenant.

  This function will be implemented once AnalyticsConfiguration resource is created.
  """
  def get_config_by_tenant(_opts \\ []) do
    nil
  end

  @doc """
  Creates analytics configuration for tenant.

  This function will be implemented once AnalyticsConfiguration resource is created.
  """
  def create_config(_config_attrs \\ %{}, _opts \\ []) do
    {:error, :not_implemented}
  end
end
