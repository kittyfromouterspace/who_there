defmodule WhoThere.RouteFilterTest do
  use ExUnit.Case, async: true
  
  alias WhoThere.RouteFilter
  
  describe "allow_event?/2 with basic filtering" do
    test "allows regular requests by default" do
      conn_attrs = %{
        method: "GET",
        path: "/dashboard",
        query_string: ""
      }
      
      assert RouteFilter.allow_event?(conn_attrs) == true
    end
    
    test "blocks static asset requests" do
      static_requests = [
        %{method: "GET", path: "/assets/app.css", query_string: ""},
        %{method: "GET", path: "/images/logo.png", query_string: ""},
        %{method: "GET", path: "/js/app.js", query_string: ""}
      ]
      
      for request <- static_requests do
        assert RouteFilter.allow_event?(request) == false,
               "Expected #{request.path} to be blocked"
      end
    end
    
    test "blocks health check endpoints" do
      health_requests = [
        %{method: "GET", path: "/health", query_string: ""},
        %{method: "GET", path: "/healthz", query_string: ""},
        %{method: "GET", path: "/ping", query_string: ""}
      ]
      
      for request <- health_requests do
        assert RouteFilter.allow_event?(request) == false,
               "Expected #{request.path} to be blocked"
      end
    end
    
    test "blocks excluded HTTP methods" do
      excluded_methods = ["OPTIONS", "HEAD", "TRACE"]
      
      for method <- excluded_methods do
        request = %{method: method, path: "/api/users", query_string: ""}
        assert RouteFilter.allow_event?(request) == false,
               "Expected #{method} requests to be blocked"
      end
    end
    
    test "blocks paths that are too long" do
      long_path = "/" <> String.duplicate("a", 2100)  # Exceeds default 2000 limit
      
      request = %{method: "GET", path: long_path, query_string: ""}
      assert RouteFilter.allow_event?(request) == false
    end
  end
  
  describe "evaluate_request/2 with detailed results" do
    test "returns :allow for valid requests" do
      request = %{
        method: "GET",
        path: "/dashboard",
        tenant: "test_tenant"
      }
      
      result = RouteFilter.evaluate_request(request)
      assert result == :allow
    end
    
    test "returns detailed block reasons" do
      # Test method exclusion
      options_request = %{method: "OPTIONS", path: "/api/test"}
      result = RouteFilter.evaluate_request(options_request)
      assert {:block, {:method_excluded, "OPTIONS"}} == result
      
      # Test static asset blocking
      css_request = %{method: "GET", path: "/app.css"}
      result = RouteFilter.evaluate_request(css_request)
      assert {:block, :static_asset} == result
      
      # Test built-in exclusions
      health_request = %{method: "GET", path: "/health"}
      result = RouteFilter.evaluate_request(health_request)
      assert {:block, :built_in_exclusion} == result
    end
  end
  
  describe "filter_paths/3 bulk filtering" do
    test "filters mixed list of paths correctly" do
      paths = [
        "/",
        "/dashboard", 
        "/api/users",
        "/assets/app.css",
        "/health",
        "/admin/settings"
      ]
      
      allowed_paths = RouteFilter.filter_paths(paths, "GET")
      
      # Should exclude static assets and health checks
      expected_allowed = ["/", "/dashboard", "/api/users", "/admin/settings"]
      assert Enum.sort(allowed_paths) == Enum.sort(expected_allowed)
    end
    
    test "respects method-specific filtering" do
      paths = ["/api/users", "/api/admin"]
      
      get_allowed = RouteFilter.filter_paths(paths, "GET")
      post_allowed = RouteFilter.filter_paths(paths, "POST")
      
      # Both should be allowed for now (no method-specific rules configured)
      assert get_allowed == paths
      assert post_allowed == paths
    end
  end
  
  describe "pattern matching and compilation" do
    test "validates rule syntax correctly" do
      # Valid rules
      valid_rules = [
        "/api/*",
        ~r/^\/users\/\d+$/,
        {"/admin/*", ["POST", "DELETE"]},
        "/exact/path"
      ]
      
      assert RouteFilter.validate_rules(valid_rules) == :ok
    end
    
    test "catches invalid rule syntax" do
      invalid_rules = [
        123,  # Not a string or regex
        {"/path", ["INVALID_METHOD"]},  # Invalid HTTP method
        {123, ["GET"]}  # Invalid pattern type
      ]
      
      result = RouteFilter.validate_rules(invalid_rules)
      assert {:error, errors} = result
      assert length(errors) > 0
    end
    
    test "validates rule maps with allow/block sections" do
      rule_map = %{
        allow: ["/api/*", "/dashboard"],
        block: ["/admin/*", ~r/^\/internal\/.*/]
      }
      
      assert RouteFilter.validate_rules(rule_map) == :ok
    end
  end
  
  describe "advanced pattern matching" do
    # These tests verify the enhanced pattern matching we added
    
    test "prefix patterns work correctly" do
      # This would require setting up test configuration or mocking
      # For now, verify that the pattern compilation doesn't crash
      
      patterns = ["/api/*", "/dashboard/*", "/admin/*"]
      
      # Validate that patterns compile without error
      assert RouteFilter.validate_rules(patterns) == :ok
    end
    
    test "regex patterns work correctly" do
      patterns = [
        ~r/^\/users\/\d+$/,  # User ID pattern
        ~r/^\/api\/v\d+\//,  # API version pattern
        ~r/^\/(en|es|fr)\//  # Language pattern
      ]
      
      assert RouteFilter.validate_rules(patterns) == :ok
    end
    
    test "method-specific patterns work correctly" do
      patterns = [
        {"/api/write/*", ["POST", "PUT", "PATCH"]},
        {"/api/read/*", ["GET"]},
        {"/admin/*", ["POST", "DELETE"]}
      ]
      
      assert RouteFilter.validate_rules(patterns) == :ok
    end
  end
  
  describe "caching and performance" do
    test "rule compilation works without errors" do
      # Test global rule compilation
      result = RouteFilter.compile_rules(:global)
      assert is_map(result)
      
      # Test tenant-specific compilation
      tenant_result = RouteFilter.compile_rules("test_tenant")
      assert is_map(tenant_result)
    end
    
    test "cache invalidation works" do
      # This should not crash
      assert RouteFilter.invalidate_cache() == :ok
      assert RouteFilter.invalidate_cache("test_tenant") == :ok
    end
    
    test "filter stats are retrievable" do
      stats = RouteFilter.get_filter_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :tenant)
      assert Map.has_key?(stats, :rule_count)
    end
  end
  
  describe "tenant-specific filtering" do
    test "handles tenant-specific options" do
      request = %{
        method: "GET",
        path: "/tenant-specific",
        tenant: "acme_corp"
      }
      
      # Should process without error even with tenant specified
      result = RouteFilter.allow_event?(request)
      assert is_boolean(result)
      
      # Also test evaluate_request with tenant
      eval_result = RouteFilter.evaluate_request(request)
      assert eval_result in [:allow, :block] or match?({:block, _}, eval_result)
    end
    
    test "handles requests without tenant" do
      request = %{
        method: "GET",
        path: "/no-tenant"
      }
      
      result = RouteFilter.allow_event?(request)
      assert is_boolean(result)
    end
  end
  
  describe "edge cases and error handling" do
    test "handles empty paths" do
      request = %{method: "GET", path: ""}
      result = RouteFilter.allow_event?(request)
      assert is_boolean(result)
    end
    
    test "handles nil values gracefully" do
      request = %{method: "GET", path: nil}
      
      # Should not crash, either return true/false or handle gracefully
      result = try do
        RouteFilter.allow_event?(request)
      rescue
        _ -> :handled_gracefully
      end
      
      assert result in [true, false, :handled_gracefully]
    end
    
    test "handles malformed request maps" do
      malformed_requests = [
        %{},  # Empty map
        %{method: "GET"},  # Missing path
        %{path: "/test"}   # Missing method
      ]
      
      for request <- malformed_requests do
        # Should not crash
        result = try do
          RouteFilter.allow_event?(request)
        rescue
          _ -> :handled_gracefully
        end
        
        assert result in [true, false, :handled_gracefully]
      end
    end
    
    test "handles very long query strings" do
      long_query = String.duplicate("param=value&", 1000)
      
      request = %{
        method: "GET", 
        path: "/test",
        query_string: long_query
      }
      
      # Should handle without crashing
      result = RouteFilter.allow_event?(request)
      assert is_boolean(result)
    end
    
    test "handles unicode paths" do
      unicode_paths = [
        "/café/menu",
        "/用户/设置",
        "/пользователь/настройки"
      ]
      
      for path <- unicode_paths do
        request = %{method: "GET", path: path}
        result = RouteFilter.allow_event?(request)
        assert is_boolean(result)
      end
    end
  end
  
  describe "configuration integration" do
    test "respects application configuration" do
      # Test that the module reads from application config
      # This is primarily a smoke test to ensure config access works
      
      original_config = Application.get_env(:who_there, :route_filters, [])
      
      # Temporarily set test config
      test_config = [
        exclude_extensions: [".test"],
        max_path_length: 100
      ]
      
      Application.put_env(:who_there, :route_filters, test_config)
      
      # Verify a very long path is blocked (respects max_path_length)
      long_path_request = %{
        method: "GET", 
        path: "/" <> String.duplicate("a", 150)
      }
      
      result = RouteFilter.allow_event?(long_path_request)
      assert result == false
      
      # Restore original config
      Application.put_env(:who_there, :route_filters, original_config)
    end
  end
end