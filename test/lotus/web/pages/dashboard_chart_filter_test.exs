defmodule Lotus.Web.Pages.DashboardChartFilterTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  doctest Lotus.Web.Dashboards.ChartFilters

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    query =
      query_fixture(%{
        name: "Revenue",
        statement: "SELECT 'North' AS region, 10 AS revenue UNION ALL SELECT 'South', 20"
      })

    chart =
      query_card_fixture(dashboard, query, %{
        title: "Revenue",
        visualization_config: %{
          "chart_type" => "bar",
          "x_field" => "region",
          "y_field" => "revenue"
        }
      })

    {:ok, region} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "region",
        label: "Region",
        filter_type: :text,
        widget: :input,
        position: 0
      })

    {:ok, dashboard: dashboard, chart: chart, region: region}
  end

  test "a click on a bar sets the filter of its field; a click on it again clears it", %{
    dashboard: dashboard,
    chart: chart
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)

    chart_el = element(live, "#chart-#{chart.id}[data-fude-select=chart_select]")
    assert has_element?(live, "#chart-#{chart.id}[title='Click the chart to filter by Region']")

    render_hook(chart_el, "chart_select", %{
      "id" => "chart-#{chart.id}",
      "x" => "North",
      "y" => 10
    })

    assert has_element?(live, ~s(#filter-bar input[name="filter[region]"][value="North"]))
    # Its bar stands out, the others faded.
    assert has_element?(live, ~s(#chart-#{chart.id}[data-fude-selected='{"x":"North"}']))

    render_hook(chart_el, "chart_select", %{
      "id" => "chart-#{chart.id}",
      "x" => "North",
      "y" => 10
    })

    refute has_element?(live, ~s(#filter-bar input[name="filter[region]"][value="North"]))
    refute has_element?(live, "#chart-#{chart.id}[data-fude-selected]")
  end

  test "a chart with no filter of its fields, and a chart in edit mode, send no click", %{
    dashboard: dashboard,
    chart: chart,
    region: region
  } do
    {:ok, _} = Lotus.update_dashboard_filter(region, %{name: "area"})
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)
    refute has_element?(live, "#chart-#{chart.id}[data-fude-select]")

    {:ok, _} = Lotus.update_dashboard_filter(region, %{name: "region"})
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)
    live |> element("#dashboard-edit") |> render_click()
    render_async(live)
    refute has_element?(live, "#chart-#{chart.id}[data-fude-select]")
  end

  test "Open the query takes the card's values to the query editor", %{dashboard: dashboard} do
    query =
      query_fixture(%{
        name: "By region",
        statement: "SELECT {{region}} AS region",
        variables: [%{name: "region", type: :text}]
      })

    card = query_card_fixture(dashboard, query, %{title: "One region", position: 1})
    [region] = Lotus.list_dashboard_filters(dashboard.id)
    {:ok, _} = Lotus.create_filter_mapping(card, region, "region")

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}?region=North")

    assert has_element?(
             live,
             ~s(#card-#{card.id}-menu-items a[href$="/queries/#{query.id}?vars[region]=North"])
           )
  end

  test "a public dashboard filters by a click too", %{dashboard: dashboard, chart: chart} do
    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    render_async(live)

    live
    |> element("#chart-#{chart.id}[data-fude-select=chart_select]")
    |> render_hook("chart_select", %{"id" => "chart-#{chart.id}", "x" => "South"})

    assert has_element?(live, ~s(#filter-bar input[name="filter[region]"][value="South"]))
  end
end
