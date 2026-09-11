defmodule Lotus.Web.Pages.PublicDashboardPageTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

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

      html = render_async(live)

      # Should show filtered results
      assert html =~ "Alice"
      refute html =~ "Bob"
      refute html =~ "Charlie"
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

      html = render_async(live)

      # Unrecognized param is ignored; the filter still uses the matched user_name param
      assert html =~ "Alice"
      refute html =~ "Bob"
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

      html = render_async(live)

      assert html =~ "Alice"
      refute html =~ "Bob"
      refute html =~ "Charlie"
    end

    test "URL param overrides filter default value", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/public/#{dashboard.public_token}?user_name=Bob")

      html = render_async(live)

      assert html =~ "Bob"
      refute html =~ "Alice"
      refute html =~ "Charlie"
    end
  end
end
