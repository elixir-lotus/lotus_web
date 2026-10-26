defmodule Lotus.Web.SchemaBuilder do
  @moduledoc """
  Builds DB schemas for the editor.

  The editor gets a source's tables up front, and a table's columns when a
  statement uses the table (`columns/5`): describing every table when the
  editor opens takes a query per table, which a database with hundreds of
  tables makes slow.
  """

  alias Lotus.Web.SourcesMap

  # The most tables `columns/5` describes at once.
  @max_tables 8

  @doc "The most tables `columns/5` describes in one call."
  def max_tables, do: @max_tables

  @doc """
  Builds the schema for CodeMirror autocomplete from SourcesMap and
  search_path: each table of the selected schemas, its columns `nil` until
  `columns/5` describes it.

  A table's key is its name, qualified by its schema ("reporting.orders")
  when several schemas are selected.
  """
  def build(sources_map, data_repo, search_path \\ nil, opts \\ [])

  def build(%SourcesMap{} = sources_map, data_repo, search_path, _opts) do
    case tables(sources_map, data_repo, search_path) do
      {:ok, tables} -> {:ok, Map.new(tables, fn {key, _schema, _table} -> {key, nil} end)}
      error -> error
    end
  end

  @doc """
  The schemas the editor's tables are of: the search_path's, or the source's
  default ones.
  """
  @spec schemas(SourcesMap.t(), String.t() | nil, String.t() | nil) :: [String.t()]
  def schemas(%SourcesMap{} = sources_map, data_repo, search_path) do
    case SourcesMap.get_database(sources_map, data_repo) do
      nil -> []
      database -> determine_selected_schemas(database, data_repo, search_path)
    end
  end

  @doc """
  The columns of the tables `keys` (as `build/4` names them), up to
  `max_tables/0` of them; a key that is no table of the editor's is left out.

  `opts` are the actor options (`:context`, `:scope`) forwarded to the core
  calls that describe each table.
  """
  @spec columns(SourcesMap.t(), String.t() | nil, String.t() | nil, [String.t()], keyword()) ::
          {:ok, %{String.t() => [String.t()]}} | {:error, :database_not_found}
  def columns(%SourcesMap{} = sources_map, data_repo, search_path, keys, opts \\ []) do
    with {:ok, tables} <- tables(sources_map, data_repo, search_path) do
      index = Map.new(tables, fn {key, schema, table} -> {key, {schema, table}} end)

      columns =
        keys
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
        |> Enum.filter(&Map.has_key?(index, &1))
        |> Enum.take(@max_tables)
        |> Map.new(fn key ->
          {schema, table} = Map.fetch!(index, key)
          {key, fetch_table_columns(data_repo, table, schema, opts)}
        end)

      {:ok, columns}
    end
  end

  # Each table of the selected schemas: {key, schema, table}.
  defp tables(sources_map, data_repo, search_path) do
    case SourcesMap.get_database(sources_map, data_repo) do
      nil ->
        {:error, :database_not_found}

      database ->
        selected = determine_selected_schemas(database, data_repo, search_path)

        tables =
          for schema <- database.schemas,
              schema.name in selected,
              table <- schema.tables,
              do: {qualify_table_name(table, schema, selected, database), schema.name, table}

        {:ok, tables}
    end
  end

  defp determine_selected_schemas(database, data_repo, search_path) do
    if search_path && search_path != "" do
      search_path |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    else
      default_schemas_for_database(database, data_repo)
    end
  end

  defp default_schemas_for_database(database, data_repo) do
    if database.supports_schemas do
      if data_repo in Lotus.list_data_source_names(),
        do: Lotus.Source.Adapter.default_schemas(Lotus.Source.get_source!(data_repo)),
        else: ["public"]
    else
      Enum.map(database.schemas, & &1.name)
    end
  end

  defp qualify_table_name(table_name, schema, selected_schemas, database) do
    case selected_schemas do
      [_single] -> table_name
      _ when database.supports_schemas -> "#{schema.name}.#{table_name}"
      _ -> table_name
    end
  end

  defp fetch_table_columns(data_repo, table_name, schema, opts) do
    case Lotus.describe_table(data_repo, table_name, [search_path: schema] ++ opts) do
      {:ok, columns} -> Enum.map(columns, & &1.name)
      {:error, _} -> []
    end
  end
end
