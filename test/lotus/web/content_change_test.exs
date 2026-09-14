defmodule Lotus.Web.ContentChangeTest do
  @moduledoc """
  Every content change the dashboard makes carries the actor, and a change a
  `:before_content_change` plug refuses is reported as refused, with nothing
  written.
  """

  use Lotus.Web.Case

  defmodule RecorderPlug do
    def init(opts), do: opts

    def call(payload, _opts) do
      recipient = :persistent_term.get({__MODULE__, :recipient})
      send(recipient, {:content_change, payload.op, payload.resource, payload.context})
      {:cont, payload}
    end
  end

  defmodule RefusePlug do
    def init(opts), do: opts

    def call(payload, _opts) do
      if payload.resource in :persistent_term.get({__MODULE__, :resources}, []),
        do: {:halt, "Refused by test"},
        else: {:cont, payload}
    end
  end

  @refused "The change was refused: Refused by test"

  # Lotus.Web.Test.ScopedResolver resolves this context for /scoped.
  @context %{user_id: 42}

  setup do
    previous = Application.get_env(:lotus, :middleware)

    Application.put_env(:lotus, :middleware, %{
      before_content_change: [{RefusePlug, []}],
      after_content_change: [{RecorderPlug, []}]
    })

    Lotus.Config.reload!()
    Lotus.Middleware.compile(Lotus.Config.middleware())
    :persistent_term.put({RecorderPlug, :recipient}, self())
    refuse([])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lotus, :middleware, previous),
        else: Application.delete_env(:lotus, :middleware)

      Lotus.Config.reload!()
      Lotus.Middleware.compile(Lotus.Config.middleware())
      :persistent_term.erase({RecorderPlug, :recipient})
      :persistent_term.erase({RefusePlug, :resources})
    end)

    :ok
  end

  describe "queries" do
    test "saving a new query passes the actor" do
      {:ok, live, _html} = live(build_conn(), "/scoped/queries/new")

      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{"query" => %{"statement" => "SELECT 1"}})

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "Scoped"}})

      assert_receive {:content_change, :create, :query, @context}
    end

    test "a refused save keeps the editor and says why" do
      query = query_fixture(%{name: "Original", statement: "SELECT 1"})
      refuse([:query])

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "Renamed"}})

      assert_push_event(live, "toast", %{message: @refused})
      assert Lotus.get_query(query.id).name == "Original"
      assert render(live) =~ "query-editor-page"
    end

    test "a refused chart settings write leaves the query unsaved too" do
      query = query_fixture(%{name: "Original", statement: "SELECT 1"})
      refuse([:visualization])

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      # The saved query runs on load. Its result renders the page again from the
      # LiveView's assigns, which would drop a config set before it arrives.
      render_async(live)

      Phoenix.LiveView.send_update(live.pid, Lotus.Web.QueryEditorPage,
        id: "page",
        visualization_config: %{"chart_type" => "bar", "x_field" => "a", "y_field" => "b"}
      )

      render(live)

      live
      |> with_target("#query-editor-page")
      |> render_submit("save_query", %{"query" => %{"name" => "Renamed"}})

      assert_push_event(live, "toast", %{message: @refused})
      assert Lotus.get_query(query.id).name == "Original"
      assert Lotus.list_visualizations(query.id) == []
    end

    test "deleting a query passes the actor, and a refused delete keeps it" do
      query = query_fixture(%{name: "Keep", statement: "SELECT 1"})
      refuse([:query])

      {:ok, live, _html} = live(build_conn(), "/scoped/queries/#{query.id}")

      live |> with_target("#query-editor-page") |> render_click("delete_query", %{})

      assert_push_event(live, "toast", %{message: @refused})
      assert Lotus.get_query(query.id)

      refuse([])

      live |> with_target("#query-editor-page") |> render_click("delete_query", %{})

      assert_receive {:content_change, :delete, :query, @context}
      refute Lotus.get_query(query.id)
    end
  end

  describe "dashboards" do
    test "saving a dashboard passes the actor to every write" do
      dashboard = dashboard_fixture(%{name: "Sales"})
      dashboard_card_fixture(dashboard, %{title: "Note"})

      {:ok, live, _html} = live(build_conn(), "/scoped/dashboards/#{dashboard.id}")

      live
      |> with_target("#dashboard-editor")
      |> render_submit("save_dashboard", %{"dashboard" => %{"name" => "Sales"}})

      assert_receive {:content_change, :update, :dashboard, @context}
      assert_receive {:content_change, :update, :dashboard_card, @context}
    end

    test "a refused card write leaves the whole save unwritten" do
      dashboard = dashboard_fixture(%{name: "Original"})
      dashboard_card_fixture(dashboard, %{title: "Note"})
      refuse([:dashboard_card])

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      live
      |> with_target("#dashboard-editor")
      |> render_submit("save_dashboard", %{"dashboard" => %{"name" => "Renamed"}})

      assert render(live) =~ @refused
      assert Lotus.get_dashboard(dashboard.id).name == "Original"
    end

    test "sharing uses the sharing functions with the actor" do
      dashboard = dashboard_fixture(%{name: "Shared"})

      {:ok, live, _html} = live(build_conn(), "/scoped/dashboards/#{dashboard.id}")
      editor = with_target(live, "#dashboard-editor")

      render_click(editor, "enable_sharing", %{})

      assert_receive {:content_change, :enable_sharing, :dashboard, @context}
      token = Lotus.get_dashboard(dashboard.id).public_token
      assert is_binary(token)
      assert render(live) =~ token

      render_click(editor, "disable_sharing", %{})

      assert_receive {:content_change, :disable_sharing, :dashboard, @context}
      assert Lotus.get_dashboard(dashboard.id).public_token == nil
    end

    test "a refused share link says why" do
      dashboard = dashboard_fixture(%{name: "Private"})
      refuse([:dashboard])

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      live |> with_target("#dashboard-editor") |> render_click("enable_sharing", %{})

      assert render(live) =~ @refused
      assert Lotus.get_dashboard(dashboard.id).public_token == nil
    end

    test "a refused delete keeps the dashboard and says why" do
      dashboard = dashboard_fixture(%{name: "Keep"})
      refuse([:dashboard])

      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")

      live |> with_target("#dashboard-editor") |> render_click("delete_dashboard", %{})

      assert render(live) =~ @refused
      assert Lotus.get_dashboard(dashboard.id)
    end
  end

  defp refuse(resources), do: :persistent_term.put({RefusePlug, :resources}, resources)
end
