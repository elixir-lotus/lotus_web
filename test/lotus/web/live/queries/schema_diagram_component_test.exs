defmodule Lotus.Web.Queries.SchemaDiagramComponentTest do
  use Lotus.Web.Case

  import ExUnit.CaptureLog

  alias Lotus.Web.Queries.SchemaDiagramComponent

  defp open_explorer do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    render_async(live)
    live |> element("[phx-click='toggle_schema_explorer']") |> render_click()
    live
  end

  # The diagram is in a portal (a <template>): its HTML is read whole.
  defp diagram(live), do: live |> element("#schema-diagram-portal") |> render()

  defp close(live),
    do: live |> with_target("#query-editor-page") |> render_click("close_schema_diagram")

  test "the explorer opens the diagram of the active schema, over the page" do
    live = open_explorer()

    assert has_element?(live, "#open-schema-diagram[phx-value-database='public']")
    refute has_element?(live, "#schema-diagram-portal")

    live |> element("#open-schema-diagram") |> render_click()
    render_async(live)
    html = diagram(live)

    assert html =~ ~s(role="dialog")
    assert html =~ "lotus-diagram"

    # The canvas: arranged only, laid out as it opens, at a readable zoom.
    assert html =~ ~s(id="schema-diagram-canvas")
    assert html =~ ~s(data-tidy="true")
    assert html =~ "&quot;arrange&quot;:true"
    assert html =~ "&quot;fit&quot;:&quot;readable&quot;"
    assert html =~ "&quot;algorithm&quot;:&quot;force&quot;"

    # The tables of public, and the foreign key between two of them.
    assert html =~ ~s(data-id="test_posts")
    assert html =~ ~s(data-id="test_users")
    refute html =~ ~s(data-id="customers")

    assert html =~
             ~s(data-source="test_posts" data-source-handle="user_id" data-target="test_users")

    # Nothing to edit in a table.
    refute html =~ "hakushi-kit-field"
  end

  test "it closes, from its button and from Escape (the page's event)" do
    live = open_explorer()

    live |> element("#open-schema-diagram") |> render_click()
    render_async(live)
    html = diagram(live)
    assert html =~ ~s(phx-click="close_schema_diagram")
    assert html =~ ~s(phx-window-keydown="close_schema_diagram" phx-key="Escape")

    close(live)
    refute has_element?(live, "#schema-diagram-portal")
  end

  describe "load/4" do
    test "the active schema of a source the user may query" do
      assert {:ok, %{schema: "reporting", graph: graph}} =
               SchemaDiagramComponent.load("public", "reporting", ["public"], [])

      assert Hakushi.Graph.node(graph, "orders")
    end

    test "not a source the user may not query" do
      assert {:error, :unavailable} =
               SchemaDiagramComponent.load("public", nil, ["reporting"], [])
    end

    test "not a source that does not exist" do
      capture_log(fn ->
        assert {:error, :unavailable} =
                 SchemaDiagramComponent.load("nowhere", nil, ["nowhere"], [])
      end)
    end
  end
end
