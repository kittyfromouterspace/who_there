# Start ExUnit
ExUnit.start()

# Start the Repo for tests
{:ok, _} = Application.ensure_all_started(:who_there)

# Configure Ecto for testing
Ecto.Adapters.SQL.Sandbox.mode(WhoThere.Repo, :manual)

# Load support modules
Code.require_file("support/data_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/fixtures.ex", __DIR__)
