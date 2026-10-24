defmodule Lotus.Web.ProCardsTest do
  @moduledoc """
  Lotus Pro's cards (`card_type: :pro`) and its actions on a table card's
  rows. Only Pro adds them: the free version offers no Pro card and its
  tables have no row actions.

  `ProWeb` stands in for `Lotus.Pro.Web` through a setting, so these tests
  run alone.
  """
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  defmodule ProWeb do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def card_kinds(_info),
      do: [%{kind: "action", label: "Action", description: "A button that runs an action"}]

    def render_card(%{content: %{"kind" => "action"}}, _assigns),
      do: Phoenix.HTML.raw(~s(<button data-pro-card="action">Approve</button>))

    def render_card(_card, _assigns), do: nil

    def row_actions(_card, _info) do
      test = :persistent_term.get({__MODULE__, :test})

      [
        %{label: "Contact", on_action: fn context -> send(test, {:contact, context.row}) end},
        %{label: "Open in CRM", navigate: fn row -> "/crm/#{Enum.at(row, 0)}" end}
      ]
    end
  end

  defp with_pro do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    :persistent_term.put({ProWeb, :test}, self())

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({ProWeb, :test})
    end)
  end

  defp open_add_card(dashboard) do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    live |> element("#dashboard-edit") |> render_click()
    render_click(with_target(live, "#dashboard-editor"), "show_add_card_modal", %{})
    live
  end

  defp table_card(dashboard) do
    query = query_fixture(%{statement: "SELECT 'acme' AS customer"})

    dashboard_card_fixture(dashboard, %{
      card_type: :query,
      query_id: query.id,
      content: %{}
    })
  end

  describe "the free version, without Lotus Pro" do
    test "offers no Pro card, and its tables have no row actions" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      card = table_card(dashboard)

      live = open_add_card(dashboard)
      refute has_element?(live, ~s(button[phx-value-type^="pro:"]))

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
      render_async(live)

      assert has_element?(live, "#table-#{card.id}")
      refute render(live) =~ "Contact"
    end
  end

  test "a Pro card saved while Pro was installed says it needs Lotus Pro" do
    dashboard = dashboard_fixture(%{name: "Sales"})

    dashboard_card_fixture(dashboard, %{
      card_type: :pro,
      title: nil,
      content: %{"kind" => "action"}
    })

    {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

    assert html =~ "This card needs Lotus Pro"
  end

  describe "with Lotus Pro" do
    setup do
      with_pro()
      :ok
    end

    test "Pro's card kinds are offered, and a Pro card is added and drawn by Pro" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      live = open_add_card(dashboard)

      assert has_element?(live, ~s(button[phx-value-type="pro:action"]), "Action")

      live |> element(~s(button[phx-value-type="pro:action"])) |> render_click()
      html = live |> element(~s(button[phx-click="confirm_add_card"])) |> render_click()

      assert html =~ ~s(data-pro-card="action")
    end

    test "Pro draws a saved Pro card" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      dashboard_card_fixture(dashboard, %{card_type: :pro, content: %{"kind" => "action"}})

      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ ~s(data-pro-card="action")
      refute html =~ "This card needs Lotus Pro"
    end

    test "a kind Pro does not offer is not added" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      live = open_add_card(dashboard)

      html =
        render_click(with_target(live, "#dashboard-editor"), "confirm_add_card", %{
          "type" => "pro:rogue"
        })

      refute html =~ "This card needs Lotus Pro"
      refute html =~ "data-pro-card"
    end

    test "Pro's row actions run on a table card's rows" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      card = table_card(dashboard)

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
      render_async(live)

      # A row's id: its values and how many rows with the same values came
      # before it.
      row_id = :erlang.phash2({["acme"], 0})

      Masu.Test.row_action(live, "table-#{card.id}", "Contact", row_id)
      assert_received {:contact, ["acme"]}

      assert {:navigate, "/crm/acme"} =
               Masu.Test.row_action(live, "table-#{card.id}", "Open in CRM", row_id)
    end
  end
end
