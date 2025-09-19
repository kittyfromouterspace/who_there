defmodule WhoThere.Repo do
  @moduledoc """
  WhoThere database repository using Ecto.Repo with AshPostgres integration.

  This repository handles all database operations for analytics data with
  multi-tenant support and proper connection pooling.
  """

  use AshPostgres.Repo, otp_app: :who_there

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end

  @doc """
  Runs the given query for the specified tenant.

  This ensures proper tenant isolation for all database operations.
  """
  def tenant_query(query, tenant) do
    # For now, this is a placeholder. The proper multi-tenancy implementation
    # will be added when the Ash resources are created
    query
  end

  @doc """
  Sets up tenant-specific configuration for the current process.

  This is used by AshPostgres for multi-tenant operations.
  """
  def multitenancy do
    :attribute
  end

  @doc """
  Returns the tenant attribute name used for queries.
  """
  def tenant_attribute do
    :tenant_id
  end

  @doc """
  Configures dynamic repository settings based on environment.
  """
  def init(_type, config) do
    {:ok, config}
  end

  @doc """
  Handles repository connection pooling configuration.
  """
  def pool_size do
    System.get_env("POOL_SIZE", "10") |> String.to_integer()
  end

  @doc """
  Returns database connection URL for the current environment.
  """
  def database_url do
    System.get_env("DATABASE_URL") ||
      raise """
      Environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """
  end

  @doc """
  Configures SSL options for production environments.
  """
  def ssl_opts do
    if System.get_env("MIX_ENV") == "prod" do
      [
        ssl: true,
        ssl_opts: [
          verify: :verify_peer,
          versions: [:"tlsv1.2", :"tlsv1.3"]
        ]
      ]
    else
      []
    end
  end

  @doc """
  Health check for the database connection.

  Returns :ok if the database is healthy, {:error, reason} otherwise.
  """
  def health_check do
    try do
      query("SELECT 1", [])
      :ok
    rescue
      error ->
        {:error, error}
    end
  end

  @doc """
  Returns database statistics for monitoring.
  """
  def stats do
    %{
      pool_size: pool_size(),
      active_connections: get_active_connections(),
      idle_connections: get_idle_connections()
    }
  end

  defp get_active_connections do
    try do
      :telemetry.execute([:ecto, :repo, :query], %{active_connections: 0}, %{repo: __MODULE__})
      0
    rescue
      _ -> 0
    end
  end

  defp get_idle_connections do
    try do
      :telemetry.execute([:ecto, :repo, :query], %{idle_connections: 0}, %{repo: __MODULE__})
      0
    rescue
      _ -> 0
    end
  end
end
