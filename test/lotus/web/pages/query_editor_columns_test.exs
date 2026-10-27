defmodule Lotus.Web.Pages.QueryEditorColumnsTest do
  # The editor gets a source's tables when it opens, and the columns of the
  # tables a statement uses as the person writes it.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    live |> with_target("#query-editor-page") |> render_click("request_editor_schema", %{})
    %{live: live}
  end

  defp editor_schema(live) do
    [json] =
      live
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-editor-schema]")
      |> LazyHTML.attribute("data-editor-schema")

    JSON.decode!(json)
  end

  defp ask(live, tables) do
    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_columns", %{"tables" => tables})

    assert_reply(live, %{columns: columns})
    columns
  end

  test "the editor opens with the tables, not their columns", %{live: live} do
    schema = editor_schema(live)

    assert Map.has_key?(schema, "test_users")
    assert schema["test_users"] == nil

    assert render(live) =~ ~s(data-editor-schemas="[&quot;public&quot;]")
    assert has_element?(live, ~s([data-editor-source="public"]))
  end

  test "describes the tables a statement uses, and keeps them", %{live: live} do
    columns = ask(live, ["test_users", "nowhere"])

    assert Map.keys(columns) == ["test_users"]
    assert "email" in columns["test_users"]

    schema = editor_schema(live)
    assert "email" in schema["test_users"]
    assert schema["test_posts"] == nil

    # Asked again, from what it keeps.
    assert ask(live, ["test_users"]) == columns
  end

  test "says each column's type, for the columns it describes and keeps", %{live: live} do
    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_columns", %{"tables" => ["test_users"]})

    assert_reply(live, %{columns: %{"test_users" => names}, types: %{"test_users" => types}})
    assert Map.keys(types) |> Enum.sort() == Enum.sort(names)
    assert is_binary(types["email"])

    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_columns", %{"tables" => ["test_users"]})

    assert_reply(live, %{types: %{"test_users" => ^types}})
  end

  test "keeps the columns when the editor's source comes back", %{live: live} do
    ask(live, ["test_users"])

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_change(%{"query" => %{"data_source" => "reporting"}})

    # Another source: its own tables, not described yet.
    assert editor_schema(live)["test_users"] == nil

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_change(%{"query" => %{"data_source" => "public"}})

    assert "email" in editor_schema(live)["test_users"]
  end

  test "ignores a request that names no tables", %{live: live} do
    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_columns", %{"tables" => "test_users"})

    assert_reply(live, %{columns: %{}, types: %{}})
  end
end
