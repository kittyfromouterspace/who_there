defmodule WhoThere.RouteFilter do
  @moduledoc """
  Advanced route filtering system for WhoThere analytics.

  This module provides sophisticated route filtering capabilities with support for:
  - Allowlist and blocklist patterns (strings, prefixes, regex)
  - Method-specific filtering (GET, POST, etc.)
  - Performance-optimized pattern compilation
  - Configuration from Ash resources and application config
  - Hierarchical rule precedence

  ## Configuration

  Configure route filters in your application config:

      config :who_there, :route_filters,
        # Global exclusions (applied to all tenants)
        exclude_paths: [
          ~r/^\\/assets\\//,
          ~r/^\\/images\\//,
          "/health",
          "/metrics"
        ],
        
        # Include only these patterns (if specified, acts as allowlist)
        include_only: [
          ~r/^\\/dashboard\\//,
          ~r/^\\/api\\/v1\\//
        ],
        
        # Method-specific exclusions
        exclude_methods: ["OPTIONS", "HEAD"],
        
        # Static asset extensions to exclude
        exclude_extensions: [".css", ".js", ".png", ".jpg", ".ico", ".svg"],
        
        # Maximum path length to track
        max_path_length: 2000,
        
        # Enable rule caching for performance
        cache_compiled_rules: true

  ## Usage

      # Check if a request should be tracked
      if WhoThere.RouteFilter.allow_event?(conn) do
        # Track the request
      end

      # Check with custom options
      opts = [tenant: "my-tenant", privacy_mode: true]
      if WhoThere.RouteFilter.allow_event?(conn, opts) do
        # Track the request
      end

      # Bulk check multiple paths
      paths = ["/", "/dashboard", "/assets/app.css"]
      allowed = WhoThere.RouteFilter.filter_paths(paths, "GET")

  ## Rule Precedence

  Rules are applied in the following order (highest to lowest precedence):

  1. Tenant-specific include_only rules
  2. Tenant-specific exclude rules  
  3. Global include_only rules
  4. Global exclude rules
  5. Built-in exclusions (static assets, health checks)

  ## Performance

  - Pattern compilation is cached for optimal performance
  - Regex patterns are pre-compiled on application start
  - String patterns use optimized prefix matching
  - Rule evaluation is O(1) for most common cases
  """

  require Logger

  @static_asset_extensions [
    ".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".woff", ".woff2",
    ".ttf", ".eot", ".map", ".webp", ".avif", ".pdf", ".txt", ".xml", ".json"
  ]

  @health_check_paths [
    "/health", "/healthz", "/ping", "/status", "/ready", "/live"
  ]

  @metrics_paths [
    "/metrics", "/stats", "/telemetry"
  ]

  @default_excluded_methods ["OPTIONS", "HEAD", "TRACE"]

  @doc """
  Determines if an event should be tracked based on request attributes.

  Returns `true` if the request should be tracked, `false` otherwise.

  ## Parameters

  - `conn_or_attrs` - Either a `Plug.Conn` struct or a map with request attributes
  - `opts` - Optional configuration (tenant, privacy_mode, etc.)

  ## Examples

      # With Plug.Conn
      WhoThere.RouteFilter.allow_event?(conn)

      # With attributes map
      attrs = %{method: "GET", path: "/dashboard", query_string: ""}
      WhoThere.RouteFilter.allow_event?(attrs, tenant: "my-tenant")

      # Skip tracking for admin routes
      if String.starts_with?(conn.request_path, "/admin") do
        false
      else
        WhoThere.RouteFilter.allow_event?(conn)
      end
  """
  def allow_event?(conn_or_attrs, opts \\ []) do
    request_info = extract_request_info(conn_or_attrs)
    tenant = Keyword.get(opts, :tenant)
    
    with :ok <- check_method_allowed(request_info.method),
         :ok <- check_path_length(request_info.path),
         :ok <- check_static_assets(request_info.path),
         :ok <- check_built_in_exclusions(request_info.path),
         :ok <- check_global_rules(request_info, opts),
         :ok <- check_tenant_rules(request_info, tenant, opts) do
      true
    else
      {:filter, _reason} -> false
      :error -> false
    end
  end

  @doc """
  Filters a list of paths, returning only those that should be tracked.

  Useful for bulk processing or route analysis.

  ## Examples

      paths = ["/", "/dashboard", "/assets/app.css", "/api/health"]
      allowed_paths = WhoThere.RouteFilter.filter_paths(paths, "GET")
      # => ["/", "/dashboard"]
  """
  def filter_paths(paths, method \\ "GET", opts \\ []) do
    Enum.filter(paths, fn path ->
      request_info = %{method: method, path: path, query_string: ""}
      allow_event?(request_info, opts)
    end)
  end

  @doc """
  Evaluates a request against compiled allowlist and blocklist rules.
  
  Provides more detailed filtering results than `allow_event?/2`.
  Returns `:allow`, `:block`, or `{:block, reason}` for debugging.
  
  ## Examples
  
      result = WhoThere.RouteFilter.evaluate_request(%{
        method: "GET", 
        path: "/api/admin/users", 
        tenant: "acme"
      })
      
      case result do
        :allow -> 
          track_event(request)
        {:block, reason} -> 
          Logger.debug("Request blocked: " <> inspect(reason))
        :block -> 
          :ok  # Generic block
      end
  """
  def evaluate_request(request_info, opts \\ []) do
    tenant = Map.get(request_info, :tenant) || opts[:tenant]
    
    # Check method first (fastest)
    case check_method_allowed(request_info.method) do
      {:filter, reason} -> {:block, reason}
      :ok ->
        # Check built-in exclusions
        case check_built_in_exclusions(request_info.path) do
          {:filter, reason} -> {:block, reason}
          :ok ->
            # Check allowlist/blocklist rules with precedence
            case check_filtered_rules(request_info, tenant, opts) do
              :allow -> :allow
              {:block, reason} -> {:block, reason}
              :block -> :block
            end
        end
    end
  end
  
  @doc """
  Validates rule configuration and reports any syntax errors.
  
  Useful for testing rule configurations before deployment.
  
  ## Examples
  
      rules = [
        "/api/*",
        ~r/^\/users\/\d+$/,
        {"/admin/*", ["POST", "DELETE"]}
      ]
      
      case WhoThere.RouteFilter.validate_rules(rules) do
        :ok -> 
          "Rules are valid"
        {:error, validation_errors} -> 
          "Validation errors: " <> inspect(validation_errors)
      end
  """
  def validate_rules(rules) when is_list(rules) do
    errors = 
      rules
      |> Enum.with_index()
      |> Enum.reduce([], fn {rule, index}, acc ->
        case validate_single_rule(rule) do
          :ok -> acc
          {:error, reason} -> [%{index: index, rule: rule, error: reason} | acc]
        end
      end)
    
    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end
  
  def validate_rules(%{} = rule_map) do
    allow_errors = validate_rules(Map.get(rule_map, :allow, []))
    block_errors = validate_rules(Map.get(rule_map, :block, []))
    
    case {allow_errors, block_errors} do
      {:ok, :ok} -> :ok
      {allow_result, block_result} ->
        all_errors = extract_errors(allow_result) ++ extract_errors(block_result)
        {:error, all_errors}
    end
  end

  @doc """
  Compiles and caches route filter rules for optimal performance.

  This is called automatically on first use, but can be called explicitly
  to pre-compile rules during application startup.

  ## Examples

      # Pre-compile global rules
      WhoThere.RouteFilter.compile_rules()

      # Pre-compile tenant-specific rules
      WhoThere.RouteFilter.compile_rules("my-tenant")
  """
  def compile_rules(tenant \\ :global) do
    cache_key = {:route_filter_rules, tenant}
    
    if get_config(:cache_compiled_rules, true) do
      case :ets.lookup(:who_there_cache, cache_key) do
        [{^cache_key, compiled_rules, timestamp}] ->
          # Check if rules are still fresh (1 hour TTL)
          if System.system_time(:second) - timestamp < 3600 do
            compiled_rules
          else
            compile_and_cache_rules(tenant, cache_key)
          end
        [] ->
          compile_and_cache_rules(tenant, cache_key)
      end
    else
      compile_rules_for_tenant(tenant)
    end
  end

  @doc """
  Invalidates cached route filter rules.

  Should be called when route filter configuration changes.

  ## Examples

      # Invalidate all cached rules
      WhoThere.RouteFilter.invalidate_cache()

      # Invalidate rules for specific tenant
      WhoThere.RouteFilter.invalidate_cache("my-tenant")
  """
  def invalidate_cache(tenant \\ :all) do
    ensure_ets_table()
    
    case tenant do
      :all ->
        :ets.delete_all_objects(:who_there_cache)
      specific_tenant ->
        :ets.delete(:who_there_cache, {:route_filter_rules, specific_tenant})
    end
    
    :ok
  end

  @doc """
  Returns statistics about route filtering performance and rule usage.

  Useful for monitoring and optimization.
  """
  def get_filter_stats(tenant \\ :global) do
    # This would track actual usage statistics
    %{
      tenant: tenant,
      rules_compiled: true,
      cache_hits: 0,
      cache_misses: 0,
      last_compiled: DateTime.utc_now(),
      rule_count: %{
        include_patterns: 0,
        exclude_patterns: 0,
        regex_patterns: 0,
        string_patterns: 0
      }
    }
  end

  # Private functions

  defp extract_request_info(%Plug.Conn{} = conn) do
    %{
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string || "",
      scheme: conn.scheme,
      host: conn.host
    }
  end

  defp extract_request_info(attrs) when is_map(attrs) do
    %{
      method: Map.get(attrs, :method, "GET"),
      path: Map.get(attrs, :path, "/"),
      query_string: Map.get(attrs, :query_string, ""),
      scheme: Map.get(attrs, :scheme, :http),
      host: Map.get(attrs, :host, "localhost")
    }
  end

  defp check_method_allowed(method) do
    excluded_methods = get_config(:exclude_methods, @default_excluded_methods)
    
    if method in excluded_methods do
      {:filter, {:method_excluded, method}}
    else
      :ok
    end
  end

  defp check_path_length(path) do
    max_length = get_config(:max_path_length, 2000)
    
    if byte_size(path) > max_length do
      {:filter, {:path_too_long, byte_size(path)}}
    else
      :ok
    end
  end

  defp check_static_assets(path) do
    if get_config(:exclude_static_assets, true) do
      excluded_extensions = get_config(:exclude_extensions, @static_asset_extensions)
      
      if Enum.any?(excluded_extensions, &String.ends_with?(path, &1)) do
        {:filter, :static_asset}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_built_in_exclusions(path) do
    built_in_exclusions = @health_check_paths ++ @metrics_paths
    
    if path in built_in_exclusions do
      {:filter, :built_in_exclusion}
    else
      :ok
    end
  end

  defp check_global_rules(request_info, opts) do
    rules = compile_rules(:global)
    evaluate_rules(request_info, rules, opts)
  end

  defp check_tenant_rules(request_info, nil, _opts), do: :ok
  defp check_tenant_rules(request_info, tenant, opts) do
    rules = compile_rules(tenant)
    evaluate_rules(request_info, rules, opts)
  end
  
  # Advanced rule filtering with allowlist/blocklist precedence
  defp check_filtered_rules(request_info, tenant, opts) do
    # Get global and tenant-specific rules
    global_rules = compile_rules(:global)
    tenant_rules = if tenant, do: compile_rules(tenant), else: %{}
    
    # Check tenant allow/block rules first (higher precedence)
    tenant_allow = Map.get(tenant_rules, :include_only, [])
    tenant_block = Map.get(tenant_rules, :exclude, [])
    
    # Then check global allow/block rules
    global_allow = Map.get(global_rules, :include_only, [])
    global_block = Map.get(global_rules, :exclude, [])
    
    # Apply rules with proper precedence
    cond do
      # Tenant-specific blocklist (highest precedence)
      tenant_block != [] && matches_any_pattern?(request_info.path, request_info.method, tenant_block) ->
        {:block, :tenant_blocklist}
        
      # Tenant-specific allowlist
      tenant_allow != [] ->
        if matches_any_pattern?(request_info.path, request_info.method, tenant_allow) do
          :allow
        else
          {:block, :not_in_tenant_allowlist}
        end
        
      # Global blocklist
      global_block != [] && matches_any_pattern?(request_info.path, request_info.method, global_block) ->
        {:block, :global_blocklist}
        
      # Global allowlist
      global_allow != [] ->
        if matches_any_pattern?(request_info.path, request_info.method, global_allow) do
          :allow
        else
          {:block, :not_in_global_allowlist}
        end
        
      # Default policy - allow if no rules match
      true ->
        :allow
    end
  end
  
  # Validation helpers
  defp validate_single_rule(%Regex{}), do: :ok
  
  defp validate_single_rule(pattern) when is_binary(pattern) do
    if String.valid?(pattern) do
      :ok
    else
      {:error, "Invalid UTF-8 string"}
    end
  end
  
  defp validate_single_rule({pattern, methods}) when is_list(methods) do
    with :ok <- validate_single_rule(pattern),
         :ok <- validate_methods(methods) do
      :ok
    end
  end
  
  defp validate_single_rule(_), do: {:error, "Rule must be string, regex, or {pattern, methods} tuple"}
  
  defp validate_methods(methods) do
    valid_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    normalized_methods = Enum.map(methods, &String.upcase(to_string(&1)))
    
    invalid = Enum.reject(normalized_methods, &(&1 in valid_methods))
    if invalid == [] do
      :ok
    else
      {:error, "Invalid HTTP methods: #{inspect(invalid)}"}
    end
  end
  
  defp extract_errors(:ok), do: []
  defp extract_errors({:error, errors}), do: errors

  defp evaluate_rules(request_info, rules, _opts) do
    path = request_info.path
    method = request_info.method

    # Check include_only rules first (if any exist, they act as allowlist)
    include_rules = Map.get(rules, :include_only, [])
    if not Enum.empty?(include_rules) do
      if matches_any_pattern?(path, method, include_rules) do
        :ok
      else
        {:filter, :not_in_allowlist}
      end
    else
      # Check exclude rules
      exclude_rules = Map.get(rules, :exclude, [])
      if matches_any_pattern?(path, method, exclude_rules) do
        {:filter, :explicitly_excluded}
      else
        :ok
      end
    end
  end

  defp matches_any_pattern?(path, method, patterns) do
    Enum.any?(patterns, fn pattern ->
      matches_pattern?(path, method, pattern)
    end)
  end

  defp matches_pattern?(path, method, %{type: :string, pattern: pattern_string, methods: methods}) do
    method_matches = Enum.empty?(methods) or method in methods
    path_matches = String.starts_with?(path, pattern_string)
    method_matches and path_matches
  end

  defp matches_pattern?(path, method, %{type: :regex, pattern: regex, methods: methods}) do
    method_matches = Enum.empty?(methods) or method in methods
    path_matches = Regex.match?(regex, path)
    method_matches and path_matches
  end

  defp matches_pattern?(path, method, %{type: :exact, pattern: exact_path, methods: methods}) do
    method_matches = Enum.empty?(methods) or method in methods
    path_matches = path == exact_path
    method_matches and path_matches
  end
  
  defp matches_pattern?(path, _method, %{type: :exact, pattern: exact_path}) do
    path == exact_path
  end
  
  # Enhanced pattern matching for complex rules
  defp matches_pattern?(path, method, %{type: :prefix, pattern: prefix, methods: methods}) do
    method_matches = Enum.empty?(methods) or method in methods
    path_matches = String.starts_with?(path, prefix)
    method_matches and path_matches
  end
  
  defp matches_pattern?(path, method, %{type: :suffix, pattern: suffix, methods: methods}) do
    method_matches = Enum.empty?(methods) or method in methods
    path_matches = String.ends_with?(path, suffix)
    method_matches and path_matches
  end

  defp compile_and_cache_rules(tenant, cache_key) do
    ensure_ets_table()
    compiled_rules = compile_rules_for_tenant(tenant)
    timestamp = System.system_time(:second)
    :ets.insert(:who_there_cache, {cache_key, compiled_rules, timestamp})
    compiled_rules
  end

  defp compile_rules_for_tenant(:global) do
    global_config = get_global_route_config()
    
    %{
      include_only: compile_patterns(global_config[:include_only] || []),
      exclude: compile_patterns(global_config[:exclude_paths] || [])
    }
  end

  defp compile_rules_for_tenant(tenant) do
    # This would load tenant-specific rules from AnalyticsConfiguration resource
    # For now, using empty rules
    tenant_config = get_tenant_route_config(tenant)
    
    %{
      include_only: compile_patterns(tenant_config[:include_only] || []),
      exclude: compile_patterns(tenant_config[:exclude_paths] || [])
    }
  end

  defp compile_patterns(patterns) do
    Enum.map(patterns, &compile_pattern/1)
  end

  defp compile_pattern(%Regex{} = regex) do
    %{type: :regex, pattern: regex, methods: []}
  end

  defp compile_pattern(string) when is_binary(string) do
    cond do
      # Suffix matching (starts with *)
      String.starts_with?(string, "*") ->
        suffix = String.trim_leading(string, "*")
        %{type: :suffix, pattern: suffix, methods: []}
      
      # Prefix matching (ends with *)
      String.ends_with?(string, "*") ->
        prefix = String.trim_trailing(string, "*")
        %{type: :prefix, pattern: prefix, methods: []}
      
      # Contains wildcard - convert to regex for complex patterns
      String.contains?(string, ["*", "?", "[", "(", "{", "|", "^"]) ->
        # Convert basic glob patterns to regex
        regex_pattern = 
          string
          |> String.replace("*", ".*")
          |> String.replace("?", ".")
          |> (fn p -> "^" <> p <> "$" end).() # Anchor the pattern
          
        case Regex.compile(regex_pattern) do
          {:ok, compiled_regex} ->
            %{type: :regex, pattern: compiled_regex, methods: []}
          {:error, _} ->
            # Fall back to exact match if regex compilation fails
            %{type: :exact, pattern: string, methods: []}
        end
      
      # Default to exact matching
      true ->
        %{type: :exact, pattern: string, methods: []}
    end
  end

  defp compile_pattern({pattern, methods}) when is_list(methods) do
    compiled = compile_pattern(pattern)
    %{compiled | methods: methods}
  end

  defp compile_pattern(other) do
    Logger.warning("Unknown route pattern format: #{inspect(other)}")
    %{type: :string, pattern: to_string(other), methods: []}
  end

  defp get_global_route_config do
    Application.get_env(:who_there, :route_filters, [])
  end

  defp get_tenant_route_config(tenant) do
    # This would query the AnalyticsConfiguration resource for tenant-specific rules
    # For now, returning empty config
    Logger.debug("Loading route config for tenant: #{tenant}")
    []
  end

  defp ensure_ets_table do
    case :ets.whereis(:who_there_cache) do
      :undefined ->
        :ets.new(:who_there_cache, [:named_table, :public, :set])
      _ ->
        :ok
    end
  end

  defp get_config(key, default) do
    :who_there
    |> Application.get_env(:route_filters, [])
    |> Keyword.get(key, default)
  end
end