import Config

config :who_there,
  ecto_repos: [WhoThere.Repo],
  ash_domains: [WhoThere.Domain]

config :ash, :include_embedded_source_by_default?, false

import_config "#{config_env()}.exs"
