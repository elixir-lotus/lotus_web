defmodule Lotus.Web.SourcesMap do
  @moduledoc """
  Data structure representing the complete database schema hierarchy.
  """

  require Logger

  defstruct databases: []

  defmodule Database do
    @moduledoc false

    defstruct [:name, :source_type, :supports_schemas, schemas: []]
  end

  defmodule Schema do
    @moduledoc false

    defstruct [:name, :is_default, :display_name, tables: []]
  end

  def build() do
    databases =
      Lotus.list_data_source_names()
      |> Enum.map(&load_database/1)
      |> Enum.reject(&is_nil/1)

    %__MODULE__{databases: databases}
  end

  defp load_database(db_name) do
    source_type = Lotus.Source.source_type(db_name)
    supports_schemas = Lotus.Source.supports_feature?(db_name, :schema_hierarchy)

    repo = Lotus.Config.get_data_source!(db_name)

    schemas =
      if supports_schemas do
        load_postgres_schemas(db_name, repo)
      else
        load_simple_tables(db_name)
      end

    %Database{
      name: db_name,
      source_type: source_type,
      supports_schemas: supports_schemas,
      schemas: schemas
    }
  rescue
    error in [DBConnection.ConnectionError] ->
      Logger.warning(
        "Failed to load database #{inspect(db_name)} for the explorer: " <>
          Exception.message(error)
      )

      nil

    error in [RuntimeError, ArgumentError] ->
      Logger.error(
        "Unexpected error loading database #{inspect(db_name)}: " <>
          Exception.message(error)
      )

      nil
  end

  defp load_postgres_schemas(db_name, _repo) do
    with {:ok, schema_names} <- Lotus.list_schemas(db_name),
         adapter <- Lotus.Source.get_source!(db_name),
         [default_schema | _] <- Lotus.Source.Adapter.default_schemas(adapter),
         search_path <- Enum.join(schema_names, ","),
         {:ok, all_tables} <- Lotus.list_tables(db_name, search_path: search_path) do
      all_tables
      |> Enum.group_by(fn {schema, _table} -> schema end, fn {_schema, table} -> table end)
      |> Enum.map(fn {schema_name, tables} ->
        is_default = schema_name == default_schema

        %Schema{
          name: schema_name,
          is_default: is_default,
          display_name: schema_name,
          tables: Enum.sort(tables)
        }
      end)
      |> Enum.sort_by(fn schema -> if schema.is_default, do: "", else: schema.name end)
    else
      _ -> []
    end
  end

  defp load_simple_tables(db_name) do
    case Lotus.list_tables(db_name) do
      {:ok, tables} ->
        table_names = extract_table_names(tables)

        [
          %Schema{
            name: "default",
            is_default: false,
            display_name: Lotus.Source.hierarchy_label(db_name),
            tables: Enum.sort(table_names)
          }
        ]

      _ ->
        []
    end
  end

  defp extract_table_names([]), do: []
  defp extract_table_names([{_schema, _table} | _] = tables), do: Enum.map(tables, &elem(&1, 1))
  defp extract_table_names(tables), do: tables

  def get_database(_sources_map, db_name) when is_nil(db_name), do: nil

  def get_database(sources_map, db_name) do
    Enum.find(sources_map.databases, &(&1.name == db_name))
  end

  def get_tables_for_database(sources_map, db_name) do
    case get_database(sources_map, db_name) do
      %Database{schemas: schemas} -> Enum.flat_map(schemas, & &1.tables)
      nil -> []
    end
  end

  def get_schema_count(database) do
    if database.supports_schemas do
      length(database.schemas)
    else
      0
    end
  end

  def get_table_count(database) do
    database.schemas
    |> Enum.map(&length(&1.tables))
    |> Enum.sum()
  end
end
