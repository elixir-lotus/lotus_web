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

  describe "cascading filters" do
    setup do
      create_test_users()
      create_test_posts()

      dashboard = dashboard_fixture(%{name: "Cascading Dashboard"})

      titles =
        query_fixture(%{
          name: "Post Titles",
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

      {:ok, post_title} =
        Lotus.create_dashboard_filter(dashboard, %{
          name: "post_title",
          label: "Post",
          filter_type: :select,
          widget: :select,
          source_query_id: titles.id,
          depends_on_filter_id: user_name.id,
          position: 1
        })

      {:ok, dashboard: dashboard, titles: titles, user_name: user_name, post_title: post_title}
    end

    test "lists the options of a dependent filter for the parent value", %{dashboard: dashboard} do
      {:ok, live, _html} =
        live(build_conn(), "/lotus/dashboards/#{dashboard.id}?user_name=Alice")

      assert has_element?(live, "select[name='filter[post_title]'] option", "First Post")
      assert has_element?(live, "select[name='filter[post_title]'] option", "Draft Post")
      refute has_element?(live, "select[name='filter[post_title]'] option", "Another Post")
    end

    test "disables the dependent filter while the parent has no value", %{dashboard: dashboard} do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert has_element?(live, "select[name='filter[post_title]'][disabled]")
      refute has_element?(live, "select[name='filter[user_name]'][disabled]")
    end

    test "a parent change lists the new options and clears the child value", %{
      dashboard: dashboard
    } do
      {:ok, live, _html} =
        live(
          build_conn(),
          "/lotus/dashboards/#{dashboard.id}?user_name=Alice&post_title=First+Post"
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

    test "shows the error of a failing source query", %{dashboard: dashboard, post_title: filter} do
      broken = query_fixture(%{statement: "SELECT missing_column FROM test_users"})
      {:ok, _filter} = Lotus.update_dashboard_filter(filter, %{source_query_id: broken.id})

      {:ok, live, _html} =
        live(build_conn(), "/lotus/dashboards/#{dashboard.id}?user_name=Alice")

      assert has_element?(live, "#filter-post_title-error")
      assert render(live) =~ "Cascading Dashboard"
    end

    test "the filter editor shows the source query and the parent filter", %{
      dashboard: dashboard,
      post_title: filter,
      user_name: parent,
      titles: titles
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
      open_filter_editor(live, filter)

      assert has_element?(
               live,
               "select[name='filter[source_query_id]'] option[value='#{titles.id}'][selected]"
             )

      assert has_element?(
               live,
               "select[name='filter[depends_on_filter_id]'] option[value='#{parent.id}'][selected]"
             )

      refute has_element?(
               live,
               "select[name='filter[depends_on_filter_id]'] option[value='#{filter.id}']"
             )
    end

    test "the filter editor shows the dependency errors", %{
      dashboard: dashboard,
      post_title: child,
      user_name: parent,
      titles: titles
    } do
      other_dashboard = dashboard_fixture()

      {:ok, other_filter} =
        Lotus.create_dashboard_filter(other_dashboard, %{
          name: "other",
          label: "Other",
          filter_type: :text,
          widget: :input,
          position: 0
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      cases = [
        {parent, %{"widget" => "input", "filter_type" => "text", "source_query_id" => titles.id},
         "needs the select widget"},
        {parent, %{"depends_on_filter_id" => child.id}, "needs a source query"},
        {child, %{"depends_on_filter_id" => child.id}, "cannot be the filter itself"},
        {child, %{"depends_on_filter_id" => other_filter.id},
         "must be a filter of the same dashboard"},
        {parent, %{"source_query_id" => titles.id, "depends_on_filter_id" => child.id},
         "would create a dependency cycle"}
      ]

      for {filter, params, message} <- cases do
        open_filter_editor(live, filter)
        html = submit_filter(live, filter, params)

        assert html =~ message
        assert has_element?(live, "#filter-modal")
        live |> element("#filter-modal button", "Cancel") |> render_click()
      end
    end

    test "saves a dependency on a filter added in the same edit", %{
      dashboard: dashboard,
      titles: titles
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      live |> element("#filter-bar button", "Add Filter") |> render_click()

      live
      |> element("#filter-modal form")
      |> render_submit(%{
        "filter" => %{
          "label" => "Author",
          "name" => "author",
          "filter_type" => "select",
          "widget" => "select",
          "options" => "Alice\nBob"
        }
      })

      live |> element("#filter-bar button", "Add Filter") |> render_click()

      [_match, author_id] =
        Regex.run(~r/<option value="(new_\d+)"[^>]*>\s*Author/, render(live))

      live
      |> element("#filter-modal form")
      |> render_submit(%{
        "filter" => %{
          "label" => "Title",
          "name" => "title",
          "filter_type" => "select",
          "widget" => "select",
          "source_query_id" => to_string(titles.id),
          "depends_on_filter_id" => author_id
        }
      })

      live |> element("button", "Save") |> render_click()

      live
      |> element("#save-dashboard-modal form")
      |> render_submit(%{"dashboard" => %{"name" => "Cascading Dashboard"}})

      filters = Map.new(Lotus.list_dashboard_filters(dashboard.id), &{&1.name, &1})

      assert filters["title"].source_query_id == titles.id
      assert filters["title"].depends_on_filter_id == filters["author"].id
    end

    test "deleting the parent filter removes the dependency", %{
      dashboard: dashboard,
      user_name: parent
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert has_element?(live, "select[name='filter[post_title]'][disabled]")

      live
      |> element("button[phx-click='delete_filter'][phx-value-filter-id='#{parent.id}']")
      |> render_click()

      refute has_element?(live, "select[name='filter[post_title]'][disabled]")
    end
  end

  defp open_filter_editor(live, filter) do
    live
    |> element("button[phx-click='edit_filter'][phx-value-filter-id='#{filter.id}']")
    |> render_click()
  end

  defp submit_filter(live, filter, params) do
    base = %{
      "label" => filter.label,
      "name" => filter.name,
      "filter_type" => to_string(filter.filter_type),
      "widget" => to_string(filter.widget),
      "source_query_id" => to_string(filter.source_query_id || ""),
      "depends_on_filter_id" => to_string(filter.depends_on_filter_id || "")
    }

    params = Map.new(params, fn {key, value} -> {key, to_string(value)} end)

    live
    |> element("#filter-modal form")
    |> render_submit(%{"filter" => Map.merge(base, params)})
  end
end
