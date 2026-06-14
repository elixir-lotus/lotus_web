defmodule Lotus.Web.SourcesMapTest do
  use Lotus.Web.Case, async: true

  alias Lotus.Web.SourcesMap
  alias Lotus.Web.SourcesMap.{Database, Schema}

  defp public_tables(sources_map) do
    sources_map
    |> SourcesMap.get_database("public")
    |> Map.fetch!(:schemas)
    |> Enum.find(&(&1.name == "public"))
    |> Map.fetch!(:tables)
  end

  describe "build/1 with :include_views" do
    test "excludes views by default" do
      tables = public_tables(SourcesMap.build())

      assert "test_users" in tables
      refute "active_test_users" in tables
    end

    test "includes views when include_views: true" do
      tables = public_tables(SourcesMap.build(include_views: true))

      assert "test_users" in tables
      assert "active_test_users" in tables
    end
  end

  describe "build/0" do
    test "builds complete sources map with all configured databases" do
      sources_map = SourcesMap.build()

      assert %SourcesMap{databases: databases} = sources_map
      assert length(databases) == 2

      public_db = Enum.find(databases, &(&1.name == "public"))

      assert %Database{
               name: "public",
               source_type: :postgres,
               supports_schemas: true,
               schemas: public_schemas
             } = public_db

      reporting_db = Enum.find(databases, &(&1.name == "reporting"))

      assert %Database{
               name: "reporting",
               source_type: :postgres,
               supports_schemas: true,
               schemas: reporting_schemas
             } = reporting_db

      public_schema = Enum.find(public_schemas, &(&1.name == "public"))

      assert %Schema{
               name: "public",
               is_default: true,
               display_name: "public",
               tables: public_tables
             } = public_schema

      assert "test_users" in public_tables
      assert "test_posts" in public_tables

      reporting_schema = Enum.find(reporting_schemas, &(&1.name == "reporting"))

      assert %Schema{
               name: "reporting",
               is_default: false,
               display_name: "reporting",
               tables: reporting_tables
             } = reporting_schema

      assert "customers" in reporting_tables
      assert "orders" in reporting_tables
    end
  end

  describe "get_database/2" do
    test "returns database by name when it exists" do
      sources_map = SourcesMap.build()

      database = SourcesMap.get_database(sources_map, "public")
      assert %Database{name: "public"} = database

      database = SourcesMap.get_database(sources_map, "reporting")
      assert %Database{name: "reporting"} = database
    end

    test "returns nil when database does not exist" do
      sources_map = SourcesMap.build()

      database = SourcesMap.get_database(sources_map, "nonexistent")
      assert database == nil
    end

    test "returns nil when database name is nil" do
      sources_map = SourcesMap.build()

      database = SourcesMap.get_database(sources_map, nil)
      assert database == nil
    end

    test "returns nil when database name is empty string" do
      sources_map = SourcesMap.build()

      database = SourcesMap.get_database(sources_map, "")
      assert database == nil
    end
  end

  describe "get_tables_for_database/2" do
    test "returns all tables for a database across all schemas" do
      sources_map = SourcesMap.build()

      public_tables = SourcesMap.get_tables_for_database(sources_map, "public")
      assert "test_users" in public_tables
      assert "test_posts" in public_tables

      reporting_tables = SourcesMap.get_tables_for_database(sources_map, "reporting")
      assert "customers" in reporting_tables
      assert "orders" in reporting_tables
    end

    test "returns empty list when database does not exist" do
      sources_map = SourcesMap.build()

      tables = SourcesMap.get_tables_for_database(sources_map, "nonexistent")
      assert tables == []
    end

    test "returns empty list when database name is nil" do
      sources_map = SourcesMap.build()

      tables = SourcesMap.get_tables_for_database(sources_map, nil)
      assert tables == []
    end
  end

  describe "schema and table counting" do
    test "get_schema_count/1 returns correct schema count for PostgreSQL databases" do
      sources_map = SourcesMap.build()
      public_db = SourcesMap.get_database(sources_map, "public")
      reporting_db = SourcesMap.get_database(sources_map, "reporting")

      assert SourcesMap.get_schema_count(public_db) >= 1
      assert SourcesMap.get_schema_count(reporting_db) >= 1
    end

    test "get_table_count/1 returns correct total table count across all schemas" do
      sources_map = SourcesMap.build()
      public_db = SourcesMap.get_database(sources_map, "public")
      reporting_db = SourcesMap.get_database(sources_map, "reporting")

      # Public database has test_users and test_posts
      assert SourcesMap.get_table_count(public_db) >= 2

      # Reporting database has customers and orders
      assert SourcesMap.get_table_count(reporting_db) >= 2
    end

    test "get_schema_count/1 returns 0 for non-PostgreSQL databases" do
      # Create a mock MySQL-style database
      mysql_db = %Database{
        name: "mysql_test",
        source_type: :mysql,
        supports_schemas: false,
        schemas: [
          %Schema{
            name: "default",
            is_default: false,
            display_name: "Tables",
            tables: ["users", "posts"]
          }
        ]
      }

      assert SourcesMap.get_schema_count(mysql_db) == 0
    end

    test "handles empty databases gracefully" do
      empty_db = %Database{
        name: "empty",
        source_type: :postgres,
        supports_schemas: true,
        schemas: []
      }

      assert SourcesMap.get_schema_count(empty_db) == 0
      assert SourcesMap.get_table_count(empty_db) == 0
    end
  end

  describe "data structure integrity" do
    test "all databases have required fields populated" do
      sources_map = SourcesMap.build()

      Enum.each(sources_map.databases, fn database ->
        assert database.name != nil
        assert database.source_type != nil
        assert is_boolean(database.supports_schemas)
        assert is_list(database.schemas)
      end)
    end

    test "all schemas have required fields populated" do
      sources_map = SourcesMap.build()

      Enum.each(sources_map.databases, fn database ->
        Enum.each(database.schemas, fn schema ->
          assert schema.name != nil
          assert is_boolean(schema.is_default)
          assert schema.display_name != nil
          assert is_list(schema.tables)
        end)
      end)
    end

    test "tables are sorted alphabetically within each schema" do
      sources_map = SourcesMap.build()

      Enum.each(sources_map.databases, fn database ->
        Enum.each(database.schemas, fn schema ->
          sorted_tables = Enum.sort(schema.tables)
          assert schema.tables == sorted_tables
        end)
      end)
    end
  end
end
