defmodule WhoThere.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use WhoThere.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias WhoThere.Repo

      import Ecto.Changeset
      import Ecto.Query
      import WhoThere.DataCase
      import WhoThere.TestHelpers
      import WhoThere.Fixtures
    end
  end

  setup tags do
    WhoThere.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(WhoThere.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Creates a test tenant context for multi-tenant tests.
  """
  def test_tenant_context(tenant \\ "test-tenant") do
    %{tenant: tenant}
  end

  @doc """
  Sets up Ash context for testing with multi-tenancy.
  """
  def ash_context(tenant \\ "test-tenant") do
    # Simple context map for testing
    %{
      tenant: tenant,
      actor: nil
    }
  end

  @doc """
  Helper to create test data with proper tenant isolation.
  """
  def with_tenant(tenant, fun) do
    original_tenant = Process.get(:current_tenant)
    
    try do
      Process.put(:current_tenant, tenant)
      fun.()
    after
      if original_tenant do
        Process.put(:current_tenant, original_tenant)
      else
        Process.delete(:current_tenant)
      end
    end
  end
end