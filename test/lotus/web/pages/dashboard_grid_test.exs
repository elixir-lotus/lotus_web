defmodule Lotus.Web.Pages.DashboardGridTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    a = dashboard_card_fixture(dashboard, %{title: "A", layout: %{x: 0, y: 0, w: 6, h: 4}})

    b =
      dashboard_card_fixture(dashboard, %{
        title: "B",
        position: 1,
        layout: %{x: 6, y: 0, w: 6, h: 4, folded: true}
      })

    {:ok, dashboard: dashboard, a: a, b: b}
  end

  test "the grid has its hook, and each card its place and how it starts", %{
    dashboard: dashboard,
    a: a,
    b: b
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    assert has_element?(
             live,
             ~s(#dashboard-grid[phx-hook="DashboardGrid"][data-dashboard-id="#{dashboard.id}"][data-editing="false"])
           )

    assert has_element?(
             live,
             ~s(#card-#{a.id}[data-x="0"][data-y="0"][data-w="6"][data-h="4"][data-folded-default="false"])
           )

    assert has_element?(live, ~s(#card-#{b.id}[data-folded-default="true"][data-folded="true"]))

    assert has_element?(
             live,
             ~s(#card-#{b.id} button[data-card-fold][aria-controls="card-#{b.id}-body"])
           )

    # Moving and resizing are for edit mode.
    refute has_element?(live, "[data-card-handle]")
    refute has_element?(live, "[data-card-resize]")
  end

  test "in edit mode, cards move and resize, and Save keeps their places", %{
    dashboard: dashboard,
    a: a,
    b: b
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    live |> element("#dashboard-edit") |> render_click()

    assert has_element?(live, ~s(#dashboard-grid[data-editing="true"]))
    assert has_element?(live, "#card-#{a.id} [data-card-handle]")
    assert has_element?(live, "#card-#{a.id} [data-card-resize]")
    assert has_element?(live, "#dashboard-tidy", "Tidy up")
    # Open in edit mode: a card that starts folded says so.
    assert has_element?(live, ~s(#card-#{b.id}[data-folded="false"]), "Starts folded")

    live
    |> with_target("#dashboard-editor")
    |> render_click("update_layouts", %{
      "layouts" => %{
        to_string(a.id) => %{"x" => 6, "y" => 0, "w" => 6, "h" => 4},
        to_string(b.id) => %{"x" => 0, "y" => 0, "w" => 99, "h" => 2}
      }
    })

    assert has_element?(live, ~s(#card-#{a.id}[data-x="6"]))
    # A width is kept on the 12 columns.
    assert has_element?(live, ~s(#card-#{b.id}[data-x="0"][data-w="12"][data-h="2"]))

    live
    |> with_target("#dashboard-editor")
    |> render_click("fold_card", %{"card_id" => to_string(a.id), "folded" => true})

    assert has_element?(live, ~s(#card-#{a.id}[data-folded-default="true"]))

    live |> element("#dashboard-save") |> render_click()

    layouts = Map.new(Lotus.list_dashboard_cards(dashboard.id), &{&1.title, &1.layout})
    assert %{x: 6, w: 6, folded: true} = layouts["A"]
    assert %{x: 0, w: 12, h: 2, folded: true} = layouts["B"]
  end

  test "a card's menu sets its width in edit mode", %{dashboard: dashboard, a: a} do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    refute has_element?(live, ~s(#card-#{a.id}-menu-items button[title="6 of 12 columns"]))

    live |> element("#dashboard-edit") |> render_click()

    assert has_element?(
             live,
             ~s(#card-#{a.id}-menu-items button[title="6 of 12 columns"][aria-pressed="true"])
           )
  end

  test "a viewer who may not manage cannot move cards", %{dashboard: dashboard, a: a} do
    {:ok, live, _html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")

    live
    |> with_target("#dashboard-editor")
    |> render_click("update_layouts", %{"layouts" => %{to_string(a.id) => %{"x" => 6}}})

    assert render(live) =~ "Restricted: manage_dashboard"
    assert has_element?(live, ~s(#card-#{a.id}[data-x="0"]))
  end

  test "a chart fills its card", %{dashboard: dashboard} do
    query = query_fixture(%{statement: "SELECT 'N' AS r, 1 AS v"})

    card =
      query_card_fixture(dashboard, query, %{
        position: 2,
        layout: %{x: 0, y: 4, w: 12, h: 4},
        visualization_config: %{"chart_type" => "bar", "x_field" => "r", "y_field" => "v"}
      })

    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    render_async(live)

    assert has_element?(
             live,
             "#chart-#{card.id} .fude-plot-fill, #chart-#{card.id} .fude-frame-fill"
           )
  end
end
