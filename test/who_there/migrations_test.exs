defmodule WhoThere.MigrationsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias WhoThere.Repo

  describe "migration up/down" do
    @tag :migration
    test "migration up creates all tables and indexes" do
      # Check that tables exist after migration
      tables = get_tables()

      assert "analytics_configurations" in tables
      assert "analytics_events" in tables
      assert "analytics_sessions" in tables
      assert "daily_analytics" in tables
    end

    @tag :migration
    test "migration creates proper indexes" do
      indexes = get_indexes()

      # Check some key indexes exist
      assert has_index?(
               indexes,
               "analytics_configurations",
               "analytics_configurations_tenant_id_index"
             )

      assert has_index?(indexes, "analytics_events", "analytics_events_tenant_id_timestamp_index")

      assert has_index?(
               indexes,
               "analytics_sessions",
               "analytics_sessions_tenant_id_session_fingerprint_index"
             )

      assert has_index?(indexes, "daily_analytics", "daily_analytics_tenant_id_date_index")
    end

    @tag :migration
    test "migration creates proper constraints" do
      constraints = get_constraints()

      # Check some key constraints exist
      assert has_constraint?(constraints, "analytics_events", "valid_event_type")
      assert has_constraint?(constraints, "analytics_events", "valid_country_code")
      assert has_constraint?(constraints, "analytics_events", "valid_path")
      assert has_constraint?(constraints, "analytics_configurations", "valid_session_timeout")
    end

    @tag :migration
    test "tables have correct primary keys" do
      # All tables should use binary_id primary keys
      primary_keys = get_primary_keys()

      assert primary_keys["analytics_configurations"] == "id"
      assert primary_keys["analytics_events"] == "id"
      assert primary_keys["analytics_sessions"] == "id"
      assert primary_keys["daily_analytics"] == "id"
    end
  end

  # Helper functions to query database metadata
  defp get_tables do
    {:ok, result} =
      SQL.query(
        Repo,
        """
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
          AND table_name LIKE 'analytics_%' OR table_name LIKE 'daily_%'
        """,
        []
      )

    result.rows |> Enum.map(&List.first/1)
  end

  defp get_indexes do
    {:ok, result} =
      SQL.query(
        Repo,
        """
          SELECT schemaname, tablename, indexname
          FROM pg_indexes
          WHERE schemaname = 'public'
          AND (tablename LIKE 'analytics_%' OR tablename LIKE 'daily_%')
        """,
        []
      )

    result.rows
  end

  defp get_constraints do
    {:ok, result} =
      SQL.query(
        Repo,
        """
          SELECT table_name, constraint_name, constraint_type
          FROM information_schema.table_constraints
          WHERE table_schema = 'public'
          AND (table_name LIKE 'analytics_%' OR table_name LIKE 'daily_%')
          AND constraint_type IN ('CHECK', 'FOREIGN KEY', 'UNIQUE')
        """,
        []
      )

    result.rows
  end

  defp get_primary_keys do
    {:ok, result} =
      SQL.query(
        Repo,
        """
          SELECT t.table_name, k.column_name
          FROM information_schema.table_constraints t
          JOIN information_schema.key_column_usage k
          ON t.constraint_name = k.constraint_name
          WHERE t.constraint_type = 'PRIMARY KEY'
          AND t.table_schema = 'public'
          AND (t.table_name LIKE 'analytics_%' OR t.table_name LIKE 'daily_%')
        """,
        []
      )

    result.rows |> Enum.into(%{}, fn [table, column] -> {table, column} end)
  end

  defp has_index?(indexes, table_name, index_name) do
    Enum.any?(indexes, fn [_schema, table, index] ->
      table == table_name and index == index_name
    end)
  end

  defp has_constraint?(constraints, table_name, constraint_name) do
    Enum.any?(constraints, fn [table, constraint, _type] ->
      table == table_name and constraint == constraint_name
    end)
  end
end
