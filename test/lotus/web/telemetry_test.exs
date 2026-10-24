defmodule Lotus.Web.TelemetryTest do
  @moduledoc """
  The dashboard's telemetry (`Lotus.Web.Telemetry`): views, card runs,
  exports and AI actions.
  """
  use Lotus.Web.Case, async: false

  use Phoenix.VerifiedRoutes,
    endpoint: Lotus.Web.Endpoint,
    router: Lotus.Web.Test.Router

  import Phoenix.LiveViewTest

  alias Lotus.Web.ExportController

  defp attach(events) do
    pid = self()
    id = "telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      id,
      events,
      fn event, measurements, metadata, _ -> send(pid, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp query_card(dashboard, query) do
    dashboard_card_fixture(dashboard, %{
      card_type: :query,
      query_id: query.id,
      content: %{}
    })
  end

  describe "a dashboard" do
    setup do
      attach([[:lotus_web, :dashboard, :view], [:lotus_web, :card, :run, :stop]])
      dashboard = public_dashboard_fixture(%{name: "Sales"})
      query = query_fixture(%{statement: "SELECT 1 AS n"})
      card = query_card(dashboard, query)
      %{dashboard: dashboard, query: query, card: card}
    end

    test "opened in the app: one view, and each card's run", %{
      dashboard: dashboard,
      query: query,
      card: card
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
      render_async(live)

      dashboard_id = dashboard.id
      query_id = query.id

      assert_receive {[:lotus_web, :dashboard, :view], %{system_time: _},
                      %{dashboard: %{id: ^dashboard_id}, public: false}}

      assert_receive {[:lotus_web, :card, :run, :stop], %{duration: _},
                      %{
                        dashboard_id: ^dashboard_id,
                        card_id: card_id,
                        query: %{id: ^query_id},
                        public: false,
                        status: :ok,
                        result: {:ok, %Lotus.Result{}}
                      }}

      assert card_id == card.id
      refute_receive {[:lotus_web, :dashboard, :view], _, _}
    end

    test "opened through its share link: a public view, with no context", %{
      dashboard: dashboard
    } do
      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      render_async(live)

      dashboard_id = dashboard.id

      assert_receive {[:lotus_web, :dashboard, :view], _,
                      %{dashboard: %{id: ^dashboard_id}, public: true, context: nil}}

      assert_receive {[:lotus_web, :card, :run, :stop], _,
                      %{public: true, context: nil, status: :ok}}
    end

    test "a card that fails stops with :error", %{dashboard: dashboard} do
      broken = query_fixture(%{statement: "SELECT * FROM no_such_table"})
      query_card(dashboard, broken)

      {:ok, live, _html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      render_async(live)

      broken_id = broken.id

      assert_receive {[:lotus_web, :card, :run, :stop], _,
                      %{query: %{id: ^broken_id}, status: :error, result: {:error, _}}}
    end
  end

  test "an export is a span with the bytes sent" do
    attach([[:lotus_web, :export, :start], [:lotus_web, :export, :stop]])
    query = query_fixture(%{statement: "SELECT 1 AS n"})

    token =
      ExportController.generate_token(Lotus.Web.Endpoint, %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => "n.csv"
      })

    conn = get(build_conn(), ~p"/lotus/export/csv?token=#{token}")
    assert conn.status == 200

    query_id = query.id
    bytes = byte_size(conn.resp_body)

    assert_receive {[:lotus_web, :export, :start], _,
                    %{query: %{id: ^query_id}, source: "public", format: :csv}}

    assert_receive {[:lotus_web, :export, :stop], %{duration: _, bytes: ^bytes},
                    %{status: :ok, format: :csv}}
  end

  test "an AI action is a span with what was asked" do
    attach([[:lotus_web, :ai, :start], [:lotus_web, :ai, :stop]])

    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    render_async(live)

    live
    |> with_target("#query-editor-page")
    |> render_hook("explain_fragment", %{"fragment" => "1"})

    # The statement is empty, so nothing is asked.
    refute_receive {[:lotus_web, :ai, :start], _, _}

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_change(%{"query" => %{"statement" => "SELECT 1"}})

    live |> with_target("#query-editor-page") |> render_hook("explain_query", %{})
    render_async(live)

    assert_receive {[:lotus_web, :ai, :start], _, %{action: :explain, source: "public"}}
    assert_receive {[:lotus_web, :ai, :stop], %{duration: _}, %{action: :explain, status: _}}
  end
end
