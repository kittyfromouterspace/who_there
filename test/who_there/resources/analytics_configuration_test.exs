defmodule WhoThere.Resources.AnalyticsConfigurationTest do
  use ExUnit.Case, async: true

  import Ash.Expr

  alias WhoThere.Resources.AnalyticsConfiguration

  setup do
    tenant_id = Ash.UUID.generate()
    {:ok, tenant_id: tenant_id}
  end

  describe "creation" do
    test "creates configuration with valid attributes", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        enabled: true,
        collect_user_agents: true,
        anonymize_ips: true
      }

      assert {:ok, config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)
      assert config.tenant_id == tenant_id
      assert config.enabled == true
      assert config.anonymize_ips == true
    end

    test "creates with default values", %{tenant_id: tenant_id} do
      attrs = %{tenant_id: tenant_id}

      assert {:ok, config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)
      assert config.enabled == true
      assert config.anonymize_ips == true
      assert config.collect_user_agents == true
      assert config.session_timeout_minutes == 30
      assert config.data_retention_days == 365
    end

    test "validates tenant_id is required" do
      attrs = %{enabled: true}

      assert {:error, %Ash.Error.Invalid{} = error} = AnalyticsConfiguration.create(attrs)
      assert error.errors |> Enum.any?(fn e -> e.field == :tenant_id end)
    end

    test "validates session timeout range", %{tenant_id: tenant_id} do
      # Test minimum boundary
      attrs = %{tenant_id: tenant_id, session_timeout_minutes: 0}

      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Test maximum boundary
      attrs = %{tenant_id: tenant_id, session_timeout_minutes: 1441}

      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Test valid range
      attrs = %{tenant_id: tenant_id, session_timeout_minutes: 60}
      assert {:ok, _config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)
    end

    test "validates data retention range", %{tenant_id: tenant_id} do
      # Test minimum boundary
      attrs = %{tenant_id: tenant_id, data_retention_days: 0}

      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Test maximum boundary
      attrs = %{tenant_id: tenant_id, data_retention_days: 3651}

      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Test valid range
      attrs = %{tenant_id: tenant_id, data_retention_days: 90}
      assert {:ok, _config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)
    end

    test "validates exclude patterns", %{tenant_id: tenant_id} do
      # Valid patterns
      valid_patterns = ["/admin/*", "/api/internal/*", "/health"]
      attrs = %{tenant_id: tenant_id, exclude_patterns: valid_patterns}
      assert {:ok, _config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Invalid patterns (not starting with /)
      invalid_patterns = ["admin/*", "api/internal/*"]
      attrs = %{tenant_id: tenant_id, exclude_patterns: invalid_patterns}

      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)
    end
  end

  describe "reading" do
    test "reads configuration by tenant", %{tenant_id: tenant_id} do
      attrs = %{tenant_id: tenant_id, enabled: false}
      assert {:ok, created} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      assert {:ok, [found]} = AnalyticsConfiguration.by_tenant(tenant_id, tenant: tenant_id)
      assert found.id == created.id
      assert found.enabled == false
    end

    test "tenant isolation works correctly" do
      tenant1 = Ash.UUID.generate()
      tenant2 = Ash.UUID.generate()

      # Create config for tenant1
      attrs1 = %{tenant_id: tenant1, enabled: true}
      assert {:ok, _config1} = AnalyticsConfiguration.create(attrs1, tenant: tenant1)

      # Create config for tenant2
      attrs2 = %{tenant_id: tenant2, enabled: false}
      assert {:ok, _config2} = AnalyticsConfiguration.create(attrs2, tenant: tenant2)

      # Tenant1 should only see their config
      assert {:ok, [config]} = AnalyticsConfiguration.by_tenant(tenant1, tenant: tenant1)
      assert config.enabled == true

      # Tenant2 should only see their config
      assert {:ok, [config]} = AnalyticsConfiguration.by_tenant(tenant2, tenant: tenant2)
      assert config.enabled == false
    end
  end

  describe "updating" do
    test "updates configuration successfully", %{tenant_id: tenant_id} do
      attrs = %{tenant_id: tenant_id, enabled: true}
      assert {:ok, config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      update_attrs = %{enabled: false, anonymize_ips: false}

      assert {:ok, updated} =
               AnalyticsConfiguration.update(config, update_attrs, tenant: tenant_id)

      assert updated.enabled == false
      assert updated.anonymize_ips == false
    end

    test "bulk update works correctly", %{tenant_id: tenant_id} do
      attrs = %{tenant_id: tenant_id}
      assert {:ok, config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      bulk_attrs = %{
        enabled: false,
        bot_detection_enabled: false,
        dashboard_enabled: false
      }

      assert {:ok, updated} =
               AnalyticsConfiguration.bulk_update(config, bulk_attrs, tenant: tenant_id)

      assert updated.enabled == false
      assert updated.bot_detection_enabled == false
      assert updated.dashboard_enabled == false
    end
  end

  describe "calculations" do
    test "calculates privacy score correctly", %{tenant_id: tenant_id} do
      # High privacy configuration
      high_privacy_attrs = %{
        tenant_id: tenant_id,
        anonymize_ips: true,
        collect_user_agents: false,
        collect_referrers: false,
        collect_geolocation: false,
        data_retention_days: 30
      }

      assert {:ok, config} = AnalyticsConfiguration.create(high_privacy_attrs, tenant: tenant_id)

      assert {:ok, [config_with_calc]} =
               AnalyticsConfiguration
               |> Ash.Query.load(:privacy_score)
               |> Ash.Query.filter(expr(id == ^config.id))
               |> AnalyticsConfiguration.read(tenant: tenant_id)

      # Should get maximum privacy score
      assert config_with_calc.privacy_score == 100
    end

    test "calculates compliance level correctly", %{tenant_id: tenant_id} do
      # Strict compliance
      strict_attrs = %{
        tenant_id: tenant_id,
        anonymize_ips: true,
        collect_user_agents: false,
        data_retention_days: 30
      }

      assert {:ok, config} = AnalyticsConfiguration.create(strict_attrs, tenant: tenant_id)

      assert {:ok, [config_with_calc]} =
               AnalyticsConfiguration
               |> Ash.Query.load(:compliance_level)
               |> Ash.Query.filter(expr(id == ^config.id))
               |> AnalyticsConfiguration.read(tenant: tenant_id)

      assert config_with_calc.compliance_level == "Strict"
    end

    test "calculates feature summary correctly", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        enabled: true,
        bot_detection_enabled: true,
        dashboard_enabled: true
      }

      assert {:ok, config} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      assert {:ok, [config_with_calc]} =
               AnalyticsConfiguration
               |> Ash.Query.load(:feature_summary)
               |> Ash.Query.filter(expr(id == ^config.id))
               |> AnalyticsConfiguration.read(tenant: tenant_id)

      summary = config_with_calc.feature_summary
      assert summary.analytics_enabled == true
      assert summary.bot_detection == true
      assert summary.dashboard_access == true
      assert is_map(summary.privacy_features)
    end
  end

  describe "validations" do
    test "validates exclude patterns format" do
      # Test the private validation function indirectly
      valid_config = %{
        tenant_id: Ash.UUID.generate(),
        exclude_patterns: ["/admin/*", "/api/*"]
      }

      assert {:ok, _} =
               AnalyticsConfiguration.create(valid_config, tenant: valid_config.tenant_id)

      invalid_config = %{
        tenant_id: Ash.UUID.generate(),
        exclude_patterns: ["admin", "no-slash-prefix"]
      }

      assert {:error, _} =
               AnalyticsConfiguration.create(invalid_config, tenant: invalid_config.tenant_id)
    end
  end

  describe "identity constraints" do
    test "enforces unique configuration per tenant", %{tenant_id: tenant_id} do
      attrs = %{tenant_id: tenant_id}

      # First creation should succeed
      assert {:ok, _config1} = AnalyticsConfiguration.create(attrs, tenant: tenant_id)

      # Second creation with same tenant should fail
      assert {:error, %Ash.Error.Invalid{}} =
               AnalyticsConfiguration.create(attrs, tenant: tenant_id)
    end
  end
end
