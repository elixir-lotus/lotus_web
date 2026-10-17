defmodule Lotus.Web.Queries.SchemaExplorerComponentTest do
  use Lotus.Web.Case

  defp open_table(table) do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    render_async(live)

    live |> element("[phx-click='toggle_schema_explorer']") |> render_click()

    live
    |> element("[phx-click='select_table'][phx-value-table='#{table}']")
    |> render_click()

    live
  end

  test "a foreign key column shows the column it references" do
    live = open_table("test_posts")

    assert has_element?(live, "[data-references='test_users.id']")
    assert live |> element("[data-references]") |> render() =~ "→ test_users.id"
  end

  test "a column that is not a foreign key shows no reference" do
    live = open_table("test_users")

    refute has_element?(live, "[data-references]")
  end
end
