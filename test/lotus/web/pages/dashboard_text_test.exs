defmodule Lotus.Web.Pages.DashboardTextTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    {:ok, _filter} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "region",
        label: "Region",
        filter_type: :text,
        widget: :input,
        default_value: "North",
        position: 0
      })

    {:ok, dashboard: dashboard}
  end

  test "a text card writes the filters' values", %{dashboard: dashboard} do
    card =
      dashboard_card_fixture(dashboard, %{
        title: "About",
        content: %{"text" => "Revenue in **{{region}}**"}
      })

    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    assert has_element?(live, "#card-#{card.id} strong", "North")

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}?region=South")
    assert has_element?(live, "#card-#{card.id} strong", "South")
  end

  test "a text card that is one heading has no frame, and does not fold", %{dashboard: dashboard} do
    card = dashboard_card_fixture(dashboard, %{title: nil, content: %{"text" => "## Revenue"}})

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    assert has_element?(live, ~s(#card-#{card.id}[data-heading="true"] h2), "Revenue")
    refute has_element?(live, "#card-#{card.id} [data-card-fold]")
  end

  test "edit mode writes a heading card as a text card, and Save keeps it", %{
    dashboard: dashboard
  } do
    card =
      dashboard_card_fixture(dashboard, %{
        card_type: :heading,
        title: "Welcome",
        content: %{"text" => "Overview"}
      })

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    live |> element("#dashboard-edit") |> render_click()

    assert has_element?(live, "#card-#{card.id} #card-text-#{card.id}[phx-hook='Kotoba']")

    live |> element("#dashboard-save") |> render_click()

    assert [%{card_type: :text, title: nil, content: %{"text" => "## Overview"}}] =
             Lotus.list_dashboard_cards(dashboard.id)

    # Still a heading: no frame.
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    assert has_element?(live, ~s(#card-#{card.id}[data-heading="true"]))
  end

  test "Add Card offers a chart, a text and a link, not a heading", %{dashboard: dashboard} do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    live |> element("#dashboard-edit") |> render_click()
    live |> element("#dashboard-edit-bar button", "Text") |> render_click()

    assert has_element?(live, ~s(#add-card-modal button[phx-value-type="text"]))
    refute has_element?(live, ~s(#add-card-modal button[phx-value-type="heading"]))
  end
end
