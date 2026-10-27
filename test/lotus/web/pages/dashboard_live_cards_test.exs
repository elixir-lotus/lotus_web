defmodule Lotus.Web.Pages.DashboardLiveCardsTest do
  # A live card's chart takes the rows after its last one, every tick,
  # without being sent again whole.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Web.TestRepo

  setup do
    TestRepo.query!("CREATE TABLE live_events (at timestamp NOT NULL, n integer NOT NULL)")

    for minute <- 1..4, do: insert(minute)

    dashboard = public_dashboard_fixture(%{name: "Orders"})

    query =
      query_fixture(%{
        name: "Orders per minute",
        statement: "SELECT at, n FROM live_events WHERE 1=1 [[AND at > {{since}}]] ORDER BY at"
      })

    card =
      query_card_fixture(dashboard, query, %{
        title: "Orders",
        visualization_config: %{
          "chart_type" => "line",
          "x_field" => "at",
          "y_field" => "n",
          "live" => "true",
          "live_window" => "3"
        }
      })

    {:ok, dashboard: dashboard, card: card}
  end

  defp insert(minute) do
    TestRepo.query!("INSERT INTO live_events (at, n) VALUES ($1, $2)", [
      NaiveDateTime.add(~N[2026-10-27 10:00:00], minute * 60),
      minute
    ])
  end

  # As the timer sends it: to the dashboard it is in.
  defp tick(live) do
    live |> element("#live-cards-timer") |> render_hook("live_tick", %{})
    render_async(live)
  end

  defp appended_values(live, card) do
    id = "chart-#{card.id}"
    assert_push_event(live, "fude:append", %{id: ^id, max: 3, wire: wire})
    wire |> Jason.encode!() |> Jason.decode!()
  end

  for {name, path} <- [
        {"the dashboard", "/lotus/dashboards/"},
        {"its public link", "/lotus/public/"}
      ] do
    test "on #{name}, a tick sends only the new rows to the chart", %{
      dashboard: dashboard,
      card: card
    } do
      key = if unquote(path) == "/lotus/public/", do: dashboard.public_token, else: dashboard.id
      {:ok, live, _html} = live(build_conn(), unquote(path) <> to_string(key))
      render_async(live)

      assert has_element?(live, "#live-cards-timer[data-event=live_tick]")
      assert has_element?(live, "[id$='-live'].lotus-live-dot")

      # Nothing new: nothing sent.
      tick(live)
      refute_push_event(live, "fude:append", %{})

      insert(5)
      insert(6)
      tick(live)
      wire = appended_values(live, card)
      encoded = Jason.encode!(wire)
      # The two new minutes, not the four the chart already has.
      assert encoded =~ "10:05:00"
      assert encoded =~ "10:06:00"
      refute encoded =~ "10:04:00"

      # The cursor moved: the next tick asks after 10:06.
      tick(live)
      refute_push_event(live, "fude:append", %{})
    end
  end

  test "the dashboard's auto-refresh reaches the dashboard and runs its cards again", %{
    dashboard: dashboard,
    card: card
  } do
    {:ok, _} = Lotus.update_dashboard(dashboard, %{auto_refresh_seconds: 60})

    test_pid = self()
    handler = "auto-refresh-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:lotus_web, :card, :run, :stop],
      fn _event, _measurements, %{card_id: id, result: {:ok, result}}, _config ->
        send(test_pid, {:card_ran, id, length(result.rows)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)
    card_id = card.id
    assert_receive {:card_ran, ^card_id, 4}

    insert(5)
    live |> element("#auto-refresh-timer") |> render_hook("auto_refresh_tick", %{})
    render_async(live)
    assert_receive {:card_ran, ^card_id, 5}
  end

  test "a card that is not live has no timer, and its settings say how to make it live", %{
    dashboard: dashboard,
    card: card
  } do
    {:ok, _} =
      Lotus.update_dashboard_card(card, %{
        visualization_config: Map.put(card.visualization_config, "live", "false")
      })

    {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
    render_async(live)

    refute has_element?(live, "#live-cards-timer")
    refute has_element?(live, ".lotus-live-dot")
  end

  describe "the card's settings" do
    defp open_settings(dashboard, card) do
      {:ok, live, _html} = live(build_conn(), "/lotus/dashboards/#{dashboard.id}")
      render_async(live)
      live |> element("button", "Edit") |> render_click()
      editor = with_target(live, "#dashboard-editor")
      render_click(editor, "open_card_settings", %{"card-id" => to_string(card.id)})
      {live, editor}
    end

    test "switch a line chart live, with the points it keeps, and save it", %{
      dashboard: dashboard,
      card: card
    } do
      {:ok, card} =
        Lotus.update_dashboard_card(card, %{
          visualization_config: Map.delete(card.visualization_config, "live")
        })

      {live, editor} = open_settings(dashboard, card)
      assert has_element?(live, "#card-live-settings #card-live-toggle:not([disabled])")
      refute has_element?(live, "#card-live-window")

      viz = %{"chart_type" => "line", "x_field" => "at", "y_field" => "n"}

      render_change(editor, "update_card_visualization", %{
        "card_id" => to_string(card.id),
        "visualization" => Map.merge(viz, %{"live" => "true", "live_window" => "120"})
      })

      assert has_element?(live, "#card-live-window option[value='120'][selected]")

      render_submit(editor, "save_dashboard", %{"dashboard" => %{"name" => dashboard.name}})

      [saved] = Lotus.list_dashboard_cards(dashboard.id)
      assert saved.visualization_config["live"] == "true"
      assert saved.visualization_config["live_window"] == "120"
    end

    test "say how to make a chart live when its query does not read {{since}}", %{
      dashboard: dashboard,
      card: card
    } do
      query = query_fixture(%{name: "All orders", statement: "SELECT at, n FROM live_events"})
      {:ok, card} = Lotus.update_dashboard_card(card, %{query_id: query.id})

      {live, _editor} = open_settings(dashboard, card)
      assert has_element?(live, "#card-live-toggle[disabled]")
      assert render(live) =~ "[[WHERE created_at &gt; {{since}}]]"
    end

    test "offer nothing live for a bar chart", %{dashboard: dashboard, card: card} do
      {:ok, card} =
        Lotus.update_dashboard_card(card, %{
          visualization_config: %{"chart_type" => "bar", "x_field" => "at", "y_field" => "n"}
        })

      {live, _editor} = open_settings(dashboard, card)
      refute has_element?(live, "#card-live-settings")
    end
  end
end
