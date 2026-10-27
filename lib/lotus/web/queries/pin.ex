defmodule Lotus.Web.Queries.Pin do
  @moduledoc false

  # A result the editor keeps beside the next ones, to compare them, as long
  # as the page: the rows it showed when it was pinned (its page, not the
  # query run again), the statement that ran with its source, search path
  # and variables (to compare every row of it with the next run's,
  # `Lotus.diff/3`), and the editor's text then, to restore it.

  defstruct [:result, :statement, :text, :pinned_at, :data_source, :search_path, vars: %{}]

  @type t :: %__MODULE__{
          result: map(),
          statement: String.t() | nil,
          text: String.t() | nil,
          pinned_at: DateTime.t(),
          data_source: String.t() | nil,
          search_path: String.t() | nil,
          vars: map()
        }

  @doc """
  Pins a result, with `attrs` (`:statement`, `:text`, `:data_source`,
  `:search_path`, `:vars`).
  """
  def new(result, attrs, now \\ DateTime.utc_now()) do
    struct(
      %__MODULE__{result: result},
      Map.put(attrs, :pinned_at, DateTime.truncate(now, :second))
    )
  end

  @doc """
  The rows of a result: its total when the source counted it, else the
  rows it has.
  """
  def row_count(%{meta: %{total_count: total}}) when is_integer(total), do: total
  def row_count(%{num_rows: n}) when is_integer(n), do: n
  def row_count(%{rows: rows}) when is_list(rows), do: length(rows)
  def row_count(_result), do: 0

  @doc """
  How a result differs from the pinned one: its rows (before, after, the
  difference and its percent of before), its columns added and removed,
  and both durations.
  """
  def compare(%__MODULE__{result: pinned}, result) do
    before = row_count(pinned)
    now = row_count(result)
    pinned_columns = pinned.columns || []
    columns = result.columns || []

    %{
      rows: before,
      now: now,
      delta: now - before,
      percent: percent(now - before, before),
      added: columns -- pinned_columns,
      removed: pinned_columns -- columns,
      duration: Map.get(pinned, :duration_ms),
      now_duration: Map.get(result, :duration_ms)
    }
  end

  @doc """
  The columns both results have that can match their rows: `id` first when
  both have it.
  """
  def key_columns(%__MODULE__{result: pinned}, result) do
    shared = Enum.filter(result.columns || [], &(&1 in (pinned.columns || [])))
    {ids, rest} = Enum.split_with(shared, &(&1 == "id"))
    ids ++ rest
  end

  defp percent(_delta, 0), do: nil
  defp percent(delta, before), do: round(delta * 100 / before)
end
