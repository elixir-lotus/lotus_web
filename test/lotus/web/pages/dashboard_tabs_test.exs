defmodule Lotus.Web.Pages.DashboardTabsTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Web.Dashboards.Tabs

  setup do
    dashboard = public_dashboard_fixture(%{name: "Sales"})
    a = dashboard_card_fixture(dashboard, %{title: "Overview note", position: 0})
    b = dashboard_card_fixture(dashboard, %{title: "Detail note", position: 1})
    {:ok, dashboard: dashboard, a: a, b: b}
  end

  test "tabs are added, named and filled in edit mode, and kept by Save", %{
    dashboard: dashboard,
    a: a,
    b: b
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    # One page: no tabs out of edit mode.
    refute has_element?(live, "#dashboard-tabs")

    live |> element("#dashboard-edit") |> render_click()
    live |> element("#dashboard-add-tab") |> render_click()

    [first, second] = tabs_of(live)
    # The new tab is shown, empty, and takes a name in place.
    refute has_element?(live, "#card-#{a.id}")

    live
    |> element("#dashboard-tab-#{second}-name")
    |> render_change(%{"tab" => second, "name" => "Details"})

    live |> element("#dashboard-tab-#{first}") |> render_click()
    assert has_element?(live, "#card-#{b.id}")

    live
    |> element("#card-#{b.id}-menu-items button", "Details")
    |> render_click()

    refute has_element?(live, "#card-#{b.id}")
    assert has_element?(live, "#card-#{a.id}")

    live |> element("#dashboard-save") |> render_click()

    saved = Lotus.get_dashboard!(dashboard.id)
    assert [%{"id" => ^first}, %{"id" => ^second, "name" => "Details"}] = saved.settings["tabs"]
    cards = Map.new(Lotus.list_dashboard_cards(dashboard.id), &{&1.id, &1})
    assert cards[b.id].layout.tab == second
    assert cards[a.id].layout.tab in [nil, first]

    # Out of edit mode, the tabs show, and a tab its cards.
    assert has_element?(live, "#dashboard-tab-#{second}", "Details")
    live |> element("#dashboard-tab-#{second}") |> render_click()
    assert has_element?(live, "#card-#{b.id}")
    refute has_element?(live, "#card-#{a.id}")
  end

  test "removing the second of two tabs leaves one page, its cards on it", %{
    dashboard: dashboard,
    a: a,
    b: b
  } do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    live |> element("#dashboard-edit") |> render_click()
    live |> element("#dashboard-add-tab") |> render_click()
    [first, second] = tabs_of(live)

    live |> element("#dashboard-tab-#{first}") |> render_click()
    live |> element("#card-#{b.id}-menu-items button", "Tab 2") |> render_click()

    live |> element("#dashboard-tab-#{second}") |> render_click()

    live
    |> element("#dashboard-tab-#{second}-name button[phx-click=delete_tab]")
    |> render_click()

    assert has_element?(live, "#card-#{a.id}")
    assert has_element?(live, "#card-#{b.id}")

    live |> element("#dashboard-save") |> render_click()
    refute has_element?(live, "#dashboard-tabs")
    assert Lotus.get_dashboard!(dashboard.id).settings["tabs"] in [nil, []]
  end

  test "a public dashboard shows its tabs", %{dashboard: dashboard, a: a, b: b} do
    {:ok, dashboard} =
      Lotus.update_dashboard(dashboard, %{
        settings: %{
          "tabs" => [%{"id" => "one", "name" => "One"}, %{"id" => "two", "name" => "Two"}]
        }
      })

    {:ok, _} = Lotus.update_dashboard_card(b, %{layout: %{x: 0, y: 0, w: 6, h: 2, tab: "two"}})

    {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    assert has_element?(live, "#card-#{a.id}")
    refute has_element?(live, "#card-#{b.id}")

    live |> element("#dashboard-tab-two") |> render_click()
    assert has_element?(live, "#card-#{b.id}")
    refute has_element?(live, "#card-#{a.id}")
  end

  describe "Tabs" do
    test "a dashboard with no tabs has its cards on one page" do
      dashboard = %{settings: %{}, cards: [%{id: 1, layout: %{tab: nil}}]}
      assert Tabs.list(dashboard) == []
      assert Tabs.current(dashboard, "gone") == nil
      assert [%{id: 1}] = Tabs.cards(dashboard, nil)
    end

    test "a card with no tab is on the first, and a move puts it under the cards there" do
      dashboard = %{
        settings: %{"tabs" => [%{"id" => "a", "name" => "A"}, %{"id" => "b", "name" => "B"}]},
        cards: [
          %{id: 1, layout: %{x: 6, y: 0, w: 6, h: 3, tab: nil}},
          %{id: 2, layout: %{x: 0, y: 0, w: 6, h: 2, tab: "b"}}
        ]
      }

      assert Tabs.current(dashboard, nil) == "a"
      assert [%{id: 1}] = Tabs.cards(dashboard, "a")

      moved = Tabs.move_card(dashboard, 1, "b")
      assert [%{id: 1, layout: %{tab: "b", x: 0, y: 2}}, %{id: 2}] = moved.cards
    end
  end

  defp tabs_of(live) do
    live
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#dashboard-tabs input[name=tab], #dashboard-tabs [role=tab]")
    |> Enum.map(fn node ->
      [value] = LazyHTML.attribute(node, "value") ++ LazyHTML.attribute(node, "phx-value-tab")
      value
    end)
  end
end
