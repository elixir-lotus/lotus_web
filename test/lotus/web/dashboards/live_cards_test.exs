defmodule Lotus.Web.Dashboards.LiveCardsTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Dashboards.LiveCards

  @statement "SELECT at, n FROM events WHERE 1=1 [[AND at > {{since}}]] ORDER BY at"

  defp card(config, statement \\ @statement) do
    %{
      id: 1,
      card_type: :query,
      query: %{statement: statement},
      visualization_config:
        Map.merge(%{"chart_type" => "line", "x_field" => "at", "y_field" => "n"}, config)
    }
  end

  defp result(rows), do: %{columns: ["at", "n"], rows: rows}

  describe "live?/1" do
    test "a line, area or scatter chart, switched on, whose query reads {{since}}" do
      assert LiveCards.live?(card(%{"live" => "true"}))
      assert LiveCards.live?(card(%{"live" => true, "chart_type" => "area"}))
      assert LiveCards.live?(card(%{"live" => "true", "chart_type" => "scatter"}))
    end

    test "not when switched off, of another kind, or when the query does not read {{since}}" do
      refute LiveCards.live?(card(%{}))
      refute LiveCards.live?(card(%{"live" => "false"}))
      refute LiveCards.live?(card(%{"live" => "true", "chart_type" => "bar"}))
      refute LiveCards.live?(card(%{"live" => "true"}, "SELECT at, n FROM events"))
      refute LiveCards.live?(card(%{"live" => "true", "x_field" => nil}))
      refute LiveCards.live?(%{card_type: :text, visualization_config: %{"live" => "true"}})
    end
  end

  test "window/1 is the card's, or 60" do
    assert LiveCards.window(card(%{"live_window" => "120"})) == 120
    assert LiveCards.window(card(%{})) == 60
    assert LiveCards.window(card(%{"live_window" => "nonsense"})) == 60
  end

  test "trim/2 keeps a live card's last rows, and any other card's all" do
    rows = for n <- 1..5, do: [n, n]
    live = card(%{"live" => "true", "live_window" => "3"})

    assert LiveCards.trim(result(rows), live).rows == [[3, 3], [4, 4], [5, 5]]
    assert LiveCards.trim(result(rows), card(%{})).rows == rows
  end

  describe "cursor/2 and after_cursor/3" do
    test "by time" do
      t1 = ~U[2026-10-27 10:00:00Z]
      t2 = ~U[2026-10-27 10:00:05Z]
      t3 = ~U[2026-10-27 10:00:10Z]
      live = card(%{"live" => "true"})

      assert LiveCards.cursor(result([[t2, 2], [t1, 1], [nil, 0]]), live) == t2

      assert LiveCards.after_cursor(result([[t1, 1], [t2, 2], [t3, 3]]), live, t1) == [
               [t2, 2],
               [t3, 3]
             ]
    end

    test "by number, decimal, naive time and date" do
      live = card(%{"live" => "true"})

      assert LiveCards.cursor(result([[1, 0], [10, 0], [2, 0]]), live) == 10

      assert LiveCards.after_cursor(result([[Decimal.new("1.5"), 0], [2, 0]]), live, 1.5) == [
               [2, 0]
             ]

      n1 = ~N[2026-10-27 10:00:00]
      n2 = ~N[2026-10-27 11:00:00]
      assert LiveCards.cursor(result([[n2, 0], [n1, 0]]), live) == n2

      assert LiveCards.after_cursor(
               result([[~D[2026-10-26], 0], [~D[2026-10-28], 0]]),
               live,
               ~D[2026-10-27]
             ) ==
               [[~D[2026-10-28], 0]]
    end

    test "nothing when the x field is not a column, or there are no rows" do
      live = card(%{"live" => "true"})
      assert LiveCards.cursor(result([]), live) == nil
      assert LiveCards.cursor(%{columns: ["other"], rows: [[1]]}, live) == nil
      assert LiveCards.after_cursor(%{columns: ["other"], rows: [[1]]}, live, 0) == []
    end
  end

  test "reads_since?/1 and kind?/1 say why a card can't be live" do
    assert LiveCards.reads_since?(card(%{}))
    refute LiveCards.reads_since?(card(%{}, "SELECT 1"))
    assert LiveCards.kind?(card(%{}))
    refute LiveCards.kind?(card(%{"chart_type" => "pie"}))
  end
end
