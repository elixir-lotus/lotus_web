defmodule Lotus.Web.Pages.QueriesPageTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  describe "navbar" do
    test "shows New button on protected routes" do
      {:ok, live, _html} = live(build_conn(), "/lotus")

      assert has_element?(live, "#new-item-dropdown button", "New")
    end
  end

  describe "empty state" do
    test "shows message when no queries exist" do
      {:ok, _live, html} = live(build_conn(), "/lotus")

      assert html =~ "No saved queries yet."
    end
  end

  describe "with queries" do
    setup do
      query1 = query_fixture(%{name: "All users"})
      query2 = query_fixture(%{name: "Active customers"})

      {:ok, live, _html} = live(build_conn(), "/lotus")

      {:ok, live: live, query1: query1, query2: query2}
    end

    test "lists saved queries", %{live: live, query1: query1, query2: query2} do
      assert has_query?(live, query1.name)
      assert has_query?(live, query2.name)
    end

    test "navigating to a saved query", %{live: live, query1: query1} do
      {:ok, query_live, _html} =
        live
        |> element("a", query1.name)
        |> render_click()
        |> follow_redirect(build_conn())

      assert render(query_live) =~ query1.name
      assert render(query_live) =~ query1.statement
    end
  end

  describe "dashboards tab" do
    setup do
      sales = dashboard_fixture(%{name: "Sales", description: "Revenue by region"})
      dashboard_card_fixture(sales, %{position: 0})
      dashboard_card_fixture(sales, %{position: 1})

      marketing = dashboard_fixture(%{name: "Marketing"})
      dashboard_card_fixture(marketing, %{position: 0})

      {:ok, sales: sales, marketing: marketing}
    end

    test "a gallery of tiles, each with its layout sketched and its cards counted", %{
      sales: sales,
      marketing: marketing
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus?tab=dashboards")

      assert has_element?(
               live,
               "#dashboard-tile-#{sales.id} svg.lotus-sketch rect.lotus-sketch-card"
             )

      assert has_element?(live, "#dashboard-tile-#{sales.id}", "2 cards")
      assert has_element?(live, "#dashboard-tile-#{marketing.id}", "1 card")
      assert has_element?(live, "#dashboards-list[phx-hook=ListView][data-view=grid]")
    end

    test "the table shows the same dashboards, a sketch beside each name", %{sales: sales} do
      {:ok, live, _html} = live(build_conn(), "/lotus?tab=dashboards")

      live |> element("#dashboards-view-list") |> render_click()

      refute has_element?(live, "#dashboards-gallery")
      assert has_element?(live, ~s|#dashboards-table tr|, "Sales")
      assert has_element?(live, ~s|#dashboards-table tr|, "Marketing")
      assert has_element?(live, "#dashboards-table svg.lotus-sketch-mini")
      assert render(live) =~ ~r/Sales.*?\b2\b/s
      assert has_element?(live, "#dashboard-#{sales.id}-updated-row[phx-hook=RelativeTime]")
    end

    test "the chosen view stays as the LiveView renders again" do
      {:ok, live, _html} = live(build_conn(), "/lotus?tab=dashboards")
      live |> element("#dashboards-view-list") |> render_click()

      # A render of the LiveView itself (a flash) hands the page its assigns.
      send(live.pid, {:put_flash, [:info, "Saved"]})

      assert has_element?(live, "#dashboards-list[data-view=list]")
      assert has_element?(live, "#dashboards-table")
    end

    test "search keeps the dashboards with its words, in name or description", %{
      sales: sales,
      marketing: marketing
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus?tab=dashboards")

      live
      |> element("#dashboards-search")
      |> render_change(%{"search" => "region", "sort" => "name"})

      assert has_element?(live, "#dashboard-tile-#{sales.id}")
      refute has_element?(live, "#dashboard-tile-#{marketing.id}")

      live
      |> element("#dashboards-search")
      |> render_change(%{"search" => "nothing like it", "sort" => "name"})

      assert render(live) =~ "No dashboard has these words."
    end

    test "a tile's Duplicate copies the dashboard and opens the copy", %{sales: sales} do
      {:ok, live, _html} = live(build_conn(), "/lotus?tab=dashboards")

      assert {:error, {:live_redirect, %{to: to}}} =
               live |> element("#dashboard-tile-#{sales.id}-duplicate") |> render_click()

      [_, id] = Regex.run(~r{/dashboards/(\d+)$}, to)
      assert Lotus.get_dashboard!(String.to_integer(id)).name == "Sales (copy)"
    end
  end

  defp has_query?(live, query_name) do
    has_element?(live, "#queries-table", query_name)
  end
end
