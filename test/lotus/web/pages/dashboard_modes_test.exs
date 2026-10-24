defmodule Lotus.Web.Pages.DashboardModesTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    query =
      query_fixture(%{name: "Revenue", statement: "SELECT 'North' AS region, 10 AS revenue"})

    chart =
      query_card_fixture(dashboard, query, %{
        title: "Revenue",
        visualization_config: %{
          "chart_type" => "bar",
          "x_field" => "region",
          "y_field" => "revenue"
        }
      })

    note = dashboard_card_fixture(dashboard, %{title: "Note", position: 1})

    {:ok, dashboard: dashboard, chart: chart, note: note, query: query}
  end

  test "a dashboard opens in view mode: no editor, and a card is not picked by a click", %{
    dashboard: dashboard,
    chart: chart
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)

    assert has_element?(live, "#dashboard-edit")
    refute has_element?(live, "#dashboard-edit-bar")
    refute has_element?(live, "#add-card-btn")
    refute has_element?(live, "#card-#{chart.id}[phx-click]")
    refute has_element?(live, ~s(#card-#{chart.id} button[phx-click="open_card_settings"]))
    # When its data was read.
    assert has_element?(live, "#dashboard-refreshed-at[phx-hook=RelativeTime]")
    # Full screen, for a wall or a TV.
    assert has_element?(live, ~s(#dashboard-fullscreen[phx-click*="lotus:fullscreen"]))
  end

  test "Edit opens the editor; Cancel puts the dashboard back as it was", %{
    dashboard: dashboard,
    note: note
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    live |> element("#dashboard-edit") |> render_click()

    assert has_element?(live, "#dashboard-edit-bar")
    assert has_element?(live, "#add-card-btn")
    refute has_element?(live, "#dashboard-fullscreen")
    assert has_element?(live, "#card-#{note.id}[phx-click]")

    live
    |> element("#card-#{note.id}-menu-items button", "Remove from dashboard")
    |> render_click()

    refute has_element?(live, "#card-#{note.id}")

    live |> element("#dashboard-cancel-edit") |> render_click()

    assert has_element?(live, "#card-#{note.id}")
    refute has_element?(live, "#dashboard-edit-bar")
    assert [_, _] = Lotus.list_dashboard_cards(dashboard.id)
  end

  test "Save writes the edits at once and leaves edit mode", %{dashboard: dashboard, note: note} do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    live |> element("#dashboard-edit") |> render_click()

    live
    |> element("#card-#{note.id}-menu-items button", "Remove from dashboard")
    |> render_click()

    live |> element("#dashboard-save") |> render_click()

    assert [_] = Lotus.list_dashboard_cards(dashboard.id)
    assert Lotus.get_dashboard!(dashboard.id).name == "Sales"
    refute has_element?(live, "#dashboard-edit-bar")
  end

  test "the edit bar's Text opens the add card dialog on text", %{dashboard: dashboard} do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    live |> element("#dashboard-edit") |> render_click()
    live |> element("#dashboard-edit-bar button", "Text") |> render_click()

    assert has_element?(
             live,
             ~s(#add-card-modal button[phx-value-type="text"][class*="border-pink-500"])
           )
  end

  test "a card's menu refreshes it and opens its query", %{
    dashboard: dashboard,
    chart: chart,
    query: query
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)

    menu = "#card-#{chart.id}-menu-items"
    assert has_element?(live, "#{menu} button", "Refresh")
    assert has_element?(live, "#{menu} button", "Save as PNG")
    assert has_element?(live, ~s(#{menu} a[href$="/queries/#{query.id}"]), "Open the query")
    refute has_element?(live, "#{menu} button", "Remove from dashboard")
  end

  test "the public dashboard has no editor, and no way to its queries", %{
    dashboard: dashboard,
    chart: chart
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    render_async(live)

    refute has_element?(live, "#dashboard-edit")
    refute has_element?(live, "#card-#{chart.id}-menu-items a")
    refute has_element?(live, "#card-#{chart.id}-menu-items button", "Refresh")
    assert has_element?(live, "#card-#{chart.id}-menu-items button", "Save as PNG")
  end

  test "a card's new result from live updates shows, on the public dashboard too", %{
    dashboard: dashboard,
    chart: chart
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    render_async(live)

    result = %Lotus.Result{
      columns: ["region", "revenue"],
      rows: [["Live North", 99]],
      num_rows: 1
    }

    send(live.pid, {:card_result, chart.id, result})

    assert render(live) =~ "Live North"
  end

  test "a public dashboard goes full screen too", %{dashboard: dashboard} do
    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    assert has_element?(live, ~s(#dashboard-fullscreen[phx-click*="lotus:fullscreen"]))
  end
end
