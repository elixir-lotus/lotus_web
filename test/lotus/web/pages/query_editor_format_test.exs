defmodule Lotus.Web.Pages.QueryEditorFormatTest do
  # The editor formats SQL in the browser (formatter.js), in the dialect of
  # the source; the page offers it for SQL and JSON sources.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    # The editor asks for its schema and dialect when it mounts (EditorForm).
    live |> with_target("#query-editor-page") |> render_click("request_editor_schema", %{})
    %{live: live}
  end

  test "a SQL source offers Format", %{live: live} do
    assert has_element?(live, ~s(#format-query-btn[data-title="Format query"]))

    assert has_element?(
             live,
             ~s([data-editor-formattable="true"][data-editor-dialect="postgres"])
           )
  end

  test "Format asks the editor to format in the source's dialect", %{live: live} do
    live |> element("#format-query-btn") |> render_click()

    assert_push_event(live, "format-editor-content", %{dialect: "postgres"})
  end

  test "SQL the editor cannot format leaves a short message", %{live: live} do
    live
    |> with_target("#query-editor-page")
    |> render_click("format-editor-content-error", %{
      "error" => ~s(Parse error: Unexpected "(" at line 1 column 8.)
    })

    assert_push_event(live, "toast", %{message: message})
    assert message =~ "Could not format query: Parse error"
  end

  test "before the editor asks for its source's language, no Format" do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

    refute has_element?(live, "#format-query-btn")
    assert has_element?(live, ~s([data-editor-formattable="false"]))
  end
end
