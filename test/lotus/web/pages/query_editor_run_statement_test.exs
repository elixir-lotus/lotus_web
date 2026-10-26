defmodule Lotus.Web.Pages.QueryEditorRunStatementTest do
  # The editor runs the text selected, or the statement at the cursor, as
  # `run_statement`: the query keeps its whole text.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  @scratch "SELECT name FROM test_users WHERE name = 'Alice';\nSELECT email FROM test_users ORDER BY email"

  setup do
    create_test_users()
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    %{live: live}
  end

  defp run(live, params) do
    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(Map.merge(%{"query" => %{"statement" => @scratch}}, params))

    render_async(live)
  end

  defp grid(html) do
    [grid] = Regex.run(~r/id="(results-grid-[^"]+)"/, html, capture: :all_but_first)
    grid
  end

  test "runs the part of the text the editor sends, and keeps the whole text", %{live: live} do
    html = run(live, %{"run_statement" => "SELECT email FROM test_users ORDER BY email"})

    rows = Masu.Test.rows(live, grid(html))
    assert Enum.map(rows, & &1["email"]) == ["alice@test.com", "bob@test.com", "charlie@test.com"]

    # The editor's text is the query's, both statements.
    assert html =~ "SELECT name FROM test_users WHERE name = &#39;Alice&#39;;"
  end

  test "runs the whole text without run_statement", %{live: live} do
    html = run(live, %{"run_statement" => ""})

    assert html =~ "Only a single statement is allowed"
  end

  test "the pages and the grid's filters run the part that ran", %{live: live} do
    html = run(live, %{"run_statement" => "SELECT name FROM test_users ORDER BY name"})
    grid = grid(html)

    Masu.Test.filter(live, grid, [{"name", :starts_with, "C"}])
    render_async(live)

    assert live |> Masu.Test.rows(grid) |> Enum.map(& &1["name"]) == ["Charlie"]
  end

  test "the export runs the part that ran", %{live: live} do
    run(live, %{"run_statement" => "SELECT email FROM test_users"})
    live |> with_target("#query-editor-page") |> render_click("export_csv", %{})

    assert_receive {_ref, {:push_event, "open-blank", %{location: location}}}
    %{"token" => token} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    {:ok, params} = Phoenix.Token.decrypt(Lotus.Web.Endpoint, "lotus_export", token)

    assert params["query_attrs"]["statement"] == "SELECT email FROM test_users"
  end

  test "a saved query's export runs the part that ran, not the saved text" do
    query = query_fixture(%{name: "Users", statement: "SELECT name FROM test_users"})
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
    render_async(live)

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(%{
      "query" => %{"statement" => "SELECT name FROM test_users; SELECT 1 AS one"},
      "run_statement" => "SELECT 1 AS one"
    })

    render_async(live)
    live |> with_target("#query-editor-page") |> render_click("export_csv", %{})

    assert_receive {_ref, {:push_event, "open-blank", %{location: location}}}
    %{"token" => token} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    {:ok, params} = Phoenix.Token.decrypt(Lotus.Web.Endpoint, "lotus_export", token)

    refute Map.has_key?(params, "query_id")
    assert params["query_attrs"]["statement"] == "SELECT 1 AS one"
  end

  test "the run buttons say what they run", %{live: live} do
    live
    |> with_target("#query-editor-page")
    |> render_click("editor_content_changed", %{"statement" => @scratch})

    assert has_element?(live, ~s(#toolbar-run-query-tippy[data-title="Run query"]))

    live
    |> with_target("#query-editor-page")
    |> render_click("editor_run_scope", %{"scope" => "selection"})

    assert has_element?(live, ~s(#toolbar-run-query-tippy[data-title="Run selection"]))
    assert has_element?(live, ~s(#run-query-btn[title="Run selection"]))

    live
    |> with_target("#query-editor-page")
    |> render_click("editor_run_scope", %{"scope" => "statement"})

    assert has_element?(live, ~s(#toolbar-run-query-tippy[data-title="Run statement at cursor"]))

    live
    |> with_target("#query-editor-page")
    |> render_click("editor_run_scope", %{"scope" => "nonsense"})

    assert has_element?(live, ~s(#toolbar-run-query-tippy[data-title="Run query"]))
  end

  test "the editor gets the lexical rules the server tokenizes the source with", %{live: live} do
    live
    |> with_target("#query-editor-page")
    |> render_hook("fetch_dialect_config", %{"dialect" => "postgres"})

    assert_reply(live, %{config: %{tokenizer: tokenizer}})
    assert tokenizer[:dollar_quotes?] == true
    assert tokenizer[:nested_block_comments?] == true
    assert tokenizer.string_quotes == ["'"]
  end
end
