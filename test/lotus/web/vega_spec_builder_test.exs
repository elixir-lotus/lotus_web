defmodule Lotus.Web.VegaSpecBuilderTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.VegaSpecBuilder

  # -- Helpers ---------------------------------------------------------------

  defp result(columns, rows) do
    %Lotus.Result{columns: columns, rows: rows, num_rows: length(rows)}
  end

  defp simple_result do
    result(["name", "value"], [["A", 10], ["B", 20], ["C", 30]])
  end

  # -- chart_type_ids/0 ------------------------------------------------------

  describe "chart_type_ids/0" do
    test "returns a non-empty list of strings" do
      ids = VegaSpecBuilder.chart_type_ids()
      assert is_list(ids)
      refute ids == []
      assert Enum.all?(ids, &is_binary/1)
    end

    test "includes common chart types" do
      ids = VegaSpecBuilder.chart_type_ids()

      for type <- ~w(bar line area pie scatter kpi) do
        assert type in ids
      end
    end
  end

  # -- chart_type_label/1 ----------------------------------------------------

  describe "chart_type_label/1" do
    test "returns a label for known chart types" do
      assert VegaSpecBuilder.chart_type_label("bar") == "Bar Chart"
      assert VegaSpecBuilder.chart_type_label("line") == "Line Chart"
      assert VegaSpecBuilder.chart_type_label("pie") == "Pie Chart"
    end

    test "returns a fallback for unknown chart type" do
      assert VegaSpecBuilder.chart_type_label("unknown") == "Chart"
    end
  end

  # -- valid_config?/1 -------------------------------------------------------

  describe "valid_config?/1" do
    test "returns false for nil" do
      refute VegaSpecBuilder.valid_config?(nil)
    end

    test "returns false for empty map" do
      refute VegaSpecBuilder.valid_config?(%{})
    end

    test "returns false when only chart_type is set (no x/y fields)" do
      refute VegaSpecBuilder.valid_config?(%{"chart_type" => "bar"})
    end

    test "returns false when x_field or y_field is empty string" do
      refute VegaSpecBuilder.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "",
               "y_field" => "value"
             })

      refute VegaSpecBuilder.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "name",
               "y_field" => ""
             })
    end

    test "returns true for standard chart with x_field and y_field" do
      assert VegaSpecBuilder.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "name",
               "y_field" => "value"
             })
    end

    test "returns true for KPI with value_field" do
      assert VegaSpecBuilder.valid_config?(%{
               "chart_type" => "kpi",
               "value_field" => "total"
             })
    end

    test "returns true for gauge with value_field" do
      assert VegaSpecBuilder.valid_config?(%{
               "chart_type" => "gauge",
               "value_field" => "score"
             })
    end

    test "returns true for histogram with x_field" do
      assert VegaSpecBuilder.valid_config?(%{
               "chart_type" => "histogram",
               "x_field" => "amount"
             })
    end

    test "returns false for KPI without value_field" do
      refute VegaSpecBuilder.valid_config?(%{"chart_type" => "kpi"})
    end

    test "returns false for histogram without x_field" do
      refute VegaSpecBuilder.valid_config?(%{"chart_type" => "histogram"})
    end
  end

  # -- build_config/1 --------------------------------------------------------

  describe "build_config/1" do
    test "returns empty map when chart_type is nil" do
      assert VegaSpecBuilder.build_config(%{"chart_type" => nil}) == %{}
    end

    test "returns empty map when chart_type is empty string" do
      assert VegaSpecBuilder.build_config(%{"chart_type" => ""}) == %{}
    end

    test "includes only relevant fields for bar chart" do
      viz = %{
        "chart_type" => "bar",
        "x_field" => "name",
        "y_field" => "value",
        "series_field" => "category",
        "value_field" => "stale",
        "bin_count" => "10"
      }

      config = VegaSpecBuilder.build_config(viz)

      assert config["chart_type"] == "bar"
      assert config["x_field"] == "name"
      assert config["y_field"] == "value"
      assert config["series_field"] == "category"
      refute Map.has_key?(config, "value_field")
      refute Map.has_key?(config, "bin_count")
    end

    test "includes only relevant fields for KPI" do
      viz = %{
        "chart_type" => "kpi",
        "value_field" => "total",
        "kpi_label" => "Revenue",
        "x_field" => "stale"
      }

      config = VegaSpecBuilder.build_config(viz)

      assert config["chart_type"] == "kpi"
      assert config["value_field"] == "total"
      assert config["kpi_label"] == "Revenue"
      refute Map.has_key?(config, "x_field")
    end

    test "includes only relevant fields for histogram" do
      viz = %{
        "chart_type" => "histogram",
        "x_field" => "amount",
        "bin_count" => "20",
        "series_field" => "group",
        "y_field" => "stale"
      }

      config = VegaSpecBuilder.build_config(viz)

      assert config["chart_type"] == "histogram"
      assert config["x_field"] == "amount"
      assert config["bin_count"] == "20"
      assert config["series_field"] == "group"
      refute Map.has_key?(config, "y_field")
    end

    test "strips nil and empty string values" do
      viz = %{
        "chart_type" => "bar",
        "x_field" => "name",
        "y_field" => nil,
        "series_field" => ""
      }

      config = VegaSpecBuilder.build_config(viz)

      assert config["x_field"] == "name"
      refute Map.has_key?(config, "y_field")
      refute Map.has_key?(config, "series_field")
    end

    test "includes combo-specific fields" do
      viz = %{
        "chart_type" => "combo",
        "x_field" => "month",
        "y_field" => "revenue",
        "y2_field" => "orders",
        "y2_axis_title" => "Order Count",
        "series_field" => "region"
      }

      config = VegaSpecBuilder.build_config(viz)

      assert config["y2_field"] == "orders"
      assert config["y2_axis_title"] == "Order Count"
      assert config["series_field"] == "region"
    end
  end

  # -- build/2 ---------------------------------------------------------------

  describe "build/2" do
    test "bar chart produces valid Vega-Lite spec" do
      config = %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["$schema"] =~ "vega-lite"
      assert spec["mark"]["type"] == "bar"
      assert spec["encoding"]["x"]["field"] == "name"
      assert spec["encoding"]["y"]["field"] == "value"
      assert spec["encoding"]["y"]["type"] == "quantitative"
      assert length(spec["data"]["values"]) == 3
    end

    test "line chart has point marks" do
      config = %{"chart_type" => "line", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["mark"]["type"] == "line"
      assert spec["mark"]["point"] == true
    end

    test "area chart has line marks" do
      config = %{"chart_type" => "area", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["mark"]["type"] == "area"
      assert spec["mark"]["line"] == true
    end

    test "pie chart uses theta and color encoding" do
      config = %{"chart_type" => "pie", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["mark"]["type"] == "arc"
      assert spec["encoding"]["theta"]["field"] == "value"
      assert spec["encoding"]["color"]["field"] == "name"
    end

    test "donut chart has inner radius" do
      config = %{"chart_type" => "donut", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["mark"]["type"] == "arc"
      assert spec["mark"]["innerRadius"] == 50
    end

    test "horizontal bar swaps x and y axes" do
      config = %{
        "chart_type" => "horizontal_bar",
        "x_field" => "name",
        "y_field" => "value"
      }

      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["mark"]["type"] == "bar"
      assert spec["encoding"]["y"]["field"] == "name"
      assert spec["encoding"]["x"]["field"] == "value"
      assert spec["encoding"]["x"]["type"] == "quantitative"
    end

    test "scatter chart uses point marks" do
      r = result(["x", "y"], [[1, 2], [3, 4]])
      config = %{"chart_type" => "scatter", "x_field" => "x", "y_field" => "y"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["mark"]["type"] == "point"
    end

    test "series_field adds color encoding" do
      r = result(["name", "value", "group"], [["A", 10, "g1"], ["B", 20, "g2"]])

      config = %{
        "chart_type" => "bar",
        "x_field" => "name",
        "y_field" => "value",
        "series_field" => "group"
      }

      spec = VegaSpecBuilder.build(r, config)

      assert spec["encoding"]["color"]["field"] == "group"
      assert spec["encoding"]["color"]["type"] == "nominal"
    end

    test "histogram uses binning on x-axis" do
      r = result(["amount"], [[10], [20], [30], [15], [25]])
      config = %{"chart_type" => "histogram", "x_field" => "amount"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["encoding"]["x"]["bin"] == %{"maxbins" => 10}
      assert spec["encoding"]["y"]["aggregate"] == "count"
    end

    test "histogram respects custom bin_count" do
      r = result(["amount"], [[10], [20]])
      config = %{"chart_type" => "histogram", "x_field" => "amount", "bin_count" => "25"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["encoding"]["x"]["bin"] == %{"maxbins" => 25}
    end

    test "funnel chart uses centered bars" do
      r = result(["stage", "count"], [["Leads", 100], ["Sales", 30]])
      config = %{"chart_type" => "funnel", "x_field" => "stage", "y_field" => "count"}
      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["layer"])
      bar_layer = Enum.find(spec["layer"], &(get_in(&1, ["mark", "type"]) == "bar"))
      assert bar_layer["encoding"]["x"]["stack"] == "center"
    end

    test "heatmap uses rect marks" do
      r = result(["x", "y"], [["A", "B"]])
      config = %{"chart_type" => "heatmap", "x_field" => "x", "y_field" => "y"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["mark"]["type"] == "rect"
      assert spec["encoding"]["color"]["scale"]["scheme"] == "yellowgreenblue"
    end

    test "waterfall chart uses cumulative transforms" do
      r = result(["step", "delta"], [["Revenue", 100], ["Costs", -60]])
      config = %{"chart_type" => "waterfall", "x_field" => "step", "y_field" => "delta"}
      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["transform"])
      assert spec["encoding"]["y"]["field"] == "_prev_cumulative"
      assert spec["encoding"]["y2"]["field"] == "_cumulative"
    end

    test "KPI renders value and label text layers" do
      r = result(["total"], [[42]])
      config = %{"chart_type" => "kpi", "value_field" => "total", "kpi_label" => "Orders"}
      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["layer"])
      assert length(spec["layer"]) == 2

      label_layer = List.last(spec["layer"])
      assert label_layer["encoding"]["text"]["field"] == "_label"

      label_value = spec["data"]["values"] |> List.first() |> Map.get("_label")
      assert label_value == "Orders"
    end

    test "gauge renders arc layers" do
      r = result(["score"], [[75]])

      config = %{
        "chart_type" => "gauge",
        "value_field" => "score",
        "min_value" => "0",
        "max_value" => "100"
      }

      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["layer"])
      arcs = Enum.filter(spec["layer"], &(get_in(&1, ["mark", "type"]) == "arc"))
      assert length(arcs) == 2
    end

    test "progress bar renders bar layers with goal" do
      r = result(["done"], [[60]])

      config = %{
        "chart_type" => "progress",
        "value_field" => "done",
        "goal_value" => "100"
      }

      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["layer"])
      bars = Enum.filter(spec["layer"], &(get_in(&1, ["mark", "type"]) == "bar"))
      assert length(bars) == 2
    end

    test "trend renders value, label, and delta layers" do
      r = result(["sales"], [[120], [100]])
      config = %{"chart_type" => "trend", "value_field" => "sales"}
      spec = VegaSpecBuilder.build(r, config)

      assert is_list(spec["layer"])
      assert length(spec["layer"]) == 3
    end

    test "sparkline has no axes" do
      r = result(["day", "val"], [["Mon", 10], ["Tue", 20]])
      config = %{"chart_type" => "sparkline", "x_field" => "day", "y_field" => "val"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["mark"]["type"] == "area"
      assert spec["encoding"]["x"]["axis"] == nil
      assert spec["encoding"]["y"]["axis"] == nil
    end

    test "combo chart produces bar and line layers" do
      r = result(["month", "revenue", "orders"], [["Jan", 100, 5], ["Feb", 200, 8]])

      config = %{
        "chart_type" => "combo",
        "x_field" => "month",
        "y_field" => "revenue",
        "y2_field" => "orders"
      }

      spec = VegaSpecBuilder.build(r, config)

      assert length(spec["layer"]) == 2
      marks = Enum.map(spec["layer"], &get_in(&1, ["mark", "type"]))
      assert "bar" in marks
      assert "line" in marks
      assert spec["resolve"]["scale"]["y"] == "independent"
    end
  end

  # -- build/2 data normalization --------------------------------------------

  describe "build/2 data normalization" do
    test "normalizes Decimal values to numbers" do
      r = result(["name", "amount"], [["A", Decimal.new("9.99")], ["B", Decimal.new("20")]])
      config = %{"chart_type" => "bar", "x_field" => "name", "y_field" => "amount"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["amount"] == 9.99
      assert Enum.at(values, 1)["amount"] == 20
    end

    test "normalizes NaiveDateTime to ISO8601 strings" do
      ndt = ~N[2025-07-12 07:34:36]
      r = result(["date", "value"], [[ndt, 10]])
      config = %{"chart_type" => "bar", "x_field" => "date", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["date"] == "2025-07-12T07:34:36"
    end

    test "normalizes Date to ISO8601 strings" do
      r = result(["date", "value"], [[~D[2025-07-01], 10]])
      config = %{"chart_type" => "bar", "x_field" => "date", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["date"] == "2025-07-01"
    end

    test "normalizes DateTime to ISO8601 strings" do
      {:ok, dt, _} = DateTime.from_iso8601("2025-07-12T07:34:36Z")
      r = result(["date", "value"], [[dt, 10]])
      config = %{"chart_type" => "bar", "x_field" => "date", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["date"] == "2025-07-12T07:34:36Z"
    end

    test "preserves nil values" do
      r = result(["name", "value"], [["A", nil]])
      config = %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["value"] == nil
    end

    test "preserves plain integers and strings" do
      r = result(["name", "value"], [["A", 42]])
      config = %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      values = spec["data"]["values"]
      assert Enum.at(values, 0)["name"] == "A"
      assert Enum.at(values, 0)["value"] == 42
    end

    test "spec with normalized data is JSON-encodable" do
      r =
        result(
          ["date", "amount", "label"],
          [
            [~N[2025-07-12 07:34:36], Decimal.new("9.99"), "order"],
            [~D[2025-07-01], Decimal.new("0"), nil]
          ]
        )

      config = %{"chart_type" => "bar", "x_field" => "date", "y_field" => "amount"}
      spec = VegaSpecBuilder.build(r, config)

      assert {:ok, json} = Jason.encode(spec)
      assert is_binary(json)
    end
  end

  # -- build/2 type inference ------------------------------------------------

  describe "build/2 type inference" do
    test "infers temporal type for NaiveDateTime values" do
      r = result(["date", "value"], [[~N[2025-01-01 00:00:00], 10]])
      config = %{"chart_type" => "bar", "x_field" => "date", "y_field" => "value"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["encoding"]["x"]["type"] == "temporal"
    end

    test "infers quantitative type for numeric values" do
      r = result(["x", "y"], [[1, 10]])
      config = %{"chart_type" => "bar", "x_field" => "x", "y_field" => "y"}
      spec = VegaSpecBuilder.build(r, config)

      assert spec["encoding"]["x"]["type"] == "quantitative"
    end

    test "infers nominal type for string values" do
      config = %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"}
      spec = VegaSpecBuilder.build(simple_result(), config)

      assert spec["encoding"]["x"]["type"] == "nominal"
    end
  end
end
