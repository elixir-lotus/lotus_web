defmodule Lotus.Web.Pages.QueriesPageTest do
  use Lotus.Web.Case

  doctest Lotus.Web.Queries.QueryList

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

  describe "a query's SQL, as its list shows it" do
    alias Lotus.Web.Queries.QueryList

    test "a one-line statement has its clauses on lines; a JOIN stays with its kind" do
      sql =
        "SELECT u.name FROM posts p LEFT JOIN users u ON u.id = p.user_id JOIN tags t ON true WHERE p.id = 1"

      lines =
        sql
        |> QueryList.tokens(5)
        |> Enum.chunk_by(&(&1 == :newline))
        |> Enum.reject(&(&1 == [:newline]))
        |> Enum.map(fn tokens -> Enum.map_join(tokens, fn {_kind, text} -> text end) end)

      assert lines == [
               "SELECT u.name",
               "FROM posts p",
               "LEFT JOIN users u ON u.id = p.user_id",
               "JOIN tags t ON true",
               "WHERE p.id = 1"
             ]

      refute :newline in QueryList.tokens(sql, :one_line)
    end
  end

  describe "queries gallery" do
    setup do
      chart =
        query_fixture(%{
          name: "Orders by status",
          description: "Orders per status",
          statement: "SELECT status, COUNT(*) AS n FROM orders GROUP BY status"
        })

      {:ok, _} =
        Lotus.create_visualization(chart, %{
          name: "Chart",
          position: 0,
          config: %{"chart_type" => "bar", "x_field" => "status", "y_field" => "n"}
        })

      plain =
        query_fixture(%{
          name: "Users",
          statement: "SELECT name, '<b>x</b>' AS tag FROM users\nWHERE name = {{name}}",
          variables: [%{name: "name", type: :text}],
          data_source: "reporting"
        })

      dashboard = dashboard_fixture(%{name: "Sales"})
      query_card_fixture(dashboard, chart, %{title: "Orders"})

      {:ok, chart: chart, plain: plain}
    end

    test "a tile sketches the chart a query is saved with, or shows its SQL", %{
      chart: chart,
      plain: plain
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus")

      assert has_element?(live, "#query-tile-#{chart.id} svg.lotus-sketch rect.lotus-sketch-mark")
      assert has_element?(live, "#query-tile-#{chart.id}", "In 1 dashboard")
      refute has_element?(live, "#query-tile-#{chart.id} pre")

      assert has_element?(live, "#query-tile-#{plain.id} pre span", "SELECT")
      assert has_element?(live, "#query-tile-#{plain.id} pre span", "{{name}}")
      assert has_element?(live, "#query-tile-#{plain.id} span", "{{name}}")
      assert has_element?(live, "#query-tile-#{plain.id}", "reporting")

      # The SQL is text: its markup is escaped, never rendered.
      html = live |> element("#query-tile-#{plain.id} pre") |> render()
      assert html =~ "&lt;b&gt;x&lt;/b&gt;"
      refute html =~ "<b>x</b>"
    end

    test "the list, search and the source chips", %{chart: chart, plain: plain} do
      {:ok, live, _html} = live(build_conn(), "/lotus")

      live |> element("#queries-view-list") |> render_click()
      assert has_element?(live, "#query-row-#{chart.id}", "Orders by status")
      assert has_element?(live, "#query-row-#{plain.id} code span", "SELECT")

      live |> element("button[phx-value-source=reporting]") |> render_click()
      assert has_element?(live, "#query-row-#{plain.id}")
      refute has_element?(live, "#query-row-#{chart.id}")

      live |> element("button[phx-value-source='']") |> render_click()

      live
      |> element("#queries-search")
      |> render_change(%{"search" => "per status", "source" => ""})

      assert has_element?(live, "#query-row-#{chart.id}")
      refute has_element?(live, "#query-row-#{plain.id}")
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
    has_element?(live, "#queries-list", query_name)
  end
end
