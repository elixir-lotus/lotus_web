defmodule Lotus.Web.Pages.DashboardEditorPageTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  describe "new dashboard" do
    test "shows empty state with Add Card button" do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/new")

      assert html =~ "New Dashboard"
      assert html =~ "Add Card"
      assert html =~ "Save"
    end

    test "shows save modal when clicking Save button" do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/new")

      html =
        live
        |> element("button", "Save")
        |> render_click()

      assert html =~ "Save Dashboard"
      assert html =~ "Enter dashboard name"
    end
  end

  describe "edit dashboard" do
    setup do
      dashboard = dashboard_fixture(%{name: "Existing Dashboard"})
      {:ok, dashboard: dashboard}
    end

    test "loads existing dashboard", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "Existing Dashboard"
      assert html =~ "Delete"
      assert html =~ "Save"
    end

    test "redirects when dashboard not found" do
      # When trying to access a non-existent dashboard, it redirects to the home page
      assert {:error, {:live_redirect, %{to: "/lotus?tab=dashboards", flash: %{"error" => _}}}} =
               live(build_conn(), "/lotus/dashboards/999999")
    end

    test "shows delete modal when clicking Delete button", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      html =
        live
        |> element("button", "Delete")
        |> render_click()

      assert html =~ "Delete Dashboard"
      assert html =~ "Are you sure you want to delete"
    end

    test "deletes dashboard and redirects", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      # Open delete modal
      live
      |> element("button", "Delete")
      |> render_click()

      # Confirm deletion - this triggers push_navigate
      live
      |> element("#delete-dashboard-modal button", "Delete")
      |> render_click()
      |> follow_redirect(build_conn())

      # Verify the dashboard was actually deleted
      assert Lotus.get_dashboard(dashboard.id) == nil
    end
  end

  describe "adding cards" do
    test "shows add card modal" do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/new")

      html =
        live
        |> element("button", "Add Card")
        |> render_click()

      assert html =~ "add-card-modal"
      assert html =~ "Text"
      assert html =~ "Query"
    end

    test "can select text card type in modal" do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/new")

      # Open add card modal
      live
      |> element("button", "Add Card")
      |> render_click()

      # Select text card type - the component handles the event
      html =
        live
        |> element("#add-card-modal button[phx-value-type='text']")
        |> render_click()

      # After selecting text type, the Text button should be highlighted
      assert html =~ "border-pink-500"
    end
  end

  describe "with query cards" do
    setup do
      create_test_users()
      dashboard = dashboard_fixture(%{name: "Dashboard with Query"})

      query =
        query_fixture(%{
          name: "User Query",
          statement: "SELECT name, email FROM test_users ORDER BY name"
        })

      card = query_card_fixture(dashboard, query, %{title: "Users Table"})
      {:ok, dashboard: dashboard, query: query, card: card}
    end

    test "auto-runs query cards on load", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      # Wait for async query execution
      html = render_async(live)

      # Should show query results
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Charlie"
    end

    test "displays query card title", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "Users Table"
    end

    test "displays the card in the grid", %{dashboard: dashboard, card: card} do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "card-#{card.id}"
    end
  end

  describe "filter default values" do
    setup do
      create_test_users()

      dashboard = dashboard_fixture(%{name: "Filtered Dashboard"})

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
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      html = render_async(live)

      assert html =~ "Alice"
      refute html =~ "Bob"
      refute html =~ "Charlie"
    end

    test "URL param overrides filter default value", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/dashboards/#{dashboard.id}?user_name=Bob")

      html = render_async(live)

      assert html =~ "Bob"
      refute html =~ "Alice"
      refute html =~ "Charlie"
    end
  end

  describe "with text cards" do
    setup do
      dashboard = dashboard_fixture(%{name: "Dashboard with Text"})
      card = dashboard_card_fixture(dashboard, %{title: "Info Card", card_type: :text})
      {:ok, dashboard: dashboard, card: card}
    end

    test "displays text card title", %{dashboard: dashboard} do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "Info Card"
    end

    test "displays the card in the grid", %{dashboard: dashboard, card: card} do
      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "card-#{card.id}"
    end

    test "renders markdown content as HTML", %{dashboard: dashboard} do
      markdown = "**bold text**\n\n- item one\n- item two"

      _card =
        dashboard_card_fixture(dashboard, %{
          title: "Markdown Card",
          card_type: :text,
          content: %{"text" => markdown}
        })

      {:ok, _live, html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert html =~ "<strong>bold text</strong>"
      assert html =~ "item one"
      assert html =~ "item two"
      assert html =~ "<ul>"
    end
  end
end
