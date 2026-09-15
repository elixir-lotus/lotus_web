defmodule Lotus.Web.Pages.PublicDashboardPageTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Dashboards.DateToken
  alias Lotus.Web.Dashboards.DateTokens

  describe "invalid token" do
    test "shows error for invalid token" do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/invalid-token-123")

      assert html =~ "Dashboard not found"
    end
  end

  describe "valid token access" do
    setup do
      dashboard =
        public_dashboard_fixture(%{name: "Public Dashboard", description: "Shared view"})

      {:ok, dashboard: dashboard}
    end

    test "loads dashboard with valid public token", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert html =~ "Public Dashboard"
      assert html =~ "Shared view"
    end

    test "does not show edit controls (Save button)", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      # Verify Save button is not present
      refute has_element?(live, "button", "Save")
    end

    test "does not show New button on public routes", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      refute has_element?(live, "#new-item-dropdown")
    end

    test "shows footer with Lotus branding", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert html =~ "Powered by"
      assert html =~ "Lotus"
    end
  end

  describe "cascading filters" do
    setup do
      create_test_users()
      create_test_posts()

      dashboard = public_dashboard_fixture(%{name: "Public Cascading"})

      titles =
        query_fixture(%{
          statement: """
          SELECT p.title FROM test_posts p
          JOIN test_users u ON u.id = p.user_id
          WHERE u.name = {{user_name}}
          ORDER BY p.title
          """
        })

      {:ok, user_name} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "user_name",
          label: "User",
          filter_type: :select,
          widget: :select,
          config: %{"options" => ["Alice", "Bob"]},
          position: 0
        })

      {:ok, _post_title} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "post_title",
          label: "Post",
          filter_type: :select,
          widget: :select,
          source_query_id: titles.id,
          depends_on_filter_id: user_name.id,
          position: 1
        })

      {:ok, dashboard: dashboard}
    end

    test "disables the dependent filter while the parent has no value", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert has_element?(live, "select[name='filter[user_name]'] option", "Alice")
      assert has_element?(live, "select[name='filter[post_title]'][disabled]")
    end

    test "a parent change lists the new options and clears the child value", %{
      dashboard: dashboard
    } do
      {:ok, live, _html} =
        live(
          build_conn(),
          "/lotus/public/#{dashboard.public_token}?user_name=Alice&post_title=First+Post"
        )

      assert has_element?(
               live,
               "select[name='filter[post_title]'] option[selected]",
               "First Post"
             )

      live
      |> element("#filter-bar form")
      |> render_change(%{"filter" => %{"user_name" => "Bob", "post_title" => "First Post"}})

      assert has_element?(live, "select[name='filter[post_title]'] option", "Another Post")
      refute has_element?(live, "select[name='filter[post_title]'] option[selected]")
      assert_push_event(live, "update-query-params", %{params: %{"user_name" => "Bob"}})
    end
  end

  describe "empty dashboard" do
    setup do
      dashboard = public_dashboard_fixture(%{name: "Empty Dashboard"})
      {:ok, dashboard: dashboard}
    end

    test "shows empty state message", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert html =~ "This dashboard has no cards"
    end
  end

  describe "dashboard with query card" do
    setup do
      create_test_users()
      dashboard = public_dashboard_fixture(%{name: "Dashboard with Content"})

      query =
        query_fixture(%{
          name: "Users Query",
          statement: "SELECT name, email FROM test_users ORDER BY name"
        })

      _card = query_card_fixture(dashboard, query, %{title: "Users"})
      {:ok, dashboard: dashboard}
    end

    test "displays query card title", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      # Query cards show their title in the header
      assert html =~ "Users"
    end
  end

  describe "query execution" do
    setup do
      create_test_users()
      dashboard = public_dashboard_fixture(%{name: "Query Dashboard"})

      query =
        query_fixture(%{
          name: "Users List",
          statement: "SELECT name, email FROM test_users ORDER BY name"
        })

      _card = query_card_fixture(dashboard, query, %{title: "Users"})
      {:ok, dashboard: dashboard}
    end

    test "executes query cards on load", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      # Wait for async query execution
      html = render_async(live)

      # Should show query results
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Charlie"
    end
  end

  describe "URL query params pre-fill filters" do
    setup do
      create_test_users()

      dashboard = public_dashboard_fixture(%{name: "Filtered Dashboard"})

      query =
        query_fixture(%{
          name: "Filtered Users",
          statement: "SELECT name FROM test_users WHERE name = {{user_name}} ORDER BY name"
        })

      card = query_card_fixture(dashboard, query, %{title: "Filtered Users"})

      {:ok, filter} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "user_name",
          label: "User Name",
          filter_type: :text,
          widget: :input,
          default_value: "%",
          position: 0
        })

      {:ok, _mapping} = Lotus.create_filter_mapping(card, filter, "user_name")

      {:ok, dashboard: dashboard, filter: filter}
    end

    test "pre-fills filter values from URL query params", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?user_name=Alice")

      render_async(live)

      # Should show filtered results
      assert has_element?(live, "td", "Alice")
      refute has_element?(live, "td", "Bob")
      refute has_element?(live, "td", "Charlie")
    end

    test "shows filter bar when dashboard has filters", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(
          build_conn(),
          "/lotus/public/#{dashboard.public_token}?user_name=Alice"
        )

      html = render(live)
      assert html =~ "Filtered Dashboard"
      assert html =~ "filter[user_name]"
      assert html =~ "User Name"
    end

    test "does not show Add Filter button on public view", %{dashboard: dashboard} do
      {:ok, _live, html} =
        live(
          build_conn(),
          "/lotus/public/#{dashboard.public_token}?user_name=Alice"
        )

      refute html =~ "Add Filter"
    end

    test "ignores unrecognized query params", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(
          build_conn(),
          "/lotus/public/#{dashboard.public_token}?unknown_param=foo&user_name=Alice"
        )

      render_async(live)

      # Unrecognized param is ignored; the filter still uses the matched user_name param
      assert has_element?(live, "td", "Alice")
      refute has_element?(live, "td", "Bob")
    end

    test "filter widgets reflect pre-filled values", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?user_name=Alice")

      # The filter input should have the pre-filled value
      assert has_element?(live, "input[name='filter[user_name]'][value='Alice']")
    end
  end

  describe "filter default values" do
    setup do
      create_test_users()

      dashboard = public_dashboard_fixture(%{name: "Default Filter Dashboard"})

      query =
        query_fixture(%{
          name: "Filtered Users",
          statement: "SELECT name FROM test_users WHERE name = {{user_name}} ORDER BY name"
        })

      card = query_card_fixture(dashboard, query, %{title: "Filtered Users"})

      {:ok, filter} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "user_name",
          label: "User Name",
          filter_type: :text,
          widget: :input,
          default_value: "Alice",
          position: 0
        })

      {:ok, _mapping} = Lotus.create_filter_mapping(card, filter, "user_name")

      {:ok, dashboard: dashboard}
    end

    test "applies filter default value when URL has no param", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      render_async(live)

      assert has_element?(live, "td", "Alice")
      refute has_element?(live, "td", "Bob")
      refute has_element?(live, "td", "Charlie")
    end

    test "URL param overrides filter default value", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?user_name=Bob")

      render_async(live)

      assert has_element?(live, "td", "Bob")
      refute has_element?(live, "td", "Alice")
      refute has_element?(live, "td", "Charlie")
    end
  end

  describe "relative date tokens" do
    setup do
      dashboard = public_dashboard_fixture(%{name: "Token Dashboard"})
      token_filters_fixture(dashboard)
      {:ok, dashboard: dashboard}
    end

    test "cards get the dates a token default covers, split by the transforms", %{
      dashboard: dashboard
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      html = render_async(live)
      {first, last} = resolved_range("last_30_days")

      assert html =~ first
      assert html =~ last
      assert html =~ Date.to_iso8601(Date.add(Date.utc_today(), -1))
      refute html =~ "Invalid date"
    end

    test "a fixed range in the URL still splits", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?period=2026-01-01,2026-03-31")

      render_async(live)

      assert has_element?(live, "td", "2026-01-01")
      assert has_element?(live, "td", "2026-03-31")
    end

    test "the bar shows the token label and the dates it covers", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert has_element?(live, "#filter-period-presets-button", "Last 30 days")

      assert has_element?(
               live,
               "#filter-period-presets-button",
               DateTokens.describe("last_30_days", Date.utc_today())
             )
    end

    test "a preset puts the token in the filter value and the URL", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      render_async(live)

      live
      |> element("#filter-period-presets [role=menuitemradio]", "This quarter")
      |> render_click()

      assert_push_event(live, "update-query-params", %{params: %{"period" => "this_quarter"}})
      assert has_element?(live, "input[type=hidden][name='filter[period]'][value=this_quarter]")

      {first, last} = resolved_range("this_quarter")
      html = render_async(live)
      assert html =~ first
      assert html =~ last
    end

    test "a token in the URL stays a token", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?period=last_year")

      assert has_element?(live, "input[type=hidden][name='filter[period]'][value=last_year]")
      assert has_element?(live, "#filter-period-presets-button", "Last year")
    end

    test "custom range starts from the dates the token covers", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      live
      |> element("#filter-period-presets [role=menuitemradio]", "Custom range")
      |> render_click()

      {first, last} = resolved_range("last_30_days")
      assert has_element?(live, "input[name='filter[period][start]'][value='#{first}']")
      assert has_element?(live, "input[name='filter[period][end]'][value='#{last}']")
      refute has_element?(live, "input[type=hidden][name='filter[period]']")
    end

    test "a date filter offers only the single-day presets", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert has_element?(live, "#filter-day-presets [role=menuitemradio]", "Yesterday")
      refute has_element?(live, "#filter-day-presets [role=menuitemradio]", "Last 7 days")
      assert has_element?(live, "#filter-day-presets [role=menuitemradio]", "Fixed date")
    end
  end

  defp token_filters_fixture(dashboard) do
    period_query =
      query_fixture(%{
        statement:
          "SELECT CAST({{range_start}} AS text) AS first_day, CAST({{range_end}} AS text) AS last_day"
      })

    day_query = query_fixture(%{statement: "SELECT CAST({{day}} AS text) AS picked_day"})

    period_card = query_card_fixture(dashboard, period_query, %{title: "Period Card"})
    day_card = query_card_fixture(dashboard, day_query, %{title: "Day Card", position: 1})

    {:ok, period} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "period",
        label: "Period",
        filter_type: :date_range,
        widget: :date_range_picker,
        default_value: "last_30_days",
        position: 0
      })

    {:ok, day} =
      Lotus.create_dashboard_filter(dashboard, %{
        name: "day",
        label: "Day",
        filter_type: :date,
        widget: :date_picker,
        default_value: "yesterday",
        position: 1
      })

    {:ok, _} =
      Lotus.create_filter_mapping(period_card, period, "range_start",
        transform: %{type: "date_range_start"}
      )

    {:ok, _} =
      Lotus.create_filter_mapping(period_card, period, "range_end",
        transform: %{type: "date_range_end"}
      )

    {:ok, _} = Lotus.create_filter_mapping(day_card, day, "day")

    %{period: period, day: day, period_card: period_card}
  end

  defp resolved_range(token) do
    token
    |> DateToken.resolve(:date_range, Date.utc_today())
    |> String.split(",")
    |> List.to_tuple()
  end
end
