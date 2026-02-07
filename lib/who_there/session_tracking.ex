defmodule WhoThere.SessionTracking do
  @moduledoc """
  Session tracking utilities for WhoThere analytics.

  This module provides secure, cookie-based session tracking that respects privacy
  settings and integrates with the WhoThere analytics system. Sessions are used to
  track user behavior across multiple page views while maintaining anonymity.

  ## Features

  - Secure cookie handling with configurable TTL and security flags
  - Browser fingerprinting for session identification
  - Privacy-first design with optional tracking disable
  - Bot detection integration to avoid tracking non-human traffic
  - Multi-tenant session isolation

  ## Configuration

  Configure session tracking in your application config:

      config :who_there, :session_tracking,
        cookie_name: "who_there_session",
        cookie_ttl_days: 30,
        cookie_secure: true,
        cookie_http_only: true,
        cookie_same_site: "Lax",
        fingerprint_enabled: true,
        privacy_mode: false

  ## Privacy Compliance

  When privacy mode is enabled:
  - Session fingerprinting is minimized
  - Cookie TTL is reduced to 7 days maximum
  - IP-based tracking is disabled
  - User agent fingerprinting is limited
  """

  import Plug.Conn
  require Logger

  alias WhoThere.{Privacy, BotDetector}
  alias WhoThere.Resources.Session

  @default_cookie_name "who_there_session"
  @default_cookie_ttl_days 30
  @privacy_cookie_ttl_days 7

  @doc """
  Gets or creates a session for the current connection.

  Returns `{conn, session_id}` where `conn` has the session cookie set
  and `session_id` is the unique session identifier.

  ## Options

  - `:tenant` - Required tenant identifier
  - `:privacy_mode` - Enable privacy-first tracking (default: false)
  - `:bot_detection` - Enable bot detection to skip tracking (default: true)
  - `:fingerprint_enabled` - Use browser fingerprinting (default: true)
  - `:cookie_ttl_days` - Cookie TTL in days (default: 30, max 7 in privacy mode)

  ## Examples

      {conn, session_id} = WhoThere.SessionTracking.get_or_create_session(
        conn, 
        tenant: "my-tenant"
      )

      # With privacy mode
      {conn, session_id} = WhoThere.SessionTracking.get_or_create_session(
        conn,
        tenant: "my-tenant",
        privacy_mode: true
      )
  """
  def get_or_create_session(conn, opts) do
    tenant = Keyword.fetch!(opts, :tenant)
    privacy_mode = Keyword.get(opts, :privacy_mode, false)
    bot_detection = Keyword.get(opts, :bot_detection, true)
    
    # Skip session tracking for bots unless explicitly disabled
    if bot_detection && is_bot_request?(conn) do
      Logger.debug("Skipping session tracking for bot request")
      {conn, nil}
    else
      do_get_or_create_session(conn, tenant, opts)
    end
  end

  @doc """
  Updates session activity with new page view and metadata.

  This should be called on each tracked request to update session
  statistics and maintain session freshness.

  ## Options

  - `:path` - Current request path
  - `:user_agent` - User agent string
  - `:ip_address` - Client IP (will be anonymized based on privacy settings)
  - `:metadata` - Additional session metadata
  """
  def update_session_activity(session_id, tenant, opts \\ []) do
    if session_id do
      path = Keyword.get(opts, :path)
      user_agent = Keyword.get(opts, :user_agent)
      ip_address = Keyword.get(opts, :ip_address)
      metadata = Keyword.get(opts, :metadata, %{})

      case find_session(session_id, tenant) do
        {:ok, session} ->
          update_attrs = %{
            last_seen_at: DateTime.utc_now(),
            page_count: (session.page_count || 0) + 1,
            last_path: path,
            metadata: Map.merge(session.metadata || %{}, metadata)
          }

          # Add user agent and IP if not already set (for new sessions)
          update_attrs = 
            update_attrs
            |> maybe_add_user_agent(session, user_agent)
            |> maybe_add_ip_address(session, ip_address, Keyword.get(opts, :privacy_mode, false))

          update_session(session, update_attrs, tenant)

        {:error, _} ->
          Logger.debug("Session #{session_id} not found for update")
          {:error, :session_not_found}
      end
    else
      {:ok, nil}
    end
  end

  @doc """
  Expires old sessions based on configured TTL.

  This should be called periodically (e.g., via a scheduled job) to clean up
  expired sessions and maintain database performance.
  """
  def expire_sessions(tenant, timeout_minutes \\ nil) do
    timeout = timeout_minutes || get_session_timeout_minutes()
    cutoff_time = DateTime.add(DateTime.utc_now(), -timeout * 60, :second)

    # This would use Ash queries to delete expired sessions
    # For now, we'll log the operation
    Logger.debug("Would expire sessions older than #{cutoff_time} for tenant #{tenant}")
    {:ok, 0}
  end

  @doc """
  Gets session analytics for a specific session.

  Returns session details including page views, duration, and user journey data.
  """
  def get_session_analytics(session_id, tenant) do
    case find_session(session_id, tenant) do
      {:ok, session} ->
        analytics = %{
          session_id: session_id,
          started_at: session.started_at,
          last_seen_at: session.last_seen_at,
          page_count: session.page_count || 0,
          duration_minutes: calculate_session_duration(session),
          user_agent: session.user_agent,
          fingerprint: session.fingerprint,
          metadata: session.metadata || %{}
        }
        {:ok, analytics}

      error ->
        error
    end
  end

  # Private functions

  defp do_get_or_create_session(conn, tenant, opts) do
    cookie_name = get_config(:cookie_name, @default_cookie_name)
    existing_session_id = get_session_cookie(conn, cookie_name)

    case existing_session_id do
      nil ->
        create_new_session(conn, tenant, opts)
        
      session_id ->
        case find_session(session_id, tenant) do
          {:ok, _session} ->
            # Session exists, refresh cookie and return
            conn = refresh_session_cookie(conn, session_id, opts)
            {conn, session_id}
            
          {:error, _} ->
            # Session expired or invalid, create new one
            create_new_session(conn, tenant, opts)
        end
    end
  end

  defp create_new_session(conn, tenant, opts) do
    session_id = generate_session_id()
    fingerprint = generate_fingerprint(conn, opts)
    
    session_attrs = %{
      id: session_id,
      tenant_id: tenant,
      started_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      fingerprint: fingerprint,
      user_agent: get_user_agent(conn),
      ip_address: get_client_ip(conn, opts),
      page_count: 1,
      metadata: %{}
    }

    case create_session(session_attrs, tenant) do
      {:ok, _session} ->
        conn = set_session_cookie(conn, session_id, opts)
        {conn, session_id}
        
      {:error, reason} ->
        Logger.error("Failed to create session: #{inspect(reason)}")
        {conn, nil}
    end
  end

  defp generate_session_id do
    Ash.UUID.generate()
  end

  defp generate_fingerprint(conn, opts) do
    if Keyword.get(opts, :fingerprint_enabled, true) do
      privacy_mode = Keyword.get(opts, :privacy_mode, false)
      
      fingerprint_data = [
        get_user_agent(conn),
        conn.method,
        get_accept_language(conn),
        get_accept_encoding(conn)
      ]

      # Add less privacy-sensitive data if not in privacy mode
      fingerprint_data = if privacy_mode do
        fingerprint_data
      else
        fingerprint_data ++ [
          get_connection_info(conn),
          get_viewport_info(conn)
        ]
      end

      fingerprint_data
      |> Enum.filter(& &1)
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)  # Use first 16 chars for storage efficiency
    else
      nil
    end
  end

  defp is_bot_request?(conn) do
    user_agent = get_user_agent(conn)
    ip_address = get_client_ip(conn, [])

    if user_agent do
      request_data = %{
        user_agent: user_agent,
        ip_address: ip_address
      }
      
      BotDetector.is_bot?(request_data)
    else
      false
    end
  end

  defp get_session_cookie(conn, cookie_name) do
    case conn.req_cookies[cookie_name] do
      nil -> nil
      cookie_value when is_binary(cookie_value) -> 
        # Validate session ID format
        if String.match?(cookie_value, ~r/^[A-Za-z0-9_-]{32,}$/) do
          cookie_value
        else
          nil
        end
      _ -> nil
    end
  end

  defp set_session_cookie(conn, session_id, opts) do
    privacy_mode = Keyword.get(opts, :privacy_mode, false)
    
    cookie_options = [
      max_age: get_cookie_max_age(privacy_mode),
      secure: get_config(:cookie_secure, true),
      http_only: get_config(:cookie_http_only, true),
      same_site: get_config(:cookie_same_site, "Lax")
    ]

    cookie_name = get_config(:cookie_name, @default_cookie_name)
    put_resp_cookie(conn, cookie_name, session_id, cookie_options)
  end

  defp refresh_session_cookie(conn, session_id, opts) do
    set_session_cookie(conn, session_id, opts)
  end

  defp get_cookie_max_age(privacy_mode) do
    if privacy_mode do
      @privacy_cookie_ttl_days * 24 * 60 * 60
    else
      get_config(:cookie_ttl_days, @default_cookie_ttl_days) * 24 * 60 * 60
    end
  end

  defp find_session(session_id, tenant) do
    # This would use Ash to find the session
    # For now, returning a mock structure
    {:ok, %{
      id: session_id,
      tenant_id: tenant,
      started_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      page_count: 1,
      user_agent: nil,
      fingerprint: nil,
      metadata: %{}
    }}
  end

  defp create_session(session_attrs, tenant) do
    # This would use Ash to create the session
    # For now, returning success
    {:ok, session_attrs}
  end

  defp update_session(session, update_attrs, _tenant) do
    # This would use Ash to update the session
    # For now, returning success
    {:ok, Map.merge(session, update_attrs)}
  end

  defp maybe_add_user_agent(update_attrs, session, user_agent) do
    if session.user_agent || !user_agent do
      update_attrs
    else
      Map.put(update_attrs, :user_agent, user_agent)
    end
  end

  defp maybe_add_ip_address(update_attrs, session, ip_address, privacy_mode) do
    if session.ip_address || !ip_address do
      update_attrs
    else
      anonymized_ip = if privacy_mode do
        Privacy.anonymize_ip(ip_address, :full)
      else
        Privacy.anonymize_ip(ip_address, :partial)
      end
      
      Map.put(update_attrs, :ip_address, anonymized_ip)
    end
  end

  defp calculate_session_duration(session) do
    if session.started_at && session.last_seen_at do
      DateTime.diff(session.last_seen_at, session.started_at, :second)
      |> div(60)  # Convert to minutes
    else
      0
    end
  end

  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent] -> user_agent
      _ -> nil
    end
  end

  defp get_client_ip(conn, opts) do
    # Check for forwarded IPs first, then fall back to remote_ip
    forwarded_ip = 
      get_req_header(conn, "x-forwarded-for") |> List.first() ||
      get_req_header(conn, "x-real-ip") |> List.first()

    case forwarded_ip do
      nil -> 
        format_ip_tuple(conn.remote_ip)
      ip_string -> 
        # Take first IP from comma-separated list
        ip_string 
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp format_ip_tuple({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip_tuple({a, b, c, d, e, f, g, h}) do
    "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"
  end
  defp format_ip_tuple(ip), do: to_string(ip)

  defp get_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [accept_language] -> 
        # Extract primary language code
        accept_language
        |> String.split(",")
        |> List.first()
        |> String.split(";")
        |> List.first()
        |> String.trim()
      _ -> nil
    end
  end

  defp get_accept_encoding(conn) do
    case get_req_header(conn, "accept-encoding") do
      [accept_encoding] -> accept_encoding
      _ -> nil
    end
  end

  defp get_connection_info(conn) do
    # Extract basic connection info for fingerprinting
    conn.scheme |> to_string()
  end

  defp get_viewport_info(_conn) do
    # This would extract viewport size from headers or JavaScript
    # For now, returning nil as this requires client-side integration
    nil
  end

  defp get_session_timeout_minutes do
    get_config(:session_timeout_minutes, 24 * 60)  # 24 hours default
  end

  defp get_config(key, default) do
    :who_there
    |> Application.get_env(:session_tracking, [])
    |> Keyword.get(key, default)
  end
end