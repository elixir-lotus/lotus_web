defmodule Lotus.Web.Queries.AiPreview do
  @moduledoc """
  A glimpse of what a query the AI assistant wrote returns, under its
  answer: its first rows, read-only, and the chart its columns suggest (a
  line over dates, bars over names, a number on its own), drawn small.
  """

  use Gettext, backend: Lotus.Web.Gettext

  alias Lotus.Web.CellFormatter

  @rows 50
  @measure ~r/amount|revenue|total|sum|price|value|cost|sales|spent/i
  @timeout 10_000

  @type t :: %{
          status: :loading | :ok | :error,
          columns: [String.t()],
          rows: [list()],
          error: String.t() | nil,
          chart: chart() | nil
        }

  @type chart :: %{
          type: String.t(),
          x: String.t() | nil,
          y: String.t(),
          points: [{String.t(), number()}]
        }

  @doc "Whether a statement can be previewed: it needs no variable to run."
  @spec previewable?(String.t() | nil) :: boolean()
  def previewable?(statement) when is_binary(statement),
    do: String.trim(statement) != "" and not String.contains?(statement, "{{")

  def previewable?(_statement), do: false

  @doc """
  Runs the statement on the source, read-only, for its first #{@rows} rows.
  `opts` are the actor's and the search path, as `Lotus.run_statement/3`
  takes them.
  """
  @spec run(String.t(), String.t(), keyword()) :: t()
  def run(statement, data_source, opts \\ []) do
    run_opts =
      [
        repo: data_source,
        read_only: true,
        timeout: @timeout,
        statement_timeout_ms: @timeout,
        window: [limit: @rows, offset: 0, count: :none]
      ] ++ opts

    case Lotus.run_statement(statement, [], run_opts) do
      {:ok, result} -> from_result(result)
      {:error, error} -> %{loading() | status: :error, error: message(error)}
    end
  rescue
    error -> %{loading() | status: :error, error: Exception.message(error)}
  end

  @doc "A preview that is still running."
  @spec loading() :: %{status: :loading, columns: [], rows: [], error: nil, chart: nil}
  def loading, do: %{status: :loading, columns: [], rows: [], error: nil, chart: nil}

  @doc false
  @spec from_result(map()) :: t()
  def from_result(%{columns: columns, rows: rows}) do
    columns = Enum.map(columns, &to_string/1)
    %{status: :ok, columns: columns, rows: rows, error: nil, chart: suggest(columns, rows)}
  end

  @doc """
  The chart a result suggests, or `nil`: a number on its own for one row of
  one number, a line when the first column holds dates, bars when it holds
  names, each over the first number column after it.
  """
  @spec suggest([String.t()], [list()]) :: chart() | nil
  def suggest(columns, rows)

  def suggest([column], [[value]]) do
    if number(value), do: %{type: "kpi", x: nil, y: column, points: [{column, number(value)}]}
  end

  def suggest([x | _] = columns, [_, _ | _] = rows) do
    with y_index when is_integer(y_index) <- number_column(columns, rows),
         false <- y_index == 0 do
      type = if Enum.all?(rows, &temporal?(hd(&1))), do: "line", else: "bar"

      points =
        rows
        |> Enum.map(fn row -> {label(hd(row)), number(Enum.at(row, y_index))} end)
        |> Enum.reject(fn {_x, y} -> is_nil(y) end)
        |> then(&if type == "bar", do: Enum.take(&1, 12), else: &1)

      if length(points) >= 2,
        do: %{type: type, x: x, y: Enum.at(columns, y_index), points: points}
    else
      _ -> nil
    end
  end

  def suggest(_columns, _rows), do: nil

  @doc "A cell as the preview shows it."
  @spec cell(term()) :: String.t()
  def cell(nil), do: "—"
  def cell(%DateTime{} = value), do: value |> DateTime.to_naive() |> cell()

  def cell(%NaiveDateTime{} = value) do
    if Time.compare(NaiveDateTime.to_time(value), ~T[00:00:00]) == :eq,
      do: value |> NaiveDateTime.to_date() |> Date.to_iso8601(),
      else: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  end

  def cell(value), do: value |> CellFormatter.format() |> to_string()

  # The column after the first to chart: one whose values are all numbers,
  # a measure (an amount, a revenue) before a count.
  defp number_column(columns, rows) do
    numeric =
      Enum.filter(1..(length(columns) - 1)//1, fn index ->
        Enum.all?(rows, &(number(Enum.at(&1, index)) != nil))
      end)

    Enum.find(numeric, &(Enum.at(columns, &1) =~ @measure)) || List.first(numeric)
  end

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value) when is_number(value), do: value
  defp number(_value), do: nil

  defp temporal?(%Date{}), do: true
  defp temporal?(%DateTime{}), do: true
  defp temporal?(%NaiveDateTime{}), do: true
  defp temporal?(_value), do: false

  defp label(%DateTime{} = value), do: value |> DateTime.to_date() |> label()
  defp label(%NaiveDateTime{} = value), do: value |> NaiveDateTime.to_date() |> label()
  defp label(%Date{} = value), do: Calendar.strftime(value, "%b %Y")
  defp label(value), do: cell(value)

  defp message(error) when is_binary(error), do: error
  defp message(error) when is_exception(error), do: Exception.message(error)
  defp message(error), do: inspect(error)
end
