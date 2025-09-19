defmodule WhoThere.RouteFiltering do
  @moduledoc """
  Route filtering and path pattern analysis utilities for WhoThere analytics.

  This module provides comprehensive tools for analyzing, filtering, and categorizing
  request paths in analytics data. It supports:

  - Path pattern matching and filtering
  - Route classification and grouping
  - Static asset detection and exclusion
  - API endpoint analysis
  - Dynamic route parameter extraction
  - Path normalization and cleaning
  - Route performance analysis
  - Security-focused path filtering

  ## Configuration

  Route filtering can be configured in your application config:

      config :who_there, WhoThere.RouteFiltering,
        # Default patterns to exclude from analytics
        default_excludes: [
          ~r/^\/assets\//,
          ~r/^\/static\//,
          ~r/\.css$/,
          ~r/\.js$/,
          ~r/\.map$/
        ],

        # Patterns for grouping similar routes
        route_groups: %{
          "Admin" => [~r/^\/admin\//],
          "API" => [~r/^\/api\//],
          "Auth" => [~r/^\/auth\//],
          "User Profile" => [~r/^\/users\/\d+/]
        },

        # Maximum path length to track
        max_path_length: 2000,

        # Whether to normalize query parameters
        normalize_query_params: true

  ## Examples

      # Basic path filtering
      paths = ["/users/123", "/assets/app.css", "/api/v1/posts"]
      filtered = WhoThere.RouteFiltering.filter_trackable_paths(paths)
      # Returns: ["/users/123", "/api/v1/posts"]

      # Route classification
      path = "/admin/users/edit"
      category = WhoThere.RouteFiltering.classify_route(path)
      # Returns: {:admin, "Admin"}

      # Dynamic parameter extraction
      path = "/users/123/posts/456"
      normalized = WhoThere.RouteFiltering.normalize_dynamic_path(path)
      # Returns: "/users/:id/posts/:id"
  """

  require Logger

  @type path_pattern :: Regex.t() | String.t()
  @type route_category :: atom()
  @type filter_result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Filters a list of paths to include only trackable routes.

  Removes static assets, known exclusions, and other non-trackable paths
  based on configuration and common patterns.

  ## Options

  - `:exclude_patterns` - Additional patterns to exclude
  - `:include_patterns` - Patterns to explicitly include (overrides excludes)
  - `:exclude_static_assets` - Whether to exclude static assets (default: true)
  - `:max_length` - Maximum path length to consider (default: 2000)

  ## Examples

      iex> paths = ["/home", "/assets/app.css", "/api/users", "/favicon.ico"]
      iex> WhoThere.RouteFiltering.filter_trackable_paths(paths)
      {:ok, ["/home", "/api/users"]}

  """
  def filter_trackable_paths(paths, opts \\ []) when is_list(paths) do
    exclude_patterns = get_exclude_patterns(opts)
    include_patterns = Keyword.get(opts, :include_patterns, [])
    max_length = Keyword.get(opts, :max_length, default_max_path_length())

    filtered_paths =
      paths
      |> Enum.filter(&is_valid_path?(&1, max_length))
      |> Enum.filter(&is_trackable_path?(&1, exclude_patterns, include_patterns))

    {:ok, filtered_paths}
  rescue
    error ->
      Logger.error("Failed to filter paths: #{inspect(error)}")
      {:error, :filter_failed}
  end

  @doc """
  Classifies a route into predefined categories.

  Returns the category and a human-readable label for the route.

  ## Examples

      iex> WhoThere.RouteFiltering.classify_route("/admin/users")
      {:admin, "Admin"}

      iex> WhoThere.RouteFiltering.classify_route("/api/v1/posts")
      {:api, "API"}

      iex> WhoThere.RouteFiltering.classify_route("/unknown/path")
      {:other, "Other"}

  """
  def classify_route(path) when is_binary(path) do
    route_groups = get_route_groups()

    case find_matching_group(path, route_groups) do
      {category, _patterns} -> {category, format_category_label(category)}
      nil -> {:other, "Other"}
    end
  end

  @doc """
  Normalizes dynamic paths by replacing parameters with placeholders.

  Converts paths with dynamic segments (like IDs) into normalized patterns
  for better analytics grouping.

  ## Options

  - `:id_patterns` - Additional patterns to treat as IDs
  - `:preserve_extensions` - Whether to preserve file extensions
  - `:max_segments` - Maximum number of path segments to process

  ## Examples

      iex> WhoThere.RouteFiltering.normalize_dynamic_path("/users/123/posts/456")
      "/users/:id/posts/:id"

      iex> WhoThere.RouteFiltering.normalize_dynamic_path("/files/document.pdf")
      "/files/:file"

  """
  def normalize_dynamic_path(path, opts \\ []) when is_binary(path) do
    id_patterns = get_id_patterns(opts)
    preserve_extensions = Keyword.get(opts, :preserve_extensions, false)
    max_segments = Keyword.get(opts, :max_segments, 10)

    path
    |> String.split("/", trim: true)
    |> Enum.take(max_segments)
    |> Enum.map(&normalize_segment(&1, id_patterns, preserve_extensions))
    |> then(fn segments -> "/" <> Enum.join(segments, "/") end)
  end

  @doc """
  Extracts and analyzes query parameters from a path.

  Returns normalized query parameters and statistics about parameter usage.

  ## Options

  - `:normalize_values` - Whether to normalize parameter values
  - `:exclude_params` - Parameters to exclude from analysis
  - `:max_params` - Maximum number of parameters to analyze

  """
  def analyze_query_parameters(path, opts \\ []) when is_binary(path) do
    case String.split(path, "?", parts: 2) do
      [_path_only] ->
        %{has_query: false, param_count: 0, params: %{}}

      [base_path, query_string] ->
        params = parse_query_parameters(query_string, opts)

        %{
          has_query: true,
          param_count: map_size(params),
          params: params,
          base_path: base_path
        }
    end
  end

  @doc """
  Groups similar paths together for analytics aggregation.

  Returns a map of grouped paths with statistics about each group.

  ## Options

  - `:grouping_strategy` - Strategy for grouping (`:exact`, `:normalized`, `:pattern`)
  - `:min_group_size` - Minimum number of paths required to form a group
  - `:max_groups` - Maximum number of groups to return

  """
  def group_similar_paths(paths, opts \\ []) when is_list(paths) do
    strategy = Keyword.get(opts, :grouping_strategy, :normalized)
    min_group_size = Keyword.get(opts, :min_group_size, 2)
    max_groups = Keyword.get(opts, :max_groups, 50)

    grouped =
      case strategy do
        :exact -> group_by_exact_match(paths)
        :normalized -> group_by_normalized_pattern(paths)
        :pattern -> group_by_route_pattern(paths)
      end

    grouped
    |> Enum.filter(fn {_group, paths} -> length(paths) >= min_group_size end)
    |> Enum.sort_by(fn {_group, paths} -> length(paths) end, :desc)
    |> Enum.take(max_groups)
    |> Enum.into(%{})
  end

  @doc """
  Detects potentially suspicious or problematic paths.

  Identifies paths that might indicate security issues, errors, or unusual activity.

  ## Detection Categories

  - `:security_scan` - Paths indicating security scanning attempts
  - `:bot_behavior` - Paths suggesting bot or automated access
  - `:error_prone` - Paths likely to cause errors
  - `:malformed` - Malformed or invalid paths

  """
  def detect_suspicious_paths(paths, opts \\ []) when is_list(paths) do
    categories = Keyword.get(opts, :categories, [:security_scan, :bot_behavior, :malformed])

    suspicious =
      paths
      |> Enum.map(fn path ->
        suspicion_categories = Enum.filter(categories, &is_suspicious?(&1, path))

        if suspicion_categories != [] do
          {path, suspicion_categories}
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    %{
      total_paths: length(paths),
      suspicious_paths: length(suspicious),
      suspicious_percentage: length(suspicious) / length(paths) * 100,
      details: suspicious
    }
  end

  @doc """
  Analyzes path performance patterns and identifies slow routes.

  Correlates path patterns with performance metrics to identify
  optimization opportunities.

  """
  def analyze_path_performance(path_metrics, opts \\ []) when is_list(path_metrics) do
    threshold_ms = Keyword.get(opts, :slow_threshold_ms, 1000)
    min_samples = Keyword.get(opts, :min_samples, 5)

    performance_groups =
      path_metrics
      |> Enum.group_by(fn %{path: path} -> normalize_dynamic_path(path) end)
      |> Enum.map(fn {pattern, metrics} ->
        if length(metrics) >= min_samples do
          durations = Enum.map(metrics, & &1.duration_ms)
          {pattern, calculate_performance_stats(durations)}
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.into(%{})

    slow_patterns =
      performance_groups
      |> Enum.filter(fn {_pattern, stats} -> stats.avg_duration > threshold_ms end)
      |> Enum.sort_by(fn {_pattern, stats} -> stats.avg_duration end, :desc)

    %{
      total_patterns: map_size(performance_groups),
      slow_patterns: length(slow_patterns),
      performance_groups: performance_groups,
      slowest_routes: Enum.take(slow_patterns, 10)
    }
  end

  @doc """
  Generates route-based filtering expressions for analytics queries.

  Creates filter expressions that can be used with Ash queries to filter
  analytics data by route patterns.

  """
  def build_route_filters(route_specs) when is_list(route_specs) do
    Enum.map(route_specs, fn
      {:include, pattern} -> build_include_filter(pattern)
      {:exclude, pattern} -> build_exclude_filter(pattern)
      {:category, category} -> build_category_filter(category)
      pattern when is_binary(pattern) -> build_include_filter(pattern)
    end)
  end

  # Private helper functions

  defp get_exclude_patterns(opts) do
    default_excludes = default_exclude_patterns()
    additional_excludes = Keyword.get(opts, :exclude_patterns, [])
    exclude_static = Keyword.get(opts, :exclude_static_assets, true)

    patterns = default_excludes ++ additional_excludes

    if exclude_static do
      patterns ++ static_asset_patterns()
    else
      patterns
    end
  end

  defp default_exclude_patterns do
    Application.get_env(:who_there, __MODULE__, [])
    |> Keyword.get(:default_excludes, [
      ~r/^\/assets\//,
      ~r/^\/static\//,
      ~r/^\/images\//,
      ~r/^\/css\//,
      ~r/^\/js\//,
      ~r/^\/fonts\//,
      ~r/\/favicon\.ico$/,
      ~r/\/robots\.txt$/,
      ~r/\/sitemap\.xml$/
    ])
  end

  defp static_asset_patterns do
    [
      ~r/\.css$/,
      ~r/\.js$/,
      ~r/\.map$/,
      ~r/\.png$/,
      ~r/\.jpg$/,
      ~r/\.jpeg$/,
      ~r/\.gif$/,
      ~r/\.svg$/,
      ~r/\.ico$/,
      ~r/\.woff2?$/,
      ~r/\.ttf$/,
      ~r/\.eot$/
    ]
  end

  defp default_max_path_length do
    Application.get_env(:who_there, __MODULE__, [])
    |> Keyword.get(:max_path_length, 2000)
  end

  defp get_route_groups do
    default_groups = %{
      admin: [~r/^\/admin\//],
      api: [~r/^\/api\//],
      auth: [~r/^\/auth\//, ~r/^\/login/, ~r/^\/logout/, ~r/^\/register/],
      user: [~r/^\/users\//, ~r/^\/profile/],
      dashboard: [~r/^\/dashboard/],
      docs: [~r/^\/docs\//, ~r/^\/documentation/]
    }

    Application.get_env(:who_there, __MODULE__, [])
    |> Keyword.get(:route_groups, default_groups)
  end

  defp is_valid_path?(path, max_length) do
    is_binary(path) && byte_size(path) <= max_length && String.starts_with?(path, "/")
  end

  defp is_trackable_path?(path, exclude_patterns, include_patterns) do
    # Check include patterns first (they override excludes)
    explicitly_included =
      include_patterns != [] &&
        Enum.any?(include_patterns, &matches_pattern?(&1, path))

    if explicitly_included do
      true
    else
      not Enum.any?(exclude_patterns, &matches_pattern?(&1, path))
    end
  end

  defp matches_pattern?(%Regex{} = pattern, path), do: Regex.match?(pattern, path)

  defp matches_pattern?(pattern, path) when is_binary(pattern),
    do: String.contains?(path, pattern)

  defp find_matching_group(path, route_groups) do
    Enum.find(route_groups, fn {_category, patterns} ->
      Enum.any?(patterns, &matches_pattern?(&1, path))
    end)
  end

  defp format_category_label(category) do
    category
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_id_patterns(opts) do
    default_patterns = [
      # Pure numbers
      ~r/^\d+$/,
      # UUIDs
      ~r/^[a-f0-9-]{36}$/,
      # Alphanumeric IDs
      ~r/^[a-zA-Z0-9_-]+$/
    ]

    additional = Keyword.get(opts, :id_patterns, [])
    default_patterns ++ additional
  end

  defp normalize_segment(segment, id_patterns, preserve_extensions) do
    # Check if segment looks like an ID
    if Enum.any?(id_patterns, &Regex.match?(&1, segment)) do
      ":id"
    else
      # Check for file extensions
      case String.split(segment, ".", parts: 2) do
        [name, ext] when preserve_extensions ->
          if Enum.any?(id_patterns, &Regex.match?(&1, name)) do
            ":file.#{ext}"
          else
            segment
          end

        [name, _ext] ->
          if Enum.any?(id_patterns, &Regex.match?(&1, name)) do
            ":file"
          else
            segment
          end

        [_name] ->
          segment
      end
    end
  end

  defp parse_query_parameters(query_string, opts) do
    exclude_params = Keyword.get(opts, :exclude_params, [])
    max_params = Keyword.get(opts, :max_params, 20)
    normalize_values = Keyword.get(opts, :normalize_values, true)

    query_string
    |> String.split("&")
    |> Enum.take(max_params)
    |> Enum.map(&parse_param/1)
    |> Enum.filter(fn {key, _value} -> key not in exclude_params end)
    |> Enum.map(fn {key, value} ->
      normalized_value = if normalize_values, do: normalize_param_value(value), else: value
      {key, normalized_value}
    end)
    |> Enum.into(%{})
  end

  defp parse_param(param_string) do
    case String.split(param_string, "=", parts: 2) do
      [key, value] -> {URI.decode(key), URI.decode(value)}
      [key] -> {URI.decode(key), ""}
    end
  end

  defp normalize_param_value(value) do
    cond do
      String.match?(value, ~r/^\d+$/) -> ":number"
      String.match?(value, ~r/^[a-f0-9-]{36}$/) -> ":uuid"
      String.length(value) > 20 -> ":long_string"
      true -> value
    end
  end

  defp group_by_exact_match(paths) do
    Enum.group_by(paths, & &1)
  end

  defp group_by_normalized_pattern(paths) do
    Enum.group_by(paths, &normalize_dynamic_path/1)
  end

  defp group_by_route_pattern(paths) do
    # More aggressive grouping by route patterns
    Enum.group_by(paths, fn path ->
      path
      |> String.split("/", trim: true)
      # Group by first two segments
      |> Enum.take(2)
      |> Enum.join("/")
      |> then(&("/" <> &1))
    end)
  end

  defp is_suspicious?(category, path) do
    case category do
      :security_scan ->
        security_scan_patterns()
        |> Enum.any?(&matches_pattern?(&1, path))

      :bot_behavior ->
        bot_behavior_patterns()
        |> Enum.any?(&matches_pattern?(&1, path))

      :malformed ->
        is_malformed_path?(path)

      :error_prone ->
        error_prone_patterns()
        |> Enum.any?(&matches_pattern?(&1, path))
    end
  end

  defp security_scan_patterns do
    [
      # Directory traversal
      ~r/\.\.\//,
      # Admin access attempts
      ~r/\/admin/,
      # WordPress admin
      ~r/\/wp-admin/,
      # PHP file access on non-PHP sites
      ~r/\.php$/,
      # Config file access
      ~r/\/config/,
      # Environment file access
      ~r/\/env/,
      # Git repository access
      ~r/\/\.git/,
      # Backup file access
      ~r/\/backup/,
      # XSS attempts
      ~r/<script/i,
      # SQL injection attempts
      ~r/union.*select/i
    ]
  end

  defp bot_behavior_patterns do
    [
      ~r/\/crawl/,
      ~r/\/spider/,
      ~r/\/bot/,
      ~r/\/sitemap/,
      ~r/\/feed/,
      ~r/\/rss/
    ]
  end

  defp error_prone_patterns do
    [
      ~r/\/undefined/,
      ~r/\/null/,
      ~r/\[object/,
      ~r/\/error/,
      ~r/\/404/,
      ~r/\/500/
    ]
  end

  defp is_malformed_path?(path) do
    # Check for various malformed path indicators
    # Double slashes
    # Spaces in path
    # Newlines
    # Tabs
    # Extremely long paths
    # Invalid UTF-8
    String.contains?(path, "//") ||
      String.contains?(path, " ") ||
      String.contains?(path, "\n") ||
      String.contains?(path, "\t") ||
      String.length(path) > 2000 ||
      not String.valid?(path)
  end

  defp calculate_performance_stats(durations) do
    sorted = Enum.sort(durations)
    count = length(durations)

    %{
      count: count,
      min_duration: Enum.min(durations),
      max_duration: Enum.max(durations),
      avg_duration: Enum.sum(durations) / count,
      median_duration: median(sorted),
      p95_duration: percentile(sorted, 95),
      p99_duration: percentile(sorted, 99)
    }
  end

  defp median(sorted_list) do
    count = length(sorted_list)
    middle = div(count, 2)

    if rem(count, 2) == 0 do
      (Enum.at(sorted_list, middle - 1) + Enum.at(sorted_list, middle)) / 2
    else
      Enum.at(sorted_list, middle)
    end
  end

  defp percentile(sorted_list, p) do
    count = length(sorted_list)
    index = round(count * p / 100) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_list, index)
  end

  defp build_include_filter(pattern) when is_binary(pattern) do
    {:filter, :path, :contains, pattern}
  end

  defp build_include_filter(%Regex{} = pattern) do
    {:filter, :path, :matches, pattern}
  end

  defp build_exclude_filter(pattern) when is_binary(pattern) do
    {:filter, :path, :not_contains, pattern}
  end

  defp build_exclude_filter(%Regex{} = pattern) do
    {:filter, :path, :not_matches, pattern}
  end

  defp build_category_filter(category) do
    {category_atom, _label} = {category, format_category_label(category)}
    route_groups = get_route_groups()

    case Map.get(route_groups, category_atom) do
      nil -> {:error, :unknown_category}
      patterns -> {:filter, :path, :matches_any, patterns}
    end
  end
end
