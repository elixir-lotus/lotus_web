defmodule Lotus.Web.SchemaDiagram do
  @moduledoc """
  The schema diagram of a data source: the tables of one schema and their
  foreign keys, as a `Hakushi.Graph` for `Hakushi.Kits.Schema`.

  The tables have no places of their own: the canvas lays them out as it
  opens (`tidy`). A foreign key into another schema points to a stub of the
  table it refers to (`"external" => true`), drawn as a ghost, with only the
  columns the foreign keys use.

  Only SQL sources have one (`supported?/1`): they say their primary and
  foreign keys. The tables and the references are those the actor may see
  (`Lotus.describe_table/3` drops a reference to a relation they may not).
  """

  alias Hakushi.Graph
  alias Lotus.Web.SourcesMap.Database

  @sql [:postgres, :mysql, :sqlite]

  @typedoc "A table and its columns, as `Lotus.describe_table/3` gives them."
  @type table :: {String.t(), [map()]}

  @doc "Whether the source draws a schema diagram: a SQL source that says its keys."
  @spec supported?(Database.t() | nil) :: boolean()
  def supported?(%Database{source_type: type}), do: type in @sql
  def supported?(_database), do: false

  @doc """
  The schema the diagram shows: the first of the query's `search_path` that
  the source has, else its default schema, else its first.
  """
  @spec active_schema(Database.t(), String.t() | nil) :: String.t() | nil
  def active_schema(%Database{schemas: schemas}, search_path) do
    names = Enum.map(schemas, & &1.name)

    from_path =
      (search_path || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.find(&(&1 in names))

    from_path || Enum.find_value(schemas, &(&1.is_default && &1.name)) || List.first(names)
  end

  @doc """
  Reads the tables of `schema` in the source, and gives its diagram.

  `opts` are the actor's options (`:context`, `:scope`). A table that fails
  to describe is left out.
  """
  @spec load(Database.t(), String.t() | nil, keyword()) ::
          {:ok, %{schema: String.t() | nil, tables: non_neg_integer(), graph: Graph.t()}}
          | {:error, :no_schema}
  def load(%Database{} = database, schema_name, opts \\ []) do
    case Enum.find(database.schemas, &(&1.name == schema_name)) do
      nil ->
        {:error, :no_schema}

      schema ->
        path = if database.supports_schemas, do: [search_path: schema.name], else: []

        tables =
          for table <- schema.tables,
              {:ok, columns} <- [Lotus.describe_table(database.name, table, path ++ opts)],
              do: {table, columns}

        own = if database.supports_schemas, do: schema.name
        {:ok, %{schema: schema.name, tables: length(tables), graph: graph(own, tables)}}
    end
  end

  @doc """
  The diagram of `tables` of `schema` (`nil` for a source without schemas):
  a table for each, a foreign key for each column that references a table
  shown, and a stub for each table of another schema referenced.
  """
  @spec graph(String.t() | nil, [table()]) :: Graph.t()
  def graph(schema, tables) do
    shown = Map.new(tables)

    keys =
      for {table, columns} <- tables,
          %{references: %{table: _} = ref} = column <- columns,
          key = foreign_key(schema, shown, table, column, ref),
          key != nil,
          do: key

    Graph.new(
      nodes: Enum.map(tables, &table_node/1) ++ stubs(keys),
      edges:
        Enum.map(keys, fn key ->
          %{
            id: key.source <> "." <> key.column,
            source: key.source,
            source_handle: key.column,
            target: key.target,
            target_handle: key.target_column,
            path: "smooth"
          }
        end)
    )
  end

  defp table_node({table, columns}) do
    %{
      id: table,
      type: "schema-table",
      x: 0,
      y: 0,
      data: %{"name" => table, "columns" => Enum.map(columns, &column/1)}
    }
  end

  defp column(column) do
    key =
      cond do
        column.primary_key -> "pk"
        match?(%{references: %{}}, column) -> "fk"
        true -> nil
      end

    %{"name" => column.name, "type" => column.type, "key" => key}
  end

  # A foreign key: to a table shown, or to a stub of a table of another
  # schema. One to a table of this schema that is not shown is left out.
  defp foreign_key(schema, shown, table, column, ref) do
    other = ref[:schema]

    if schema != nil and other not in [nil, schema] do
      %{
        source: table,
        column: column.name,
        target: other <> "." <> ref.table,
        target_column: ref[:column] || "id",
        stub: %{schema: other, table: ref.table, type: column.type}
      }
    else
      case Map.fetch(shown, ref.table) do
        {:ok, columns} ->
          %{
            source: table,
            column: column.name,
            target: ref.table,
            target_column: ref[:column] || primary_key(columns),
            stub: nil
          }

        :error ->
          nil
      end
    end
  end

  # The column a reference that names none points to (SQLite's): the
  # table's primary key, else its first column.
  defp primary_key(columns) do
    case Enum.find(columns, & &1.primary_key) || List.first(columns) do
      nil -> nil
      column -> column.name
    end
  end

  # A stub for each table of another schema: its referenced columns, of the
  # types of the columns that refer to them.
  defp stubs(keys) do
    keys
    |> Enum.filter(& &1.stub)
    |> Enum.group_by(& &1.target)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {id, [%{stub: stub} | _] = refs} ->
      columns =
        refs
        |> Enum.uniq_by(& &1.target_column)
        |> Enum.map(&%{"name" => &1.target_column, "type" => &1.stub.type, "key" => "pk"})

      %{
        id: id,
        type: "schema-table",
        x: 0,
        y: 0,
        data: %{
          "name" => stub.table,
          "schema" => stub.schema,
          "external" => true,
          "columns" => columns
        }
      }
    end)
  end
end
