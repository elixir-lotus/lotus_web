defmodule Lotus.Web.SchemaDiagramTest do
  use Lotus.Web.Case, async: true

  alias Hakushi.Graph
  alias Lotus.Web.SchemaDiagram
  alias Lotus.Web.SourcesMap
  alias Lotus.Web.SourcesMap.{Database, Schema}

  defp col(name, type, opts \\ []) do
    %{
      name: name,
      type: type,
      nullable: true,
      default: nil,
      primary_key: Keyword.get(opts, :pk, false)
    }
    |> then(&if Keyword.has_key?(opts, :ref), do: Map.put(&1, :references, opts[:ref]), else: &1)
  end

  describe "graph/2" do
    test "a table for each, with its keys, and a foreign key between two shown" do
      graph =
        SchemaDiagram.graph("public", [
          {"users", [col("id", "bigint", pk: true), col("email", "text")]},
          {"posts",
           [
             col("id", "bigint", pk: true),
             col("user_id", "bigint", ref: %{schema: "public", table: "users", column: "id"})
           ]}
        ])

      assert %{type: "schema-table", x: 0, y: 0, data: data} = Graph.node(graph, "users")

      assert data == %{
               "name" => "users",
               "columns" => [
                 %{"name" => "id", "type" => "bigint", "key" => "pk"},
                 %{"name" => "email", "type" => "text", "key" => nil}
               ]
             }

      assert %{"columns" => [_, %{"name" => "user_id", "key" => "fk"}]} =
               Graph.node(graph, "posts").data

      assert [
               %{
                 id: "posts.user_id",
                 source: "posts",
                 source_handle: "user_id",
                 target: "users",
                 target_handle: "id"
               }
             ] = Graph.edges(graph)
    end

    test "a foreign key into another schema points to a stub of the table, with only its columns" do
      graph =
        SchemaDiagram.graph("public", [
          {"orders",
           [
             col("id", "bigint", pk: true),
             col("invoice_id", "uuid", ref: %{schema: "billing", table: "invoices", column: "id"})
           ]},
          {"refunds",
           [
             col("invoice_id", "uuid", ref: %{schema: "billing", table: "invoices", column: "id"})
           ]}
        ])

      assert %{data: stub} = Graph.node(graph, "billing.invoices")

      assert stub == %{
               "name" => "invoices",
               "schema" => "billing",
               "external" => true,
               "columns" => [%{"name" => "id", "type" => "uuid", "key" => "pk"}]
             }

      assert graph |> Graph.edges() |> Enum.map(& &1.target) |> Enum.uniq() == [
               "billing.invoices"
             ]

      assert length(Graph.nodes(graph)) == 3
    end

    test "a foreign key to a table of this schema not shown is left out" do
      graph =
        SchemaDiagram.graph("public", [
          {"posts",
           [col("user_id", "bigint", ref: %{schema: "public", table: "users", column: "id"})]}
        ])

      assert Graph.edges(graph) == []
      assert [%{id: "posts"}] = Graph.nodes(graph)
    end

    test "a reference that names no column (SQLite) points to the primary key, without schemas" do
      graph =
        SchemaDiagram.graph(nil, [
          {"users", [col("uid", "INTEGER", pk: true)]},
          {"posts", [col("user_id", "INTEGER", ref: %{schema: nil, table: "users", column: nil})]}
        ])

      assert [%{target: "users", target_handle: "uid"}] = Graph.edges(graph)
    end
  end

  describe "active_schema/2" do
    setup do
      database = %Database{
        name: "db",
        source_type: :postgres,
        supports_schemas: true,
        schemas: [
          %Schema{name: "public", is_default: true},
          %Schema{name: "reporting", is_default: false}
        ]
      }

      %{database: database}
    end

    test "the first of the search path the source has", %{database: database} do
      assert SchemaDiagram.active_schema(database, "missing, reporting,public") == "reporting"
    end

    test "else the default schema", %{database: database} do
      assert SchemaDiagram.active_schema(database, nil) == "public"
      assert SchemaDiagram.active_schema(database, "") == "public"
      assert SchemaDiagram.active_schema(database, "missing") == "public"
    end

    test "else the first", %{database: database} do
      database = %{database | schemas: Enum.map(database.schemas, &%{&1 | is_default: false})}
      assert SchemaDiagram.active_schema(database, nil) == "public"
    end
  end

  describe "supported?/1" do
    test "SQL sources" do
      assert SchemaDiagram.supported?(%Database{source_type: :postgres})
      assert SchemaDiagram.supported?(%Database{source_type: :mysql})
      assert SchemaDiagram.supported?(%Database{source_type: :sqlite})
      refute SchemaDiagram.supported?(%Database{source_type: :elasticsearch})
      refute SchemaDiagram.supported?(nil)
    end
  end

  describe "load/3" do
    test "reads the tables of a schema of the source, and their foreign keys" do
      database = SourcesMap.build() |> SourcesMap.get_database("public")

      assert {:ok, %{schema: "reporting", tables: tables, graph: graph}} =
               SchemaDiagram.load(database, "reporting")

      assert tables >= 2
      assert %{data: %{"name" => "orders"}} = Graph.node(graph, "orders")

      assert Enum.any?(
               Graph.edges(graph),
               &match?(%{source: "orders", source_handle: "customer_id", target: "customers"}, &1)
             )
    end

    test "a schema the source does not have" do
      database = SourcesMap.build() |> SourcesMap.get_database("public")
      assert {:error, :no_schema} = SchemaDiagram.load(database, "nowhere")
    end
  end
end
