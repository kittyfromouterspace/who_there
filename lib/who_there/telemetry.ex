defmodule WhoThere.Telemetry do
  @moduledoc """
  Phoenix Telemetry handlers for LiveView and Phoenix events.

  This module provides telemetry event handling for automatic tracking of
  LiveView mount/unmount events, dead render deduplication, and other
  Phoenix-specific analytics events.
  """

  require Logger

  alias WhoThere.{Domain, SessionTracker, Privacy, BotDetector}

  @doc """
  Attaches all WhoThere telemetry handlers.

  Should be called during application startup to enable automatic
  tracking of Phoenix and LiveView events.
  """
  def attach_handlers do
    handlers = [
      # Phoenix events
      {"who-there-phoenix-endpoint-start", [:phoenix, :endpoint, :start],
       &handle_endpoint_start/4},
      {"who-there-phoenix-endpoint-stop", [:phoenix, :endpoint, :stop], &handle_endpoint_stop/4},
      {"who-there-phoenix-router-dispatch-start", [:phoenix, :router, :dispatch, :start],
       &handle_router_dispatch_start/4},
      {"who-there-phoenix-router-dispatch-stop", [:phoenix, :router, :dispatch, :stop],
       &handle_router_dispatch_stop/4},

      # LiveView events
      {"who-there-phoenix-live-view-mount", [:phoenix, :live_view, :mount, :start],
       &handle_live_view_mount_start/4},
      {"who-there-phoenix-live-view-mount-stop", [:phoenix, :live_view, :mount, :stop],
       &handle_live_view_mount_stop/4},
      {"who-there-phoenix-live-view-handle-params",
       [:phoenix, :live_view, :handle_params, :start], &handle_live_view_handle_params/4},
      {"who-there-phoenix-live-view-handle-event", [:phoenix, :live_view, :handle_event, :start],
       &handle_live_view_handle_event/4},
      {"who-there-phoenix-live-view-render", [:phoenix, :live_view, :render, :start],
       &handle_live_view_render_start/4},
      {"who-there-phoenix-live-view-render-stop", [:phoenix, :live_view, :render, :stop],
       &handle_live_view_render_stop/4},

      # Phoenix Channel events
      {"who-there-phoenix-channel-join", [:phoenix, :channel, :join], &handle_channel_join/4},
      {"who-there-phoenix-channel-leave", [:phoenix, :channel, :leave], &handle_channel_leave/4},

      # Custom WhoThere events
      {"who-there-analytics-event", [:who_there, :analytics, :event], &handle_analytics_event/4},
      {"who-there-session-start", [:who_there, :session, :start], &handle_session_start/4},
      {"who-there-session-end", [:who_there, :session, :end], &handle_session_end/4}
    ]

    Enum.each(handlers, fn {handler_id, event_name, handler_function} ->
      case :telemetry.attach(handler_id, event_name, handler_function, %{}) do
        :ok ->
          Logger.debug("Attached WhoThere telemetry handler: #{handler_id}")

        {:error, :already_exists} ->
          Logger.debug("WhoThere telemetry handler already exists: #{handler_id}")

        {:error, reason} ->
          Logger.error(
            "Failed to attach WhoThere telemetry handler #{handler_id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  @doc """
  Detaches all WhoThere telemetry handlers.

  Useful for testing or when shutting down the application.
  """
  def detach_handlers do
    handler_ids = [
      "who-there-phoenix-endpoint-start",
      "who-there-phoenix-endpoint-stop",
      "who-there-phoenix-router-dispatch-start",
      "who-there-phoenix-router-dispatch-stop",
      "who-there-phoenix-live-view-mount",
      "who-there-phoenix-live-view-mount-stop",
      "who-there-phoenix-live-view-handle-params",
      "who-there-phoenix-live-view-handle-event",
      "who-there-phoenix-live-view-render",
      "who-there-phoenix-live-view-render-stop",
      "who-there-phoenix-channel-join",
      "who-there-phoenix-channel-leave",
      "who-there-analytics-event",
      "who-there-session-start",
      "who-there-session-end"
    ]

    Enum.each(handler_ids, fn handler_id ->
      case :telemetry.detach(handler_id) do
        :ok ->
          Logger.debug("Detached WhoThere telemetry handler: #{handler_id}")

        {:error, :not_found} ->
          Logger.debug("WhoThere telemetry handler not found: #{handler_id}")

        {:error, reason} ->
          Logger.error(
            "Failed to detach WhoThere telemetry handler #{handler_id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  @doc """
  Emits a custom analytics event.

  This can be used by applications to track custom events.
  """
  def emit_analytics_event(event_type, metadata \\ %{}, measurements \\ %{}) do
    :telemetry.execute(
      [:who_there, :analytics, :event],
      Map.merge(%{count: 1}, measurements),
      Map.merge(%{event_type: event_type}, metadata)
    )
  end

  @doc """
  Emits a session start event.
  """
  def emit_session_start(session_data, metadata \\ %{}) do
    :telemetry.execute(
      [:who_there, :session, :start],
      %{count: 1},
      Map.merge(%{session: session_data}, metadata)
    )
  end

  @doc """
  Emits a session end event.
  """
  def emit_session_end(session_data, metadata \\ %{}) do
    :telemetry.execute(
      [:who_there, :session, :end],
      %{count: 1, duration: SessionTracker.session_duration(session_data)},
      Map.merge(%{session: session_data}, metadata)
    )
  end

  @doc """
  Checks if telemetry tracking is enabled for the current request.

  Uses configuration and request context to determine if events should be tracked.
  """
  def tracking_enabled?(metadata) do
    cond do
      # Check if WhoThere is globally disabled
      not Application.get_env(:who_there, :enabled, true) ->
        false

      # Check if request should be excluded based on path
      should_exclude_path?(metadata) ->
        false

      # Check if request is from a bot and bot tracking is disabled
      is_bot_request?(metadata) and not bot_tracking_enabled?(metadata) ->
        false

      # Check for do-not-track header
      has_do_not_track?(metadata) ->
        false

      # Check tenant-specific configuration
      not tenant_tracking_enabled?(metadata) ->
        false

      true ->
        true
    end
  end

  # Phoenix event handlers

  defp handle_endpoint_start(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      # Store start time for duration calculation
      Process.put(:who_there_request_start, measurements.monotonic_time)
    end
  end

  defp handle_endpoint_stop(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      start_time = Process.get(:who_there_request_start)
      duration = measurements.monotonic_time - (start_time || measurements.monotonic_time)

      event_data = %{
        event_type: "http_request",
        path: extract_path(metadata),
        method: extract_method(metadata),
        status: extract_status(metadata),
        duration_microseconds: System.convert_time_unit(duration, :native, :microsecond),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_router_dispatch_start(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      # Store route information for later use
      Process.put(:who_there_route_info, %{
        route: Map.get(metadata, :route),
        plug: Map.get(metadata, :plug),
        plug_opts: Map.get(metadata, :plug_opts)
      })
    end
  end

  defp handle_router_dispatch_stop(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      route_info = Process.get(:who_there_route_info, %{})

      event_data = %{
        event_type: "route_dispatch",
        route: Map.get(route_info, :route),
        controller: extract_controller(route_info),
        action: extract_action(route_info),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  # LiveView event handlers

  defp handle_live_view_mount_start(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) and connected_liveview?(metadata) do
      # Only track connected LiveView mounts to avoid double counting
      event_data = %{
        event_type: "liveview_mount",
        live_view: extract_live_view_module(metadata),
        connected: Map.get(metadata, :connected, false),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_live_view_mount_stop(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) and connected_liveview?(metadata) do
      event_data = %{
        event_type: "liveview_mount_complete",
        live_view: extract_live_view_module(metadata),
        duration_microseconds: measurements.duration,
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_live_view_handle_params(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) and connected_liveview?(metadata) do
      event_data = %{
        event_type: "liveview_navigation",
        live_view: extract_live_view_module(metadata),
        params: sanitize_params(Map.get(metadata, :params, %{})),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_live_view_handle_event(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      event_data = %{
        event_type: "liveview_event",
        live_view: extract_live_view_module(metadata),
        event: Map.get(metadata, :event),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_live_view_render_start(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      # Store render start time
      Process.put(:who_there_render_start, metadata)
    end
  end

  defp handle_live_view_render_stop(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      render_start = Process.get(:who_there_render_start, %{})

      # Only track slow renders to avoid noise
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

      if duration_ms > get_slow_render_threshold() do
        event_data = %{
          event_type: "slow_render",
          live_view: extract_live_view_module(metadata),
          duration_microseconds: measurements.duration,
          occurred_at: DateTime.utc_now()
        }

        track_event_async(event_data, metadata)
      end
    end
  end

  # Channel event handlers

  defp handle_channel_join(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      event_data = %{
        event_type: "channel_join",
        channel: extract_channel_module(metadata),
        topic: Map.get(metadata, :topic),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_channel_leave(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      event_data = %{
        event_type: "channel_leave",
        channel: extract_channel_module(metadata),
        topic: Map.get(metadata, :topic),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  # Custom event handlers

  defp handle_analytics_event(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      event_data = %{
        event_type: Map.get(metadata, :event_type, "custom"),
        custom_data: Map.drop(metadata, [:event_type]),
        measurements: measurements,
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  defp handle_session_start(_event_name, _measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      session_data = Map.get(metadata, :session, %{})
      tenant = extract_tenant(metadata)

      Task.start(fn ->
        case SessionTracker.track_session(session_data, tenant: tenant) do
          {:ok, _session} ->
            Logger.debug("Session started for tenant #{tenant}")

          {:error, reason} ->
            Logger.error("Failed to start session: #{inspect(reason)}")
        end
      end)
    end
  end

  defp handle_session_end(_event_name, measurements, metadata, _config) do
    if tracking_enabled?(metadata) do
      session_data = Map.get(metadata, :session, %{})
      duration = Map.get(measurements, :duration, 0)

      event_data = %{
        event_type: "session_end",
        session_duration: duration,
        is_bounce: SessionTracker.is_bounce?(session_data),
        occurred_at: DateTime.utc_now()
      }

      track_event_async(event_data, metadata)
    end
  end

  # Helper functions

  defp track_event_async(event_data, metadata) do
    tenant = extract_tenant(metadata)
    conn_data = extract_conn_data(metadata)

    Task.start(fn ->
      # Enhance event data with request context
      enhanced_event_data =
        event_data
        |> Map.merge(conn_data)
        |> Map.put(:tenant_id, tenant)

      case Domain.track_event(enhanced_event_data, tenant: tenant) do
        {:ok, _event} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to track event: #{inspect(reason)}")
      end
    end)
  end

  defp extract_path(metadata) do
    case Map.get(metadata, :conn) do
      %{request_path: path} -> path
      _ -> Map.get(metadata, :request_path, "/")
    end
  end

  defp extract_method(metadata) do
    case Map.get(metadata, :conn) do
      %{method: method} -> method
      _ -> Map.get(metadata, :method, "GET")
    end
  end

  defp extract_status(metadata) do
    case Map.get(metadata, :conn) do
      %{status: status} -> status
      _ -> Map.get(metadata, :status, 200)
    end
  end

  defp extract_controller(route_info) do
    case Map.get(route_info, :plug) do
      controller when is_atom(controller) -> inspect(controller)
      _ -> "unknown"
    end
  end

  defp extract_action(route_info) do
    case Map.get(route_info, :plug_opts) do
      action when is_atom(action) -> to_string(action)
      _ -> "unknown"
    end
  end

  defp extract_live_view_module(metadata) do
    case Map.get(metadata, :socket) do
      %{view: view} when is_atom(view) -> inspect(view)
      _ -> "unknown"
    end
  end

  defp extract_channel_module(metadata) do
    case Map.get(metadata, :socket) do
      %{channel: channel} when is_atom(channel) -> inspect(channel)
      _ -> "unknown"
    end
  end

  defp extract_tenant(metadata) do
    case Map.get(metadata, :conn) do
      %{private: %{tenant_id: tenant_id}} -> tenant_id
      _ -> Map.get(metadata, :tenant_id, "default")
    end
  end

  defp extract_conn_data(metadata) do
    case Map.get(metadata, :conn) do
      %{} = conn ->
        %{
          user_agent: get_req_header_value(conn, "user-agent"),
          accept_language: get_req_header_value(conn, "accept-language"),
          remote_ip: Map.get(conn, :remote_ip),
          req_headers: Map.get(conn, :req_headers, [])
        }

      _ ->
        %{}
    end
  end

  defp get_req_header_value(conn, header_name) do
    case Enum.find(Map.get(conn, :req_headers, []), fn {name, _value} ->
           String.downcase(name) == String.downcase(header_name)
         end) do
      {_name, value} -> value
      nil -> nil
    end
  end

  defp connected_liveview?(metadata) do
    case Map.get(metadata, :socket) do
      %{connected?: true} -> true
      _ -> false
    end
  end

  defp sanitize_params(params) do
    # Remove potentially sensitive parameter values
    sensitive_keys = ["password", "token", "api_key", "secret", "csrf_token"]

    Enum.reduce(params, %{}, fn {key, value}, acc ->
      if Enum.any?(sensitive_keys, &String.contains?(String.downcase(to_string(key)), &1)) do
        Map.put(acc, key, "[REDACTED]")
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp should_exclude_path?(metadata) do
    path = extract_path(metadata)
    excluded_paths = Application.get_env(:who_there, :excluded_paths, ["/health", "/metrics"])

    Enum.any?(excluded_paths, fn excluded_path ->
      String.starts_with?(path, excluded_path)
    end)
  end

  defp is_bot_request?(metadata) do
    case extract_conn_data(metadata) do
      %{user_agent: user_agent} when is_binary(user_agent) ->
        BotDetector.is_bot?(user_agent)

      _ ->
        false
    end
  end

  defp bot_tracking_enabled?(metadata) do
    tenant = extract_tenant(metadata)
    # This would check tenant configuration
    # For now, default to enabled
    Application.get_env(:who_there, :track_bots, true)
  end

  defp has_do_not_track?(metadata) do
    case extract_conn_data(metadata) do
      %{req_headers: headers} ->
        Enum.any?(headers, fn {name, value} ->
          String.downcase(name) == "dnt" and value == "1"
        end)

      _ ->
        false
    end
  end

  defp tenant_tracking_enabled?(metadata) do
    tenant = extract_tenant(metadata)
    # This would check tenant-specific configuration
    # For now, default to enabled
    true
  end

  defp get_slow_render_threshold do
    Application.get_env(:who_there, :slow_render_threshold_ms, 100)
  end
end
