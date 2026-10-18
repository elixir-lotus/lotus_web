defmodule Lotus.Web.Pages.QueryEditorMasuTest do
  # The results table as Masu's grid (config :lotus_web, results_table:
  # :masu): the grid shows the page Lotus read, and Lotus runs the sort and
  # the filters the person sets in it.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:lotus_web, :results_table, :masu)
    on_exit(fn -> Application.delete_env(:lotus_web, :results_table) end)

    create_test_users()

    query =
      query_fixture(%{
        name: "Users",
        statement: "SELECT name, email FROM test_users ORDER BY name"
      })

    {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
    html = render_async(live)
    [grid] = Regex.run(~r/id="(results-grid-[^"]+)"/, html, capture: :all_but_first)

    %{live: live, grid: grid}
  end

  test "the grid shows the rows Lotus read", %{live: live, grid: grid} do
    assert names(live, grid) == ["Alice", "Bob", "Charlie"]
    refute render(live) =~ ~s(id="query-results")
  end

  test "Lotus runs the grid's sort", %{live: live, grid: grid} do
    Masu.Test.sort(live, grid, {"name", :desc})
    render_async(live)

    assert names(live, grid) == ["Charlie", "Bob", "Alice"]
  end

  test "Lotus runs the grid's filters", %{live: live, grid: grid} do
    Masu.Test.filter(live, grid, [{"name", :starts_with, "B"}])
    render_async(live)

    assert names(live, grid) == ["Bob"]
  end

  test "the grid offers only the filters Lotus runs", %{live: live, grid: grid} do
    assert_raise ExUnit.AssertionError, ~r/does not filter by not_contains/, fn ->
      Masu.Test.filter(live, grid, [{"name", :not_contains, "B"}])
    end

    assert names(live, grid) == ["Alice", "Bob", "Charlie"]
  end

  test "the grid's words are in the dashboard's language" do
    query = query_fixture(%{name: "Users FR", statement: "SELECT name FROM test_users"})

    conn = Plug.Test.init_test_session(build_conn(), %{"lotus_locale" => "fr"})
    {:ok, live, _html} = live(conn, "/lotus/queries/#{query.id}")
    html = render_async(live)

    [messages] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".masu")
      |> LazyHTML.attribute("data-masu-messages")

    messages = JSON.decode!(messages)
    assert messages["apply"] == "Appliquer"
    assert messages["op_contains"] == "contient"
  end

  defp names(live, grid), do: live |> Masu.Test.rows(grid) |> Enum.map(& &1["name"])
end
