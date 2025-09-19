defmodule WhoThere.TestHelpers do
  @moduledoc """
  Test helpers for WhoThere tests.
  """

  import Ecto.Changeset

  alias WhoThere.Repo

  @doc """
  Sets up the database for tests.
  """
  def setup_db do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WhoThere.Repo)
  end

  @doc """
  Creates a test tenant ID.
  """
  def test_tenant_id, do: "test_tenant_#{:rand.uniform(1000)}"

  @doc """
  Creates a mock Plug.Conn for testing.
  """
  def mock_conn(opts \\ []) do
    import Plug.Conn

    tenant_id = Keyword.get(opts, :tenant_id, test_tenant_id())
    path = Keyword.get(opts, :path, "/")
    method = Keyword.get(opts, :method, "GET")
    headers = Keyword.get(opts, :headers, [])
    remote_ip = Keyword.get(opts, :remote_ip, {127, 0, 0, 1})

    %Plug.Conn{
      method: method,
      request_path: path,
      remote_ip: remote_ip,
      req_headers: headers
    }
    |> put_private(:tenant_id, tenant_id)
  end

  @doc """
  Creates test analytics configuration.
  """
  def create_analytics_config(tenant_id, opts \\ []) do
    attrs = %{
      tenant_id: tenant_id,
      enabled: Keyword.get(opts, :enabled, true),
      track_bots: Keyword.get(opts, :track_bots, false),
      anonymize_ips: Keyword.get(opts, :anonymize_ips, true),
      session_timeout_minutes: Keyword.get(opts, :session_timeout_minutes, 30),
      excluded_paths: Keyword.get(opts, :excluded_paths, ["/health", "/api/_health"])
    }

    WhoThere.Resources.AnalyticsConfiguration
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(tenant: tenant_id)
  end

  @doc """
  Creates a test analytics event.
  """
  def create_analytics_event(tenant_id, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    attrs = %{
      tenant_id: tenant_id,
      session_id: session_id,
      event_type: Keyword.get(opts, :event_type, "page_view"),
      path: Keyword.get(opts, :path, "/"),
      user_agent: Keyword.get(opts, :user_agent, "Mozilla/5.0 Test Browser"),
      ip_hash: Keyword.get(opts, :ip_hash, "test_ip_hash"),
      country: Keyword.get(opts, :country, "US"),
      city: Keyword.get(opts, :city, "San Francisco"),
      is_bot: Keyword.get(opts, :is_bot, false),
      occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now())
    }

    WhoThere.Resources.AnalyticsEvent
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(tenant: tenant_id)
  end

  @doc """
  Creates a test session.
  """
  def create_session(tenant_id, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    attrs = %{
      tenant_id: tenant_id,
      session_id: session_id,
      fingerprint: Keyword.get(opts, :fingerprint, "test_fingerprint_#{:rand.uniform(1000)}"),
      user_agent: Keyword.get(opts, :user_agent, "Mozilla/5.0 Test Browser"),
      ip_hash: Keyword.get(opts, :ip_hash, "test_ip_hash"),
      started_at: Keyword.get(opts, :started_at, DateTime.utc_now()),
      last_seen_at: Keyword.get(opts, :last_seen_at, DateTime.utc_now())
    }

    WhoThere.Resources.Session
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(tenant: tenant_id)
  end

  @doc """
  Generates a random session ID.
  """
  def generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc """
  Waits for a condition to be true within a timeout.
  """
  def wait_until(fun, timeout \\ 1000) do
    wait_until(fun, timeout, 50)
  end

  defp wait_until(fun, timeout, interval) when timeout > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(interval)
      wait_until(fun, timeout - interval, interval)
    end
  end

  defp wait_until(_fun, _timeout, _interval) do
    {:error, :timeout}
  end

  @doc """
  Asserts that a specific telemetry event was emitted.
  """
  def assert_telemetry_event(event_name, metadata \\ %{}, timeout \\ 1000) do
    test_pid = self()

    :telemetry.attach_many(
      "test-telemetry-#{:rand.uniform(1000)}",
      [event_name],
      fn name, measurements, meta, _ ->
        send(test_pid, {:telemetry_event, name, measurements, meta})
      end,
      nil
    )

    receive do
      {:telemetry_event, ^event_name, _measurements, received_metadata} ->
        Enum.each(metadata, fn {key, expected_value} ->
          assert Map.get(received_metadata, key) == expected_value
        end)

        :ok
    after
      timeout ->
        raise "Expected telemetry event #{inspect(event_name)} not received within #{timeout}ms"
    end
  end
end
