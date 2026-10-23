defmodule Lotus.Web.ChartsTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Charts

  # -- Helpers ---------------------------------------------------------------

  defp result(columns, rows) do
    %Lotus.Result{columns: columns, rows: rows, num_rows: length(rows)}
  end

  defp simple_result do
    result(["name", "value"], [["A", 10], ["B", 20], ["C", 30]])
  end

  # What the browser draws: the compiled chart, and its data as its table has it.
  defp wire(result, config) do
    {:ok, wire} = result |> Charts.chart(config) |> Fude.Compile.compile()
    wire
  end

  defp table(result, config), do: result |> wire(config) |> Fude.Compile.table()

  defp sales do
    result(["region", "channel", "revenue"], [
      ["North", "Online", 120],
      ["North", "Retail", 80],
      ["South", "Online", 60],
      ["South", "Retail", 90],
      ["North", "Online", 30]
    ])
  end

  defp months do
    result(
      ["month", "orders", "revenue"],
      for(m <- 1..4, do: [Date.new!(2026, m, 1), m * 100, Decimal.new("#{m * 1000}.50")])
    )
  end

  # -- chart_type_ids/0 ------------------------------------------------------

  describe "chart_type_ids/0" do
    test "returns a non-empty list of strings" do
      ids = Charts.chart_type_ids()
      assert [_ | _] = ids
      assert Enum.all?(ids, &is_binary/1)
    end

    test "includes common chart types" do
      ids = Charts.chart_type_ids()

      for type <- ~w(bar line area pie scatter kpi) do
        assert type in ids
      end
    end
  end

  # -- chart_type_label/1 ----------------------------------------------------

  describe "chart_type_label/1" do
    test "returns a label for known chart types" do
      assert Charts.chart_type_label("bar") == "Bar Chart"
      assert Charts.chart_type_label("line") == "Line Chart"
      assert Charts.chart_type_label("pie") == "Pie Chart"
    end

    test "returns a fallback for unknown chart type" do
      assert Charts.chart_type_label("unknown") == "Chart"
    end
  end

  # -- valid_config?/1 -------------------------------------------------------

  describe "valid_config?/1" do
    test "returns false for nil" do
      refute Charts.valid_config?(nil)
    end

    test "returns false for empty map" do
      refute Charts.valid_config?(%{})
    end

    test "returns false when only chart_type is set (no x/y fields)" do
      refute Charts.valid_config?(%{"chart_type" => "bar"})
    end

    test "returns false when x_field or y_field is empty string" do
      refute Charts.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "",
               "y_field" => "value"
             })

      refute Charts.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "name",
               "y_field" => ""
             })
    end

    test "returns true for standard chart with x_field and y_field" do
      assert Charts.valid_config?(%{
               "chart_type" => "bar",
               "x_field" => "name",
               "y_field" => "value"
             })
    end

    test "returns true for KPI with value_field" do
      assert Charts.valid_config?(%{
               "chart_type" => "kpi",
               "value_field" => "total"
             })
    end

    test "returns true for gauge with value_field" do
      assert Charts.valid_config?(%{
               "chart_type" => "gauge",
               "value_field" => "score"
             })
    end

    test "returns true for histogram with x_field" do
      assert Charts.valid_config?(%{
               "chart_type" => "histogram",
               "x_field" => "amount"
             })
    end

    test "returns false for KPI without value_field" do
      refute Charts.valid_config?(%{"chart_type" => "kpi"})
    end

    test "returns false for histogram without x_field" do
      refute Charts.valid_config?(%{"chart_type" => "histogram"})
    end
  end

  # -- build_config/1 --------------------------------------------------------

  describe "build_config/1" do
    test "returns empty map when chart_type is nil" do
      assert Charts.build_config(%{"chart_type" => nil}) == %{}
    end

    test "returns empty map when chart_type is empty string" do
      assert Charts.build_config(%{"chart_type" => ""}) == %{}
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

      config = Charts.build_config(viz)

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

      config = Charts.build_config(viz)

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

      config = Charts.build_config(viz)

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

      config = Charts.build_config(viz)

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

      config = Charts.build_config(viz)

      assert config["y2_field"] == "orders"
      assert config["y2_axis_title"] == "Order Count"
      assert config["series_field"] == "region"
    end
  end

  doctest Lotus.Web.Charts

  describe "chart/2: the kinds" do
    test "a bar sums the rows of its category, by series" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "series_field" => "channel"
      }

      assert wire(sales(), config)["kind"] == "bar"
      {_heads, rows} = table(sales(), config)
      assert ["North", 150, "Online"] in rows
      assert ["South", 90, "Retail"] in rows
    end

    test "the categories keep the result's order" do
      result = result(["name", "value"], [["Zeta", 1], ["Alpha", 2], ["Mid", 3]])
      wire = wire(result, %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"})
      assert wire["scales"]["x"]["domain"] == ["Zeta", "Alpha", "Mid"]
    end

    test "a horizontal bar puts the categories on the y axis" do
      wire =
        wire(simple_result(), %{
          "chart_type" => "horizontal_bar",
          "x_field" => "name",
          "y_field" => "value"
        })

      assert [%{"horizontal" => true}] = wire["layers"]
      assert wire["scales"]["y"]["domain"] == ["A", "B", "C"]
    end

    test "a line has its points; an area, its fill" do
      line =
        wire(months(), %{"chart_type" => "line", "x_field" => "month", "y_field" => "orders"})

      assert [%{"mark" => "line", "options" => %{"points" => true}}] = line["layers"]
      assert line["scales"]["x"]["type"] == "time"

      area =
        wire(months(), %{"chart_type" => "area", "x_field" => "month", "y_field" => "orders"})

      assert [%{"mark" => "area"}] = area["layers"]
    end

    test "a combo draws bars on the left axis and the line of y2 on the right" do
      config = %{
        "chart_type" => "combo",
        "x_field" => "month",
        "y_field" => "orders",
        "y2_field" => "revenue",
        "y2_axis_title" => "Revenue (EUR)"
      }

      wire = wire(months(), config)

      assert [%{"mark" => "bar", "axis" => nil}, %{"mark" => "line", "axis" => "right"}] =
               wire["layers"]

      assert wire["scales"]["y"]["domain"] == [0, 400]
      assert wire["scales"]["yRight"]["title"] == "Revenue (EUR)"
    end

    test "a combo without y2 is its bars" do
      wire =
        wire(months(), %{"chart_type" => "combo", "x_field" => "month", "y_field" => "orders"})

      assert [%{"mark" => "bar"}] = wire["layers"]
      refute Map.has_key?(wire["scales"], "yRight")
    end

    test "a scatter, and a bubble sized by its size field" do
      scatter =
        wire(months(), %{"chart_type" => "scatter", "x_field" => "orders", "y_field" => "revenue"})

      assert [%{"mark" => "point"}] = scatter["layers"]

      bubble =
        wire(months(), %{
          "chart_type" => "bubble",
          "x_field" => "orders",
          "y_field" => "revenue",
          "size_field" => "orders"
        })

      assert Map.has_key?(bubble["scales"], "size")
    end

    test "a bubble without a size field is a scatter" do
      wire =
        wire(months(), %{"chart_type" => "bubble", "x_field" => "orders", "y_field" => "revenue"})

      assert wire["kind"] == "scatter"
    end

    test "a histogram bins its field into about bin_count bins, counting the rows" do
      result = result(["score"], for(n <- 1..100, do: [n]))

      wire =
        wire(result, %{"chart_type" => "histogram", "x_field" => "score", "bin_count" => "5"})

      {_heads, rows} = Fude.Compile.table(wire)
      assert length(rows) in 4..6
      assert rows |> Enum.map(&List.last/1) |> Enum.sum() == 100
    end

    test "a heatmap colors its cells by the value field, else by their rows" do
      valued =
        wire(sales(), %{
          "chart_type" => "heatmap",
          "x_field" => "region",
          "y_field" => "channel",
          "series_field" => "revenue"
        })

      assert valued["scales"]["color"]["type"] == "sequential"
      {_heads, rows} = Fude.Compile.table(valued)
      assert ["North", "Online", 150] in rows

      counted =
        wire(sales(), %{"chart_type" => "heatmap", "x_field" => "region", "y_field" => "channel"})

      {_heads, rows} = Fude.Compile.table(counted)
      assert ["North", "Online", 2] in rows
    end

    test "a pie or a donut slices by the series field, else by x" do
      by_x =
        wire(sales(), %{"chart_type" => "pie", "x_field" => "region", "y_field" => "revenue"})

      assert by_x["scales"]["color"]["domain"] == ["North", "South"]

      by_series =
        wire(sales(), %{
          "chart_type" => "donut",
          "x_field" => "region",
          "y_field" => "revenue",
          "series_field" => "channel"
        })

      assert by_series["kind"] == "donut"
      assert by_series["scales"]["color"]["domain"] == ["Online", "Retail"]
    end

    test "a funnel and a waterfall" do
      funnel =
        wire(sales(), %{"chart_type" => "funnel", "x_field" => "region", "y_field" => "revenue"})

      assert funnel["kind"] == "funnel"

      waterfall =
        wire(sales(), %{
          "chart_type" => "waterfall",
          "x_field" => "region",
          "y_field" => "revenue"
        })

      assert waterfall["kind"] == "waterfall"
    end

    test "a sparkline has no axes" do
      wire =
        wire(months(), %{"chart_type" => "sparkline", "x_field" => "month", "y_field" => "orders"})

      assert wire["axes"] == false
    end
  end

  describe "chart/2: single values" do
    test "a KPI shows the first row's value and its label" do
      wire =
        wire(months(), %{
          "chart_type" => "kpi",
          "value_field" => "orders",
          "kpi_label" => "Orders"
        })

      assert %{"value" => 100, "label" => "Orders"} = wire["single"]
    end

    test "a KPI without a label is labelled by its field" do
      wire = wire(months(), %{"chart_type" => "kpi", "value_field" => "orders"})
      assert wire["single"]["label"] == "orders"
    end

    test "a trend compares with the comparison field, else with the second row" do
      result = result(["this_week", "last_week"], [[120, 100], [90, 80]])

      with_field =
        wire(result, %{
          "chart_type" => "trend",
          "value_field" => "this_week",
          "comparison_field" => "last_week"
        })

      assert %{"value" => 120, "compare" => 100} = with_field["single"]

      by_row = wire(result, %{"chart_type" => "trend", "value_field" => "this_week"})
      assert %{"value" => 120, "compare" => 90} = by_row["single"]
    end

    test "a gauge between its min and max, a progress toward its goal" do
      result = result(["score"], [[72]])

      gauge =
        wire(result, %{
          "chart_type" => "gauge",
          "value_field" => "score",
          "min_value" => "0",
          "max_value" => "80"
        })

      assert gauge["kind"] == "gauge"
      assert gauge["single"]["value"] == 72

      progress =
        wire(result, %{"chart_type" => "progress", "value_field" => "score", "goal_value" => 90})

      assert progress["single"]["goal"] == 90
    end
  end

  describe "chart/2: axes and data" do
    test "the axes take the config's titles, or none when their label is hidden" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "name",
        "y_field" => "value",
        "x_axis_title" => "Name",
        "y_axis_show_label" => false
      }

      wire = wire(simple_result(), config)
      assert wire["scales"]["x"]["title"] == "Name"
      refute Map.has_key?(wire["scales"]["y"], "title")
    end

    test "an axis is titled by its field's name in words, and by the name a config gives it" do
      result = result(["order_month", "total_revenue"], [["Jan", 10], ["Feb", 20]])
      config = %{"chart_type" => "bar", "x_field" => "order_month", "y_field" => "total_revenue"}

      assert %{"x" => %{"title" => "Order month"}, "y" => %{"title" => "Total revenue"}} =
               wire(result, config)["scales"]

      # The settings used to fill in the field's name as the title: that is no title of its own.
      assert wire(result, Map.put(config, "x_axis_title", "order_month"))["scales"]["x"]["title"] ==
               "Order month"

      assert wire(result, Map.put(config, "x_axis_title", "Month"))["scales"]["x"]["title"] ==
               "Month"
    end

    test "decimals, dates and times are kept; other values are written as Lotus writes them" do
      uuid =
        <<0x55, 0x0E, 0x84, 0x00, 0xE2, 0x9B, 0x41, 0xD4, 0xA7, 0x16, 0x44, 0x66, 0x55, 0x44,
          0x00, 0x00>>

      result =
        result(["id", "at", "amount", "flag", "meta"], [
          [uuid, ~N[2026-01-01 10:00:00], Decimal.new("1.50"), true, %{"a" => 1}]
        ])

      {_heads, [row]} =
        table(result, %{"chart_type" => "bar", "x_field" => "id", "y_field" => "amount"})

      assert ["550e8400-e29b-41d4-a716-446655440000", 1.5] = row
    end

    test "a field that is not a column says so, without raising" do
      chart =
        Charts.chart(simple_result(), %{
          "chart_type" => "bar",
          "x_field" => "nmae",
          "y_field" => "value"
        })

      assert {:error, [message]} = Fude.Compile.compile(chart)
      assert message =~ ~s(did you mean "name"?)
    end

    test "spec/2 is the chart as plain data, with its rows" do
      spec =
        Charts.spec(simple_result(), %{
          "chart_type" => "bar",
          "x_field" => "name",
          "y_field" => "value"
        })

      assert %{"fude" => 1, "kind" => "bar", "datasets" => _} = spec
      assert {:ok, _chart} = Fude.Spec.load(spec)
      assert spec |> JSON.encode!() |> JSON.decode!() == spec
    end
  end

  describe "chart/2: options" do
    @bars %{
      "chart_type" => "bar",
      "x_field" => "region",
      "y_field" => "revenue",
      "series_field" => "channel"
    }

    test "the number format reaches the measure's scale" do
      for {format, expected} <- [
            {"number", "number"},
            {"integer", "integer"},
            {"compact", "compact"},
            {"percent", "percent"}
          ] do
        assert wire(sales(), Map.put(@bars, "number_format", format))["scales"]["y"]["format"] ==
                 expected
      end

      config = Map.merge(@bars, %{"number_format" => "currency", "currency" => "eur"})
      assert wire(sales(), config)["scales"]["y"]["format"] == "currency:EUR"

      # A currency that is not a code is no format, rather than a chart that breaks.
      config = Map.merge(@bars, %{"number_format" => "currency", "currency" => "euros"})
      refute wire(sales(), config)["scales"]["y"]["format"]

      refute wire(sales(), @bars)["scales"]["y"]["format"]
    end

    test "a single value takes the format, as its exact number or compact" do
      result = result(["total"], [[6_893_913.6]])
      config = %{"chart_type" => "kpi", "value_field" => "total", "number_format" => "number"}
      assert wire(result, config)["single"]["format"] == "number"
    end

    test "values on the bars: on for horizontal bars unless turned off, off for others unless on" do
      labels = fn config -> hd(wire(sales(), config)["layers"])["options"]["labels"] end

      refute labels.(@bars)
      assert labels.(Map.put(@bars, "show_values", "true"))
      assert labels.(Map.put(@bars, "chart_type", "horizontal_bar"))

      refute labels.(
               Map.merge(@bars, %{"chart_type" => "horizontal_bar", "show_values" => "false"})
             )
    end

    test "series of areas stack, overlap, or stack to 100%" do
      config = %{
        "chart_type" => "area",
        "x_field" => "region",
        "y_field" => "revenue",
        "series_field" => "channel"
      }

      stack = fn value ->
        hd(wire(sales(), Map.put(config, "stack", value))["layers"])["stack"]
      end

      assert stack.("stacked") == "zero"
      assert stack.("grouped") == nil
      assert stack.("normalized") == "normalize"
    end

    test "a line has a dot at each value, but not in small multiples" do
      config = %{"chart_type" => "line", "x_field" => "region", "y_field" => "revenue"}
      points = fn config -> hd(wire(sales(), config)["layers"])["options"]["points"] end

      assert points.(config)
      refute points.(Map.put(config, "facet_field", "channel"))
    end

    test "series of bars stack, sit side by side, or stack to 100%" do
      stack = fn value -> hd(wire(sales(), Map.put(@bars, "stack", value))["layers"])["stack"] end

      assert stack.("stacked") == "zero"
      assert stack.("grouped") == nil
      assert stack.("normalized") == "normalize"
    end

    test "bars in the query's order, by value or by name" do
      result = result(["region", "revenue"], [["North", 10], ["East", 30], ["South", 20]])
      config = %{"chart_type" => "bar", "x_field" => "region", "y_field" => "revenue"}
      domain = fn sort -> wire(result, Map.put(config, "sort", sort))["scales"]["x"]["domain"] end

      assert domain.("query") == ["North", "East", "South"]
      assert domain.("value_desc") == ["East", "South", "North"]
      assert domain.("value_asc") == ["North", "South", "East"]
      assert domain.("label") == ["East", "North", "South"]
    end

    test "smooth lines, and an axis from zero" do
      config = %{"chart_type" => "line", "x_field" => "region", "y_field" => "revenue"}
      result = result(["region", "revenue"], [["A", 100], ["B", 140]])

      assert hd(wire(result, Map.put(config, "smooth", "true"))["layers"])["options"]["curve"] ==
               "monotone"

      assert [0 | _] =
               wire(result, Map.put(config, "y_axis_zero", "true"))["scales"]["y"]["domain"]

      assert [low | _] = wire(result, config)["scales"]["y"]["domain"]
      assert low > 0
    end

    test "the combo's line has its own format and its own zero" do
      result = result(["month", "orders", "revenue"], [["Jan", 10, 1500], ["Feb", 12, 1800]])

      config = %{
        "chart_type" => "combo",
        "x_field" => "month",
        "y_field" => "orders",
        "y2_field" => "revenue",
        "y2_number_format" => "compact",
        "y2_axis_zero" => "true"
      }

      assert %{"format" => "compact", "domain" => [0 | _]} =
               wire(result, config)["scales"]["yRight"]
    end

    test "a reference line, with its words" do
      config = Map.merge(@bars, %{"reference_value" => "150", "reference_label" => "Goal"})

      assert [%{"type" => "line", "y" => 150.0, "text" => "Goal"}] =
               wire(sales(), config)["annotations"]

      assert wire(sales(), Map.put(@bars, "reference_value", ""))["annotations"] == []
    end

    test "small multiples: a chart for each value of a field" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "facet_field" => "channel",
        "facet_columns" => "2"
      }

      assert %{"columns" => 2, "panels" => [_, _]} = wire(sales(), config)["facet"]
    end

    test "a subtitle and a source" do
      config = Map.merge(@bars, %{"subtitle" => "By channel", "source" => "Ledger"})
      assert %{"subtitle" => "By channel", "source" => "Ledger"} = wire(sales(), config)
    end

    test "build_config/1 keeps a type's options and drops another's" do
      viz = Map.merge(@bars, %{"stack" => "grouped", "smooth" => "true", "subtitle" => "S"})

      assert %{"stack" => "grouped", "subtitle" => "S"} = config = Charts.build_config(viz)
      refute Map.has_key?(config, "smooth")
    end
  end

  describe "chart/2: maps, tooltips and callouts" do
    defp countries do
      result(["country", "users", "plan"], [
        ["PRT", 120, "pro"],
        ["ESP", 80, "free"],
        ["FRA", 200, "pro"]
      ])
    end

    test "a map colors each region by its value, on the world unless told the US" do
      config = %{"chart_type" => "map", "x_field" => "country", "y_field" => "users"}
      wire = wire(countries(), config)

      assert wire["kind"] == "choropleth"
      assert hd(wire["layers"])["options"]["map"] == "world"
      assert wire["scales"]["region"]["domain"] == ["PRT", "ESP", "FRA"]
      assert wire["scales"]["color"]["type"] == "sequential"

      us = wire(countries(), Map.put(config, "map", "us-states"))
      assert hd(us["layers"])["options"]["map"] == "us-states"
    end

    test "a bubble map sizes a circle at each region" do
      config = %{"chart_type" => "bubble_map", "x_field" => "country", "y_field" => "users"}
      wire = wire(countries(), config)

      assert wire["kind"] == "bubble_map"
      assert %{"size" => %{"type" => "sqrt"}} = wire["scales"]
    end

    test "map types are valid with a region and a value, and keep their map" do
      assert Charts.valid_config?(%{"chart_type" => "map", "x_field" => "c", "y_field" => "v"})

      assert %{"map" => "us-states"} =
               Charts.build_config(%{
                 "chart_type" => "map",
                 "x_field" => "c",
                 "y_field" => "v",
                 "map" => "us-states"
               })
    end

    test "tooltip fields go to Fude's tooltip channel; an empty choice is none" do
      config = %{"chart_type" => "map", "x_field" => "country", "y_field" => "users"}

      assert [%{"title" => "Plan"}] =
               hd(wire(countries(), Map.put(config, "tooltip_fields", ["", "plan"]))["layers"])[
                 "tooltip"
               ]

      assert hd(wire(countries(), Map.put(config, "tooltip_fields", [""]))["layers"])["tooltip"] ==
               []

      assert Charts.build_config(Map.put(config, "tooltip_fields", [""]))
             |> Map.has_key?("tooltip_fields") ==
               false
    end

    test "callouts on the highest and the lowest value, with the value" do
      result =
        result(["month", "revenue"], [
          [~D[2026-01-01], 100],
          [~D[2026-02-01], 412_500],
          [~D[2026-03-01], 50]
        ])

      config = %{
        "chart_type" => "line",
        "x_field" => "month",
        "y_field" => "revenue",
        "mark_max" => "true",
        "mark_min" => "true"
      }

      assert [
               %{"type" => "label", "y" => 412_500, "text" => "Highest: 412.5K"},
               %{"type" => "label", "y" => 50, "text" => "Lowest: 50"}
             ] = wire(result, config)["annotations"]
    end

    test "no callouts on stacked series, whose marks are not at their values" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "series_field" => "channel",
        "mark_max" => "true"
      }

      assert wire(sales(), config)["annotations"] == []
      assert [_] = wire(sales(), Map.put(config, "stack", "grouped"))["annotations"]
    end

    test "a shaded range of dates, of categories and of numbers" do
      dates = result(["month", "revenue"], [[~D[2026-01-01], 1], [~D[2026-03-01], 2]])

      config = %{
        "chart_type" => "line",
        "x_field" => "month",
        "y_field" => "revenue",
        "band_from" => "2026-01-15",
        "band_to" => "2026-02-15",
        "band_label" => "Sale"
      }

      assert [%{"type" => "band", "x" => from, "x2" => to, "text" => "Sale"}] =
               wire(dates, config)["annotations"]

      assert {from, to} ==
               {DateTime.to_unix(~U[2026-01-15 00:00:00Z], :millisecond),
                DateTime.to_unix(~U[2026-02-15 00:00:00Z], :millisecond)}

      categories = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "band_from" => "North",
        "band_to" => "South"
      }

      assert [%{"type" => "band", "x" => 0, "x2" => 1}] = wire(sales(), categories)["annotations"]

      numbers = result(["x", "y"], [[1, 2], [10, 3]])

      config = %{
        "chart_type" => "scatter",
        "x_field" => "x",
        "y_field" => "y",
        "band_from" => "2",
        "band_to" => "5"
      }

      assert [%{"x" => 2.0, "x2" => 5.0}] = wire(numbers, config)["annotations"]
    end

    test "half a range is no range" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "band_from" => "North"
      }

      assert wire(sales(), config)["annotations"] == []
    end
  end

  describe "chart/2: decimals, colors, funnels and sparklines" do
    @series %{
      "chart_type" => "bar",
      "x_field" => "region",
      "y_field" => "revenue",
      "series_field" => "channel"
    }

    test "the decimals go with the values' format, or alone" do
      config = Map.merge(@series, %{"number_format" => "number", "decimals" => "0"})
      assert wire(sales(), config)["scales"]["y"]["format"] == "number:0"

      assert wire(sales(), Map.put(@series, "decimals", "2"))["scales"]["y"]["format"] == ":2"
      refute wire(sales(), Map.put(@series, "decimals", ""))["scales"]["y"]["format"]
    end

    test "a single value takes its decimals" do
      result = result(["total"], [[6_893_913.6]])

      config = %{
        "chart_type" => "kpi",
        "value_field" => "total",
        "number_format" => "number",
        "decimals" => "0"
      }

      assert wire(result, config)["single"]["format"] == "number:0"
    end

    test "series in the colorblind-safe scheme, or Fude's own" do
      assert wire(sales(), Map.put(@series, "color_scheme", "okabe_ito"))["scales"]["color"][
               "scheme"
             ] ==
               "okabe_ito"

      refute wire(sales(), @series)["scales"]["color"]["scheme"]
    end

    test "a value's colors: a sequential ramp, or diverging through a neutral" do
      config = %{
        "chart_type" => "heatmap",
        "x_field" => "region",
        "y_field" => "channel",
        "series_field" => "revenue"
      }

      assert wire(sales(), Map.put(config, "color_scheme", "green"))["scales"]["color"]["scheme"] ==
               "green"

      diverging = Map.merge(config, %{"color_scheme" => "red_green", "scheme_mid" => "100"})

      assert %{"scheme" => "red_green", "mid" => 100.0} =
               wire(sales(), diverging)["scales"]["color"]

      refute wire(sales(), Map.put(config, "color_scheme", "nonsense"))["scales"]["color"][
               "scheme"
             ]
    end

    test "a funnel's colors and values" do
      result = result(["stage", "people"], [["Visited", 100], ["Paid", 9]])
      config = %{"chart_type" => "funnel", "x_field" => "stage", "y_field" => "people"}

      stages =
        wire(
          result,
          Map.merge(config, %{"funnel_colors" => "stages", "funnel_labels" => "inside"})
        )

      assert %{"legend" => false, "domain" => ["Visited", "Paid"]} = stages["scales"]["color"]
      assert hd(stages["layers"])["options"]["labels"] == "inside"

      steps =
        wire(result, Map.merge(config, %{"funnel_colors" => "steps", "funnel_labels" => "none"}))

      assert %{"step" => true, "labels" => false} = hd(steps["layers"])["options"]
    end

    test "a sparkline's area, dots and last value" do
      result = result(["day", "visits"], [[~D[2026-01-01], 10], [~D[2026-01-02], 5]])

      config = %{
        "chart_type" => "sparkline",
        "x_field" => "day",
        "y_field" => "visits",
        "sparkline_area" => "true",
        "sparkline_points" => "extremes",
        "sparkline_value" => "true"
      }

      assert %{"area" => true, "points" => "extremes", "value" => true} =
               hd(wire(result, config)["layers"])["options"]
    end

    test "tooltip fields carry their values" do
      config = %{
        "chart_type" => "bar",
        "x_field" => "region",
        "y_field" => "revenue",
        "tooltip_fields" => ["channel"]
      }

      assert [%{"title" => "Channel", "values" => [_ | _]}] =
               hd(wire(sales(), config)["layers"])["tooltip"]
    end
  end
end
