defmodule WhoThere.PhoenixIntegration do
  @moduledoc """
  Phoenix framework integration for WhoThere analytics.

  This module provides seamless integration with Phoenix applications including:
  - Automatic Telemetry event handling
  - LiveView tracking support  
  - LiveDashboard metrics integration
  - Performance monitoring
  - Request/response tracking

  ## Setup

  Add to your application supervision tree:

      children = [
        # ... other children
        {WhoThere.PhoenixIntegration, []}
      ]

  Add telemetry handlers in your application start:

      def start(_type, _args) do
        WhoThere.PhoenixIntegration.attach_telemetry_handlers()
        # ... rest of your start function
      end

  ## LiveDashboard Integration

  Add to your router.ex:

      import Phoenix.LiveDashboard.Router
      
      scope "/" do
        pipe_through :browser
        live_dashboard "/dashboard",
          additional_pages: [
            analytics: {WhoThere.PhoenixIntegration.LiveDashboardPage, []}
          ]
      end

  ## Configuration

      config :who_there, :phoenix_integration,
        # Enable telemetry tracking
        telemetry_enabled: true,
        
        # Track LiveView events
        track_live_view: true,
        
        # Track database queries (via Ecto telemetry)
        track_db_queries: false,
        
        # Performance monitoring
        track_performance: true,
        
        # Custom event handlers
        custom_handlers: []
  """

  use GenServer
  require Logger

  @telemetry_events [
    # Phoenix router events
    [:phoenix, :router_dispatch, :start],
    [:phoenix, :router_dispatch, :stop],
    
    # Phoenix endpoint events
    [:phoenix, :endpoint, :start],
    [:phoenix, :endpoint, :stop],
    
    # LiveView events
    [:phoenix, :live_view, :mount, :start],
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :handle_event, :start],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :render, :start],
    [:phoenix, :live_view, :render, :stop],
    
    # Plug events
    [:plug, :router_dispatch, :stop],
    
    # Custom WhoThere events
    [:who_there, :analytics, :event_tracked],
    [:who_there, :analytics, :error]
  ]

  ## GenServer Implementation

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if get_config(:telemetry_enabled, true) do
      attach_telemetry_handlers()
    end
    
    {:ok, %{handlers_attached: true}}
  end

  @impl true
  def handle_info({:telemetry_event, event, _measurements, _metadata}, state) do
    # Handle custom telemetry events if needed
    Logger.debug("Received telemetry event: #{inspect(event)}")
    {:noreply, state}
  end

  ## Public API

  @doc """
  Attaches all WhoThere telemetry handlers.
  
  Call this from your application start function.
  """
  def attach_telemetry_handlers do
    Enum.each(@telemetry_events, &attach_handler/1)
    
    # Attach custom handlers from config
    custom_handlers = get_config(:custom_handlers, [])
    Enum.each(custom_handlers, &attach_custom_handler/1)
    
    Logger.info("WhoThere telemetry handlers attached")
  end

  @doc """
  Detaches all WhoThere telemetry handlers.
  
  Useful for testing or application shutdown.
  """
  def detach_telemetry_handlers do
    Enum.each(@telemetry_events, fn event ->
      handler_id = build_handler_id(event)
      :telemetry.detach(handler_id)
    end)
    
    Logger.info("WhoThere telemetry handlers detached")
  end

  @doc """
  Emits a custom analytics event.
  
  ## Examples
  
      WhoThere.PhoenixIntegration.emit_analytics_event(:user_signup, %{
        user_id: "123",
        plan: "premium"
      })
  """
  def emit_analytics_event(event_name, data \\ %{}) do
    :telemetry.execute(
      [:who_there, :analytics, :custom],
      %{count: 1, timestamp: System.system_time(:millisecond)},
      Map.put(data, :event_name, event_name)
    )
  end

  ## Telemetry Handlers

  defp attach_handler(event) do
    handler_id = build_handler_id(event)
    
    :telemetry.attach(
      handler_id,
      event,
      &handle_telemetry_event/4,
      %{}
    )
  end

  defp attach_custom_handler({event, handler_fun}) when is_function(handler_fun) do
    handler_id = build_handler_id(event)
    
    :telemetry.attach(
      handler_id,
      event,
      handler_fun,
      %{}
    )
  end

  defp build_handler_id(event) do
    event_name = event |> Enum.join("_") |> String.to_atom()
    :"who_there_#{event_name}"
  end

  # Main telemetry event handler
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    case event do
      [:phoenix, :endpoint, :stop] ->
        handle_phoenix_endpoint_stop(measurements, metadata)
        
      [:phoenix, :router_dispatch, :stop] ->
        handle_router_dispatch_stop(measurements, metadata)
        
      [:phoenix, :live_view, :mount, :stop] ->
        if get_config(:track_live_view, true) do
          handle_live_view_mount_stop(measurements, metadata)
        end
        
      [:phoenix, :live_view, :handle_event, :stop] ->
        if get_config(:track_live_view, true) do
          handle_live_view_event_stop(measurements, metadata)
        end
        
      [:phoenix, :live_view, :render, :stop] ->
        if get_config(:track_live_view, true) do
          handle_live_view_render_stop(measurements, metadata)
        end
        
      [:who_there, :analytics, :event_tracked] ->
        handle_analytics_event_tracked(measurements, metadata)
        
      [:who_there, :analytics, :error] ->
        handle_analytics_error(measurements, metadata)
        
      _ ->
        Logger.debug("Unhandled telemetry event: #{inspect(event)}")
    end
  rescue
    error ->
      Logger.error("Error in telemetry handler: #{inspect(error)}")
  end

  # Phoenix endpoint handler
  defp handle_phoenix_endpoint_stop(measurements, metadata) do
    if should_track_endpoint_event?(metadata) do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      
      analytics_data = %{
        event_type: :endpoint_request,
        duration_ms: duration_ms,
        metadata: %{
          endpoint: metadata[:endpoint],
          plug_stack_length: metadata[:plug_stack] && length(metadata[:plug_stack])
        }
      }
      
      emit_analytics_event(:phoenix_endpoint, analytics_data)
    end
  end

  # Phoenix router handler
  defp handle_router_dispatch_stop(measurements, metadata) do
    if should_track_router_event?(metadata) do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      
      analytics_data = %{
        event_type: :router_dispatch,
        duration_ms: duration_ms,
        metadata: %{
          route: metadata[:route],
          conn: extract_safe_conn_data(metadata[:conn])
        }
      }
      
      emit_analytics_event(:phoenix_router, analytics_data)
    end
  end

  # LiveView mount handler
  defp handle_live_view_mount_stop(measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    analytics_data = %{
      event_type: :liveview_mount,
      duration_ms: duration_ms,
      metadata: %{
        view: metadata[:view],
        connected?: metadata[:connected?] == true
      }
    }
    
    emit_analytics_event(:liveview_mount, analytics_data)
  end

  # LiveView event handler
  defp handle_live_view_event_stop(measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    analytics_data = %{
      event_type: :liveview_event,
      duration_ms: duration_ms,
      metadata: %{
        view: metadata[:view],
        event: metadata[:event]
      }
    }
    
    emit_analytics_event(:liveview_event, analytics_data)
  end

  # LiveView render handler 
  defp handle_live_view_render_stop(measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    # Only track slow renders to avoid noise
    if duration_ms > get_config(:slow_render_threshold_ms, 100) do
      analytics_data = %{
        event_type: :liveview_slow_render,
        duration_ms: duration_ms,
        metadata: %{
          view: metadata[:view]
        }
      }
      
      emit_analytics_event(:liveview_slow_render, analytics_data)
    end
  end

  # Analytics event tracking handler
  defp handle_analytics_event_tracked(measurements, metadata) do
    Logger.debug("Analytics event tracked: #{inspect(metadata)}")
    
    # Could emit metrics to external monitoring systems here
    if get_config(:emit_metrics, false) do
      emit_to_external_metrics(measurements, metadata)
    end
  end

  # Analytics error handler
  defp handle_analytics_error(_measurements, metadata) do
    Logger.warning("Analytics error: #{inspect(metadata)}")
    
    # Could emit error metrics to monitoring systems
    if get_config(:emit_error_metrics, true) do
      emit_error_metrics(metadata)
    end
  end

  ## Helper Functions

  defp should_track_endpoint_event?(metadata) do
    # Filter out health checks, assets, etc.
    conn = metadata[:conn]

    if conn do
      path = conn.request_path

      exclude_paths = get_config(:telemetry_exclude_paths, ["/health", "/metrics"])
      not Enum.any?(exclude_paths, &String.starts_with?(path, &1))
    else
      false
    end
  end

  defp should_track_router_event?(metadata) do
    # Similar filtering for router events
    should_track_endpoint_event?(metadata)
  end

  defp extract_safe_conn_data(conn) when is_map(conn) do
    %{
      method: conn.method,
      path_info: conn.path_info,
      status: conn.status,
      remote_ip: format_ip(conn.remote_ip)
    }
  end

  defp extract_safe_conn_data(_), do: %{}

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(other), do: inspect(other)

  defp emit_to_external_metrics(measurements, metadata) do
    # Implementation for external metrics systems (Datadog, New Relic, etc.)
    Logger.debug("Would emit metrics: #{inspect(%{measurements: measurements, metadata: metadata})}")
  end

  defp emit_error_metrics(metadata) do
    # Implementation for error tracking systems
    Logger.debug("Would emit error metrics: #{inspect(metadata)}")
  end

  defp get_config(key, default) do
    :who_there
    |> Application.get_env(:phoenix_integration, [])
    |> Keyword.get(key, default)
  end
end