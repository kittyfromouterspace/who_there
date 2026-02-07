defmodule WhoThere.Repo do
  @moduledoc """
  WhoThere's repository module.

  By default, this repo handles its own connections. For production use,
  you can configure it to share your application's database:

      config :who_there, :repo_delegate, MyApp.Repo

  When a delegate is configured, WhoThere.Repo copies the delegate's
  database config at startup, sharing the same database (but with its
  own small connection pool).

  ## Without Delegation (Standalone Mode)

  Configure database connection directly:

      config :who_there, WhoThere.Repo,
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        database: "who_there_dev",
        pool_size: 10

  ## With Delegation (Recommended for Production)

      config :who_there, :repo_delegate, MyApp.Repo

  """

  use AshPostgres.Repo, otp_app: :who_there

  @doc false
  def init(_context, config) do
    case Application.get_env(:who_there, :repo_delegate) do
      nil ->
        {:ok, config}

      delegate_repo ->
        # Copy database connection from the delegate repo's config
        delegate_config = Application.get_env(delegate_repo.config()[:otp_app], delegate_repo, [])

        merged =
          delegate_config
          |> Keyword.merge(config)
          |> Keyword.put_new(:pool_size, 5)

        {:ok, merged}
    end
  end

  @doc false
  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  @doc false
  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end
end
