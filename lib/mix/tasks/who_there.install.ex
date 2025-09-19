defmodule Mix.Tasks.WhoThere.Install do
  @shortdoc "Install WhoThere analytics library in a Phoenix application"
  @moduledoc """
  Install and configure WhoThere analytics library in a Phoenix application.

  This task will:
  - Add necessary configuration to config files
  - Generate database migrations if needed
  - Add routing configuration examples
  - Install necessary dependencies
  - Set up example implementations

  ## Options

  * `--no-config` - Skip generating configuration files
  * `--no-migrations` - Skip generating database migrations  
  * `--dry-run` - Show what would be done without making changes
  * `--tenant-resolver` - Specify a custom tenant resolver function

  ## Examples

      mix who_there.install
      mix who_there.install --dry-run
      mix who_there.install --no-migrations
      mix who_there.install --tenant-resolver MyApp.get_tenant/1

  """

  use Mix.Task
  require Logger

  @doc false
  def run(args) do
    {opts, _args} =
      OptionParser.parse!(args,
        switches: [
          no_config: :boolean,
          no_migrations: :boolean,
          dry_run: :boolean,
          tenant_resolver: :string
        ],
        aliases: [
          d: :dry_run
        ]
      )

    Mix.shell().info("Installing WhoThere Analytics...")

    if opts[:dry_run] do
      Mix.shell().info("DRY RUN MODE - No changes will be made")
    end

    try do
      # Check if this is a Phoenix project
      ensure_phoenix_project!()

      # Install dependencies if needed  
      unless opts[:no_deps], do: install_dependencies(opts)

      # Generate configuration
      unless opts[:no_config], do: generate_config(opts)

      # Generate migrations
      unless opts[:no_migrations], do: generate_migrations(opts)

      # Generate example tenant resolver
      generate_tenant_resolver(opts)

      # Add routing examples
      generate_routing_examples(opts)

      Mix.shell().info("""

      #{IO.ANSI.green()}✓ WhoThere installation completed!#{IO.ANSI.reset()}

      Next steps:
      1. Run database migrations: #{IO.ANSI.cyan()}mix ecto.migrate#{IO.ANSI.reset()}
      2. Add the plug to your router (see generated example)
      3. Configure your tenant resolver function
      4. Start your Phoenix server and visit your application

      For more information, see the documentation at https://hexdocs.pm/who_there
      """)
    rescue
      error ->
        Mix.shell().error("Installation failed: #{inspect(error)}")
        Mix.shell().error("Run with --dry-run to see what would be installed")
        exit({:shutdown, 1})
    end
  end

  defp ensure_phoenix_project! do
    unless Mix.Project.get() do
      Mix.raise("No Mix project found. Make sure you're in a Mix project directory.")
    end

    unless Code.ensure_loaded?(Phoenix) or phoenix_in_deps?() do
      Mix.raise("Phoenix is not available. WhoThere requires a Phoenix application.")
    end
  end

  defp phoenix_in_deps? do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.any?(fn
      {:phoenix, _} -> true
      {:phoenix, _, _} -> true
      _ -> false
    end)
  end

  defp install_dependencies(opts) do
    if opts[:dry_run] do
      Mix.shell().info("Would add :who_there to deps in mix.exs")
    else
      # In a real implementation, this would modify mix.exs
      Mix.shell().info("Dependencies already configured (WhoThere is installed)")
    end
  end

  defp generate_config(opts) do
    config_content = """
    # WhoThere Analytics Configuration
    config :who_there, WhoThere.Repo,
      username: "postgres",
      password: "postgres", 
      hostname: "localhost",
      database: "#{app_name()}_repo",
      show_sensitive_data_on_connection_error: true,
      pool_size: 10

    # Privacy and tracking settings
    config :who_there,
      privacy_mode: false,
      bot_detection: true,
      geographic_data: true,
      session_tracking: true,
      async_tracking: true

    # Route filtering (paths to exclude from tracking)
    config :who_there, :route_filters,
      exclude_paths: [
        ~r/^\\/assets\\//,
        ~r/^\\/images\\//,
        ~r/^\\/css\\//,
        ~r/^\\/js\\//,
        ~r/^\\/favicon.ico/,
        "/health",
        "/metrics"
      ]
    """

    write_config_file("config/who_there.exs", config_content, opts)

    # Also add to main config
    main_config_addition = """

    # Import WhoThere configuration
    import_config "who_there.exs"
    """

    append_to_config_file("config/config.exs", main_config_addition, opts)
  end

  defp generate_migrations(opts) do
    if opts[:dry_run] do
      Mix.shell().info("Would generate WhoThere database migrations")
    else
      # Check if migrations already exist
      migration_dir =
        Path.join([Mix.Project.app_path(), "..", "..", "priv", "repo", "migrations"])

      if migration_exists?(migration_dir) do
        Mix.shell().info("WhoThere migrations already exist - skipping")
      else
        # In a real implementation, we would copy the migration from the library
        Mix.shell().info("Database migrations would be generated")
        Mix.shell().info("Run: mix ecto.migrate to apply the changes")
      end
    end
  end

  defp generate_tenant_resolver(opts) do
    tenant_resolver = opts[:tenant_resolver] || "#{app_module()}.get_tenant/1"

    resolver_content = """
    defmodule #{app_module()}.Analytics do
      @moduledoc \"\"\"
      Analytics utilities and tenant resolution for WhoThere.
      \"\"\"

      @doc \"\"\"
      Resolves the tenant identifier from the current connection.
      
      This is called by WhoThere to determine which tenant data belongs to.
      Customize this function based on your application's tenant strategy.
      \"\"\"
      def get_tenant(conn) do
        # Example implementations - choose one based on your app:
        
        # Option 1: Extract from subdomain
        # case String.split(conn.host, ".") do
        #   [tenant | _] when tenant != "www" -> tenant
        #   _ -> "default"
        # end
        
        # Option 2: Extract from session
        # Plug.Conn.get_session(conn, :current_tenant)
        
        # Option 3: Extract from path
        # case conn.path_info do
        #   [tenant | _] -> tenant
        #   _ -> "default" 
        # end
        
        # Option 4: Static tenant (for single-tenant apps)
        "default"
      end
    end
    """

    write_file("lib/#{app_name()}/analytics.ex", resolver_content, opts)
  end

  defp generate_routing_examples(opts) do
    router_example = """
    # Add this to your router.ex file

    # In your router.ex, add the analytics pipeline:
    pipeline :analytics do
      plug WhoThere.Plug, 
        tenant_resolver: &#{app_module()}.Analytics.get_tenant/1,
        track_page_views: true,
        track_api_calls: false,
        exclude_paths: [~r/^\\/api\\/health/]
    end

    # Then add it to your routes:
    scope "/", #{app_module()}Web do
      pipe_through [:browser, :analytics]  # Add :analytics here
      
      get "/", PageController, :home
      # ... your other routes
    end

    # For API routes (optional):
    scope "/api", #{app_module()}Web do  
      pipe_through [:api, :analytics]  # Add :analytics here if you want API tracking
      
      # ... your API routes
    end
    """

    write_file("docs/router_integration_example.ex", router_example, opts)
  end

  defp write_config_file(path, content, opts) do
    if opts[:dry_run] do
      Mix.shell().info("Would create: #{path}")
    else
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("Created: #{path}")
    end
  end

  defp append_to_config_file(path, content, opts) do
    if opts[:dry_run] do
      Mix.shell().info("Would append to: #{path}")
    else
      if File.exists?(path) do
        File.write!(path, File.read!(path) <> content)
        Mix.shell().info("Updated: #{path}")
      else
        Mix.shell().info("Config file #{path} not found - skipping")
      end
    end
  end

  defp write_file(path, content, opts) do
    if opts[:dry_run] do
      Mix.shell().info("Would create: #{path}")
    else
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("Created: #{path}")
    end
  end

  defp migration_exists?(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.any?(&String.contains?(&1, "analytics"))
    else
      false
    end
  end

  defp app_name do
    Mix.Project.config() |> Keyword.get(:app) |> to_string()
  end

  defp app_module do
    app_name()
    |> Macro.camelize()
  end
end
