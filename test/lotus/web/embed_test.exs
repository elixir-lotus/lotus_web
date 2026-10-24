defmodule Lotus.Web.EmbedTest do
  @moduledoc """
  Embedding, a Lotus Pro feature: a dashboard or one card in another app's
  page (`Lotus.Web.Router.lotus_embed/2`). Pro checks the token and gives
  the viewer; the cards run as that viewer. The free version has the routes,
  and they say embedding needs Lotus Pro.

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

    def verify_embed("bad", _info), do: {:error, "This link has expired"}

    def verify_embed(token, %{kind: kind}) do
      send(:persistent_term.get({__MODULE__, :test}), {:verify, token, kind})
      grant = :persistent_term.get({__MODULE__, :grant})
      {:ok, grant}
    end
  end

  defp with_pro(grant) do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    :persistent_term.put({ProWeb, :test}, self())
    :persistent_term.put({ProWeb, :grant}, grant)

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({ProWeb, :test})
      :persistent_term.erase({ProWeb, :grant})
    end)
  end

  setup do
    dashboard = dashboard_fixture(%{name: "Acme sales", description: "For Acme"})
    query = query_fixture(%{statement: "SELECT 'north' AS region"})

    card =
      dashboard_card_fixture(dashboard, %{
        card_type: :query,
        query_id: query.id,
        title: "Revenue",
        content: %{}
      })

    note = dashboard_card_fixture(dashboard, %{title: "A note", position: 1})

    %{dashboard: dashboard, card: card, note: note}
  end

  describe "the free version, without Lotus Pro" do
    test "the embed routes say embedding needs Lotus Pro", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus-embed/dashboard/any")
      assert html =~ "Embedding needs Lotus Pro"
      refute html =~ dashboard.name

      {:ok, _live, html} = live(build_conn(), "/lotus-embed/card/any")
      assert html =~ "Embedding needs Lotus Pro"
    end

    test "no site may frame them" do
      conn = get(build_conn(), "/lotus-embed/dashboard/any")
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
    end
  end

  describe "with Lotus Pro" do
    test "a dashboard token opens the dashboard, its cards run as the viewer", %{
      dashboard: dashboard,
      card: card
    } do
      with_pro(%{
        resource: {:dashboard, dashboard.id},
        context: %{user: "u1"},
        frame_ancestors: ["https://app.example.com"]
      })

      {:ok, live, html} = live(build_conn(), "/lotus-embed/dashboard/t0ken")
      assert_received {:verify, "t0ken", :dashboard}

      assert html =~ "Acme sales"
      assert html =~ "A note"
      refute html =~ "new-item-dropdown"

      render_async(live)
      assert has_element?(live, "#table-#{card.id}")
    end

    test "only the sites Pro allows may frame it", %{dashboard: dashboard} do
      with_pro(%{
        resource: {:dashboard, dashboard.id},
        frame_ancestors: ["https://app.example.com", "https://admin.example.com"]
      })

      conn = get(build_conn(), "/lotus-embed/dashboard/t0ken")

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors https://app.example.com https://admin.example.com"
             ]

      assert get_resp_header(conn, "x-frame-options") == []
    end

    test "a card token opens that card alone, with no header or filters", %{
      card: card,
      note: note
    } do
      with_pro(%{resource: {:card, card.id}})

      {:ok, live, html} = live(build_conn(), "/lotus-embed/card/t0ken")

      refute html =~ "Acme sales"
      refute html =~ "A note"
      assert has_element?(live, "#card-#{card.id}")
      refute has_element?(live, "#card-#{note.id}")
      assert html =~ "Powered by"
    end

    test "the host's filters apply, and the viewer's URL changes them" do
      dashboard = dashboard_fixture(%{name: "Filtered"})

      {:ok, _filter} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "region",
          label: "Region",
          filter_type: :text,
          widget: :input,
          position: 0
        })

      with_pro(%{resource: {:dashboard, dashboard.id}, filters: %{"region" => "north", "x" => 1}})

      {:ok, _live, html} = live(build_conn(), "/lotus-embed/dashboard/t0ken")
      assert html =~ ~s(value="north")

      {:ok, _live, html} = live(build_conn(), "/lotus-embed/dashboard/t0ken?region=south")
      assert html =~ ~s(value="south")
    end

    test "a token for the other kind of route is refused", %{card: card} do
      with_pro(%{resource: {:card, card.id}})

      {:ok, _live, html} = live(build_conn(), "/lotus-embed/dashboard/t0ken")

      assert html =~ "This embed is not available"
    end

    test "a token Pro refuses shows Pro's message", %{dashboard: dashboard} do
      with_pro(%{resource: {:dashboard, dashboard.id}})

      {:ok, _live, html} = live(build_conn(), "/lotus-embed/dashboard/bad")

      assert html =~ "This link has expired"
      refute html =~ "Acme sales"
    end
  end
end
