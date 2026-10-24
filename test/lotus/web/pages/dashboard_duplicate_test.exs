defmodule Lotus.Web.Pages.DashboardDuplicateTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  test "Duplicate copies the dashboard, its filters, cards and connections, and opens the copy" do
    dashboard = public_dashboard_fixture(%{name: "Sales", description: "By region"})

    query =
      query_fixture(%{
        statement: "SELECT {{region}} AS region",
        variables: [%{name: "region", type: :text}]
      })

    card =
      query_card_fixture(dashboard, query, %{
        title: "Regions",
        visualization_config: %{
          "chart_type" => "bar",
          "x_field" => "region",
          "y_field" => "region"
        }
      })

    {:ok, country} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "country",
        label: "Country",
        filter_type: :text,
        widget: :input,
        position: 0
      })

    # It depends on the country: the copy's depends on the copy's country.
    {:ok, region} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "region",
        label: "Region",
        filter_type: :text,
        widget: :select,
        source_query_id: query.id,
        depends_on_filter_id: country.id,
        position: 1
      })

    {:ok, _} = Lotus.create_filter_mapping(card, region, "region")

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    assert {:error, {:live_redirect, %{to: to}}} =
             live |> element("#dashboard-duplicate") |> render_click()

    [_, id] = Regex.run(~r{/dashboards/(\d+)$}, to)
    copy = Lotus.get_dashboard!(String.to_integer(id))

    assert copy.name == "Sales (copy)"
    assert copy.description == "By region"
    assert copy.public_token in [nil, ""] or copy.public_token != dashboard.public_token

    filters = Map.new(Lotus.list_dashboard_filters(copy.id), &{&1.name, &1})
    assert filters["region"].depends_on_filter_id == filters["country"].id

    [copied] = Lotus.list_dashboard_cards(copy.id)
    assert copied.title == "Regions"
    assert copied.visualization_config["chart_type"] == "bar"

    assert [%{variable_name: "region", filter_id: filter_id}] =
             Lotus.list_card_filter_mappings(copied.id)

    assert filter_id == filters["region"].id
    # The original is as it was.
    assert [_] = Lotus.list_dashboard_cards(dashboard.id)
  end
end
