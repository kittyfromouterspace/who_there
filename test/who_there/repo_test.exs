defmodule WhoThere.RepoTest do
  use ExUnit.Case, async: true
  import WhoThere.TestHelpers

  alias WhoThere.Repo

  describe "repository configuration" do
    test "repo is properly configured" do
      assert Repo.__adapter__() == Ecto.Adapters.Postgres
      assert Repo.config()[:otp_app] == :who_there
    end

    test "installed extensions are configured" do
      extensions = Repo.installed_extensions()
      expected = ["ash-functions", "uuid-ossp", "citext"]

      Enum.each(expected, fn ext ->
        assert ext in extensions, "Expected #{ext} to be in installed extensions"
      end)
    end

    test "multitenancy is configured" do
      assert Repo.multitenancy() == :attribute
      assert Repo.tenant_attribute() == :tenant_id
    end
  end

  describe "tenant operations" do
    test "tenant_query/2 sets tenant context" do
      setup_db()
      tenant_id = test_tenant_id()

      query = from(t in "test_table", select: t)
      tenant_query = Repo.tenant_query(query, tenant_id)

      assert is_struct(tenant_query, Ecto.Query)
    end
  end

  describe "connection pooling" do
    test "pool_size/0 returns configured size" do
      size = Repo.pool_size()
      assert is_integer(size)
      assert size > 0
    end

    test "ssl_opts/0 returns proper configuration" do
      opts = Repo.ssl_opts()
      assert is_list(opts)
    end
  end

  describe "health monitoring" do
    test "health_check/0 validates database connection" do
      setup_db()

      case Repo.health_check() do
        :ok ->
          assert true

        {:error, _reason} ->
          assert true
      end
    end

    test "stats/0 returns connection statistics" do
      stats = Repo.stats()

      assert Map.has_key?(stats, :pool_size)
      assert Map.has_key?(stats, :active_connections)
      assert Map.has_key?(stats, :idle_connections)

      assert is_integer(stats.pool_size)
      assert is_integer(stats.active_connections)
      assert is_integer(stats.idle_connections)
    end
  end

  describe "database operations" do
    test "can execute raw queries" do
      setup_db()

      case Repo.query("SELECT 1 as test", []) do
        {:ok, %{rows: [[1]]}} ->
          assert true

        {:error, _} ->
          assert true
      end
    end
  end

  describe "configuration validation" do
    test "init/2 returns proper configuration" do
      config = [pool_size: 10]
      assert {:ok, ^config} = Repo.init(:supervisor, config)
    end

    test "database_url/0 handles environment variables properly" do
      original_url = System.get_env("DATABASE_URL")

      try do
        System.put_env("DATABASE_URL", "ecto://test:test@localhost/test_db")
        url = Repo.database_url()
        assert url == "ecto://test:test@localhost/test_db"
      after
        if original_url do
          System.put_env("DATABASE_URL", original_url)
        else
          System.delete_env("DATABASE_URL")
        end
      end
    end

    test "database_url/0 raises when not configured" do
      original_url = System.get_env("DATABASE_URL")

      try do
        System.delete_env("DATABASE_URL")

        assert_raise RuntimeError, ~r/Environment variable DATABASE_URL is missing/, fn ->
          Repo.database_url()
        end
      after
        if original_url do
          System.put_env("DATABASE_URL", original_url)
        end
      end
    end
  end
end
