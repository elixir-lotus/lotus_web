defmodule Lotus.Web.ProHomeTabsTest do
  # Lotus Pro's tabs of the home page, after Queries and Dashboards, each
  # drawn by a LiveComponent of Pro's.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  defmodule Tab do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns) do
      ~H"""
      <div id="pro-workflows-tab">The workflows of <%= inspect(@context) %></div>
      """
    end
  end

  defmodule ProWeb do
    @moduledoc false
    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil
    def list_options(_kind, _info), do: []
    def home_tabs(_info), do: [%{id: "workflows", label: "Workflows", count: 3, component: Tab}]
  end

  setup do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    on_exit(fn -> Application.delete_env(:lotus_web, :__pro_web__) end)
  end

  test "a tab of Pro's, with its count, opens by a click and by the URL" do
    {:ok, view, _html} = live(build_conn(), "/lotus")
    assert has_element?(view, "#tab-workflows", "Workflows")
    assert has_element?(view, "#tab-workflows", "3")
    refute has_element?(view, "#pro-workflows-tab")

    view |> element("#tab-workflows") |> render_click()
    assert has_element?(view, "#pro-workflows-tab")

    {:ok, view, _html} = live(build_conn(), "/lotus?tab=workflows")
    assert has_element?(view, "#pro-workflows-tab")
  end

  test "a tab Pro has not is the queries" do
    {:ok, view, _html} = live(build_conn(), "/lotus?tab=nope")
    refute has_element?(view, "#pro-workflows-tab")
  end
end
