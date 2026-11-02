defmodule Lotus.Web.PageIdentityTest do
  @moduledoc """
  The page a LiveView shows, the user it acts for and the state it holds come
  from its live_session and its URL, whatever a client patches to.
  """

  use Lotus.Web.Case

  alias Lotus.Storage.Dashboard

  describe "a token in the URL of the signed-in dashboard" do
    test "opens the page the path names, as the signed-in user" do
      {:ok, live, html} = live(build_conn(), "/per_dashboard?token=nope")

      refute html =~ "unavailable"
      assert has_element?(live, "#new-item-dropdown")
    end

    test "gives no way to a dashboard the user may not view" do
      hidden = dashboard_fixture(%{name: "Hidden"})
      :telemetry_test.attach_event_handlers(self(), [[:lotus_web, :dashboard, :view]])

      {:ok, live, _html} = live(build_conn(), "/per_dashboard?token=nope")
      path = "/per_dashboard/dashboards/#{hidden.id}"

      assert {:error, {:live_redirect, %{to: ^path}}} = render_patch(live, path)

      assert {:error, {:live_redirect, %{flash: %{"error" => "Hidden"}}}} =
               live(build_conn(), path)

      refute_received {[:lotus_web, :dashboard, :view], _ref, _measurements, _metadata}
    end
  end

  describe "a patch from one dashboard to another" do
    setup do
      %{mine: dashboard_fixture(%{name: "Mine"}), victim: dashboard_fixture(%{name: "Victim"})}
    end

    test "mounts the editor again", %{mine: mine, victim: victim} do
      {:ok, live, _html} = live(build_conn(), "/per_dashboard/dashboards/#{mine.id}")
      path = "/per_dashboard/dashboards/#{victim.id}"

      assert {:error, {:live_redirect, %{to: ^path}}} = render_patch(live, path)
    end

    test "acts on the dashboard it authorized", %{mine: mine, victim: victim} do
      {:ok, live, _html} = live(build_conn(), "/per_dashboard/dashboards/#{mine.id}")

      {:error, {:live_redirect, %{to: path}}} =
        render_patch(live, "/per_dashboard/dashboards/#{victim.id}")

      {:ok, live, _html} = live(build_conn(), path)

      live |> with_target("#dashboard-editor") |> render_click("enable_sharing", %{})
      live |> with_target("#dashboard-editor") |> render_click("delete_dashboard", %{})

      assert %Dashboard{public_token: nil} = Lotus.get_dashboard(victim.id)
    end
  end

  test "a new dashboard, once saved, stays in place" do
    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/new")

    live
    |> with_target("#dashboard-editor")
    |> render_submit("save_dashboard", %{"dashboard" => %{"name" => "Fresh"}})

    assert [%Dashboard{id: id}] = Lotus.list_dashboards()
    assert_patch(live, "/lotus/dashboards/#{id}")
  end

  describe "a dashboard the user may not view" do
    setup do
      %{hidden: dashboard_fixture(%{name: "Hidden"}), shown: dashboard_fixture(%{name: "Shown"})}
    end

    test "is not listed on the home page" do
      {:ok, _live, html} = live(build_conn(), "/per_dashboard?tab=dashboards")

      assert html =~ "Shown"
      refute html =~ "Hidden"
    end

    test "is not copied", %{hidden: hidden} do
      {:ok, live, _html} = live(build_conn(), "/per_dashboard?tab=dashboards")

      live
      |> with_target("#queries-page")
      |> render_click("duplicate_dashboard", %{"id" => to_string(hidden.id)})

      assert length(Lotus.list_dashboards()) == 2
    end
  end
end
