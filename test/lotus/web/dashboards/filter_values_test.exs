defmodule Lotus.Web.Dashboards.FilterValuesTest do
  @moduledoc """
  A date-range picker posts two inputs under one filter name, so its value
  arrives as a nested map. Everything downstream — the URL, the query
  variables, core's date_range transforms — speaks strings, so the nested map
  has to be flattened on the way in.
  """

  use ExUnit.Case, async: true

  alias Lotus.Web.Dashboards.FilterValues

  defmodule Filter do
    @moduledoc false
    defstruct [:name, :default_value]
  end

  describe "normalize/1" do
    test "flattens a posted date range to the start,end form" do
      posted = %{"period" => %{"start" => "2026-01-01", "end" => "2026-03-31"}}

      assert FilterValues.normalize(posted) == %{"period" => "2026-01-01,2026-03-31"}
    end

    test "keeps the comma when one end of the range is open" do
      assert FilterValues.normalize(%{"p" => %{"start" => "2026-01-01", "end" => ""}}) ==
               %{"p" => "2026-01-01,"}

      assert FilterValues.normalize(%{"p" => %{"start" => "", "end" => "2026-03-31"}}) ==
               %{"p" => ",2026-03-31"}
    end

    test "an empty range is empty, not a bare comma" do
      assert FilterValues.normalize(%{"p" => %{"start" => "", "end" => ""}}) == %{"p" => ""}
    end

    test "leaves plain values alone" do
      assert FilterValues.normalize(%{"status" => "active"}) == %{"status" => "active"}
    end
  end

  describe "from_params/2" do
    test "a date range posted to the URL survives the round-trip" do
      posted = %{"period" => %{"start" => "2026-01-01", "end" => "2026-03-31"}}
      params = FilterValues.to_params(posted)

      assert params == %{"period" => "2026-01-01,2026-03-31"}

      filters = [%Filter{name: "period", default_value: "2020-01-01,2020-12-31"}]

      assert FilterValues.from_params(params, filters) ==
               %{"period" => "2026-01-01,2026-03-31"}
    end

    test "falls back to the default only when the param carries nothing" do
      filters = [%Filter{name: "period", default_value: "2020-01-01,2020-12-31"}]

      assert FilterValues.from_params(%{}, filters) == %{"period" => "2020-01-01,2020-12-31"}

      assert FilterValues.from_params(%{"period" => ""}, filters) ==
               %{"period" => "2020-01-01,2020-12-31"}
    end

    test "a filter with neither a param nor a default is left out" do
      filters = [%Filter{name: "status", default_value: nil}]

      assert FilterValues.from_params(%{}, filters) == %{}
    end
  end

  describe "to_params/1" do
    test "drops filters carrying nothing" do
      assert FilterValues.to_params(%{"a" => "x", "b" => "", "c" => nil}) == %{"a" => "x"}
    end
  end

  describe "split_date_range/1" do
    test "splits the canonical form back into two dates" do
      assert FilterValues.split_date_range("2026-01-01,2026-03-31") ==
               {"2026-01-01", "2026-03-31"}
    end

    test "an open end comes back as nil" do
      assert FilterValues.split_date_range("2026-01-01,") == {"2026-01-01", nil}
      assert FilterValues.split_date_range(",2026-03-31") == {nil, "2026-03-31"}
    end

    test "a bare date is a start with no end" do
      assert FilterValues.split_date_range("2026-01-01") == {"2026-01-01", nil}
    end

    test "empty and unrecognised values give an empty range" do
      assert FilterValues.split_date_range("") == {nil, nil}
      assert FilterValues.split_date_range(nil) == {nil, nil}
    end

    test "still reads a nested map, for a value that never went through normalize/1" do
      assert FilterValues.split_date_range(%{"start" => "2026-01-01", "end" => "2026-03-31"}) ==
               {"2026-01-01", "2026-03-31"}
    end
  end

  describe "core transforms" do
    test "the canonical form is what date_range_start and date_range_end parse" do
      %{"period" => value} =
        FilterValues.normalize(%{"period" => %{"start" => "2026-01-01", "end" => "2026-03-31"}})

      assert ["2026-01-01", "2026-03-31"] = String.split(value, ",")
    end
  end
end
