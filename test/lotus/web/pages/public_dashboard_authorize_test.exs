defmodule Lotus.Web.Pages.PublicDashboardAuthorizeTest do
  @moduledoc """
  Lotus Pro decides whether a share link shows its dashboard
  (`Lotus.Web.Pro.authorize_public_dashboard/2`), and what a link to no
  dashboard says (`Lotus.Web.Pro.public_link_message/1`); without Pro every
  link works. `ProWeb` stands in for `Lotus.Pro.Web` through a setting, so these
  tests run alone.
  """
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  defmodule ProWeb do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def authorize_public_dashboard(dashboard, params) do
      send(:persistent_term.get({__MODULE__, :test}), {:asked, dashboard.id, params})

      case {dashboard.name, params} do
        {"Expired", _} -> {:deny, "This link has expired"}
        {"Odd", _} -> :maybe
        {"Locked", %{"grant" => "ok"}} -> {:allow, params: %{"grant" => "ok"}}
        {"Locked", _} -> {:ask, password()}
        {"No downloads", _} -> {:allow, downloads: false}
        {"Run as owner", _} -> {:allow, context: %{id: "owner"}}
        _ -> :allow
      end
    end

    def answer_public_dashboard(%{name: "Locked"}, %{"password" => "secret"}, _params),
      do: {:allow, params: %{"grant" => "ok"}}

    def answer_public_dashboard(%{name: "Locked"}, _answers, _params),
      do: {:ask, Map.put(password(), :error, "That password is not right")}

    defp password do
      %{
        message: "Enter the password to see this dashboard.",
        fields: [%{key: "password", label: "Password", type: :password}],
        submit: "Open"
      }
    end

    def public_link_message("turned-off"), do: "Its owner turned this link off"
    def public_link_message(_token), do: nil
  end

  setup do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    :persistent_term.put({ProWeb, :test}, self())

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({ProWeb, :test})
    end)
  end

  test "an allowed link shows the dashboard, and Pro sees the URL's params" do
    dashboard = public_dashboard_fixture(%{name: "Sales", description: "Shared view"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}?key=abc")

    assert html =~ "Shared view"
    id = dashboard.id
    assert_received {:asked, ^id, %{"key" => "abc", "token" => _}}
  end

  test "a denied link shows Pro's message, not the dashboard" do
    dashboard = public_dashboard_fixture(%{name: "Expired", description: "Secret numbers"})
    dashboard_card_fixture(dashboard, %{title: "Revenue note"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert html =~ "This link has expired"
    assert html =~ "Dashboard Unavailable"
    refute html =~ "Secret numbers"
    refute html =~ "Revenue note"
  end

  test "an answer Pro should not give denies" do
    dashboard = public_dashboard_fixture(%{name: "Odd", description: "Secret numbers"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert html =~ "This dashboard is not available"
    refute html =~ "Secret numbers"
  end

  test "a link Pro knows says what Pro says" do
    {:ok, _live, html} = live(build_conn(), "/lotus/public/turned-off")

    assert html =~ "Its owner turned this link off"
    refute html =~ "Dashboard not found"
  end

  test "an unknown token is not asked about" do
    {:ok, _live, html} = live(build_conn(), "/lotus/public/no-such-token")

    assert html =~ "Dashboard not found"
    refute_received {:asked, _, _}
  end

  describe "Pro asks before showing the dashboard" do
    setup do
      dashboard = public_dashboard_fixture(%{name: "Locked", description: "Secret numbers"})
      dashboard_card_fixture(dashboard, %{title: "Revenue note"})
      %{dashboard: dashboard}
    end

    test "its form, not the dashboard", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert html =~ "Enter the password to see this dashboard."
      assert html =~ ~s(type="password")
      assert html =~ "This dashboard is protected"
      refute html =~ "Secret numbers"
      refute html =~ "Revenue note"
      refute html =~ "Locked"
    end

    test "a wrong answer says so and asks again", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      html =
        live
        |> form("#public-dashboard-ask-form", answers: %{password: "nope"})
        |> render_submit()

      assert html =~ "That password is not right"
      refute html =~ "Revenue note"
    end

    test "the right answer shows it, and keeps Pro's grant in the URL", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      html =
        live
        |> form("#public-dashboard-ask-form", answers: %{password: "secret"})
        |> render_submit()

      assert html =~ "Secret numbers"
      assert html =~ "Revenue note"
      assert_push_event(live, "update-query-params", %{params: %{"grant" => "ok"}})
    end

    test "a link with the grant opens at once", %{dashboard: dashboard} do
      {:ok, _live, html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?grant=ok")

      assert html =~ "Secret numbers"
    end
  end

  test "Pro can turn a link's downloads off" do
    query = query_fixture(%{statement: "SELECT 'North' AS region, 10 AS revenue"})

    for {name, downloads?} <- [{"No downloads", false}, {"Downloads", true}] do
      dashboard = public_dashboard_fixture(%{name: name})

      chart =
        query_card_fixture(dashboard, query, %{
          title: "Chart",
          visualization_config: %{
            "chart_type" => "bar",
            "x_field" => "region",
            "y_field" => "revenue"
          }
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      render_async(live)

      assert has_element?(live, "#card-#{chart.id}-menu-items button", "Save as PNG") ==
               downloads?

      assert has_element?(live, "#chart-#{chart.id} [data-fude-export]") == downloads?
    end
  end

  test "the cards run as whoever Pro names for the link" do
    query = query_fixture(%{statement: "SELECT 1 AS one"})
    test = self()
    handler = "public-run-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:lotus, :query, :start],
      fn _event, _measurements, metadata, _config -> send(test, {:ran_as, metadata.context}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    for {name, context} <- [{"Run as owner", %{id: "owner"}}, {"Anyone", nil}] do
      dashboard = public_dashboard_fixture(%{name: name})
      query_card_fixture(dashboard, query, %{title: "One"})

      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      render_async(live)

      assert_received {:ran_as, ^context}
    end
  end
end
