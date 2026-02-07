defmodule Mix.Tasks.WhoThere.Install do
  @shortdoc "Install WhoThere analytics into your Phoenix/Ash application"
  @moduledoc """
  Installs WhoThere analytics library into a Phoenix application.

  This task will:
  - Configure WhoThere to use your application's repo
  - Add WhoThere.Domain to your ash_domains config
  - Copy database migrations to your priv/repo/migrations
  - Generate example tenant resolver and router integration

  ## Usage

      mix who_there.install

  ## Options

  * `--repo` - Specify the repo module (default: auto-detected)
  * `--dry-run` - Show what would be done without making changes

  ## Examples

      mix who_there.install
      mix who_there.install --repo MyApp.Repo
      mix who_there.install --dry-run

  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :who_there,
      adds_deps: [],
      installs: [],
      example: "mix who_there.install --repo MyApp.Repo"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter, argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        switches: [
          repo: :string,
          dry_run: :boolean
        ]
      )

    app_name = Igniter.Project.Application.app_name(igniter)
    repo = opts[:repo] || detect_repo(igniter, app_name)

    igniter
    |> configure_who_there(app_name, repo)
    |> add_domain_to_ash_config(app_name)
    |> copy_migrations()
    |> generate_tenant_resolver(app_name)
    |> print_next_steps(app_name)
  end

  defp detect_repo(igniter, _app_name) do
    # Try common repo naming patterns
    module_name = Igniter.Project.Module.module_name(igniter, "WhoThere")
    "#{module_name}.Repo"
  end

  defp configure_who_there(igniter, app_name, repo) do
    _config_content = """
    config :who_there,
      repo: #{repo},
      otp_app: :#{app_name}

    # Privacy settings
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
        ~r/^\\/_live\\//,
        "/health",
        "/metrics"
      ]
    """

    Igniter.Project.Config.configure(
      igniter,
      "config.exs",
      :who_there,
      [:repo],
      {:code, Sourceror.parse_string!(repo)}
    )
    |> Igniter.Project.Config.configure(
      "config.exs",
      :who_there,
      [:otp_app],
      app_name
    )
  end

  defp add_domain_to_ash_config(igniter, app_name) do
    Igniter.Project.Config.configure(
      igniter,
      "config.exs",
      app_name,
      [:ash_domains],
      [WhoThere.Domain],
      updater: fn list ->
        if WhoThere.Domain in list do
          {:ok, list}
        else
          {:ok, list ++ [WhoThere.Domain]}
        end
      end
    )
  end

  defp copy_migrations(igniter) do
    # Get the source migration from the library
    source_dir = Application.app_dir(:who_there, "priv/repo/migrations")
    
    if File.dir?(source_dir) do
      source_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".exs"))
      |> Enum.reduce(igniter, fn file, acc ->
        source = Path.join(source_dir, file)
        content = File.read!(source)
        
        # Generate new timestamp for the migration
        timestamp = generate_migration_timestamp()
        new_name = String.replace(file, ~r/^\d+/, timestamp)
        dest = Path.join("priv/repo/migrations", new_name)
        
        Igniter.create_new_file(acc, dest, content, on_exists: :skip)
      end)
    else
      # No pre-built migrations, generate them
      Igniter.add_notice(igniter, """
      
      No pre-built migrations found. You may need to generate them:
      
          mix ash_postgres.generate_migrations --name add_who_there_tables
          mix ecto.migrate
      
      """)
    end
  end

  defp generate_migration_timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp generate_tenant_resolver(igniter, app_name) do
    module_name = Igniter.Project.Module.module_name(igniter, "WhoThere")
    
    content = """
    defmodule #{module_name}.Analytics.TenantResolver do
      @moduledoc \"\"\"
      Resolves the tenant identifier for WhoThere analytics.
      
      Customize this module based on your multi-tenancy strategy.
      \"\"\"

      @doc \"\"\"
      Extracts the tenant ID from the connection.
      
      Called by WhoThere.Plug to determine which tenant data belongs to.
      
      ## Examples
      
          # Single-tenant app (default tenant)
          def get_tenant(_conn), do: "default"
          
          # Subdomain-based tenancy
          def get_tenant(conn) do
            case String.split(conn.host, ".") do
              [tenant | _] when tenant != "www" -> tenant
              _ -> "default"
            end
          end
          
          # Path-based tenancy
          def get_tenant(conn) do
            case conn.path_info do
              ["tenants", tenant | _] -> tenant
              _ -> "default"
            end
          end
      \"\"\"
      def get_tenant(_conn) do
        # Default implementation - customize for your app
        "default"
      end

      @doc \"\"\"
      Converts tenant identifier to a UUID for storage.
      
      WhoThere stores tenant_id as UUID. This function maps your
      tenant identifier (string, subdomain, etc.) to a UUID.
      \"\"\"
      def tenant_to_uuid(tenant_id) when is_binary(tenant_id) do
        # Option 1: Use a deterministic UUID based on tenant name
        :crypto.hash(:sha256, tenant_id)
        |> binary_part(0, 16)
        |> encode_uuid()
        
        # Option 2: Look up from database
        # MyApp.Tenants.get_by_slug!(tenant_id).id
      end

      defp encode_uuid(<<a::32, b::16, c::16, d::16, e::48>>) do
        [a, b, c, d, e]
        |> Enum.map(&Integer.to_string(&1, 16))
        |> Enum.map(&String.pad_leading(&1, 8, "0"))
        |> Enum.join("-")
        |> String.downcase()
      end
    end
    """

    path = "lib/#{app_name}/analytics/tenant_resolver.ex"
    Igniter.create_new_file(igniter, path, content, on_exists: :skip)
  end

  defp print_next_steps(igniter, app_name) do
    module_name = app_name |> to_string() |> Macro.camelize()

    Igniter.add_notice(igniter, """

    ✅ WhoThere installed successfully!

    Next steps:

    1. Run migrations:
       
       mix ecto.migrate

    2. Add WhoThere.Plug to your router:

       # In lib/#{app_name}_web/router.ex
       pipeline :browser do
         # ... existing plugs ...
         plug WhoThere.Plug,
           tenant_resolver: &#{module_name}.Analytics.TenantResolver.get_tenant/1
       end

    3. (Optional) Add the LiveDashboard page:

       # In lib/#{app_name}_web/router.ex
       live_dashboard "/dashboard",
         metrics: #{module_name}Web.Telemetry,
         additional_pages: [
           who_there: WhoThere.PhoenixIntegration.LiveDashboardPage
         ]

    4. Customize the tenant resolver:
       
       Edit lib/#{app_name}/analytics/tenant_resolver.ex

    For more information, see the documentation:
    https://hexdocs.pm/who_there

    """)
  end
end
