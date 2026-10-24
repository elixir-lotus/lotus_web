defmodule Lotus.Web.CommandsTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest
  import Jumon.Test

  describe "searching" do
    test "finds saved queries and dashboards, forgiving a typo" do
      query = query_fixture(%{name: "Orders by status"})
      dashboard = dashboard_fixture(%{name: "Business overview"})

      {:ok, view, _html} = live(build_conn(), "/lotus")

      queries = Enum.filter(search(view, "ordrs"), &(&1["source"] == "queries"))
      assert names(queries) == ["Orders by status"]
      assert hd(queries)["perform"]["to"] =~ "/lotus/queries/#{query.id}"

      dashboards = Enum.filter(search(view, "busines"), &(&1["source"] == "dashboards"))
      assert names(dashboards) == ["Business overview"]
      assert hd(dashboards)["perform"]["to"] =~ "/lotus/dashboards/#{dashboard.id}"
    end
  end

  describe "actions" do
    test "offer the pages, and what the user may create" do
      {:ok, view, _html} = live(build_conn(), "/lotus")
      names = view |> actions() |> names()

      assert "Queries" in names
      assert "Dashboards" in names
      assert "New query" in names
      assert "New dashboard" in names
    end

    test "leave out what a read-only user may not create" do
      {:ok, view, _html} = live(build_conn(), "/read_only")
      names = view |> actions() |> names()

      refute "New query" in names
      refute "New dashboard" in names
    end

    test "offer the themes only when there is a choice" do
      {:ok, view, _html} = live(build_conn(), "/lotus")
      assert "Theme" in names(actions(view))

      {:ok, view, _html} = live(build_conn(), "/one_theme")
      refute "Theme" in names(actions(view))
    end

    test "the query editor adds its own actions, which leave with it" do
      query = query_fixture(%{name: "Users"})

      {:ok, view, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
      assert "Run query" in names(actions(view))

      {:ok, view, _html} = live(build_conn(), "/lotus")
      refute "Run query" in names(actions(view))
    end
  end

  test "a public dashboard has no palette" do
    dashboard = public_dashboard_fixture()

    {:ok, _view, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    refute html =~ ~s(phx-hook="Jumon")
  end

  describe "Ask AI" do
    @describetag capture_log: true

    setup do
      Application.put_env(:lotus, :ai, enabled: true, model: "openai:gpt-4o", api_key: "sk-test")
      # The questions asked here go nowhere, at once.
      Application.put_env(:req_llm, :openai, base_url: "http://127.0.0.1:1/v1")
      Lotus.Config.reload!()

      on_exit(fn ->
        Application.delete_env(:req_llm, :openai)
        Application.delete_env(:lotus, :ai)
        Lotus.Config.reload!()
      end)
    end

    test "is an action of the query editor, which asks for a question" do
      {:ok, view, _html} = live(build_conn(), "/lotus/queries/new")

      assert %{"args" => [%{"name" => "question"}]} =
               view |> actions() |> Enum.find(&(&1["name"] == "Ask AI"))

      {:ok, view, _html} = live(build_conn(), "/lotus")
      refute "Ask AI" in names(actions(view))
    end

    test "opens the assistant on the question" do
      {:ok, view, _html} = live(build_conn(), "/lotus/queries/new")

      assert %{"ok" => true} = run(view, :ask_ai, %{"question" => "Revenue by month"})

      html = render(view)
      assert html =~ "Revenue by month"
      assert html =~ "Writing the query"
    end
  end

  test "Ask AI is not offered with AI off" do
    {:ok, view, _html} = live(build_conn(), "/lotus/queries/new")
    refute "Ask AI" in names(actions(view))
  end
end
