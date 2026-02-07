defmodule WhoThere.SessionTracker do
  @moduledoc """
  Session management, fingerprinting, and user identification utilities.

  This module provides cookie-free session tracking using browser fingerprinting,
  session lifecycle management, and integration with Phoenix Presence for
  real-time user tracking.
  """

  alias WhoThere.{Domain, Privacy}

  @doc """
  Generates a browser fingerprint from request data.

  Creates a unique fingerprint based on user agent, accepted languages,
  screen resolution, timezone, and other browser characteristics.

  ## Examples

      iex> conn_data = %{
      ...>   user_agent: "Mozilla/5.0 Chrome/91.0",
      ...>   accept_language: "en-US,en;q=0.9",
      ...>   accept_encoding: "gzip, deflate, br"
      ...> }
      iex> WhoThere.SessionTracker.generate_fingerprint(conn_data)
      "fp_a1b2c3d4e5f6"

  """
  def generate_fingerprint(conn_data) do
    components = [
      normalize_user_agent(conn_data),
      get_accept_language(conn_data),
      get_accept_encoding(conn_data),
      get_screen_info(conn_data),
      get_timezone_info(conn_data),
      get_platform_info(conn_data)
    ]

    fingerprint_hash =
      components
      |> Enum.filter(&(&1 != nil))
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "fp_#{fingerprint_hash}"
  end

  @doc """
  Starts or updates a session for the given connection.

  Returns `{:ok, session}` for new or updated sessions.
  """
  def track_session(conn_data, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    fingerprint = generate_fingerprint(conn_data)

    session_attrs = %{
      fingerprint: fingerprint,
      user_agent: Map.get(conn_data, :user_agent),
      ip_hash: get_or_create_ip_hash(conn_data),
      screen_resolution: Map.get(conn_data, :screen_resolution),
      timezone: Map.get(conn_data, :timezone),
      language: Map.get(conn_data, :accept_language),
      platform: detect_platform(conn_data),
      device_type: detect_device_type(conn_data),
      started_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      page_count: 1,
      is_bounce: true
    }

    case find_existing_session(fingerprint, tenant) do
      nil ->
        create_new_session(session_attrs, tenant)

      existing_session ->
        update_existing_session(existing_session, session_attrs, tenant)
    end
  end

  @doc """
  Determines if a session should be considered a bounce.

  A bounce is typically defined as a session with only one page view
  and duration less than a specified threshold.
  """
  def is_bounce?(session, threshold_seconds \\ 30) do
    case session do
      %{page_count: count, started_at: started, last_seen_at: last_seen} when count <= 1 ->
        duration = DateTime.diff(last_seen, started)
        duration < threshold_seconds

      _ ->
        false
    end
  end

  @doc """
  Calculates session duration in seconds.
  """
  def session_duration(session) do
    case session do
      %{started_at: started, last_seen_at: last_seen} ->
        DateTime.diff(last_seen, started)

      _ ->
        0
    end
  end

  @doc """
  Updates session activity and page count.
  """
  def update_session_activity(session_id, tenant, opts \\ []) do
    case find_session_by_id(session_id, tenant) do
      nil ->
        {:error, :session_not_found}

      session ->
        new_page_count = session.page_count + 1
        is_bounce = new_page_count <= 1

        update_attrs = %{
          last_seen_at: DateTime.utc_now(),
          page_count: new_page_count,
          is_bounce: is_bounce
        }

        update_session(session, update_attrs, tenant)
    end
  end

  @doc """
  Expires sessions that haven't been seen for a specified duration.

  Default timeout is 30 minutes.
  """
  def expire_sessions(tenant, timeout_minutes \\ 30) do
    cutoff_time =
      DateTime.utc_now()
      |> DateTime.add(-timeout_minutes * 60, :second)

    # This would use Ash queries to find and update expired sessions
    # Implementation depends on the Session resource being available
    {:ok, expired_count: 0}
  end

  @doc """
  Integrates with Phoenix Presence to track real-time user activity.

  Returns presence data that can be used with Phoenix.Presence.
  """
  def presence_data(session) do
    %{
      session_id: session.session_id,
      fingerprint: session.fingerprint,
      device_type: session.device_type,
      platform: session.platform,
      joined_at: DateTime.utc_now(),
      last_seen: session.last_seen_at
    }
  end

  @doc """
  Detects if multiple sessions might belong to the same user.

  Uses fingerprint similarity and timing analysis.
  """
  def detect_related_sessions(session, tenant, opts \\ []) do
    time_window = Keyword.get(opts, :time_window_hours, 24)

    cutoff_time =
      DateTime.utc_now()
      |> DateTime.add(-time_window * 3600, :second)

    # This would query for sessions with similar characteristics
    # Implementation depends on the Session resource and queries being available
    {:ok, []}
  end

  @doc """
  Validates session data for privacy compliance.
  """
  def validate_session_privacy(session_data) do
    violations = []

    violations =
      if has_pii_in_user_agent?(session_data),
        do: [:pii_in_user_agent | violations],
        else: violations

    violations =
      if has_tracking_identifiers?(session_data),
        do: [:tracking_identifiers | violations],
        else: violations

    case violations do
      [] -> :ok
      violations -> {:error, violations}
    end
  end

  # Private functions

  defp normalize_user_agent(conn_data) do
    case Map.get(conn_data, :user_agent) do
      nil ->
        nil

      ua ->
        ua
        # Remove version numbers
        |> String.replace(~r/\d+\.\d+\.\d+\.\d+/, "VERSION")
        # Limit length
        |> String.slice(0, 200)
    end
  end

  defp get_accept_language(conn_data) do
    Map.get(conn_data, :accept_language)
  end

  defp get_accept_encoding(conn_data) do
    Map.get(conn_data, :accept_encoding)
  end

  defp get_screen_info(conn_data) do
    Map.get(conn_data, :screen_resolution)
  end

  defp get_timezone_info(conn_data) do
    Map.get(conn_data, :timezone)
  end

  defp get_platform_info(conn_data) do
    detect_platform(conn_data)
  end

  defp detect_platform(conn_data) do
    case Map.get(conn_data, :user_agent, "") do
      ua when is_binary(ua) ->
        cond do
          String.contains?(ua, ["Windows"]) -> "Windows"
          String.contains?(ua, ["Mac OS", "macOS"]) -> "macOS"
          String.contains?(ua, ["Linux"]) -> "Linux"
          String.contains?(ua, ["iPhone", "iPad"]) -> "iOS"
          String.contains?(ua, ["Android"]) -> "Android"
          true -> "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  defp detect_device_type(conn_data) do
    case Map.get(conn_data, :user_agent, "") do
      ua when is_binary(ua) ->
        cond do
          String.contains?(ua, ["Mobile", "Android", "iPhone"]) -> "mobile"
          String.contains?(ua, ["Tablet", "iPad"]) -> "tablet"
          true -> "desktop"
        end

      _ ->
        "unknown"
    end
  end

  defp get_or_create_ip_hash(conn_data) do
    case Map.get(conn_data, :remote_ip) do
      nil ->
        "unknown"

      ip ->
        Privacy.hash_ip(ip)
    end
  end

  defp find_existing_session(fingerprint, tenant) do
    # This would use Domain functions once they're implemented
    # For now, return nil to indicate no existing session
    nil
  end

  defp create_new_session(session_attrs, _tenant) do
    session_id = generate_session_id()
    {:ok, Map.put(session_attrs, :session_id, session_id)}
  end

  defp update_existing_session(session, new_attrs, tenant) do
    # This would use Domain functions to update the session
    # For now, merge the attributes and return
    updated_attrs = %{
      session
      | last_seen_at: new_attrs.last_seen_at,
        page_count: session.page_count + 1,
        is_bounce: false
    }

    {:ok, updated_attrs}
  end

  defp find_session_by_id(session_id, tenant) do
    # This would query for the session by ID
    # For now, return nil
    nil
  end

  defp update_session(session, update_attrs, tenant) do
    # This would update the session using Domain functions
    updated_session = Map.merge(session, update_attrs)
    {:ok, updated_session}
  end

  defp generate_session_id do
    Ash.UUID.generate()
  end

  defp has_pii_in_user_agent?(session_data) do
    case Map.get(session_data, :user_agent) do
      nil -> false
      ua -> Privacy.detect_pii(ua) != []
    end
  end

  defp has_tracking_identifiers?(session_data) do
    # Check for common tracking identifiers that shouldn't be stored
    user_agent = Map.get(session_data, :user_agent, "")

    tracking_patterns = [
      # Facebook app version
      ~r/FBAV\/[\d.]+/,
      # Instagram app
      ~r/Instagram/,
      # WhatsApp
      ~r/WhatsApp/,
      # TikTok app
      ~r/TikTok/
    ]

    Enum.any?(tracking_patterns, fn pattern ->
      Regex.match?(pattern, user_agent)
    end)
  end
end
