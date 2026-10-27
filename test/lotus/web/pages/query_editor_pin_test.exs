defmodule Lotus.Web.Pages.QueryEditorPinTest do
  # A result pinned stays on screen beside the next runs, with how they
  # differ: rows and columns.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    create_test_users()
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    %{live: live}
  end

  defp run(live, statement) do
    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(%{"query" => %{"statement" => statement}})

    render_async(live)
  end

  test "pin a result, run another, and see both with what changed", %{live: live} do
    run(live, "SELECT name, email FROM test_users ORDER BY name")
    refute has_element?(live, "#pinned-result")

    live |> element("#pin-result-btn") |> render_click()
    assert has_element?(live, "#pinned-result", "Alice")
    assert has_element?(live, "#pin-compare-rows", "3 → 3")

    html = run(live, "SELECT name, id FROM test_users WHERE name <> 'Alice' ORDER BY name")

    # The pinned rows are the ones it had.
    assert has_element?(live, "#pinned-result", "Alice")
    assert has_element?(live, "#pinned-result code", "SELECT name, email FROM test_users")
    assert has_element?(live, "#pin-compare-rows", "3 → 2")
    assert has_element?(live, "#pin-compare-rows", "−1 (−33%)")
    assert has_element?(live, "#pin-compare-columns", "+id")
    assert has_element?(live, "#pin-compare-columns", "−email")
    assert has_element?(live, "#pinned-result th", "removed")
    assert html =~ "Pin this instead"
  end

  test "stacked, the pinned rows open and close", %{live: live} do
    run(live, "SELECT name FROM test_users ORDER BY name")
    live |> element("#pin-result-btn") |> render_click()
    live |> element("#pin-layout-stacked") |> render_click()

    refute has_element?(live, "#pinned-result-rows")
    live |> element("#pinned-result-toggle") |> render_click()
    assert has_element?(live, "#pinned-result-rows", "Charlie")

    live |> element("#pin-layout-split") |> render_click()
    assert has_element?(live, "#pinned-result", "Charlie")
  end

  test "restore the pinned query, and unpin", %{live: live} do
    run(live, "SELECT name FROM test_users ORDER BY name")
    live |> element("#pin-result-btn") |> render_click()
    run(live, "SELECT email FROM test_users")

    html = live |> element("#restore-pinned-sql-btn") |> render_click()
    assert html =~ "SELECT name FROM test_users ORDER BY name"

    live |> element("#unpin-result-btn") |> render_click()
    refute has_element?(live, "#pinned-result")
    refute has_element?(live, "#pin-compare-bar")
  end
end
