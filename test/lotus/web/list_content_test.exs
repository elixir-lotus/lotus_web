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
end
