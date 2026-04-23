defmodule Lotus.Web.SchemaBuilder do
  @moduledoc "Builds DB schemas for the editor."

  alias Lotus.Web.SourcesMap

  @doc """
  Builds schema for CodeMirror autocomplete from SourcesMap and search_path.
  """
  def build(%SourcesMap{} = sources_map, data_repo, search_path \\ nil) do
    case SourcesMap.get_database(sources_map, data_repo) do
      nil ->
        {:error, :database_not_found}

      database ->
        schema_map =
          database
          |> determine_selected_schemas(data_repo, search_path)
          |> build_schema_map(database, data_repo)

        {:ok, schema_map}
    end
  end

  defp determine_selected_schemas(database, data_repo, search_path) do
    if search_path && search_path != "" do
      String.split(search_path, ",", trim: true)
    else
      default_schemas_for_database(database, data_repo)
    end
  end

  defp default_schemas_for_database(database, data_repo) do
    if database.supports_schemas do
      case Lotus.Config.data_sources()[data_repo] do
        nil -> ["public"]
        _repo -> Lotus.Source.Adapter.default_schemas(Lotus.Source.get_source!(data_repo))
      end
    else
      Enum.map(database.schemas, & &1.name)
    end
  end

  defp build_schema_map(selected_schemas, database, data_repo) do
    database.schemas
    |> Enum.filter(&(&1.name in selected_schemas))
    |> Enum.reduce(%{}, fn schema, acc ->
      build_tables_for_schema(schema, selected_schemas, database, data_repo, acc)
    end)
  end

  defp build_tables_for_schema(schema, selected_schemas, database, data_repo, acc) do
    Enum.reduce(schema.tables, acc, fn table_name, inner_acc ->
      qualified_table = qualify_table_name(table_name, schema, selected_schemas, database)
      columns = fetch_table_columns(data_repo, table_name, schema)
      Map.put(inner_acc, qualified_table, columns)
    end)
  end

  defp qualify_table_name(table_name, schema, selected_schemas, database) do
    case selected_schemas do
      [_single] -> table_name
      _ when database.supports_schemas -> "#{schema.name}.#{table_name}"
      _ -> table_name
    end
  end

  defp fetch_table_columns(data_repo, table_name, schema) do
    case Lotus.describe_table(data_repo, table_name, search_path: schema.name) do
      {:ok, columns} -> Enum.map(columns, & &1.name)
      {:error, _} -> []
    end
  end
end
