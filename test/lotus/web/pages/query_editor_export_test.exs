defmodule Lotus.Web.Pages.QueryEditorExportTest do
  # The CSV export of the query editor: the results as the person sees them,
  # with their filters and sort.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Query.Filter
  alias Lotus.Query.Sort

  test "the export link carries the results' filters and sort" do
    create_test_users()
    query = query_fixture(%{name: "Users", statement: "SELECT name, age FROM test_users"})

    {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
    html = render_async(live)
    [grid] = Regex.run(~r/id="(results-grid-[^"]+)"/, html, capture: :all_but_first)

    # The person's filter and sort, in the results grid.
    Masu.Test.filter(live, grid, [{"name", :neq, "Bob"}])
    render_async(live)
    Masu.Test.sort(live, grid, {"name", :desc})
    render_async(live)
    live |> with_target("#query-editor-page") |> render_click("export_csv", %{})

    assert_receive {_ref, {:push_event, "open-blank", %{location: location}}}
    %{"token" => token} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    {:ok, params} = Phoenix.Token.decrypt(Lotus.Web.Endpoint, "lotus_export", token)

    assert params["filters"] == [Filter.new("name", :neq, "Bob")]
    assert params["sorts"] == [Sort.new("name", :desc)]
  end

  test "without filters or sort, the export link has none" do
    create_test_users()

    query = query_fixture(%{name: "Users", statement: "SELECT name FROM test_users"})

    {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
    render_async(live)
    live |> with_target("#query-editor-page") |> render_click("export_csv", %{})

    assert_receive {_ref, {:push_event, "open-blank", %{location: location}}}
    %{"token" => token} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    {:ok, params} = Phoenix.Token.decrypt(Lotus.Web.Endpoint, "lotus_export", token)

    assert params["filters"] == []
    assert params["sorts"] == []
  end
end
