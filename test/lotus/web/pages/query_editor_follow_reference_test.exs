defmodule Lotus.Web.Pages.QueryEditorFollowReferenceTest do
  # A foreign key's cell in the results opens the row it references, in a
  # new query.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    create_test_users()
    create_test_posts()
    :ok
  end

  defp run(live, statement) do
    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(%{"query" => %{"statement" => statement}})

    html = render_async(live)
    [grid] = Regex.run(~r/id="(results-grid-[^"]+)"/, html, capture: :all_but_first)
    grid
  end

  # The first post's row, and its id in the grid: a hash of its cells
  # (`MasuResults`), the first of its values.
  defp first_post do
    %{rows: [[id, title, user_id] = row]} =
      Lotus.Web.TestRepo.query!("SELECT id, title, user_id FROM test_posts ORDER BY id LIMIT 1")

    {:erlang.phash2({row, 0}), id, title, user_id}
  end

  test "a foreign key's cell opens the row it references in a new tab" do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    grid = run(live, "SELECT id, title, user_id FROM test_posts ORDER BY id")
    {row_id, _id, _title, user_id} = first_post()

    Masu.Test.cell_action(live, grid, "Open test_users row", "user_id", row_id)

    assert_push_event(live, "open-blank", %{location: location})
    %URI{path: path, query: query} = URI.parse(location)
    assert path == "/lotus/queries/new"

    assert URI.decode_query(query) == %{
             "follow_source" => "public",
             "follow_schema" => "public",
             "follow_table" => "test_users",
             "follow_column" => "id",
             "follow_value" => to_string(user_id)
           }

    # The new tab: the row's query, run.
    {:ok, live, html} = live(build_conn(), location)

    assert html =~
             "SELECT * FROM &quot;public&quot;.&quot;test_users&quot; WHERE &quot;id&quot; = {{id}}"

    html = render_async(live)
    assert html =~ "alice@test.com"
    refute html =~ "bob@test.com"
  end

  test "the grid offers it only on foreign key columns of a plain select" do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    grid = run(live, "SELECT id, title, user_id FROM test_posts ORDER BY id")
    {row_id, _id, _title, _user_id} = first_post()

    assert_raise ExUnit.AssertionError, fn ->
      Masu.Test.cell_action(live, grid, "Open test_users row", "title", row_id)
    end

    grid =
      run(
        live,
        "SELECT p.id, p.user_id FROM test_posts p JOIN test_users u ON u.id = p.user_id ORDER BY p.id"
      )

    assert_raise ExUnit.AssertionError, fn ->
      Masu.Test.cell_action(live, grid, "Open test_users row", "user_id", 0)
    end
  end

  test "a new query for a table the source does not describe opens empty" do
    {:ok, _live, html} =
      live(
        build_conn(),
        "/lotus/queries/new?follow_source=public&follow_table=nowhere&follow_column=id&follow_value=1"
      )

    refute html =~ "nowhere"
  end

  test "a source the person may not query opens nothing" do
    path =
      "/editor/queries/new?follow_source=reporting&follow_schema=reporting" <>
        "&follow_table=customers&follow_column=id&follow_value=1"

    {:ok, _live, html} = live(build_conn(), path)
    refute html =~ "customers"
  end
end
