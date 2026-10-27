defmodule Lotus.Web.Pages.QueryEditorDropdownOptionsTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  # A new query with a {{name}} variable, its widget a dropdown, and the
  # dropdown's options modal open.
  defp open_options_modal do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_content_changed", %{
      "statement" => "SELECT name FROM test_users WHERE name = {{name}}"
    })

    live
    |> with_target("#query-editor-page")
    |> render_hook("variables_detected", %{"variables" => ["name"]})

    live |> with_target("#query-editor-page") |> render_hook("request_editor_schema", %{})
    live |> element("#variable-settings-btn") |> render_click()

    live
    |> element("#variable-settings-form")
    |> render_change(%{"query" => %{"variables" => %{"0" => %{"widget" => "select"}}}})

    live |> element(~s([phx-click="open_dropdown_options_modal"])) |> render_click()

    live
  end

  defp choose_source(live, source) do
    live
    |> element(~s(#dropdown-options-modal [phx-value-source="#{source}"]))
    |> render_click()
  end

  defp test_options(live) do
    live |> element("#dropdown-options-modal button", "Test Query") |> render_click()

    # The modal asks the page, which answers the modal: one message each.
    render(live)
    render(live)
  end

  defp save_options(live) do
    live |> element("#dropdown-options-modal button", "Done") |> render_click()
    render(live)
  end

  setup do
    create_test_users()
    :ok
  end

  describe "SQL in the editor" do
    test "previews every option, the columns it reads and what to look at" do
      live = open_options_modal()
      choose_source(live, "query")

      live
      |> element("#options-sql-editor-name")
      |> render_hook("update_sql_query", %{
        "value" => "SELECT name, email, age FROM test_users UNION ALL SELECT 'Alice', 'a', 1"
      })

      html = test_options(live)

      assert html =~ "4 options"
      assert html =~ "Runs on"
      assert html =~ ~r/value ←\s*<code[^>]*>name<\/code>/
      assert html =~ ~r/label ←\s*<code[^>]*>email<\/code>/
      assert html =~ "1 value comes more than once"
      assert html =~ "age is left out"
      assert html =~ "charlie@test.com"
    end

    test "fills the dropdown once saved" do
      live = open_options_modal()
      choose_source(live, "query")

      live
      |> element("#options-sql-editor-name")
      |> render_hook("update_sql_query", %{"value" => "SELECT name FROM test_users ORDER BY name"})

      test_options(live)
      html = save_options(live)

      refute html =~ "dropdown-options-modal"
      assert html =~ "Charlie"
    end

    test "shows why a query failed" do
      live = open_options_modal()
      choose_source(live, "query")

      live
      |> element("#options-sql-editor-name")
      |> render_hook("update_sql_query", %{"value" => "SELECT nope FROM test_users"})

      html = test_options(live)

      assert html =~ "dropdown-options-error"
      assert html =~ "nope"
    end
  end

  describe "a column picked from a table" do
    test "writes the SQL that lists each value once" do
      live = open_options_modal()
      choose_source(live, "columns")

      live |> element("#dropdown-options-columns") |> render_change(%{"table" => "test_users"})

      html =
        live
        |> element("#dropdown-options-columns")
        |> render_change(%{
          "table" => "test_users",
          "value_column" => "name",
          "label_column" => "email"
        })

      assert html =~
               ~s(SELECT DISTINCT &quot;name&quot; AS value, &quot;email&quot; AS label FROM &quot;test_users&quot;)

      html = test_options(live)
      assert html =~ "3 options"

      html = save_options(live)
      assert html =~ "bob@test.com"
    end
  end

  describe "a saved query" do
    test "fills the dropdown from the saved query and follows it" do
      saved =
        query_fixture(%{
          name: "User names",
          statement: "SELECT name FROM test_users WHERE active ORDER BY name"
        })

      live = open_options_modal()
      choose_source(live, "saved_query")

      html =
        live
        |> element("#dropdown-options-saved-query")
        |> render_change(%{"saved_query_id" => to_string(saved.id)})

      assert html =~ "Open this query"

      html = test_options(live)
      assert html =~ "2 options"

      html = save_options(live)
      assert html =~ "Charlie"
      refute html =~ "Bob"

      live
      |> element(~s(form[phx-submit="save_query"]))
      |> render_submit(%{"query" => %{"name" => "Users by name", "description" => ""}})

      stored = Enum.find(Lotus.list_queries(), &(&1.name == "Users by name"))
      assert [%{options_query_id: id, options_query: nil}] = stored.variables
      assert id == saved.id
    end

    test "a dropdown whose saved query is gone says so" do
      query =
        query_fixture(%{
          statement: "SELECT name FROM test_users WHERE name = {{name}}",
          variables: [%{name: "name", type: :text, widget: :select, options_query_id: 999_999}]
        })

      {:ok, _live, html} = live(build_conn(), "/lotus/queries/#{query.id}")

      assert html =~ "Options failed"
      assert html =~ "no longer exists"
    end
  end
end
