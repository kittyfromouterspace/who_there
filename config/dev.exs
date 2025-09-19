import Config

config :who_there, WhoThere.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "who_there_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
