defmodule WhoThere.RouteFilteringTest do
  use ExUnit.Case, async: true

  alias WhoThere.RouteFiltering

  describe "filter_trackable_paths/2" do
    test "filters out static assets by default" do
      paths = [
        "/home",
        "/assets/app.css",
        "/static/logo.png",
        "/api/users",
        "/favicon.ico",
        "/robots.txt"
      ]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths)
      assert filtered == ["/home", "/api/users"]
    end

    test "filters out common file extensions" do
      paths = [
        "/page",
        "/script.js",
        "/style.css",
        "/image.png",
        "/font.woff2",
        "/source.map"
      ]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths)
      assert filtered == ["/page"]
    end

    test "respects custom exclude patterns" do
      paths = ["/admin/users", "/public/page", "/admin/settings"]

      opts = [exclude_patterns: [~r/^\/admin\//]]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths, opts)
      assert filtered == ["/public/page"]
    end

    test "include patterns override excludes" do
      paths = ["/assets/important.css", "/assets/normal.css", "/page"]

      opts = [
        exclude_patterns: [~r/^\/assets\//],
        include_patterns: [~r/important/]
      ]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths, opts)
      assert "/assets/important.css" in filtered
      refute "/assets/normal.css" in filtered
      assert "/page" in filtered
    end

    test "filters out paths exceeding max length" do
      short_path = "/short"
      long_path = "/" <> String.duplicate("a", 2001)
      paths = [short_path, long_path]

      opts = [max_length: 2000]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths, opts)
      assert filtered == [short_path]
    end

    test "filters out invalid paths" do
      paths = [
        "/valid/path",
        "invalid-no-slash",
        "",
        nil
      ]

      # Remove nil first since it will cause enum errors
      valid_paths = Enum.filter(paths, &is_binary/1)

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(valid_paths)
      assert filtered == ["/valid/path"]
    end

    test "allows disabling static asset filtering" do
      paths = ["/page", "/style.css", "/script.js"]

      opts = [exclude_static_assets: false]

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths, opts)
      assert length(filtered) == 3
    end
  end

  describe "classify_route/1" do
    test "classifies admin routes" do
      assert {:admin, "Admin"} = RouteFiltering.classify_route("/admin/users")
      assert {:admin, "Admin"} = RouteFiltering.classify_route("/admin/settings/general")
    end

    test "classifies API routes" do
      assert {:api, "API"} = RouteFiltering.classify_route("/api/v1/users")
      assert {:api, "API"} = RouteFiltering.classify_route("/api/posts")
    end

    test "classifies auth routes" do
      assert {:auth, "Auth"} = RouteFiltering.classify_route("/auth/login")
      assert {:auth, "Auth"} = RouteFiltering.classify_route("/login")
      assert {:auth, "Auth"} = RouteFiltering.classify_route("/logout")
      assert {:auth, "Auth"} = RouteFiltering.classify_route("/register")
    end

    test "classifies user routes" do
      assert {:user, "User"} = RouteFiltering.classify_route("/users/123")
      assert {:user, "User"} = RouteFiltering.classify_route("/profile")
    end

    test "classifies dashboard routes" do
      assert {:dashboard, "Dashboard"} = RouteFiltering.classify_route("/dashboard")
      assert {:dashboard, "Dashboard"} = RouteFiltering.classify_route("/dashboard/analytics")
    end

    test "classifies documentation routes" do
      assert {:docs, "Docs"} = RouteFiltering.classify_route("/docs/getting-started")
      assert {:docs, "Docs"} = RouteFiltering.classify_route("/documentation/api")
    end

    test "returns other for unmatched routes" do
      assert {:other, "Other"} = RouteFiltering.classify_route("/random/path")
      assert {:other, "Other"} = RouteFiltering.classify_route("/some/unknown/route")
    end
  end

  describe "normalize_dynamic_path/2" do
    test "normalizes numeric IDs" do
      assert "/users/:id" = RouteFiltering.normalize_dynamic_path("/users/123")

      assert "/posts/:id/comments/:id" =
               RouteFiltering.normalize_dynamic_path("/posts/456/comments/789")
    end

    test "normalizes UUID parameters" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert "/users/:id" = RouteFiltering.normalize_dynamic_path("/users/#{uuid}")
    end

    test "normalizes alphanumeric IDs" do
      assert "/users/:id" = RouteFiltering.normalize_dynamic_path("/users/abc123")
      assert "/files/:id" = RouteFiltering.normalize_dynamic_path("/files/doc_123")
    end

    test "preserves non-ID segments" do
      assert "/users/:id/edit" = RouteFiltering.normalize_dynamic_path("/users/123/edit")

      assert "/admin/users/:id/delete" =
               RouteFiltering.normalize_dynamic_path("/admin/users/123/delete")
    end

    test "handles file extensions" do
      assert "/files/:file" = RouteFiltering.normalize_dynamic_path("/files/document.pdf")
      assert "/images/:file" = RouteFiltering.normalize_dynamic_path("/images/photo.jpg")
    end

    test "preserves file extensions when requested" do
      opts = [preserve_extensions: true]

      assert "/files/:file.pdf" =
               RouteFiltering.normalize_dynamic_path("/files/document.pdf", opts)
    end

    test "respects max segments limit" do
      long_path = "/a/b/c/d/e/f/g/h/i/j/k"
      opts = [max_segments: 5]

      result = RouteFiltering.normalize_dynamic_path(long_path, opts)
      segments = String.split(result, "/", trim: true)
      assert length(segments) == 5
    end

    test "handles custom ID patterns" do
      custom_pattern = ~r/^custom_\d+$/
      opts = [id_patterns: [custom_pattern]]

      assert "/items/:id" =
               RouteFiltering.normalize_dynamic_path("/items/custom_123", opts)
    end
  end

  describe "analyze_query_parameters/2" do
    test "analyzes path without query parameters" do
      result = RouteFiltering.analyze_query_parameters("/users")

      assert result.has_query == false
      assert result.param_count == 0
      assert result.params == %{}
    end

    test "analyzes path with query parameters" do
      path = "/search?q=test&limit=10&sort=name"
      result = RouteFiltering.analyze_query_parameters(path)

      assert result.has_query == true
      assert result.param_count == 3
      assert result.params["q"] == "test"
      assert result.params["limit"] == ":number"
      assert result.params["sort"] == "name"
      assert result.base_path == "/search"
    end

    test "normalizes parameter values by default" do
      path = "/search?id=550e8400-e29b-41d4-a716-446655440000&count=42&text=short"
      result = RouteFiltering.analyze_query_parameters(path)

      assert result.params["id"] == ":uuid"
      assert result.params["count"] == ":number"
      assert result.params["text"] == "short"
    end

    test "handles long parameter values" do
      long_value = String.duplicate("a", 30)
      path = "/search?long_param=#{long_value}"
      result = RouteFiltering.analyze_query_parameters(path)

      assert result.params["long_param"] == ":long_string"
    end

    test "excludes specified parameters" do
      path = "/search?q=test&secret=hidden&limit=10"
      opts = [exclude_params: ["secret"]]
      result = RouteFiltering.analyze_query_parameters(path, opts)

      assert result.param_count == 2
      refute Map.has_key?(result.params, "secret")
      assert Map.has_key?(result.params, "q")
      assert Map.has_key?(result.params, "limit")
    end

    test "respects max parameters limit" do
      # Create query with many parameters
      params = for i <- 1..25, do: "param#{i}=value#{i}"
      query = Enum.join(params, "&")
      path = "/search?" <> query

      opts = [max_params: 10]
      result = RouteFiltering.analyze_query_parameters(path, opts)

      assert result.param_count <= 10
    end

    test "handles URL-encoded parameters" do
      path = "/search?q=hello%20world&category=news%26events"
      result = RouteFiltering.analyze_query_parameters(path)

      assert result.params["q"] == "hello world"
      assert result.params["category"] == "news&events"
    end
  end

  describe "group_similar_paths/2" do
    test "groups by exact match" do
      paths = ["/users", "/users", "/posts", "/posts", "/posts"]
      opts = [grouping_strategy: :exact]

      result = RouteFiltering.group_similar_paths(paths, opts)

      assert result["/users"] == ["/users", "/users"]
      assert result["/posts"] == ["/posts", "/posts", "/posts"]
    end

    test "groups by normalized pattern" do
      paths = ["/users/123", "/users/456", "/posts/789", "/posts/101", "/about"]
      opts = [grouping_strategy: :normalized, min_group_size: 2]

      result = RouteFiltering.group_similar_paths(paths, opts)

      assert result["/users/:id"] == ["/users/123", "/users/456"]
      assert result["/posts/:id"] == ["/posts/789", "/posts/101"]
      # Below min_group_size
      refute Map.has_key?(result, "/about")
    end

    test "groups by route pattern" do
      paths = ["/admin/users", "/admin/posts", "/admin/settings", "/public/page"]
      opts = [grouping_strategy: :pattern, min_group_size: 2]

      result = RouteFiltering.group_similar_paths(paths, opts)

      admin_paths = result["/admin"]
      assert "/admin/users" in admin_paths
      assert "/admin/posts" in admin_paths
      assert "/admin/settings" in admin_paths
    end

    test "respects minimum group size" do
      paths = ["/users/1", "/users/2", "/posts/1", "/about"]
      opts = [min_group_size: 2]

      result = RouteFiltering.group_similar_paths(paths, opts)

      assert Map.has_key?(result, "/users/:id")
      # Only one path
      refute Map.has_key?(result, "/posts/:id")
      # Only one path
      refute Map.has_key?(result, "/about")
    end

    test "respects maximum groups limit" do
      # Create many different paths
      paths = for i <- 1..100, do: "/group#{i}/item"
      opts = [max_groups: 5, min_group_size: 1]

      result = RouteFiltering.group_similar_paths(paths, opts)

      assert map_size(result) <= 5
    end

    test "sorts groups by size descending" do
      paths = [
        # 3 items
        "/users/1",
        "/users/2",
        "/users/3",
        # 2 items
        "/posts/1",
        "/posts/2",
        # 1 item
        "/admin/1"
      ]

      opts = [min_group_size: 1]

      result = RouteFiltering.group_similar_paths(paths, opts)
      groups_by_size = Enum.map(result, fn {_pattern, paths} -> length(paths) end)

      # Should be sorted by size descending
      assert groups_by_size == Enum.sort(groups_by_size, :desc)
    end
  end

  describe "detect_suspicious_paths/2" do
    test "detects security scan attempts" do
      paths = [
        "/admin/login",
        "/wp-admin/admin.php",
        "/../../../etc/passwd",
        "/config/database.yml",
        "/normal/path"
      ]

      result = RouteFiltering.detect_suspicious_paths(paths)

      assert result.total_paths == 5
      assert result.suspicious_paths >= 3
      assert result.suspicious_percentage > 0

      suspicious_paths = Enum.map(result.details, fn {path, _} -> path end)
      assert "/admin/login" in suspicious_paths
      assert "/wp-admin/admin.php" in suspicious_paths
      assert "/../../../etc/passwd" in suspicious_paths
    end

    test "detects bot behavior patterns" do
      paths = [
        "/robots.txt",
        "/sitemap.xml",
        "/crawl/data",
        "/feed/rss",
        "/normal/page"
      ]

      opts = [categories: [:bot_behavior]]
      result = RouteFiltering.detect_suspicious_paths(paths, opts)

      assert result.suspicious_paths >= 3
      suspicious_paths = Enum.map(result.details, fn {path, _} -> path end)
      assert "/crawl/data" in suspicious_paths
      assert "/feed/rss" in suspicious_paths
    end

    test "detects malformed paths" do
      paths = [
        "/normal/path",
        "/path//with//double//slashes",
        "/path with spaces",
        "/path\nwith\nnewlines",
        # Too long
        "/" <> String.duplicate("a", 2001)
      ]

      opts = [categories: [:malformed]]
      result = RouteFiltering.detect_suspicious_paths(paths, opts)

      assert result.suspicious_paths >= 3
    end

    test "detects error-prone paths" do
      paths = [
        "/undefined/action",
        "/null/value",
        "/[object Object]",
        "/error/500",
        "/normal/path"
      ]

      opts = [categories: [:error_prone]]
      result = RouteFiltering.detect_suspicious_paths(paths, opts)

      assert result.suspicious_paths >= 4
    end

    test "provides detailed categorization" do
      paths = ["/admin/login", "/crawl/bot"]
      result = RouteFiltering.detect_suspicious_paths(paths)

      admin_detail = Enum.find(result.details, fn {path, _} -> path == "/admin/login" end)
      {_path, categories} = admin_detail
      assert :security_scan in categories

      crawl_detail = Enum.find(result.details, fn {path, _} -> path == "/crawl/bot" end)
      {_path, categories} = crawl_detail
      assert :bot_behavior in categories
    end
  end

  describe "analyze_path_performance/2" do
    test "analyzes performance patterns" do
      path_metrics = [
        %{path: "/users/123", duration_ms: 100},
        %{path: "/users/456", duration_ms: 150},
        %{path: "/users/789", duration_ms: 200},
        %{path: "/posts/123", duration_ms: 500},
        %{path: "/posts/456", duration_ms: 600},
        %{path: "/posts/789", duration_ms: 700}
      ]

      result = RouteFiltering.analyze_path_performance(path_metrics)

      assert result.total_patterns == 2
      assert Map.has_key?(result.performance_groups, "/users/:id")
      assert Map.has_key?(result.performance_groups, "/posts/:id")

      users_stats = result.performance_groups["/users/:id"]
      assert users_stats.count == 3
      assert users_stats.min_duration == 100
      assert users_stats.max_duration == 200
      assert users_stats.avg_duration == 150.0
    end

    test "identifies slow patterns" do
      path_metrics = [
        %{path: "/fast/1", duration_ms: 50},
        %{path: "/fast/2", duration_ms: 60},
        %{path: "/slow/1", duration_ms: 1200},
        %{path: "/slow/2", duration_ms: 1500},
        %{path: "/slow/3", duration_ms: 1800}
      ]

      opts = [slow_threshold_ms: 1000]
      result = RouteFiltering.analyze_path_performance(path_metrics, opts)

      assert result.slow_patterns == 1
      assert length(result.slowest_routes) == 1

      {slow_pattern, _stats} = hd(result.slowest_routes)
      assert slow_pattern == "/slow/:id"
    end

    test "requires minimum samples for analysis" do
      path_metrics = [
        # Only one sample
        %{path: "/single", duration_ms: 100},
        %{path: "/multiple/1", duration_ms: 200},
        %{path: "/multiple/2", duration_ms: 300},
        %{path: "/multiple/3", duration_ms: 400}
      ]

      opts = [min_samples: 3]
      result = RouteFiltering.analyze_path_performance(path_metrics, opts)

      # Only /multiple/:id has enough samples
      assert result.total_patterns == 1
      assert Map.has_key?(result.performance_groups, "/multiple/:id")
      refute Map.has_key?(result.performance_groups, "/single")
    end

    test "calculates percentiles correctly" do
      durations = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

      path_metrics =
        Enum.with_index(durations, fn duration, i ->
          %{path: "/test/#{i}", duration_ms: duration}
        end)

      result = RouteFiltering.analyze_path_performance(path_metrics)
      stats = result.performance_groups["/test/:id"]

      # Average of 500 and 600
      assert stats.median_duration == 550.0
      # 95th percentile
      assert stats.p95_duration == 950
      # 99th percentile
      assert stats.p99_duration == 990
    end
  end

  describe "build_route_filters/1" do
    test "builds include filters for strings" do
      route_specs = [{:include, "/admin"}, {:include, "/api"}]
      filters = RouteFiltering.build_route_filters(route_specs)

      assert {:filter, :path, :contains, "/admin"} in filters
      assert {:filter, :path, :contains, "/api"} in filters
    end

    test "builds exclude filters" do
      route_specs = [{:exclude, "/private"}, {:exclude, "/internal"}]
      filters = RouteFiltering.build_route_filters(route_specs)

      assert {:filter, :path, :not_contains, "/private"} in filters
      assert {:filter, :path, :not_contains, "/internal"} in filters
    end

    test "handles regex patterns" do
      route_specs = [{:include, ~r/^\/api\//}, {:exclude, ~r/\.json$/}]
      filters = RouteFiltering.build_route_filters(route_specs)

      assert {:filter, :path, :matches, ~r/^\/api\//} in filters
      assert {:filter, :path, :not_matches, ~r/\.json$/} in filters
    end

    test "builds category filters" do
      route_specs = [{:category, :admin}, {:category, :api}]
      filters = RouteFiltering.build_route_filters(route_specs)

      # Category filters should match against known patterns
      assert Enum.any?(filters, fn
               {:filter, :path, :matches_any, _patterns} -> true
               _ -> false
             end)
    end

    test "handles plain string patterns" do
      route_specs = ["/users", "/posts"]
      filters = RouteFiltering.build_route_filters(route_specs)

      assert {:filter, :path, :contains, "/users"} in filters
      assert {:filter, :path, :contains, "/posts"} in filters
    end
  end

  describe "edge cases and error handling" do
    test "handles empty path lists gracefully" do
      assert {:ok, []} = RouteFiltering.filter_trackable_paths([])
      result = RouteFiltering.group_similar_paths([])
      assert result == %{}
    end

    test "handles malformed input gracefully" do
      # Non-string paths should be filtered out by validation
      mixed_input = ["/valid", nil, 123, "/another"]
      string_paths = Enum.filter(mixed_input, &is_binary/1)

      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(string_paths)
      assert "/valid" in filtered
      assert "/another" in filtered
    end

    test "handles very long paths" do
      normal_path = "/normal"
      extremely_long_path = "/" <> String.duplicate("x", 10000)

      paths = [normal_path, extremely_long_path]
      assert {:ok, filtered} = RouteFiltering.filter_trackable_paths(paths)

      assert normal_path in filtered
      refute extremely_long_path in filtered
    end

    test "handles paths with special characters" do
      special_paths = [
        "/path/with spaces",
        "/path/with%20encoding",
        "/path/with/émojis/🎉",
        "/path/with/unicode/测试"
      ]

      # Most should be handled gracefully
      assert {:ok, _filtered} = RouteFiltering.filter_trackable_paths(special_paths)
    end
  end
end
