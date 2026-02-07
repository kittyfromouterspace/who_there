defmodule WhoThere.Plug do
  @moduledoc """
  Phoenix Plug for automatic request tracking with WhoThere analytics.

  This plug automatically tracks incoming requests, handles session management,
  performs bot detection, extracts geographic data, and respects privacy settings.

  ## Usage

  Add to your Phoenix router or endpoint:

      # In your router.ex
      pipeline :analytics do
        plug WhoThere.Plug, tenant_resolver: &MyApp.get_tenant/1
      end

      # Or in your endpoint.ex
      plug WhoThere.Plug,
        tenant_resolver: &MyApp.get_tenant/1,
        exclude_paths: [~r/^\/api\/health/],
        track_api_calls: true

  ## Configuration Options

  - `:tenant_resolver` - Function to determine tenant from conn (required)
  - `:exclude_paths` - List of path patterns to exclude from tracking
  - `:track_page_views` - Track page view requests (default: true)
  - `:track_api_calls` - Track API requests (default: false)
  - `:track_static_assets` - Track static asset requests (default: false)
  - `:session_tracking` - Enable session tracking (default: true)
  - `:bot_detection` - Enable bot detection (default: true)
  - `:geographic_data` - Extract geographic data (default: true)
  - `:async_tracking` - Process analytics asynchronously (default: true)
  - `:max_path_length` - Maximum path length to track (default: 2000)
  - `:privacy_mode` - Enable privacy-first mode (default: false)

  ## Tenant Resolution

  The tenant resolver function receives the connection and should return
  the tenant identifier:

      def get_tenant(conn) do
        case get_session(conn, :current_tenant) do
          nil -> extract_tenant_from_domain(conn.host)
          tenant -> tenant
        end
      end

  ## Privacy Mode

  When privacy mode is enabled:
  - IP addresses are fully anonymized
  - User agents are normalized
  - Geographic data is limited to country level
  - Session tracking uses minimal fingerprinting

  ## Performance

  The plug is designed for minimal performance impact:
  - Async processing by default
  - Efficient bot detection
  - Configurable tracking scope
  - Automatic static asset exclusion
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias WhoThere.{
    SessionTracker,
    BotDetector,
    GeographicDataParser,
    RouteFiltering,
    Privacy
  }

  @impl true
  def init(opts) do
    %{
      tenant_resolver: Keyword.fetch!(opts, :tenant_resolver),
      exclude_paths: Keyword.get(opts, :exclude_paths, []),
      track_page_views: Keyword.get(opts, :track_page_views, true),
      track_api_calls: Keyword.get(opts, :track_api_calls, false),
      track_static_assets: Keyword.get(opts, :track_static_assets, false),
      session_tracking: Keyword.get(opts, :session_tracking, true),
      bot_detection: Keyword.get(opts, :bot_detection, true),
      geographic_data: Keyword.get(opts, :geographic_data, true),
      async_tracking: Keyword.get(opts, :async_tracking, true),
      max_path_length: Keyword.get(opts, :max_path_length, 2000),
      privacy_mode: Keyword.get(opts, :privacy_mode, false)
    }
  end

  @impl true
  def call(conn, opts) do
    start_time = System.monotonic_time()

    conn
    |> maybe_track_request(opts, start_time)
    |> register_response_tracking(opts, start_time)
  end

  # Private functions

  defp maybe_track_request(conn, opts, start_time) do
    with {:ok, tenant} <- resolve_tenant(conn, opts),
         true <- should_track_request?(conn, opts),
         {:ok, tracking_data} <- build_tracking_data(conn, opts, tenant) do
      if opts.async_tracking do
        # Process asynchronously to avoid blocking the request
        Task.start(fn ->
          process_analytics_tracking(tracking_data, start_time)
        end)
      else
        # Process synchronously (useful for testing or critical tracking)
        process_analytics_tracking(tracking_data, start_time)
      end

      # Store tracking data in conn for potential use by other plugs
      put_private(conn, :who_there_tracking, tracking_data)
    else
      {:error, reason} ->
        Logger.debug("WhoThere tracking skipped: #{inspect(reason)}")
        conn

      false ->
        Logger.debug("WhoThere tracking skipped: request filtered")
        conn
    end
  end

  defp register_response_tracking(conn, opts, start_time) do
    # Register a callback to capture response data
    register_before_send(conn, fn conn ->
      if Map.has_key?(conn.private, :who_there_tracking) do
        duration_ms =
          System.convert_time_unit(
            System.monotonic_time() - start_time,
            :native,
            :millisecond
          )

        # Update tracking data with response information
        update_tracking_with_response(conn, duration_ms, opts)
      end

      conn
    end)
  end

  defp resolve_tenant(conn, opts) do
    try do
      case opts.tenant_resolver.(conn) do
        nil -> {:error, :no_tenant}
        tenant when is_binary(tenant) -> {:ok, tenant}
        other -> {:error, {:invalid_tenant, other}}
      end
    rescue
      error ->
        Logger.error("Failed to resolve tenant: #{inspect(error)}")
        {:error, :tenant_resolution_failed}
    end
  end

  defp should_track_request?(conn, opts) do
    path = conn.request_path

    cond do
      # Check path length
      byte_size(path) > opts.max_path_length ->
        false

      # Check exclude patterns
      matches_exclude_patterns?(path, opts.exclude_paths) ->
        false

      # Check request type tracking preferences
      not tracking_enabled_for_request?(conn, opts) ->
        false

      # Check if it's a static asset and we're not tracking those
      not opts.track_static_assets and is_static_asset?(path) ->
        false

      true ->
        true
    end
  end

  defp matches_exclude_patterns?(path, patterns) do
    Enum.any?(patterns, fn
      %Regex{} = pattern -> Regex.match?(pattern, path)
      string_pattern -> String.contains?(path, string_pattern)
    end)
  end

  defp tracking_enabled_for_request?(conn, opts) do
    cond do
      is_api_request?(conn) -> opts.track_api_calls
      is_page_request?(conn) -> opts.track_page_views
      true -> false
    end
  end

  defp is_api_request?(conn) do
    # Consider it an API request if:
    # - Path starts with /api/
    # - Accept header prefers JSON
    # - Content-Type is JSON
    path_is_api = String.starts_with?(conn.request_path, "/api/")

    accepts_json =
      case get_req_header(conn, "accept") do
        [] -> false
        [accept_header | _] -> String.contains?(accept_header, "application/json")
      end

    content_type_json =
      case get_req_header(conn, "content-type") do
        [] -> false
        [content_type | _] -> String.contains?(content_type, "application/json")
      end

    path_is_api or accepts_json or content_type_json
  end

  defp is_page_request?(conn) do
    # Consider it a page request if:
    # - Method is GET
    # - Accept header includes HTML
    # - Not an API request
    method_is_get = conn.method == "GET"

    accepts_html =
      case get_req_header(conn, "accept") do
        # Default assumption for GET requests
        [] -> true
        [accept_header | _] -> String.contains?(accept_header, "text/html")
      end

    method_is_get and accepts_html and not is_api_request?(conn)
  end

  defp is_static_asset?(path) do
    # Check if path looks like a static asset
    static_extensions = [
      ".css",
      ".js",
      ".map",
      ".png",
      ".jpg",
      ".jpeg",
      ".gif",
      ".svg",
      ".ico",
      ".woff",
      ".woff2",
      ".ttf",
      ".eot",
      ".pdf",
      ".zip"
    ]

    static_paths = ["/assets/", "/static/", "/images/", "/css/", "/js/", "/fonts/"]

    has_static_extension = Enum.any?(static_extensions, &String.ends_with?(path, &1))
    has_static_path = Enum.any?(static_paths, &String.starts_with?(path, &1))

    has_static_extension or has_static_path
  end

  defp build_tracking_data(conn, opts, tenant) do
    try do
      # Extract basic request data
      base_data = %{
        tenant: tenant,
        path: conn.request_path,
        method: conn.method,
        user_agent: get_user_agent(conn),
        remote_ip: get_remote_ip(conn),
        headers: extract_relevant_headers(conn),
        timestamp: DateTime.utc_now(),
        event_type: determine_event_type(conn, opts)
      }

      # Add optional data based on configuration
      tracking_data =
        base_data
        |> maybe_add_session_data(conn, opts)
        |> maybe_add_geographic_data(opts)
        |> maybe_add_bot_detection(opts)
        |> maybe_apply_privacy_filters(opts)

      {:ok, tracking_data}
    rescue
      error ->
        Logger.error("Failed to build tracking data: #{inspect(error)}")
        {:error, :build_tracking_failed}
    end
  end

  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [] -> nil
      [user_agent | _] -> user_agent
    end
  end

  defp get_remote_ip(conn) do
    # Check for forwarded IP in proxy headers first
    forwarded_ip = get_forwarded_ip(conn)
    forwarded_ip || conn.remote_ip
  end

  defp get_forwarded_ip(conn) do
    # Check common proxy headers
    headers_to_check = [
      "x-forwarded-for",
      "x-real-ip",
      "cf-connecting-ip",
      "x-client-ip"
    ]

    Enum.find_value(headers_to_check, fn header ->
      case get_req_header(conn, header) do
        [] ->
          nil

        [ip_string | _] ->
          # Take the first IP from comma-separated list
          ip_string
          |> String.split(",")
          |> List.first()
          |> String.trim()
          |> parse_ip_address()
      end
    end)
  end

  defp parse_ip_address(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> nil
    end
  end

  defp extract_relevant_headers(conn) do
    # Extract headers useful for analytics (geographic, device info, etc.)
    relevant_headers = [
      "accept-language",
      "accept-encoding",
      "cf-ipcountry",
      "cf-ipcity",
      "cf-region",
      "cloudfront-viewer-country",
      "x-country-code",
      "x-forwarded-for"
    ]

    Enum.reduce(relevant_headers, %{}, fn header, acc ->
      case get_req_header(conn, header) do
        [] -> acc
        [value | _] -> Map.put(acc, header, value)
      end
    end)
  end

  defp determine_event_type(conn, opts) do
    cond do
      is_api_request?(conn) -> :api_call
      is_page_request?(conn) -> :page_view
      true -> :other
    end
  end

  defp maybe_add_session_data(tracking_data, conn, opts) do
    if opts.session_tracking do
      conn_data = %{
        user_agent: tracking_data.user_agent,
        remote_ip: tracking_data.remote_ip,
        accept_language: Map.get(tracking_data.headers, "accept-language"),
        accept_encoding: Map.get(tracking_data.headers, "accept-encoding")
      }

      case SessionTracker.track_session(conn_data, tenant: tracking_data.tenant) do
        {:ok, session} ->
          Map.merge(tracking_data, %{
            session_id: session.session_id,
            fingerprint: session.fingerprint,
            device_type: session.device_type,
            platform: session.platform
          })

        {:error, reason} ->
          Logger.debug("Session tracking failed: #{inspect(reason)}")
          tracking_data
      end
    else
      tracking_data
    end
  end

  defp maybe_add_geographic_data(tracking_data, opts) do
    if opts.geographic_data and tracking_data.remote_ip do
      conn_data = %{
        remote_ip: tracking_data.remote_ip,
        headers: tracking_data.headers
      }

      geo_opts =
        if opts.privacy_mode do
          [country_only: true, ip_anonymization: :full]
        else
          [ip_anonymization: :partial]
        end

      case GeographicDataParser.extract_geographic_data(conn_data, geo_opts) do
        {:ok, geo_data} ->
          Map.merge(tracking_data, %{
            country_code: geo_data.country_code,
            city: geo_data.city,
            ip_address: format_ip_for_storage(tracking_data.remote_ip, opts)
          })

        {:error, reason} ->
          Logger.debug("Geographic data extraction failed: #{inspect(reason)}")
          tracking_data
      end
    else
      tracking_data
    end
  end

  defp maybe_add_bot_detection(tracking_data, opts) do
    if opts.bot_detection and tracking_data.user_agent do
      request_data = %{
        user_agent: tracking_data.user_agent,
        ip_address: tracking_data.remote_ip
      }

      if BotDetector.is_bot?(request_data) do
        bot_info = BotDetector.get_bot_info(request_data)

        Map.merge(tracking_data, %{
          event_type: :bot_traffic,
          bot_name: bot_info.bot_name,
          device_type: "bot"
        })
      else
        tracking_data
      end
    else
      tracking_data
    end
  end

  defp maybe_apply_privacy_filters(tracking_data, opts) do
    if opts.privacy_mode do
      tracking_data
      |> Privacy.sanitize_user_agent()
      |> Privacy.anonymize_ip_data()
      |> Privacy.remove_pii()
    else
      tracking_data
    end
  end

  defp format_ip_for_storage(ip_tuple, opts) when is_tuple(ip_tuple) do
    anonymization_level = if opts.privacy_mode, do: :full, else: :partial

    ip_tuple
    |> GeographicDataParser.anonymize_ip(anonymization_level)
    |> :inet.ntoa()
    |> to_string()
  end

  defp format_ip_for_storage(ip, _opts), do: ip

  defp process_analytics_tracking(tracking_data, start_time) do
    try do
      # Create the analytics event
      # Note: session_id is omitted until session persistence is implemented
      event_attrs = %{
        tenant_id: tracking_data.tenant,
        event_type: tracking_data.event_type,
        timestamp: tracking_data.timestamp,
        path: tracking_data.path,
        method: tracking_data.method,
        user_agent: tracking_data.user_agent,
        device_type: Map.get(tracking_data, :device_type),
        ip_address: Map.get(tracking_data, :ip_address),
        country_code: Map.get(tracking_data, :country_code),
        city: Map.get(tracking_data, :city),
        bot_name: Map.get(tracking_data, :bot_name),
        metadata: build_metadata(tracking_data)
      }

      # Remove nil values
      clean_attrs = Enum.reject(event_attrs, fn {_k, v} -> is_nil(v) end) |> Enum.into(%{})

      case WhoThere.Domain.track_event(clean_attrs, tenant: tracking_data.tenant) do
        {:ok, _event} ->
          Logger.debug("Analytics event tracked successfully")

        {:error, reason} ->
          Logger.error("Failed to track analytics event: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.error("Error processing analytics tracking: #{inspect(error)}")
    end
  end

  defp build_metadata(tracking_data) do
    %{
      headers: tracking_data.headers,
      fingerprint: Map.get(tracking_data, :fingerprint),
      platform: Map.get(tracking_data, :platform)
    }
  end

  defp update_tracking_with_response(conn, duration_ms, opts) do
    tracking_data = Map.get(conn.private, :who_there_tracking)

    if tracking_data && opts.async_tracking do
      # Update the event with response data
      Task.start(fn ->
        update_attrs = %{
          status_code: conn.status,
          duration_ms: duration_ms
        }

        # This would update the previously created event
        # Implementation depends on having the event ID available
        Logger.debug("Would update analytics event with response data: #{inspect(update_attrs)}")
      end)
    end
  end
end
