defmodule Lotus.Web.Pages.DashboardFilterConnectTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  doctest Lotus.Web.Dashboards.FilterConnections

  setup do
    dashboard = dashboard_fixture(%{name: "Sales"})

    region_query =
      query_fixture(%{
        name: "By region",
        statement: "SELECT {{region}} AS region, 10 AS revenue",
        variables: [%{name: "region", type: :text, label: "Region"}]
      })

    other_query =
      query_fixture(%{
        name: "By country",
        statement: "SELECT {{country}} AS country",
        variables: [%{name: "country", type: :text}]
      })

    region_card = query_card_fixture(dashboard, region_query, %{title: "Regions"})
    country_card = query_card_fixture(dashboard, other_query, %{title: "Countries", position: 1})
    note = dashboard_card_fixture(dashboard, %{title: "Note", position: 2})

    {:ok, dashboard: dashboard, region_card: region_card, country_card: country_card, note: note}
  end

  test "a new filter connects to the cards with a variable of its name, and shows the cards", %{
    dashboard: dashboard,
    region_card: region_card,
    country_card: country_card,
    note: note
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    add_filter(live, %{"name" => "region", "label" => "Region"})

    # Connect mode: the filter, a hint, and on each card what it sets.
    assert has_element?(live, "#filter-connect-hint", "Region")
    assert has_element?(live, "#filter-region-connect", "1 card")

    assert has_element?(
             live,
             "#card-#{region_card.id}-connect[data-connected=true] option[value=region][selected]"
           )

    assert has_element?(live, "#card-#{country_card.id}-connect[data-connected=false]")
    assert has_element?(live, "#card-#{note.id}-connect", "{{region}}")

    live |> element("#filter-connect-done") |> render_click()
    refute has_element?(live, "[id$='-connect'].lotus-card-connect")

    live |> element("#dashboard-save") |> render_click()

    [filter] = Lotus.list_dashboard_filters(dashboard.id)

    assert [%{variable_name: "region", filter_id: filter_id}] =
             Lotus.list_card_filter_mappings(region_card.id)

    assert filter_id == filter.id
    assert [] = Lotus.list_card_filter_mappings(country_card.id)
  end

  test "a card is connected from its overlay, and the filter counts it", %{
    dashboard: dashboard,
    country_card: country_card
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    add_filter(live, %{"name" => "place", "label" => "Place"})

    assert has_element?(live, "#filter-place-connect", "Not connected")

    live
    |> element("#card-#{country_card.id}-connect-form")
    |> render_change(%{
      "card-id" => to_string(country_card.id),
      "filter-name" => "place",
      "filter_mapping" => %{"place" => "country"}
    })

    assert has_element?(live, "#filter-place-connect", "1 card")
    assert has_element?(live, "#card-#{country_card.id}-connect[data-connected=true]")

    # The filter's button leaves connect mode, and opens it again.
    live |> element("#filter-place-connect") |> render_click()
    refute has_element?(live, "#filter-connect-hint")
    live |> element("#filter-place-connect") |> render_click()
    assert has_element?(live, "#filter-connect-hint")
  end

  test "a date range connects to a card's start and end", %{dashboard: dashboard} do
    query =
      query_fixture(%{
        statement: "SELECT {{start_date}} AS a, {{end_date}} AS b",
        variables: [%{name: "start_date", type: :date}, %{name: "end_date", type: :date}]
      })

    card = query_card_fixture(dashboard, query, %{title: "Period", position: 3})

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    add_filter(live, %{
      "name" => "period",
      "label" => "Period",
      "filter_type" => "date_range",
      "widget" => "date_range_picker"
    })

    assert has_element?(live, "#card-#{card.id}-connect[data-connected=true]")

    live |> element("#dashboard-save") |> render_click()

    assert card.id
           |> Lotus.list_card_filter_mappings()
           |> Enum.map(&{&1.variable_name, &1.transform})
           |> Enum.sort() == [
             {"end_date", %{"type" => "date_range_end"}},
             {"start_date", %{"type" => "date_range_start"}}
           ]
  end

  test "a filter may not take the name of another", %{dashboard: dashboard} do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    add_filter(live, %{"name" => "region", "label" => "Region"})

    live |> element("#dashboard-filter-bar button", "Add Filter") |> render_click()

    html =
      live
      |> element("#dashboard-filter-form")
      |> render_submit(%{
        "filter" => %{
          "name" => "region",
          "label" => "Area",
          "filter_type" => "text",
          "widget" => "input"
        }
      })

    assert html =~ "is the name of another filter"
    assert has_element?(live, "#filter-modal")
  end

  defp add_filter(live, params) do
    live |> element("#dashboard-edit") |> render_click()
    live |> element("#dashboard-edit-bar button", "Filter") |> render_click()

    live
    |> element("#dashboard-filter-form")
    |> render_submit(%{
      "filter" => Map.merge(%{"filter_type" => "text", "widget" => "input"}, params)
    })
  end
end
