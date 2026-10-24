defmodule Lotus.Web.Schedules.CadenceTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Schedules.Cadence

  describe "to_cron/1 and from_cron/1" do
    for {cron, frequency} <- [
          {"*/15 * * * *", "minutes"},
          {"30 * * * *", "hourly"},
          {"0 */6 * * *", "hourly"},
          {"0 9 * * *", "daily"},
          {"30 7 * * 1-5", "daily"},
          {"0 8 * * 1,3,5", "weekly"},
          {"0 8 * * 0", "weekly"},
          {"0 8 15 * *", "monthly"},
          {"0 18 L * *", "monthly"},
          {"0 8 * * 1#1", "monthly"},
          {"0 17 * * 5L", "monthly"}
        ] do
      test "#{cron} is a #{frequency} cadence and back" do
        cadence = Cadence.from_cron(unquote(cron))
        assert cadence["frequency"] == unquote(frequency)
        assert Cadence.to_cron(cadence) == unquote(cron)
      end
    end

    test "names and ranges of weekdays are read" do
      assert Cadence.from_cron("0 8 * * MON")["days"] == ["1"]
      assert Cadence.from_cron("0 8 * * MON-WED")["days"] == ~w(1 2 3)
      assert Cadence.from_cron("0 8 * * MON-FRI")["weekdays"] == "true"
      assert Cadence.from_cron("0 8 * * 0-6")["frequency"] == "daily"
    end

    test "any other expression is a custom cadence" do
      for cron <- ["0 9,17 * * *", "*/7 * * * *", "0 8 1 1 *", "15 8-18 * * 1-5"] do
        assert %{"frequency" => "custom", "cron" => ^cron} = Cadence.from_cron(cron)
        assert Cadence.to_cron(Cadence.from_cron(cron)) == cron
      end
    end

    test "a weekly cadence without days runs on Mondays" do
      assert Cadence.to_cron(%{Cadence.default() | "days" => []}) == "0 8 * * 1"
    end

    test "Koyomi's time with seconds is read" do
      cadence = %{Cadence.default() | "frequency" => "daily", "time" => "18:45:00"}
      assert Cadence.to_cron(cadence) == "45 18 * * *"
    end
  end

  describe "describe/1" do
    test "says each cadence" do
      assert Cadence.describe("*/15 * * * *") == "Every 15 minutes"
      assert Cadence.describe("0 * * * *") == "Every hour at o'clock"
      assert Cadence.describe("30 */2 * * *") == "Every 2 hours at 30 past"
      assert Cadence.describe("0 9 * * *") == "Every day at 09:00"
      assert Cadence.describe("30 7 * * 1-5") == "Every weekday at 07:30"
      assert Cadence.describe("0 8 * * 1") == "Every Monday at 08:00"
      assert Cadence.describe("0 8 * * 1,3,5") == "Every Monday, Wednesday and Friday at 08:00"
      assert Cadence.describe("0 8 15 * *") == "Every month on day 15 at 08:00"
      assert Cadence.describe("0 18 L * *") == "Every month on the last day at 18:00"
      assert Cadence.describe("0 17 * * 5L") == "Every month on the last Friday at 17:00"
      assert Cadence.describe("0 8 * * 1#2") == "Every month on the second Monday at 08:00"
      assert Cadence.describe("0 9,17 * * *") == "On a custom schedule"
    end
  end

  describe "next_runs/4" do
    test "lists the next runs in the zone, as UTC" do
      from = ~U[2027-01-04 10:00:00Z]

      assert [first, second] = Cadence.next_runs("0 8 * * 1", "Europe/Lisbon", 2, from)
      assert first == ~U[2027-01-11 08:00:00.000000Z]
      assert second == ~U[2027-01-18 08:00:00.000000Z]
    end

    test "none for an expression that is not valid" do
      assert Cadence.next_runs("nope", "Etc/UTC", 3) == []
    end
  end
end
