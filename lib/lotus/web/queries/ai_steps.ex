defmodule Lotus.Web.Queries.AiSteps do
  @moduledoc """
  The work the AI assistant does while it answers: each tool the model asks
  for (`Lotus.AI`'s `:on_tool_call`), as a step the panel shows while it
  runs and keeps, folded, under the answer.
  """

  use Gettext, backend: Lotus.Web.Gettext

  @type step :: %{
          id: term(),
          tool: String.t(),
          args: map(),
          status: :running | :done | :failed,
          summary: String.t() | nil,
          ms: non_neg_integer() | nil
        }

  @doc "Adds a tool call that started, or settles one that stopped."
  @spec track([step()], map()) :: [step()]
  def track(steps, %{phase: :start, id: id, tool: tool} = event) do
    steps ++
      [
        %{
          id: id,
          tool: tool,
          args: Map.get(event, :args, %{}),
          status: :running,
          summary: nil,
          ms: nil
        }
      ]
  end

  def track(steps, %{phase: :stop, id: id} = event) do
    Enum.map(steps, fn
      %{id: ^id} = step ->
        {status, summary} = outcome(step, Map.get(event, :result))
        ms = System.convert_time_unit(Map.get(event, :duration, 0), :native, :millisecond)
        %{step | status: status, summary: summary, ms: ms}

      step ->
        step
    end)
  end

  def track(steps, _event), do: steps

  @doc "What a step does, in a few words."
  @spec label(step()) :: String.t()
  def label(%{tool: "list_tables"}), do: gettext("Listing the tables")
  def label(%{tool: "list_schemas"}), do: gettext("Listing the schemas")
  def label(%{tool: "list_data_sources"}), do: gettext("Listing the data sources")
  def label(%{tool: "validate_statement"}), do: gettext("Checking the query")
  def label(%{tool: "execute_statement"}), do: gettext("Running the query")

  def label(%{tool: "describe_table"} = step),
    do: gettext("Reading %{table}", table: table(step) || gettext("a table"))

  def label(%{tool: "get_column_values"} = step) do
    case {table(step), arg(step, "column_name")} do
      {table, column} when is_binary(table) and is_binary(column) ->
        gettext("Looking at the values of %{column}", column: "#{table}.#{column}")

      _ ->
        gettext("Looking at a column's values")
    end
  end

  def label(%{tool: tool}), do: tool

  @doc "Which kind of step it is, for its icon: `:list`, `:table`, `:values`, `:check` or `:run`."
  @spec kind(step()) :: atom()
  def kind(%{tool: tool}) when tool in ~w(list_tables list_schemas list_data_sources), do: :list
  def kind(%{tool: "describe_table"}), do: :table
  def kind(%{tool: "get_column_values"}), do: :values
  def kind(%{tool: "validate_statement"}), do: :check
  def kind(_step), do: :run

  @doc "The tables the steps read, in the order they were first read."
  @spec tables([step()]) :: [String.t()]
  def tables(steps) do
    steps
    |> Enum.filter(&(&1.tool in ~w(describe_table get_column_values)))
    |> Enum.map(&table/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc "A line that sums the steps up, under an answer."
  @spec headline([step()], non_neg_integer() | nil) :: String.t()
  def headline(steps, elapsed_ms) do
    work =
      case tables(steps) do
        [] ->
          ngettext("%{count} step", "%{count} steps", length(steps), count: length(steps))

        tables ->
          ngettext("Read %{count} table", "Read %{count} tables", length(tables),
            count: length(tables)
          )
      end

    case elapsed_ms do
      ms when is_integer(ms) and ms > 0 -> "#{work} · #{seconds(ms)}"
      _ -> work
    end
  end

  @doc "Milliseconds as seconds, for people: `3.2s`, `140ms`."
  @spec seconds(non_neg_integer()) :: String.t()
  def seconds(ms) when ms < 1000, do: "#{ms}ms"
  def seconds(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 1) <> "s"

  defp outcome(_step, {:error, _reason}), do: {:failed, nil}

  defp outcome(step, result) when is_binary(result) do
    case Lotus.JSON.decode(result) do
      {:ok, %{"error" => error}} when is_binary(error) -> {:failed, error}
      {:ok, decoded} -> {:done, summary(step.tool, decoded)}
      _ -> {:done, nil}
    end
  end

  defp outcome(_step, _result), do: {:done, nil}

  defp summary("list_tables", %{"tables" => tables}) when is_list(tables),
    do: ngettext("%{count} table", "%{count} tables", length(tables), count: length(tables))

  defp summary("list_schemas", %{"schemas" => schemas}) when is_list(schemas),
    do: ngettext("%{count} schema", "%{count} schemas", length(schemas), count: length(schemas))

  defp summary("describe_table", %{"columns" => columns}) when is_list(columns),
    do: ngettext("%{count} column", "%{count} columns", length(columns), count: length(columns))

  defp summary("get_column_values", %{"values" => values}) when is_list(values) do
    shown = values |> Enum.take(3) |> Enum.map_join(", ", &to_string/1)
    if length(values) > 3, do: shown <> ", …", else: shown
  end

  defp summary("validate_statement", %{"valid" => true}), do: gettext("valid")
  defp summary("validate_statement", %{"valid" => false}), do: gettext("needs a fix")
  defp summary(_tool, _result), do: nil

  defp table(step), do: arg(step, "table_name")

  # The model's arguments come with string keys, or atom keys once validated.
  @arg_atoms %{"table_name" => :table_name, "column_name" => :column_name}

  defp arg(%{args: args}, key) when is_map(args),
    do: Map.get(args, key) || Map.get(args, @arg_atoms[key])

  defp arg(_step, _key), do: nil
end
