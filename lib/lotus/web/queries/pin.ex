defmodule Lotus.Web.Queries.Pin do
  @moduledoc false

  # A result the editor keeps beside the next ones, to compare them: the
  # rows it showed when it was pinned (its page, not the query run again),
  # the statement that ran, and the editor's text then, to restore it.
  # One at a time; it lives as long as the page.

  defstruct [:result, :statement, :text, :pinned_at]

  @type t :: %__MODULE__{
          result: Lotus.Result.t() | map(),
          statement: String.t() | nil,
          text: String.t() | nil,
          pinned_at: DateTime.t()
        }

  @doc "Pins a result, the statement it ran and the editor's text."
  def new(result, statement, text, now \\ DateTime.utc_now()) do
    %__MODULE__{
      result: result,
      statement: statement,
      text: text,
      pinned_at: DateTime.truncate(now, :second)
    }
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

  defp percent(_delta, 0), do: nil
  defp percent(delta, before), do: round(delta * 100 / before)
end
