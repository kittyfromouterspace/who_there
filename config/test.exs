import Config

config :who_there, WhoThere.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "who_there_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: :warning
