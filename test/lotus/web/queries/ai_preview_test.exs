defmodule Lotus.Web.Queries.AiPreviewTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Queries.AiPreview

  test "a query with variables is not previewed" do
    assert AiPreview.previewable?("SELECT * FROM users")
    refute AiPreview.previewable?("SELECT * FROM users WHERE id = {{id}}")
    refute AiPreview.previewable?("  ")
    refute AiPreview.previewable?(nil)
  end

  test "dates in the first column suggest a line, over a measure before a count" do
    rows = [
      [~D[2026-01-01], 31, Decimal.new("7154.98")],
      [~D[2026-02-01], 28, Decimal.new("6803.22")],
      [~D[2026-03-01], 30, Decimal.new("7044.53")]
    ]

    assert %{type: "line", x: "month", y: "revenue", points: points} =
             AiPreview.suggest(["month", "orders", "revenue"], rows)

    assert [{"Jan 2026", 7154.98} | _] = points
  end

  test "names in the first column suggest bars, at most twelve" do
    rows = for n <- 1..20, do: ["product #{n}", n]

    assert %{type: "bar", y: "sold", points: points} = AiPreview.suggest(["name", "sold"], rows)
    assert length(points) == 12
  end

  test "one number on its own is a KPI" do
    assert %{type: "kpi", y: "total"} = AiPreview.suggest(["total"], [[Decimal.new("42.5")]])
  end

  test "nothing to chart without a number column, or with one row of many" do
    assert AiPreview.suggest(["name", "email"], [["a", "a@x"], ["b", "b@x"]]) == nil
    assert AiPreview.suggest(["name", "n"], [["a", 1]]) == nil
    assert AiPreview.suggest(["n"], [["not a number"]]) == nil
  end

  test "a timestamp at midnight is shown as its date" do
    assert AiPreview.cell(~N[2026-01-01 00:00:00.000000]) == "2026-01-01"
    assert AiPreview.cell(~N[2026-01-01 14:30:12]) == "2026-01-01 14:30"
    assert AiPreview.cell(nil) == "—"
  end
end
