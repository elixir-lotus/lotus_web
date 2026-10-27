defmodule Lotus.Web.SchemaBuilderTest do
  use Lotus.Web.Case, async: true

  alias Lotus.Web.SchemaBuilder
  alias Lotus.Web.SourcesMap

  setup do
    sources_map = SourcesMap.build()
    {:ok, sources_map: sources_map}
  end

  describe "build/3 with SourcesMap" do
    test "returns schema for public schema tables", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")

      {:ok, schema} = SchemaBuilder.columns(sources_map, "public", nil, Map.keys(schema))

      assert "name" in schema["test_users"]
      assert "email" in schema["test_users"]
      assert "age" in schema["test_users"]
      assert "active" in schema["test_users"]
      assert "metadata" in schema["test_users"]
      assert "inserted_at" in schema["test_users"]
      assert "updated_at" in schema["test_users"]

      assert "title" in schema["test_posts"]
      assert "content" in schema["test_posts"]
      assert "user_id" in schema["test_posts"]
      assert "published" in schema["test_posts"]
      assert "view_count" in schema["test_posts"]
      assert "tags" in schema["test_posts"]
    end

    test "returns schema for reporting schema tables", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "reporting", "reporting")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "customers")
      assert Map.has_key?(schema, "orders")

      {:ok, schema} =
        SchemaBuilder.columns(sources_map, "reporting", "reporting", Map.keys(schema))

      assert "name" in schema["customers"]
      assert "email" in schema["customers"]
      assert "active" in schema["customers"]

      assert "order_number" in schema["orders"]
      assert "customer_id" in schema["orders"]
      assert "total_amount" in schema["orders"]
      assert "status" in schema["orders"]
    end

    test "returns all columns including id and timestamps", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public")

      assert {:ok, schema} = result
      {:ok, schema} = SchemaBuilder.columns(sources_map, "public", nil, Map.keys(schema))

      assert "id" in schema["test_users"]
      assert "id" in schema["test_posts"]

      assert "inserted_at" in schema["test_users"]
      assert "updated_at" in schema["test_users"]
      assert "inserted_at" in schema["test_posts"]
      assert "updated_at" in schema["test_posts"]
    end

    test "schema contains only allowed tables based on visibility rules", %{
      sources_map: sources_map
    } do
      result = SchemaBuilder.build(sources_map, "public")

      assert {:ok, schema} = result

      refute Map.has_key?(schema, "schema_migrations")
      refute Map.has_key?(schema, "lotus_queries")

      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")
    end

    test "returns error for non-existent database", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "nonexistent")
      assert {:error, :database_not_found} = result
    end

    test "handles nil database name", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, nil)
      assert {:error, :database_not_found} = result
    end
  end

  describe "search_path functionality" do
    test "uses default schema when no search_path provided", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public", nil)

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")
      # Tables should not be schema-qualified for single schema
      refute Map.has_key?(schema, "public.test_users")
    end

    test "uses specified search_path for single schema", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "reporting", "reporting")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "customers")
      assert Map.has_key?(schema, "orders")
      # Tables should not be schema-qualified for single schema
      refute Map.has_key?(schema, "reporting.customers")
    end

    test "ignores empty search_path", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public", "")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")
    end

    test "filters schemas based on search_path", %{sources_map: sources_map} do
      # For reporting database, only get reporting schema tables
      result = SchemaBuilder.build(sources_map, "reporting", "reporting")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "customers")
      assert Map.has_key?(schema, "orders")

      # Should not include tables from other schemas
      refute Map.has_key?(schema, "test_users")
      refute Map.has_key?(schema, "test_posts")
    end
  end

  describe "multi-schema support" do
    test "handles multiple schemas in search_path with comma separation", %{
      sources_map: sources_map
    } do
      # With multiple schemas in search_path, table names should be qualified
      result = SchemaBuilder.build(sources_map, "public", "public,information_schema")

      assert {:ok, schema} = result
      # Tables should be qualified when multiple schemas are specified
      assert Map.has_key?(schema, "public.test_users")
      assert Map.has_key?(schema, "public.test_posts")
      # Unqualified names should not exist
      refute Map.has_key?(schema, "test_users")
      refute Map.has_key?(schema, "test_posts")
    end
  end

  describe "table qualification behavior" do
    test "does not qualify table names for single schema", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public", "public")

      assert {:ok, schema} = result

      # With single schema, tables should not be qualified
      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")
      refute Map.has_key?(schema, "public.test_users")
      refute Map.has_key?(schema, "public.test_posts")
    end

    test "gives the tables without their columns", %{sources_map: sources_map} do
      result = SchemaBuilder.build(sources_map, "public")

      assert {:ok, schema} = result
      assert map_size(schema) > 0

      Enum.each(schema, fn {_table_name, columns} ->
        assert columns == nil
      end)
    end
  end

  describe "database adapter handling" do
    test "works with PostgreSQL databases (supports_schemas=true)", %{sources_map: sources_map} do
      # Both our test databases are PostgreSQL
      result_public = SchemaBuilder.build(sources_map, "public")
      result_reporting = SchemaBuilder.build(sources_map, "reporting")

      assert {:ok, _schema_public} = result_public
      assert {:ok, _schema_reporting} = result_reporting
    end

    test "handles schema selection for PostgreSQL correctly", %{sources_map: sources_map} do
      # PostgreSQL should default to "public" schema when no search_path provided
      result = SchemaBuilder.build(sources_map, "public")

      assert {:ok, schema} = result
      assert Map.has_key?(schema, "test_users")
      assert Map.has_key?(schema, "test_posts")
    end
  end

  describe "edge cases" do
    test "handles empty sources_map gracefully" do
      empty_sources_map = %SourcesMap{databases: []}
      result = SchemaBuilder.build(empty_sources_map, "public")

      assert {:error, :database_not_found} = result
    end

    test "handles database with no schemas", %{sources_map: sources_map} do
      # Create a sources map with a database that has no schemas
      db_with_no_schemas = %SourcesMap.Database{
        name: "empty_db",
        source_type: :postgres,
        supports_schemas: true,
        schemas: []
      }

      sources_map_with_empty = %SourcesMap{
        databases: sources_map.databases ++ [db_with_no_schemas]
      }

      result = SchemaBuilder.build(sources_map_with_empty, "empty_db")

      assert {:ok, schema} = result
      assert schema == %{}
    end
  end

  describe "describe/5" do
    test "describes the tables asked for, each column with its type", %{sources_map: sources_map} do
      assert {:ok, %{"test_posts" => columns}} =
               SchemaBuilder.describe(sources_map, "public", nil, ["test_posts"])

      assert %{name: "user_id", type: type} = Enum.find(columns, &(&1.name == "user_id"))
      assert is_binary(type)
    end
  end

  describe "columns/5" do
    test "describes the tables asked for", %{sources_map: sources_map} do
      assert {:ok, columns} = SchemaBuilder.columns(sources_map, "public", nil, ["test_posts"])
      assert Map.keys(columns) == ["test_posts"]
      assert "user_id" in columns["test_posts"]
    end

    test "names a table as build/4 does, qualified for several schemas", %{
      sources_map: sources_map
    } do
      assert {:ok, %{"public.test_users" => columns}} =
               SchemaBuilder.columns(sources_map, "public", "public,information_schema", [
                 "public.test_users"
               ])

      assert "email" in columns
    end

    test "leaves out a table the editor does not have", %{sources_map: sources_map} do
      assert {:ok, %{}} =
               SchemaBuilder.columns(sources_map, "public", nil, ["nowhere", "public.test_users"])
    end

    test "describes a few tables at a time" do
      keys = for i <- 1..20, do: "t#{i}"

      database = %SourcesMap.Database{
        name: "public",
        source_type: :postgres,
        supports_schemas: true,
        schemas: [%SourcesMap.Schema{name: "public", tables: keys, is_default: true}]
      }

      sources_map = %SourcesMap{databases: [database]}

      assert {:ok, columns} = SchemaBuilder.columns(sources_map, "public", "public", keys)
      assert map_size(columns) == SchemaBuilder.max_tables()
    end

    test "errs for a source it does not know", %{sources_map: sources_map} do
      assert {:error, :database_not_found} =
               SchemaBuilder.columns(sources_map, "nope", nil, ["a"])
    end
  end
end
