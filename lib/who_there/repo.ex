defmodule WhoThere.Repo do
  @moduledoc """
  WhoThere's repository module.

  By default, this repo handles its own connections. For production use,
  you can configure it to delegate to your application's repo:

      config :who_there, :repo_delegate, MyApp.Repo

  When a delegate repo is configured, database operations are forwarded
  to it, allowing WhoThere to share your application's connection pool
  and transaction context.

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

  This shares your existing database connection and ensures
  WhoThere tables are in the same database as your app.
  """

  use AshPostgres.Repo, otp_app: :who_there

  @doc false
  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  @doc false
  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end
end
