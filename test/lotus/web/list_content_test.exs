defmodule Lotus.Web.ListContentTest do
  @moduledoc """
  Every list and lookup of saved queries and dashboards carries the viewer's
  context, so a `:list_content` plug decides what they see: what it hides is
  not listed, and opening it reads as not found.
  """

  use Lotus.Web.Case

  alias Lotus.Web.Pro

  defmodule HidePlug do
    import Ecto.Query, only: [where: 3]

    def init(opts), do: opts

    # Hides what is named "Hidden" from the viewer with a context.
    def call(%{context: %{user_id: _}, query: query} = payload, _opts) do
      send(:persistent_term.get({__MODULE__, :recipient}), {:list_content, payload.resource})
      {:cont, %{payload | query: where(query, [c], c.name != "Hidden")}}
    end

    def call(payload, _opts), do: {:cont, payload}
  end

  setup do
    previous = Application.get_env(:lotus, :middleware)
    Application.put_env(:lotus, :middleware, %{list_content: [{HidePlug, []}]})
    Lotus.Config.reload!()
    Lotus.Middleware.compile(Lotus.Config.middleware())
    :persistent_term.put({HidePlug, :recipient}, self())

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lotus, :middleware, previous),
        else: Application.delete_env(:lotus, :middleware)

      Lotus.Config.reload!()
      Lotus.Middleware.compile(Lotus.Config.middleware())
      :persistent_term.erase({HidePlug, :recipient})
    end)

    %{
      hidden_query: query_fixture(%{name: "Hidden", statement: "SELECT 1"}),
      shown_query: query_fixture(%{name: "Shown", statement: "SELECT 1"}),
      hidden_dashboard: dashboard_fixture(%{name: "Hidden"}),
      shown_dashboard: dashboard_fixture(%{name: "Shown"})
    }
  end

  test "the lists leave out what the viewer may not read" do
    {:ok, _live, html} = live(build_conn(), "/scoped?tab=queries")
    assert html =~ "Shown"
    refute html =~ "Hidden"
    assert_received {:list_content, :query}

    {:ok, _live, html} = live(build_conn(), "/scoped?tab=dashboards")
    assert html =~ "Shown"
    refute html =~ "Hidden"
    assert_received {:list_content, :dashboard}
  end

  test "without a context, every query and dashboard is listed" do
    {:ok, _live, html} = live(build_conn(), "/lotus?tab=queries")
    assert html =~ "Hidden"
    refute_received {:list_content, _resource}
  end

  test "a hidden query reads as not found", %{hidden_query: hidden, shown_query: shown} do
    assert {:error, {:live_redirect, %{flash: %{"error" => "Query not found"}}}} =
             live(build_conn(), "/scoped/queries/#{hidden.id}")

    assert {:ok, _live, _html} = live(build_conn(), "/scoped/queries/#{shown.id}")
  end

  test "a hidden dashboard reads as not found", %{
    hidden_dashboard: hidden,
    shown_dashboard: shown
  } do
    assert {:error, {:live_redirect, %{flash: %{"error" => "Dashboard not found"}}}} =
             live(build_conn(), "/scoped/dashboards/#{hidden.id}")

    assert {:ok, _live, _html} = live(build_conn(), "/scoped/dashboards/#{shown.id}")
  end

  test "the lists the pages share pass the viewer's context" do
    viewer = %{context: %{user_id: 42}, scope: nil}

    assert [%{name: "Shown"}] = Pro.list_queries(viewer)
    assert [%{name: "Shown"}] = Pro.list_dashboards(viewer, preload: [:cards])
    assert length(Pro.list_queries(%{context: nil})) == 2
  end

  describe "a dashboard card" do
    setup %{hidden_query: hidden} do
      %{dashboard: dashboard_fixture(%{name: "Board"}), hidden: hidden}
    end

    test "cannot take a query the viewer may not read", %{dashboard: dashboard, hidden: hidden} do
      {:ok, live, _html} = live(build_conn(), "/scoped/dashboards/#{dashboard.id}")
      editor = with_target(live, "#dashboard-editor")
      render_click(editor, "edit", %{})

      render_click(editor, "confirm_add_card", %{"type" => "query", "query-id" => "#{hidden.id}"})
      html = render(live)

      assert html =~ "Query not found"
      render_submit(editor, "save_dashboard", %{"dashboard" => %{"name" => "Board"}})
      assert Lotus.list_dashboard_cards(dashboard.id) == []
    end

    test "whose query the viewer may not read does not run it", %{
      dashboard: dashboard,
      hidden: hidden
    } do
      {:ok, _card} =
        Lotus.create_dashboard_card(dashboard.id, %{
          card_type: :query,
          query_id: hidden.id,
          position: 0
        })

      {:ok, live, _html} = live(build_conn(), "/scoped/dashboards/#{dashboard.id}")

      refute render_async(live) =~ "Hidden"
    end
  end
end
