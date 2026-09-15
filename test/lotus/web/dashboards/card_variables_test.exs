defmodule Lotus.Web.Dashboards.CardVariablesTest do
  use ExUnit.Case, async: true

  alias Lotus.Storage.DashboardCardFilterMapping, as: Mapping
  alias Lotus.Web.Dashboards.CardVariables

  @today ~D[2026-09-15]

  defmodule Filter do
    @moduledoc false
    defstruct [:id, :name, :filter_type, :default_value]
  end

  defp period(default_value) do
    %Filter{id: 1, name: "period", filter_type: :date_range, default_value: default_value}
  end

  defp split_mappings do
    [
      %Mapping{filter_id: 1, variable_name: "from", transform: %{"type" => "date_range_start"}},
      %Mapping{filter_id: 1, variable_name: "to", transform: %{"type" => "date_range_end"}}
    ]
  end

  describe "build/4 with saved mappings" do
    test "resolves a token default and splits it through both transforms" do
      vars = CardVariables.build(split_mappings(), [period("last_30_days")], %{}, @today)

      assert vars == %{"from" => "2026-08-17", "to" => "2026-09-15"}
    end

    test "a filter value wins over the default" do
      vars =
        CardVariables.build(
          split_mappings(),
          [period("last_30_days")],
          %{"period" => "2026-01-01,2026-03-31"},
          @today
        )

      assert vars == %{"from" => "2026-01-01", "to" => "2026-03-31"}
    end

    test "resolves a single-day token for a date filter" do
      filter = %Filter{id: 2, name: "day", filter_type: :date, default_value: "today"}
      mappings = [%Mapping{filter_id: 2, variable_name: "day"}]

      assert CardVariables.build(mappings, [filter], %{}, @today) == %{"day" => "2026-09-15"}
    end

    test "passes a range to one variable without a transform" do
      mappings = [%Mapping{filter_id: 1, variable_name: "period"}]

      assert CardVariables.build(mappings, [period("this_month")], %{}, @today) ==
               %{"period" => "2026-09-01,2026-09-30"}
    end

    test "leaves out a filter with no value and a mapping to no filter" do
      mappings = [
        %Mapping{filter_id: 1, variable_name: "from"},
        %Mapping{filter_id: 9, variable_name: "x"}
      ]

      assert CardVariables.build(mappings, [period(nil)], %{}, @today) == %{}
    end

    test "does not resolve a token in a text filter" do
      filter = %Filter{id: 3, name: "word", filter_type: :text, default_value: "today"}
      mappings = [%Mapping{filter_id: 3, variable_name: "word"}]

      assert CardVariables.build(mappings, [filter], %{}, @today) == %{"word" => "today"}
    end
  end

  describe "build/4 with the editor's in-memory mappings" do
    test "applies the same rule, transforms included" do
      mappings = %{
        "period" => [
          %{variable_name: "from", transform: %{"type" => "date_range_start"}},
          %{variable_name: "to", transform: %{"type" => "date_range_end"}}
        ]
      }

      assert CardVariables.build(mappings, [period("last_7_days")], %{}, @today) ==
               %{"from" => "2026-09-09", "to" => "2026-09-15"}
    end

    test "leaves out an entry with no variable" do
      mappings = %{"period" => [%{variable_name: "", transform: nil}]}

      assert CardVariables.build(mappings, [period("today")], %{}, @today) == %{}
    end
  end
end
