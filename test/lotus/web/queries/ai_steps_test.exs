defmodule Lotus.Web.Queries.AiStepsTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Queries.AiSteps

  defp start(id, tool, args), do: %{phase: :start, id: id, tool: tool, args: args}

  defp stop(id, result),
    do: %{
      phase: :stop,
      id: id,
      result: result,
      duration: System.convert_time_unit(42, :millisecond, :native)
    }

  test "a tool call starts as a running step and settles with what it found" do
    steps =
      []
      |> AiSteps.track(start(1, "describe_table", %{"table_name" => "orders"}))

    assert [%{status: :running, summary: nil}] = steps
    assert AiSteps.label(hd(steps)) == "Reading orders"

    steps =
      AiSteps.track(
        steps,
        stop(1, ~s({"table":"orders","columns":[{"name":"id"},{"name":"total"}]}))
      )

    assert [%{status: :done, summary: "2 columns", ms: 42}] = steps
  end

  test "a tool that reports an error fails" do
    steps =
      []
      |> AiSteps.track(start(1, "list_tables", %{}))
      |> AiSteps.track(stop(1, ~s({"error":"denied"})))

    assert [%{status: :failed, summary: "denied"}] = steps
  end

  test "a column's values are summed up by the first few" do
    steps =
      []
      |> AiSteps.track(
        start(1, "get_column_values", %{table_name: "orders", column_name: "status"})
      )
      |> AiSteps.track(stop(1, ~s({"values":["completed","pending","shipped","refunded"]})))

    assert [%{summary: "completed, pending, shipped, …"} = step] = steps
    assert AiSteps.label(step) == "Looking at the values of orders.status"
  end

  test "the headline names the tables read and the time it took" do
    steps =
      []
      |> AiSteps.track(start(1, "list_tables", %{}))
      |> AiSteps.track(start(2, "describe_table", %{"table_name" => "orders"}))
      |> AiSteps.track(
        start(3, "get_column_values", %{"table_name" => "orders", "column_name" => "status"})
      )
      |> AiSteps.track(start(4, "describe_table", %{"table_name" => "users"}))

    assert AiSteps.tables(steps) == ["orders", "users"]
    assert AiSteps.headline(steps, 3240) == "Read 2 tables · 3.2s"
    assert AiSteps.headline(Enum.take(steps, 1), nil) == "1 step"
  end

  test "a stop for a step it does not know changes nothing" do
    steps = AiSteps.track([], start(1, "list_tables", %{}))
    assert AiSteps.track(steps, stop(2, "{}")) == steps
  end
end
