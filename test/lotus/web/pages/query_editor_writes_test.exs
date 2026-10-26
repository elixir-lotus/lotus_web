defmodule Lotus.Web.Pages.QueryEditorWritesTest do
  # On a source that takes writes, a statement that changes data waits for
  # the person to say so, every time it would run; an export never runs one.
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  alias Lotus.Web.ExportController
  alias Lotus.Web.TestRepo

  @update "UPDATE test_users SET age = age + 1 WHERE name = 'Alice'"

  setup do
    create_test_users()
    writable(true)
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    %{live: live}
  end

  defp writable(on?) do
    previous = Application.get_env(:lotus, :data_source_read_only)

    if on?,
      do: Application.put_env(:lotus, :data_source_read_only, %{"public" => false}),
      else: Application.delete_env(:lotus, :data_source_read_only)

    Lotus.Config.reload!()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lotus, :data_source_read_only, previous),
        else: Application.delete_env(:lotus, :data_source_read_only)

      Lotus.Config.reload!()
    end)
  end

  defp run(live, statement) do
    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(%{"query" => %{"statement" => statement}})

    render_async(live)
  end

  defp age(name) do
    %{rows: [[age]]} = TestRepo.query!("SELECT age FROM test_users WHERE name = $1", [name])
    age
  end

  test "a statement that changes data asks first, and runs once said", %{live: live} do
    html = run(live, @update)

    assert html =~ "Change data in public?"
    assert age("Alice") == 30

    live |> element("#write-query-confirm") |> render_click()
    html = render_async(live)

    assert age("Alice") == 31
    refute html =~ "Change data in public?"
    assert html =~ "1 row changed"
    # Its export would run it again: there is none.
    refute html =~ "Export (.csv)"
  end

  test "cancelled, it does not run", %{live: live} do
    run(live, @update)
    live |> with_target("#query-editor-page") |> render_click("cancel_write", %{})

    refute render(live) =~ "Change data in public?"
    assert age("Alice") == 30
  end

  test "a read runs without asking", %{live: live} do
    html = run(live, "SELECT name FROM test_users ORDER BY name")

    refute html =~ "Change data in public?"
    assert html =~ "Showing"
  end

  test "a read-only source refuses it without asking" do
    writable(false)
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

    html = run(live, @update)

    refute html =~ "Change data in public?"
    assert age("Alice") == 30
  end

  test "a page of its results asks again", %{live: live} do
    run(live, "UPDATE test_users SET age = age + 1 RETURNING name")
    live |> element("#write-query-confirm") |> render_click()
    render_async(live)
    assert age("Alice") == 31

    html =
      live |> with_target("#query-editor-page") |> render_click("goto_page", %{"index" => "0"})

    assert html =~ "Change data in public?"
    assert age("Alice") == 31
  end

  test "an export does not run a statement that changes data" do
    conn = build_conn()

    params = %{
      "query_attrs" => %{"statement" => @update, "data_source" => "public", "variables" => []},
      "repo" => "public",
      "vars" => %{},
      "filename" => "users.csv"
    }

    token = ExportController.generate_token(Lotus.Web.Endpoint, params)

    assert_raise RuntimeError, ~r/Only read-only queries are allowed/, fn ->
      get(conn, "/lotus/export/csv?token=#{token}")
    end

    assert age("Alice") == 30
  end

  describe "the Stop button" do
    test "shows once the source gives the running statement's token", %{live: live} do
      refute has_element?(live, "#stop-query-btn")

      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_submit(%{"query" => %{"statement" => "SELECT pg_sleep(0.5)"}})

      # Postgres can stop a statement: the token arrives as it starts.
      assert eventually(fn -> has_element?(live, "#stop-query-btn") end)
      assert has_element?(live, "#toolbar-stop-query-btn")

      render_async(live, 2_000)
      refute has_element?(live, "#stop-query-btn")
      assert has_element?(live, "#run-query-btn")
    end

    test "a token of an earlier run does not show it", %{live: live} do
      Phoenix.LiveView.send_update(live.pid, Lotus.Web.QueryEditorPage,
        id: "page",
        action: :cancel_token,
        run: make_ref(),
        token: :spent
      )

      refute has_element?(live, "#stop-query-btn")
    end

    # Stopping it is Lotus's `cancel/1`, tested against a real pool in
    # Lotus: here, the sandbox's one connection would wait for the statement.
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
