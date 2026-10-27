defmodule Lotus.Web.Queries.PinTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Queries.Pin

  defp result(columns, n, extra \\ %{}),
    do: Map.merge(%{columns: columns, rows: [], num_rows: n, duration_ms: 5, meta: %{}}, extra)

  test "compare/2: rows, their change, and the columns added and removed" do
    pin = Pin.new(result(~w(id total), 847, %{duration_ms: 14}), "SELECT 1", "SELECT 1")

    assert %{
             rows: 847,
             now: 312,
             delta: -535,
             percent: -63,
             added: ["region"],
             removed: ["total"],
             duration: 14,
             now_duration: 5
           } = Pin.compare(pin, result(~w(id region), 312))
  end

  test "row_count/1 is the source's total when it counted it" do
    assert Pin.row_count(result(["a"], 50, %{meta: %{total_count: 900}})) == 900
    assert Pin.row_count(result(["a"], 50)) == 50
  end

  test "no percent from nothing" do
    pin = Pin.new(result(["a"], 0), nil, nil)
    assert %{delta: 4, percent: nil} = Pin.compare(pin, result(["a"], 4))
  end
end
