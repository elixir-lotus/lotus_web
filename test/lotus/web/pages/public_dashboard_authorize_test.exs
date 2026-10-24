defmodule Lotus.Web.Pages.PublicDashboardAuthorizeTest do
  @moduledoc """
  A package decides whether a share link shows its dashboard
  (`Lotus.Web.Pro.authorize_public_dashboard/2`). The package is stood in
  for through a setting, so these tests run alone.
  """
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  defmodule Package do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def authorize_public_dashboard(dashboard, params) do
      send(:persistent_term.get({__MODULE__, :test}), {:asked, dashboard.id, params})

      case dashboard.name do
        "Expired" -> {:deny, "This link has expired"}
        "Odd" -> :maybe
        _ -> :allow
      end
    end
  end

  setup do
    Application.put_env(:lotus_web, :__pro_web__, Package)
    :persistent_term.put({Package, :test}, self())

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({Package, :test})
    end)
  end

  test "an allowed link shows the dashboard, and the package sees the URL's params" do
    dashboard = public_dashboard_fixture(%{name: "Sales", description: "Shared view"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}?key=abc")

    assert html =~ "Shared view"
    id = dashboard.id
    assert_received {:asked, ^id, %{"key" => "abc", "token" => _}}
  end

  test "a denied link shows the package's message, not the dashboard" do
    dashboard = public_dashboard_fixture(%{name: "Expired", description: "Secret numbers"})
    dashboard_card_fixture(dashboard, %{title: "Revenue note"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert html =~ "This link has expired"
    assert html =~ "Dashboard Unavailable"
    refute html =~ "Secret numbers"
    refute html =~ "Revenue note"
  end

  test "an answer the package should not give denies" do
    dashboard = public_dashboard_fixture(%{name: "Odd", description: "Secret numbers"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert html =~ "This dashboard is not available"
    refute html =~ "Secret numbers"
  end

  test "an unknown token is not asked about" do
    {:ok, _live, html} = live(build_conn(), "/lotus/public/no-such-token")

    assert html =~ "Dashboard not found"
    refute_received {:asked, _, _}
  end
end
