defmodule Lotus.Web.Pages.QueryEditorClearTest do
  # The editor sends its text as the person writes. Cleared, a saved
  # query's editor stays empty: the server does not put the saved statement
  # back.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  defp statement(live) do
    [textarea] =
      live
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(textarea[phx-hook="EditorForm"]))
      |> Enum.to_list()

    LazyHTML.text(textarea)
  end

  test "a saved query's editor, cleared, stays empty" do
    query = query_fixture(%{statement: "SELECT 42 AS answer WHERE {{x}} = 1"})
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
    assert statement(live) =~ "SELECT 42 AS answer"

    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_content_changed", %{"statement" => ""})

    assert String.trim(statement(live)) == ""

    # The editor tells the server the text's variables a moment later.
    live
    |> with_target("#query-editor-page")
    |> render_hook("variables_detected", %{"variables" => []})

    assert String.trim(statement(live)) == ""

    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_content_changed", %{"statement" => "SELECT 1"})

    assert statement(live) =~ "SELECT 1"
  end
end
