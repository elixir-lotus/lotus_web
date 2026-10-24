defmodule Lotus.Web.Pages.CardMaximizeTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    query =
      query_fixture(%{name: "Revenue", statement: "SELECT 'North' AS region, 10 AS revenue"})

    card =
      query_card_fixture(dashboard, query, %{
        title: "Revenue",
        visualization_config: %{
          "chart_type" => "bar",
          "x_field" => "region",
          "y_field" => "revenue"
        }
      })

    {:ok, dashboard: dashboard, card: card}
  end

  for {view, path} <- [
        {"the dashboard", "/lotus/dashboards/:id"},
        {"the public dashboard", "/lotus/public/:token"}
      ] do
    test "a chart card maximizes over #{view}, and closes again", %{
      dashboard: dashboard,
      card: card
    } do
      path =
        unquote(path)
        |> String.replace(":id", to_string(dashboard.id))
        |> String.replace(":token", to_string(dashboard.public_token))

      {:ok, live, _html} = live(build_conn(), path)
      render_async(live)

      refute has_element?(live, "#card-#{card.id}-maximized")

      live |> element("#card-#{card.id}-maximize") |> render_click()

      assert has_element?(live, "#card-#{card.id}-maximized[role=dialog]", "Revenue")
      assert has_element?(live, "#card-#{card.id}-maximized #chart-max-#{card.id}")
      # The card under it is not selected by the click.
      refute has_element?(live, "#card-#{card.id}.border-pink-500")

      live |> element("#card-#{card.id}-restore") |> render_click()

      refute has_element?(live, "#card-#{card.id}-maximized")
      assert has_element?(live, "#chart-#{card.id}")
    end
  end

  test "a chart's data is in its place unless the card says otherwise", %{
    dashboard: dashboard,
    card: card
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert render_async(live) =~ ~s(id="chart-#{card.id}-data")
    assert has_element?(live, "#chart-#{card.id} .fude-data-toggle button[aria-pressed]")
  end
end
