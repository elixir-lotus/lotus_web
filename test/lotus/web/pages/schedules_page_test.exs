defmodule Lotus.Web.Pages.SchedulesPageTest do
  @moduledoc """
  Schedules (`features: [:schedules]`): their tab on the home page, and the
  editor of one.
  """
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Schedules
  alias Lotus.Storage.ScheduleRun

  defmodule Elixir.Lotus.Web.Test.ChangeCondition do
    @moduledoc false
    def validate(_rule), do: :ok
    def evaluate(_rule, _result, _state), do: {:ok, false, nil}
    def describe(_rule, _status, _value), do: ""
  end

  defmodule Elixir.Lotus.Web.Test.MailChannel do
    @moduledoc false
    @behaviour Lotus.Delivery.Channel
    def formats, do: :any
    def label, do: "Mail"

    def settings,
      do: [
        %{key: "to", label: "Recipients", type: :email_list, required: true},
        %{key: "subject", label: "Subject", type: :text}
      ]

    def validate_config(_config), do: :ok

    # A test is sent from a task: it tells the test process, by name.
    def deliver(content, _attachments, config) do
      if pid = Process.whereis(:lotus_web_delivery_test),
        do: send(pid, {:delivered, content.title, config})

      :ok
    end
  end

  defmodule Elixir.Lotus.Web.Test.ClosedChannel do
    @moduledoc false
    @behaviour Lotus.Delivery.Channel
    def formats, do: :any
    def settings, do: [%{key: "room", label: "Room", type: :text}]
    def validate_config(_config), do: :ok
    def deliver(_content, _attachments, _config), do: {:error, "the room is closed"}
  end

  defmodule Elixir.Lotus.Web.Test.PigeonChannel do
    @moduledoc false
    @behaviour Lotus.Delivery.Channel
    def formats, do: :any
    def available, do: {:error, "the pigeons are not set up"}
    def validate_config(_config), do: :ok
    def deliver(_content, _attachments, _config), do: :ok
  end

  defmodule Elixir.Lotus.Web.Test.PlainChannel do
    @moduledoc false
    @behaviour Lotus.Delivery.Channel
    def formats, do: :any
    def validate_config(_config), do: :ok
    def deliver(_content, _attachments, _config), do: :ok
  end

  defp put_channels(channels) do
    Application.put_env(:lotus, :delivery, channels: channels)
    Lotus.Config.reload!()

    on_exit(fn ->
      Application.delete_env(:lotus, :delivery)
      Lotus.Config.reload!()
    end)
  end

  defp schedule_fixture(query, attrs \\ %{}) do
    {:ok, schedule} =
      Schedules.create_schedule(
        Map.merge(%{name: "Weekly revenue", query_id: query.id, cron: "0 8 * * MON"}, attrs)
      )

    schedule
  end

  describe "without the feature" do
    test "there is no Schedules tab, and its paths are the home page" do
      {:ok, live, html} = live(build_conn(), "/lotus/schedules")

      assert html =~ "queries-page"
      refute has_element?(live, "#tab-schedules")

      {:ok, _live, html} = live(build_conn(), "/lotus/schedules/new")
      refute html =~ "schedule-form"
    end
  end

  describe "the Schedules tab" do
    setup do
      %{query: query_fixture(%{name: "Revenue", statement: "SELECT 1 AS n"})}
    end

    test "is on the home page, and starts with ways to begin" do
      {:ok, live, _html} = live(build_conn(), "/scheduled")
      assert has_element?(live, "#tab-schedules")

      html = live |> element("#tab-schedules") |> render_click()
      assert html =~ "Reports and alerts, delivered"

      assert has_element?(
               live,
               ~s(#schedules-empty a[href="/scheduled/schedules/new?cron=0+8+%2A+%2A+1"])
             )
    end

    test "shows each schedule in a sentence, with its status", %{query: query} do
      schedule_fixture(query, %{time_zone: "Europe/Lisbon"})

      alert =
        schedule_fixture(query, %{
          name: "Too many",
          cron: "*/15 * * * *",
          rule: %{condition: "above", threshold: 5}
        })

      alert |> Ecto.Changeset.change(state: %{"status" => "firing"}) |> Lotus.repo().update!()

      {:ok, live, html} = live(build_conn(), "/scheduled/schedules")

      assert html =~ "Every Monday at 08:00"
      assert html =~ "Lisbon"
      assert html =~ "Every 15 minutes"
      assert has_element?(live, "#schedule-#{alert.id}-status", "Firing")

      html = live |> element("#schedules-filter-firing") |> render_click()
      refute html =~ "Every Monday at 08:00"
      assert html =~ "Too many"
    end

    test "pauses and resumes a schedule", %{query: query} do
      schedule = schedule_fixture(query)
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")

      live |> element("#schedule-#{schedule.id}-toggle") |> render_click()
      refute Schedules.get_schedule!(schedule.id).enabled
      assert has_element?(live, "#schedule-#{schedule.id}-status", "Paused")

      live |> element("#schedule-#{schedule.id}-toggle") |> render_click()
      assert Schedules.get_schedule!(schedule.id).enabled
    end

    test "has a table view", %{query: query} do
      schedule = schedule_fixture(query)
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules")

      live |> element("#schedules-view-list") |> render_click()
      assert has_element?(live, "#schedule-row-#{schedule.id}", "Every Monday at 08:00")
    end
  end

  describe "the editor" do
    setup do
      %{query: query_fixture(%{name: "Revenue", statement: "SELECT 1 AS n"})}
    end

    test "creates a weekly schedule with a webhook", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new")

      live |> element("#target-query-#{query.id}") |> render_click()
      assert has_element?(live, "#schedule-target", "Revenue")

      live |> element("#add-delivery") |> render_click()
      live |> element("#add-webhook") |> render_click()

      live
      |> form("#schedule-form",
        draft: %{
          cadence: %{frequency: "weekly", days: ["1", "3"], time: "07:30:00"},
          deliveries: %{
            "0" => %{
              format: "csv",
              values: %{url: "https://hooks.example.com/x", authorization: "Bearer s3cret"}
            }
          }
        }
      )
      |> render_change()

      assert has_element?(live, "#schedule-sentence", "Every Monday and Wednesday at 07:30")
      assert has_element?(live, "#next-runs li")

      live |> element("#zone-button") |> render_click()
      live |> form("#schedule-form", zone_search: "lisbon") |> render_change()
      live |> element("#zone-Europe-Lisbon") |> render_click()

      # Koyomi's field is phx-update="ignore": in the browser its hook keeps
      # the input's value, here the submit gives it.
      assert {:error, {:live_redirect, %{to: "/scheduled/schedules"}}} =
               live
               |> form("#schedule-form", draft: %{cadence: %{time: "07:30:00"}})
               |> render_submit()

      assert [schedule] = Schedules.list_schedules()
      assert schedule.name == "Revenue"
      assert schedule.cron == "30 7 * * 1,3"
      assert schedule.time_zone == "Europe/Lisbon"

      assert [
               %{
                 channel: "webhook",
                 format: "csv",
                 config: %{
                   "url" => "https://hooks.example.com/x",
                   "authorization" => "Bearer s3cret"
                 }
               }
             ] = schedule.deliveries
    end

    test "a Slack destination takes its webhook URL, and has no format to choose", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")

      live |> element("#add-delivery") |> render_click()
      assert has_element?(live, "#add-slack", "Slack")
      live |> element("#add-slack") |> render_click()

      refute has_element?(
               live,
               ~s(#delivery-0 input[type="radio"][name="draft[deliveries][0][format]"])
             )

      assert has_element?(
               live,
               ~s(#delivery-0 input[type="password"][name="draft[deliveries][0][values][webhook_url]"])
             )

      hook = "https://hooks.slack.com/services/T000/B000/XXXX"

      assert {:error, {:live_redirect, _}} =
               live
               |> form("#schedule-form",
                 draft: %{name: "To Slack", deliveries: %{"0" => %{values: %{webhook_url: hook}}}}
               )
               |> render_submit()

      assert [%{deliveries: [%{channel: "slack", config: %{"webhook_url" => ^hook}}]}] =
               Schedules.list_schedules()
    end

    test "a channel's settings form: email recipients as chips", %{query: query} do
      put_channels(%{"mail" => Lotus.Web.Test.MailChannel})

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()
      live |> element("#add-mail") |> render_click()

      # The tag input's hook writes the addresses to the hidden input.
      live
      |> form("#schedule-form")
      |> render_change(%{
        draft: %{deliveries: %{"0" => %{values: %{to: "a@example.com,b@example.com"}}}}
      })

      assert has_element?(live, "#delivery-0-to-chip-0", "a@example.com")
      assert has_element?(live, "#delivery-0-to-chip-1", "b@example.com")

      live
      |> element(~s(#delivery-0-to-chip-0 button))
      |> render_click()

      refute has_element?(live, "#delivery-0", "a@example.com")

      # An address still being typed is saved too.
      assert {:error, {:live_redirect, _}} =
               live
               |> form("#schedule-form",
                 draft: %{
                   name: "Mail",
                   deliveries: %{
                     "0" => %{pending: %{to: "c@example.com"}, values: %{subject: " Weekly "}}
                   }
                 }
               )
               |> render_submit()

      assert [%{deliveries: [%{channel: "mail", config: config}]}] = Schedules.list_schedules()
      assert config == %{"to" => ["b@example.com", "c@example.com"], "subject" => "Weekly"}
    end

    test "sends a test to a destination as it stands in the form", %{query: query} do
      put_channels(%{"mail" => Lotus.Web.Test.MailChannel})
      Process.register(self(), :lotus_web_delivery_test)

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()
      live |> element("#add-mail") |> render_click()

      live
      |> form("#schedule-form", draft: %{name: "Weekly revenue"})
      |> render_change(%{draft: %{deliveries: %{"0" => %{values: %{to: "ops@example.com"}}}}})

      live |> element("#test-delivery-0") |> render_click()
      render_async(live)

      assert has_element?(live, "#test-delivery-0-result", "Test sent")
      assert_received {:delivered, "Test: Weekly revenue", %{"to" => ["ops@example.com"]}}
      assert Schedules.list_schedules() == []
    end

    test "a test that fails says the channel's reason", %{query: query} do
      put_channels(%{"closed" => Lotus.Web.Test.ClosedChannel})

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()
      live |> element("#add-closed") |> render_click()
      live |> element("#test-delivery-0") |> render_click()
      render_async(live)

      assert has_element?(live, "#test-delivery-0-result", "the room is closed")
    end

    test "a channel that cannot send is shown with why, and cannot be added", %{query: query} do
      put_channels(%{"pigeon" => Lotus.Web.Test.PigeonChannel})

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()

      assert has_element?(live, "#add-pigeon[disabled]", "the pigeons are not set up")
      render_click(with_target(live, "#schedules-page"), "add_delivery", %{"channel" => "pigeon"})
      refute has_element?(live, "#delivery-0")
    end

    test "email is offered, and says what it needs until the app has a mailer", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()

      assert has_element?(live, "#add-email[disabled]", "Not set up:")
      assert has_element?(live, "#add-email", "Swoosh")
    end

    test "a channel that does not describe its settings takes them as JSON", %{query: query} do
      put_channels(%{"plain" => Lotus.Web.Test.PlainChannel})

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")
      live |> element("#add-delivery") |> render_click()
      live |> element("#add-plain") |> render_click()

      html =
        live
        |> form("#schedule-form", draft: %{deliveries: %{"0" => %{json: "[1]"}}})
        |> render_submit()

      assert html =~ "must be a JSON object"

      assert {:error, {:live_redirect, _}} =
               live
               |> form("#schedule-form",
                 draft: %{name: "Plain", deliveries: %{"0" => %{json: ~s({"room": "ops"})}}}
               )
               |> render_submit()

      assert [%{deliveries: [%{config: %{"room" => "ops"}}]}] = Schedules.list_schedules()
    end

    test "a webhook saved with an authorization header shows it in its field", %{query: query} do
      schedule =
        schedule_fixture(query, %{
          deliveries: [
            %{
              channel: "webhook",
              format: "json",
              config: %{
                "url" => "https://hooks.example.com/x",
                "headers" => %{"authorization" => "Bearer old", "x-team" => "data"}
              }
            }
          ]
        })

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/#{schedule.id}")

      assert has_element?(
               live,
               ~s(#delivery-0 input[name="draft[deliveries][0][values][authorization]"][value="Bearer old"])
             )

      live |> form("#schedule-form") |> render_submit()

      assert %{deliveries: [%{config: config}]} = Schedules.get_schedule!(schedule.id)

      assert config == %{
               "url" => "https://hooks.example.com/x",
               "authorization" => "Bearer old",
               "headers" => %{"x-team" => "data"}
             }
    end

    test "each frequency writes its cron", %{query: query} do
      {:ok, live, _html} =
        live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")

      for {cadence, sentence} <- [
            {%{frequency: "minutes", every: "30"}, "Every 30 minutes"},
            {%{frequency: "hourly", every: "6", minute: "15"}, "Every 6 hours at 15 past"},
            {%{frequency: "daily", weekdays: "true", time: "09:00:00"}, "Every weekday at 09:00"},
            {%{
               frequency: "monthly",
               month_mode: "weekday",
               ordinal: "last",
               weekday: "5",
               time: "17:00:00"
             }, "Every month on the last Friday at 17:00"}
          ] do
        live
        |> form("#schedule-form", draft: %{cadence: %{frequency: cadence.frequency}})
        |> render_change()

        live |> form("#schedule-form", draft: %{cadence: cadence}) |> render_change()
        assert has_element?(live, "#schedule-sentence", sentence)
      end
    end

    test "a custom cron is checked as it is typed, and refused", %{query: query} do
      {:ok, live, _html} =
        live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}")

      live |> form("#schedule-form", draft: %{cadence: %{frequency: "custom"}}) |> render_change()
      live |> form("#schedule-form", draft: %{cadence: %{cron: "every day"}}) |> render_change()
      assert has_element?(live, "#cron-error")

      html = live |> form("#schedule-form", draft: %{name: "x"}) |> render_submit()

      assert html =~ "It could not be saved"
      assert Schedules.list_schedules() == []

      live |> element(~s(button[phx-value-cron="0 9,17 * * 1-5"])) |> render_click()
      refute has_element?(live, "#cron-error")
    end

    test "saves an alert with its rule", %{query: query} do
      {:ok, live, _html} =
        live(
          build_conn(),
          "/scheduled/schedules/new?query_id=#{query.id}&cron=*/15+*+*+*+*&alert=true"
        )

      live
      |> form("#schedule-form",
        draft: %{name: "Too many", column: "n", condition: "above", threshold: "500"}
      )
      |> render_submit()

      assert [%{cron: "*/15 * * * *", rule: %{condition: "above", column: "n"} = rule}] =
               Schedules.list_schedules()

      assert Decimal.equal?(rule.threshold, 500)
    end

    test "a dashboard has no alert" do
      dashboard = dashboard_fixture(%{name: "Sales"})

      {:ok, live, _html} =
        live(build_conn(), "/scheduled/schedules/new?dashboard_id=#{dashboard.id}&alert=true")

      assert has_element?(live, "#schedule-target", "Sales")
      refute has_element?(live, "#schedule-alert-toggle")
    end

    test "offers a condition registered by name (Lotus Pro's, or the app's)", %{query: query} do
      Application.put_env(:lotus, :alerts,
        conditions: %{"change" => Lotus.Web.Test.ChangeCondition}
      )

      Lotus.Config.reload!()

      on_exit(fn ->
        Application.delete_env(:lotus, :alerts)
        Lotus.Config.reload!()
      end)

      {:ok, live, _html} =
        live(build_conn(), "/scheduled/schedules/new?query_id=#{query.id}&alert=true")

      assert has_element?(live, ~s(#alert-condition option[value="change"]))
      assert has_element?(live, ~s(#alert-condition option[value="above"]))
    end

    test "edits a schedule, shows its runs, and deletes it", %{query: query} do
      schedule = schedule_fixture(query)

      {:ok, run} =
        schedule.id
        |> ScheduleRun.claim_changeset(~U[2026-10-26 08:00:00.000000Z])
        |> Lotus.repo().insert()

      {:ok, _run} =
        run
        |> ScheduleRun.update_changeset(%{status: "failed", error: "the source is down"})
        |> Lotus.repo().update()

      {:ok, live, html} = live(build_conn(), "/scheduled/schedules/#{schedule.id}")

      assert html =~ "2026-10-26 08:00 UTC"
      assert html =~ "the source is down"
      assert has_element?(live, "#frequency-weekly[checked]")

      live
      |> form("#schedule-form",
        draft: %{name: "Monday revenue", cadence: %{days: ["1", "5"]}}
      )
      |> render_submit()

      assert %{name: "Monday revenue", cron: "0 8 * * 1,5"} = Schedules.get_schedule!(schedule.id)

      {:ok, live, _html} = live(build_conn(), "/scheduled/schedules/#{schedule.id}")
      live |> element("#delete-schedule") |> render_click()
      assert Schedules.get_schedule(schedule.id) == nil
    end

    test "a schedule that does not exist goes back to the list" do
      assert {:error, {:live_redirect, %{to: "/scheduled/schedules"}}} =
               live(build_conn(), "/scheduled/schedules/0")
    end

    test "the query editor and a dashboard link here", %{query: query} do
      {:ok, live, _html} = live(build_conn(), "/scheduled/queries/#{query.id}")

      assert has_element?(
               live,
               ~s(#schedule-query[href="/scheduled/schedules/new?query_id=#{query.id}"])
             )
    end
  end

  describe "a read-only user" do
    test "sees the schedules but cannot change them" do
      query = query_fixture(%{statement: "SELECT 1"})
      schedule = schedule_fixture(query)

      {:ok, live, html} = live(build_conn(), "/scheduled_read_only/schedules")

      assert html =~ "Weekly revenue"
      refute has_element?(live, "#new-schedule")
      refute has_element?(live, "#schedule-#{schedule.id}-toggle")

      render_click(with_target(live, "#queries-page"), "toggle_schedule", %{
        "id" => to_string(schedule.id)
      })

      assert Schedules.get_schedule!(schedule.id).enabled

      {:ok, live, _html} = live(build_conn(), "/scheduled_read_only/schedules/#{schedule.id}")
      refute has_element?(live, "#save-schedule")
      refute has_element?(live, "#delete-schedule")

      render_click(with_target(live, "#schedules-page"), "delete_schedule", %{})
      assert Schedules.get_schedule(schedule.id)

      render_click(with_target(live, "#schedules-page"), "test_delivery", %{"index" => "0"})
      refute has_element?(live, "#test-delivery-0-result")
    end
  end
end
