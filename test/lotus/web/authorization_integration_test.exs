defmodule Lotus.Web.AuthorizationIntegrationTest do
  @moduledoc """
  The dashboard asks the resolver before it renders a control and again in the
  handler. A control the user may not use is not rendered, and a crafted event
  for it is refused.
  """

  use Lotus.Web.Case

  use Phoenix.VerifiedRoutes,
    endpoint: Lotus.Web.Endpoint,
    router: Lotus.Web.Test.Router

  alias Lotus.Web.ExportController

  # Mounted with Lotus.Web.Test.RestrictedResolver, which allows only :query
  # and :view_dashboard and denies the rest with "Restricted: <action>".
  describe "a resolver that implements authorize/3" do
    test "the navbar and the empty states offer nothing to create" do
      {:ok, live, html} = live(build_conn(), "/restricted")

      refute has_element?(live, "#new-item-dropdown")
      refute html =~ "Create your first query"

      {:ok, _live, html} = live(build_conn(), "/restricted?tab=dashboards")

      refute html =~ "Create your first dashboard"
    end

    test "the query editor runs the query but hides save, delete, export and AI" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/restricted/queries/#{query.id}")
      html = render_async(live)

      assert html =~ "Alice"
      refute has_element?(live, "#export-csv-btn")
      refute has_element?(live, "#save-query-modal")
      refute has_element?(live, "#delete-query-modal")
      refute has_element?(live, ~s(button[phx-click*="save-query-modal"]))
      refute has_element?(live, ~s(button[phx-click*="delete-query-modal"]))
      refute has_element?(live, "#ai-assistant-btn")
      assert has_element?(live, ~s(#editor-context-menu-wrapper[data-ai-enabled="false"]))
    end

    test "the query editor refuses crafted events" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/restricted/queries/#{query.id}")
      render_async(live)
      page = with_target(live, "#query-editor-page")

      render_click(page, "delete_query", %{})
      assert Lotus.get_query(query.id)
      assert render(live) =~ "Restricted: delete_query"

      render_submit(page, "save_query", %{"query" => %{"name" => "Renamed"}})
      assert Lotus.get_query(query.id).name == "Users"
      assert render(live) =~ "Restricted: update_query"

      render_click(page, "export_csv", %{})
      refute_push_event(live, "open-blank", _)
      assert render(live) =~ "Restricted: export"

      render_click(page, "explain_query", %{})
      assert render(live) =~ "Restricted: ai_generate"
    end

    test "a new query is not saved" do
      {:ok, live, _html} = live(build_conn(), "/restricted/queries/new")

      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{"query" => %{"statement" => "SELECT 1"}})

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "New one"}})

      assert Lotus.list_queries() == []
    end

    test "the dashboard editor shows the dashboard but no control that writes" do
      dashboard = dashboard_fixture(%{name: "Sales"})

      {:ok, live, html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")

      assert html =~ "Sales"
      refute has_element?(live, "#add-card-btn")
      refute has_element?(live, "button", "Add Filter")
      refute has_element?(live, ~s(button[phx-click="show_save_modal"]))
      refute has_element?(live, ~s(button[phx-click="show_delete_modal"]))

      live |> element(~s(button[phx-click="toggle_settings"])) |> render_click()

      refute has_element?(live, ~s(button[phx-click="enable_sharing"]))
      refute has_element?(live, "button", "Delete Dashboard")
    end

    test "the dashboard editor refuses crafted events" do
      dashboard = dashboard_fixture(%{name: "Sales"})

      {:ok, live, _html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")
      editor = with_target(live, "#dashboard-editor")

      render_click(editor, "enable_sharing", %{})
      assert Lotus.get_dashboard(dashboard.id).public_token == nil
      assert render(live) =~ "Restricted: share_dashboard"

      render_submit(editor, "save_dashboard", %{"dashboard" => %{"name" => "Renamed"}})
      assert Lotus.get_dashboard(dashboard.id).name == "Sales"

      render_click(editor, "delete_dashboard", %{})
      assert Lotus.get_dashboard(dashboard.id)
      assert render(live) =~ "Restricted: manage_dashboard"
    end

    test "a dashboard card runs only on a source the user may query" do
      create_test_users()
      dashboard = dashboard_fixture(%{name: "Mixed"})

      allowed = query_fixture(%{name: "Users", statement: "SELECT name FROM test_users"})

      denied =
        query_fixture(%{name: "Report", statement: "SELECT 1 AS n", data_source: "reporting"})

      query_card_fixture(dashboard, allowed, %{title: "Allowed card"})
      query_card_fixture(dashboard, denied, %{title: "Denied card", position: 1})

      {:ok, live, _html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")
      html = render_async(live)

      assert html =~ "Alice"
      assert html =~ "Restricted: query"
    end

    test "a crafted add card event is refused" do
      dashboard = dashboard_fixture(%{name: "Empty"})

      {:ok, live, _html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")

      live
      |> with_target("#dashboard-editor")
      |> render_click("confirm_add_card", %{"type" => "text"})

      html = render(live)
      assert html =~ "Restricted: manage_dashboard"
      refute html =~ ~s(id="card-)
    end

    test "a saved query on a source the user may not query shows the reason on load" do
      query =
        query_fixture(%{name: "Report", statement: "SELECT 1 AS n", data_source: "reporting"})

      {:ok, live, _html} = live(build_conn(), "/restricted/queries/#{query.id}")

      assert render(live) =~ "Restricted: query"
    end

    test "the editor offers only the sources the user may query" do
      {:ok, live, _html} = live(build_conn(), "/restricted/queries/new")

      # The source selector renders its options as listbox items, not <option>.
      assert has_element?(live, ~s(li[role="option"][data-value="public"]))
      refute has_element?(live, ~s(li[role="option"][data-value="reporting"]))
    end

    test "the dashboard hides card settings and refuses crafted card edits" do
      dashboard = dashboard_fixture(%{name: "Cards"})
      card = dashboard_card_fixture(dashboard, %{title: "Note"})

      {:ok, live, _html} = live(build_conn(), "/restricted/dashboards/#{dashboard.id}")

      refute has_element?(live, ~s(button[phx-click="open_card_settings"]))
      refute has_element?(live, ~s(#card-#{card.id}[phx-click]))

      live
      |> with_target("#dashboard-editor")
      |> render_click("delete_card", %{"card-id" => to_string(card.id)})

      assert render(live) =~ "Restricted: manage_dashboard"
      assert has_element?(live, "#card-#{card.id}")

      live |> element(~s(button[phx-click="toggle_settings"])) |> render_click()

      refute has_element?(live, ~s(select[name="auto_refresh_seconds"]))
    end

    test "the export route also needs :query on the source" do
      token =
        ExportController.generate_token(Lotus.Web.Endpoint, %{
          "query_attrs" => %{"statement" => "SELECT 1 AS n", "variables" => []},
          "repo" => "reporting",
          "vars" => %{},
          "filename" => "report.csv"
        })

      conn = get(build_conn(), ~p"/restricted/export/csv?token=#{token}")

      assert conn.status == 403
      assert conn.resp_body == "Restricted: query"
    end

    test "the new dashboard page sends the user back" do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(build_conn(), "/restricted/dashboards/new")

      assert to =~ "/restricted"
    end

    test "the export route answers 403 with the reason" do
      query = users_query()
      token = export_token(query)

      conn = get(build_conn(), ~p"/restricted/export/csv?token=#{token}")

      assert conn.status == 403
      assert conn.resp_body == "Restricted: export"
    end
  end

  # Mounted with Lotus.Web.Test.EditorResolver, which allows everything except
  # running queries on "reporting", where it allows only :discover.
  describe "a source the user may browse but not query" do
    test "the editor lists it" do
      {:ok, live, _html} = live(build_conn(), "/editor/queries/new")

      assert has_element?(live, ~s(li[role="option"][data-value="public"]))
      assert has_element?(live, ~s(li[role="option"][data-value="reporting"]))
    end

    test "a save that moves a query to it is refused" do
      query = query_fixture(%{name: "Moved", statement: "SELECT 1", data_source: "public"})

      {:ok, live, _html} = live(build_conn(), "/editor/queries/#{query.id}")
      render_async(live)

      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{"query" => %{"data_source" => "reporting", "statement" => "SELECT 1"}})

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "Moved"}})

      assert Lotus.get_query(query.id).data_source == "public"
      assert render(live) =~ "Editor: query"
    end

    test "a save that keeps the stored source needs no :query there" do
      query =
        query_fixture(%{name: "Stays", statement: "SELECT 1 AS n", data_source: "reporting"})

      {:ok, live, _html} = live(build_conn(), "/editor/queries/#{query.id}")
      render_async(live)

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "Renamed"}})

      assert Lotus.get_query(query.id).name == "Renamed"
    end

    test "its dropdown options do not run" do
      query = options_query("reporting")

      {:ok, live, _html} = live(build_conn(), "/editor/queries/#{query.id}")

      refute render_async(live) =~ "hidden-option"
    end
  end

  # Mounted with Lotus.Web.Test.ReadOnlyResolver, which implements only
  # resolve_access/1 and returns :read_only.
  describe "a resolver that returns :read_only and has no authorize/3" do
    test "the query editor keeps export and hides save and delete" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/read_only/queries/#{query.id}")
      render_async(live)

      assert has_element?(live, "#export-csv-btn")
      refute has_element?(live, "#save-query-modal")
      refute has_element?(live, "#delete-query-modal")
    end

    test "the handler refuses with the default reason" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/read_only/queries/#{query.id}")
      render_async(live)

      live |> with_target("#query-editor-page") |> render_click("delete_query", %{})

      assert Lotus.get_query(query.id)
      assert render(live) =~ "You don&#39;t have permission to delete queries"
    end

    test "the export route still streams, as it did before" do
      query = users_query()
      token = export_token(query)

      conn = get(build_conn(), ~p"/read_only/export/csv?token=#{token}")

      assert conn.status == 200
      assert conn.resp_body =~ "Alice"
    end
  end

  describe "no resolver" do
    test "dropdown options run on a source the user may query" do
      query = options_query("reporting")

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      assert render_async(live) =~ "hidden-option"
    end

    test "saving a query that was deleted meanwhile sends the user back" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
      render_async(live)

      {:ok, _} = Lotus.delete_query(query)

      assert {:error, {:live_redirect, %{to: _}}} =
               live
               |> with_target("#query-editor-page")
               |> render_submit("save_query", %{"query" => %{"name" => "Gone"}})
    end

    test "a crafted delete on the new query page does nothing" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      html =
        live
        |> with_target("#query-editor-page")
        |> render_click("delete_query", %{})

      assert html =~ "New Query"
    end

    test "saving a dashboard does not turn a disabled public link back on" do
      dashboard = public_dashboard_fixture(%{name: "Shared"})

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      # Someone else turns the link off while this page is open.
      {:ok, _} = Lotus.update_dashboard(dashboard, %{"public_token" => nil})

      live
      |> with_target("#dashboard-editor")
      |> render_submit("save_dashboard", %{"dashboard" => %{"name" => "Shared"}})

      assert Lotus.get_dashboard(dashboard.id).public_token == nil
    end

    test "every control renders" do
      query = users_query()

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
      render_async(live)

      assert has_element?(live, "#new-item-dropdown")
      assert has_element?(live, "#export-csv-btn")
      assert has_element?(live, "#save-query-modal")
      assert has_element?(live, "#delete-query-modal")

      dashboard = dashboard_fixture(%{name: "Sales"})
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      assert has_element?(live, "#add-card-btn")
      assert has_element?(live, ~s(button[phx-click="show_save_modal"]))
      assert has_element?(live, ~s(button[phx-click="show_delete_modal"]))
    end
  end

  # The options query builds its value from two strings, so the value appears in
  # the page only when the query ran, not from the rendered SQL text.
  defp options_query(source) do
    query_fixture(%{
      name: "Options",
      statement: "SELECT {{v}} AS v",
      data_source: source,
      variables: [
        %{
          name: "v",
          type: "text",
          widget: "select",
          options_query: "SELECT 'hidden' || '-option' AS v"
        }
      ]
    })
  end

  defp users_query do
    create_test_users()
    query_fixture(%{name: "Users", statement: "SELECT name FROM test_users ORDER BY name"})
  end

  defp export_token(query) do
    ExportController.generate_token(Lotus.Web.Endpoint, %{
      "query_id" => query.id,
      "repo" => "public",
      "vars" => %{},
      "filename" => "users.csv"
    })
  end
end
