defmodule Lotus.Web.ProSlotsTest do
  @moduledoc """
  Lotus Pro's ways into the dashboard: the lists it scopes
  (`Lotus.Web.Pro.list_options/2`, by tenant or owner) and the named slots it
  fills (`Lotus.Web.Pro.render_slot/2`). The free version lists every query
  and dashboard and its slots stay empty.

  `ProWeb` stands in for `Lotus.Pro.Web` through a setting, so these tests
  run alone.
  """
  use Lotus.Web.Case, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Lotus.Storage.{Dashboard, Query}

  defmodule ProWeb do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []

    # Every slot shows its name, the record it was given, and whether it was
    # given the request (`:info`).
    def render_slot(name, assigns) do
      record = assigns[:query] || assigns[:dashboard] || assigns[:card]
      label = if record, do: "#{name}:#{record.id}", else: "#{name}"
      label = if is_map(assigns[:info]), do: label <> ":info", else: label
      Phoenix.HTML.raw(~s(<span data-pro-slot="#{label}"></span>))
    end

    # The tenant of the request, or "mine" when the URL asks for it.
    def list_options(_kind, %{params: %{"owner" => "me"}}), do: [owner_id: "u1"]
    def list_options(_kind, %{params: %{"owner" => "shared"}}), do: [filter: :shared, page: 2]
    def list_options(_kind, _info), do: [tenant_id: "acme"]
  end

  defp with_pro do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    on_exit(fn -> Application.delete_env(:lotus_web, :__pro_web__) end)
  end

  defp set_fields(schema, record, fields) do
    Lotus.repo().update_all(from(r in schema, where: r.id == ^record.id), set: fields)
  end

  setup do
    acme = query_fixture(%{name: "Acme revenue"})
    globex = query_fixture(%{name: "Globex revenue"})
    set_fields(Query, acme, tenant_id: "acme", owner_id: "u1")
    set_fields(Query, globex, tenant_id: "globex")

    board = dashboard_fixture(%{name: "Acme board"})
    other = dashboard_fixture(%{name: "Globex board"})
    set_fields(Dashboard, board, tenant_id: "acme")
    set_fields(Dashboard, other, tenant_id: "globex")

    %{acme: acme, globex: globex, board: board, other: other}
  end

  describe "the free version, without Lotus Pro" do
    test "lists every query and dashboard, and its slots are empty" do
      {:ok, live, html} = live(build_conn(), "/lotus")

      assert html =~ "Acme revenue"
      assert html =~ "Globex revenue"
      refute html =~ "data-pro-slot"

      html = live |> element("button", "Dashboards") |> render_click()
      assert html =~ "Acme board"
      assert html =~ "Globex board"
    end
  end

  describe "with Lotus Pro" do
    setup do
      with_pro()
      :ok
    end

    test "Pro scopes the lists: a tenant's queries and dashboards", %{acme: acme, board: board} do
      {:ok, live, html} = live(build_conn(), "/lotus")

      assert html =~ "Acme revenue"
      refute html =~ "Globex revenue"
      assert html =~ ~s(data-pro-slot="query_badges:#{acme.id}")

      html = live |> element("button", "Dashboards") |> render_click()
      assert html =~ "Acme board"
      refute html =~ "Globex board"
      assert html =~ ~s(data-pro-slot="dashboard_badges:#{board.id}")
    end

    test "Pro reads the URL, so its toolbar can filter by patching it" do
      {:ok, _live, html} = live(build_conn(), "/lotus?owner=me")

      assert html =~ "Acme revenue"
      refute html =~ "Globex revenue"
    end

    test "Pro's filter reaches core, and keys it does not know do not" do
      assert Lotus.Web.Pro.list_options(:queries, %{params: %{"owner" => "shared"}}) ==
               [filter: :shared]
    end

    test "Pro fills the header and the list toolbar" do
      {:ok, _live, html} = live(build_conn(), "/lotus")

      assert html =~ ~s(data-pro-slot="nav")
      assert html =~ ~s(data-pro-slot="list_toolbar")
    end

    test "Pro fills the query editor's header, given the request", %{acme: acme} do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{acme.id}")

      assert render(live) =~ ~s(data-pro-slot="query_editor_header:#{acme.id}:info")
    end

    test "Pro fills a dashboard's header, given the request", %{board: board} do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{board.id}")

      assert render(live) =~ ~s(data-pro-slot="dashboard_header:#{board.id}:info")
    end

    test "Pro fills the public link's box, given the request", %{board: board} do
      {:ok, board} = Lotus.enable_public_sharing(board)
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{board.id}")

      html = live |> element("button", "Share") |> render_click()
      assert html =~ ~s(data-pro-slot="public_link:#{board.id}:info")
    end

    test "Pro fills each card's header", %{board: board} do
      card = dashboard_card_fixture(board, %{title: "Notes"})

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{board.id}")

      assert render(live) =~ ~s(data-pro-slot="card_header:#{card.id}")
    end

    test "the lists Pro scopes are the ones the palette and the card picker use" do
      info = Lotus.Web.Pro.request_info(%{})

      assert Enum.map(Lotus.Web.Pro.list_queries(info), & &1.name) == ["Acme revenue"]
      assert Enum.map(Lotus.Web.Pro.list_dashboards(info), & &1.name) == ["Acme board"]
    end
  end

  test "without Pro, a list has no options" do
    assert Lotus.Web.Pro.list_options(:queries, %{}) == []
  end
end
