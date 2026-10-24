defmodule Lotus.Web.Pages.SchedulesPageTest do
  @moduledoc """
  The Schedules page (`features: [:schedules]`): the schedules and alerts,
  their form and their runs.
  """
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Schedules
  alias Lotus.Storage.ScheduleRun

  defp page(live), do: with_target(live, "#schedules-page")

  defp schedule_fixture(query, attrs \\ %{}) do
    {:ok, schedule} =
      Schedules.create_schedule(
        Map.merge(%{name: "Weekly revenue", query_id: query.id, cron: "0 8 * * MON"}, attrs)
      )

    schedule
  end

  describe "without the feature" do
    test "there is no Schedules page or link" do
      {:ok, _live, html} = live(build_conn(), "/lotus/schedules")

      refute html =~ "schedules-page"
      refute html =~ "nav-schedules"
    end
  end

  describe "with features: [:schedules]" do
    setup do
      %{query: query_fixture(%{name: "Revenue", statement: "SELECT 1 AS n"})}
    end

    test "the header links to the page, which starts empty" do
      {:ok, live, html} = live(build_conn(), "/scheduled")
      assert html =~ "nav-schedules"

      {:ok, _live, html} =
        live |> element("#nav-schedules") |> render_click() |> follow_redirect(build_conn())

      assert html =~ "No schedules yet."
    end

    test "a schedule is created with the form, with a webhook delivery", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")

      live |> element("#new-schedule") |> render_click()
      live |> element("#add-delivery") |> render_click()

      live
      |> form("#schedule-form",
        draft: %{
          name: "Weekly revenue",
          target: "query:#{query.id}",
          cron: "0 8 * * MON",
          time_zone: "Europe/Lisbon",
          deliveries: %{
            "0" => %{channel: "webhook", format: "csv", url: "https://hooks.example.com/x"}
          }
        }
      )
      |> render_submit()

      assert [schedule] = Schedules.list_schedules()
      assert schedule.time_zone == "Europe/Lisbon"

      assert [
               %{
                 channel: "webhook",
                 format: "csv",
                 config: %{"url" => "https://hooks.example.com/x"}
               }
             ] = schedule.deliveries

      html = render(live)
      assert html =~ "Weekly revenue"
      assert html =~ "Revenue"
      refute html =~ "schedule-form"
    end

    test "what does not validate is shown, and nothing is saved", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")
      live |> element("#new-schedule") |> render_click()

      html =
        live
        |> form("#schedule-form",
          draft: %{name: "x", target: "query:#{query.id}", cron: "every day"}
        )
        |> render_submit()

      assert html =~ "is not a cron expression"
      assert Schedules.list_schedules() == []
    end

    test "an alert is saved with its rule, and the list says it is one", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")
      live |> element("#new-schedule") |> render_click()

      live |> form("#schedule-form", draft: %{alert: "true"}) |> render_change()

      live
      |> form("#schedule-form",
        draft: %{
          name: "Too many",
          target: "query:#{query.id}",
          cron: "*/15 * * * *",
          alert: "true",
          condition: "above",
          column: "n",
          threshold: "500"
        }
      )
      |> render_submit()

      assert [%{rule: %{condition: "above", column: "n"} = rule} = schedule] =
               Schedules.list_schedules()

      assert Decimal.equal?(rule.threshold, 500)
      assert has_element?(live, "#schedule-#{schedule.id}-alert", "Alert")
    end

    test "a schedule is edited, paused and deleted", %{query: query} do
      schedule = schedule_fixture(query)
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")

      live |> element("#schedule-#{schedule.id}-edit") |> render_click()
      live |> form("#schedule-form", draft: %{name: "Monday revenue"}) |> render_submit()
      assert Schedules.get_schedule!(schedule.id).name == "Monday revenue"

      live |> element("#schedule-#{schedule.id}-toggle") |> render_click()
      refute Schedules.get_schedule!(schedule.id).enabled
      assert render(live) =~ "Paused"

      live |> element("#schedule-#{schedule.id}-delete") |> render_click()
      assert Schedules.get_schedule(schedule.id) == nil
    end

    test "a schedule's runs are listed", %{query: query} do
      schedule = schedule_fixture(query)

      {:ok, run} =
        schedule.id
        |> ScheduleRun.claim_changeset(~U[2026-10-26 08:00:00.000000Z])
        |> Lotus.repo().insert()

      {:ok, _run} =
        run
        |> ScheduleRun.update_changeset(%{status: "failed", error: "the source is down"})
        |> Lotus.repo().update()

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")
      html = live |> element("#schedule-#{schedule.id}-runs") |> render_click()

      assert html =~ "2026-10-26 08:00 UTC"
      assert html =~ "the source is down"
    end

    test "the query editor links here to schedule its query", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/queries/#{query.id}")
      assert has_element?(live, "#schedule-query")

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules?query_id=#{query.id}")
      assert has_element?(live, ~s(#schedule-form option[value="query:#{query.id}"][selected]))
    end
  end

  describe "a read-only user" do
    test "sees the schedules but cannot change them" do
      query = query_fixture(%{statement: "SELECT 1"})
      schedule = schedule_fixture(query)

      {:ok, live, html} = live(build_conn(), "/scheduled_read_only/schedules")

      assert html =~ "Weekly revenue"
      refute has_element?(live, "#new-schedule")
      refute has_element?(live, "#schedule-#{schedule.id}-delete")

      render_click(page(live), "delete_schedule", %{"id" => to_string(schedule.id)})
      assert Schedules.get_schedule(schedule.id)
    end
  end
end
