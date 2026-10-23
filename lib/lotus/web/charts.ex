defmodule Lotus.Web.Charts do
  @moduledoc """
  Lotus's charts: a visualization config, as Lotus stores it (a
  `"chart_type"` and the fields its type reads), drawn with
  [Fude](https://hex.pm/packages/fude).

  `chart/2` makes the `Fude.Chart` of a query result and a config, which a
  page draws with `Fude.Components.chart/1`; `spec/2` gives it as plain
  data (`Fude.Spec.dump/2`), with its rows.

  ## Config shape

      %{
        "chart_type" => "bar" | "horizontal_bar" | "line" | "area" | "combo" | "scatter" |
                        "bubble" | "histogram" | "heatmap" | "pie" | "donut" | "funnel" |
                        "waterfall" | "kpi" | "trend" | "gauge" | "progress" | "sparkline",
        "x_field" => "column_name",
        "y_field" => "column_name",
        "series_field" => "column_name" | nil,
        "x_axis_title" => "Custom Label" | nil,
        "y_axis_title" => "Custom Label" | nil,
        "x_axis_show_label" => boolean (default: true),
        "y_axis_show_label" => boolean (default: true),
        "size_field" => "column_name" (bubble),
        "y2_field" => "column_name", "y2_axis_title" => "Label" (combo),
        "bin_count" => integer (histogram, default: 10),
        "value_field" => "column_name", "kpi_label" => "Label" (kpi, trend, gauge, progress),
        "comparison_field" => "column_name" (trend),
        "min_value" => number, "max_value" => number (gauge),
        "goal_value" => number (progress),

        # How the chart looks (all optional; see option_keys/0):
        "number_format" => "number" | "integer" | "compact" | "percent" | "currency",
        "currency" => "USD" (with "currency"),
        "y2_number_format" => ... (combo: the line's),
        "y_axis_zero" => boolean, "y2_axis_zero" => boolean,
        "show_values" => boolean (the values on the marks),
        "stack" => "stacked" | "grouped" | "normalized" (bars and areas with a series),
        "sort" => "query" | "value_desc" | "value_asc" | "label" (bars),
        "smooth" => boolean (lines and areas),
        "reference_value" => number, "reference_label" => "Goal",
        "facet_field" => "column_name", "facet_columns" => integer (small multiples),
        "subtitle" => "How it is measured", "source" => "Where the data comes from"
      }

  Booleans arrive from forms as `"true"` and `"false"`; both forms are read.
  """

  use Phoenix.Component
  use Gettext, backend: Lotus.Web.Gettext

  @chart_type_ids ~w(bar horizontal_bar line area combo scatter bubble histogram heatmap pie donut funnel waterfall map bubble_map kpi trend gauge progress sparkline)

  @doc "Returns the ordered list of chart type ID strings."
  def chart_type_ids, do: @chart_type_ids

  @doc "Returns chart types organized into display groups for the UI grid."
  def chart_type_groups do
    [
      {gettext("Charts"), ~w(bar horizontal_bar line area combo)},
      {gettext("Distribution"), ~w(scatter bubble histogram heatmap)},
      {gettext("Part of whole"), ~w(pie donut funnel waterfall)},
      {gettext("Maps"), ~w(map bubble_map)},
      {gettext("Single value"), ~w(kpi trend gauge progress sparkline)}
    ]
  end

  @doc "Returns a human-readable label for the given chart type ID."
  def chart_type_label("bar"), do: gettext("Bar Chart")
  def chart_type_label("horizontal_bar"), do: gettext("Horizontal Bar")
  def chart_type_label("line"), do: gettext("Line Chart")
  def chart_type_label("area"), do: gettext("Area Chart")
  def chart_type_label("combo"), do: gettext("Combo Chart")
  def chart_type_label("scatter"), do: gettext("Scatter Plot")
  def chart_type_label("bubble"), do: gettext("Bubble Chart")
  def chart_type_label("pie"), do: gettext("Pie Chart")
  def chart_type_label("donut"), do: gettext("Donut Chart")
  def chart_type_label("funnel"), do: gettext("Funnel Chart")
  def chart_type_label("waterfall"), do: gettext("Waterfall")
  def chart_type_label("heatmap"), do: gettext("Heatmap")
  def chart_type_label("histogram"), do: gettext("Histogram")
  def chart_type_label("map"), do: gettext("Map")
  def chart_type_label("bubble_map"), do: gettext("Bubble Map")
  def chart_type_label("kpi"), do: gettext("KPI Card")
  def chart_type_label("trend"), do: gettext("Trend")
  def chart_type_label("gauge"), do: gettext("Gauge")
  def chart_type_label("progress"), do: gettext("Progress Bar")
  def chart_type_label("sparkline"), do: gettext("Sparkline")
  def chart_type_label(_), do: gettext("Chart")

  @doc """
  Returns `true` when `config` contains enough fields for its chart type to render.

  Used by both the query editor and results components to decide whether a
  visualization can be shown.
  """
  @spec valid_config?(map() | nil) :: boolean()
  def valid_config?(nil), do: false

  def valid_config?(%{"chart_type" => ct, "value_field" => vf})
      when ct in ~w(kpi gauge progress trend) and is_binary(vf) and vf != "",
      do: true

  def valid_config?(%{"chart_type" => "histogram", "x_field" => xf})
      when is_binary(xf) and xf != "",
      do: true

  def valid_config?(config) when is_map(config) do
    Map.has_key?(config, "chart_type") &&
      Map.has_key?(config, "x_field") && config["x_field"] != "" &&
      Map.has_key?(config, "y_field") && config["y_field"] != ""
  end

  def valid_config?(_), do: false

  @doc """
  Builds the appropriate config map for a given chart type, picking only the
  relevant keys from `viz`. Prevents stale fields from leaking across type switches.

  Returns `%{}` when `chart_type` is nil or empty (i.e. "Table (default)" selected).

  Note: axis display fields (x_axis_title, y_axis_title, etc.) are intentionally
  excluded because the dashboard card settings don't currently expose axis controls.
  """
  @spec build_config(map()) :: map()
  def build_config(%{"chart_type" => ct}) when ct in [nil, ""], do: %{}

  def build_config(viz) do
    chart_type = viz["chart_type"]
    base = %{"chart_type" => chart_type}

    Enum.reduce(config_fields(chart_type), base, fn key, acc ->
      case viz[key] do
        nil -> acc
        "" -> acc
        list when is_list(list) -> put_list(acc, key, list)
        val -> Map.put(acc, key, val)
      end
    end)
  end

  defp config_fields(type), do: fields(type) ++ option_keys(type)

  # A list of a form (the tooltip's fields) without the empty value that lets
  # it send none.
  defp put_list(config, key, list) do
    case Enum.reject(list, &(&1 == "")) do
      [] -> config
      list -> Map.put(config, key, list)
    end
  end

  defp fields("kpi"), do: ~w(value_field kpi_label)
  defp fields("gauge"), do: ~w(value_field kpi_label min_value max_value)
  defp fields("progress"), do: ~w(value_field kpi_label goal_value)
  defp fields("trend"), do: ~w(value_field kpi_label comparison_field)
  defp fields("histogram"), do: ~w(x_field bin_count series_field)
  defp fields("bubble"), do: ~w(x_field y_field series_field size_field)
  defp fields("combo"), do: ~w(x_field y_field y2_field series_field y2_axis_title)
  defp fields("map"), do: ~w(x_field y_field map)
  defp fields("bubble_map"), do: ~w(x_field y_field series_field map)
  defp fields(_), do: ~w(x_field y_field series_field)

  @words ~w(subtitle source)
  @format ~w(number_format currency decimals)
  @series_scheme ["color_scheme"]
  @value_scheme ~w(color_scheme scheme_mid)
  @reference ~w(reference_value reference_label)
  @facet ~w(facet_field facet_columns)
  @tooltip ["tooltip_fields"]
  @tooltip_adds ["tooltip_adds"]
  @motion ["animate"]
  @marks ~w(mark_max mark_min)
  @band ~w(band_from band_to band_label)

  @doc """
  The keys of the options of a chart type: how it looks, beyond its fields.
  The settings offer these, and `build_config/1` keeps them.

      iex> Lotus.Web.Charts.option_keys("pie")
      ["number_format", "currency", "decimals", "color_scheme", "tooltip_fields", "subtitle", "source", "animate"]
  """
  @spec option_keys(String.t() | nil) :: [String.t()]
  def option_keys("bar"),
    do:
      @format ++
        ~w(show_values stack sort) ++
        @series_scheme ++
        @tooltip ++ @tooltip_adds ++ @marks ++ @reference ++ @band ++ @facet ++ @words ++ @motion

  def option_keys("horizontal_bar"),
    do:
      @format ++
        ~w(show_values stack sort) ++
        @series_scheme ++ @tooltip ++ @tooltip_adds ++ @reference ++ @facet ++ @words ++ @motion

  def option_keys("line"),
    do:
      @format ++
        ~w(y_axis_zero smooth) ++
        @series_scheme ++
        @tooltip ++ @tooltip_adds ++ @marks ++ @reference ++ @band ++ @facet ++ @words ++ @motion

  # An area starts at zero: it is filled down to it.
  def option_keys("area"),
    do:
      @format ++
        ~w(stack smooth) ++
        @series_scheme ++
        @tooltip ++ @tooltip_adds ++ @marks ++ @reference ++ @band ++ @facet ++ @words ++ @motion

  def option_keys(type) when type in ~w(scatter bubble),
    do:
      @format ++
        ["y_axis_zero"] ++
        @series_scheme ++ @tooltip ++ @reference ++ @band ++ @facet ++ @words ++ @motion

  def option_keys("combo"),
    do:
      @format ++
        ~w(y2_number_format y_axis_zero y2_axis_zero smooth) ++
        @marks ++ @reference ++ @band ++ @words ++ @motion

  def option_keys("sparkline"),
    do: @format ++ ~w(smooth sparkline_area sparkline_points sparkline_value) ++ @words ++ @motion

  def option_keys(type) when type in ~w(pie donut),
    do: @format ++ @series_scheme ++ @tooltip ++ @words ++ @motion

  def option_keys(type) when type in ~w(heatmap map),
    do: @format ++ @value_scheme ++ @tooltip ++ @words ++ @motion

  def option_keys("bubble_map"), do: @format ++ @series_scheme ++ @tooltip ++ @words ++ @motion
  def option_keys("histogram"), do: @format ++ @series_scheme ++ @words ++ @motion
  def option_keys("funnel"), do: @format ++ ~w(funnel_colors funnel_labels) ++ @words ++ @motion
  def option_keys("waterfall"), do: @format ++ @words ++ @motion

  def option_keys(type) when type in ~w(kpi trend gauge progress), do: @format ++ @words
  def option_keys(_type), do: []

  @doc """
  Whether a chart type writes its values on its marks unless told not to.
  Horizontal bars do: their values sit at the ends of the bars, where a
  reader looks, and the labels do not crowd them. (Fude writes the values
  of bars only, so far.)
  """
  @spec show_values_default?(String.t() | nil) :: boolean()
  def show_values_default?(type), do: type == "horizontal_bar"

  @doc """
  The `Fude.Chart` of a query result (`%{columns: [...], rows: [...]}`) and a
  visualization config.

  A field that is not a column of the result does not raise: the chart says
  so in place of its plot (`Fude.Components.chart/1`).

  ## Examples

      iex> result = %{columns: ["name", "value"], rows: [["A", 10], ["B", 20]]}
      iex> chart = Lotus.Web.Charts.chart(result, %{"chart_type" => "bar", "x_field" => "name", "y_field" => "value"})
      iex> Fude.Chart.kind(chart)
      :bar
  """
  @spec chart(Lotus.Result.t(), map()) :: Fude.Chart.t()
  def chart(result, %{"chart_type" => type} = config) do
    data = data(result)

    type
    |> build(data, config)
    |> reference(type, config)
    |> marks(type, data, config)
    |> band(type, data, config)
    |> facet(type, config)
  end

  @doc """
  Draws the chart of a result and a config, in the dashboard's language
  and Lotus's colors (`.lotus-chart`). A config that Fude refuses shows
  why in place of the chart, rather than raising.
  """
  attr(:id, :string, required: true)
  attr(:result, :map, required: true)
  attr(:config, :map, required: true)
  attr(:height, :integer, default: nil, doc: "the plot's height, in pixels")
  attr(:export, :boolean, default: false, doc: "whether the chart has buttons that save it")
  attr(:class, :any, default: nil)

  def draw(assigns) do
    assigns =
      assign(assigns,
        built: build_chart(assigns.result, assigns.config),
        locale: Gettext.get_locale(Lotus.Web.Gettext)
      )

    ~H"""
    <%= case @built do %>
      <% {:ok, chart} -> %>
        <Fude.Components.chart
          id={@id}
          chart={chart}
          height={@height}
          locale={@locale}
          export={@export}
          class={["lotus-chart", @class]}
        />
      <% {:error, message} -> %>
        <div id={@id} class="flex items-center justify-center h-full p-4 text-sm text-red-500 dark:text-red-400" role="alert">
          {gettext("The chart could not be drawn: %{reason}", reason: message)}
        </div>
    <% end %>
    """
  end

  @doc """
  The chart of a result and a config, or why Fude refuses the config (a
  field that is not a text, a value of the wrong type).
  """
  @spec build_chart(Lotus.Result.t(), map()) :: {:ok, Fude.Chart.t()} | {:error, String.t()}
  def build_chart(result, config) do
    {:ok, chart(result, config)}
  rescue
    error in ArgumentError -> {:error, String.replace_prefix(error.message, "Fude: ", "")}
  end

  @doc """
  The chart of `result` and `config` as plain data, with its rows
  (`Fude.Spec.dump/2` with `data: true`): JSON a client can keep, read or
  draw again with `Fude.Spec.load/1`.
  """
  @spec spec(Lotus.Result.t(), map()) :: Fude.Spec.t()
  def spec(result, config), do: result |> chart(config) |> Fude.Spec.dump(data: true)

  # -- The kinds ---------------------------------------------------------------

  defp build("bar", data, c), do: Fude.bar(data, bars(c) ++ tooltip(c) ++ words(c))

  defp build("horizontal_bar", data, c),
    do: Fude.bar(data, bars(c) ++ [horizontal: true] ++ tooltip(c) ++ words(c))

  # A dot at each value, but not in small multiples: their narrow panels
  # would be all dots.
  defp build("line", data, c) do
    points = present(c["facet_field"]) == nil
    Fude.line(data, cartesian(c) ++ [points: points] ++ curve(c) ++ tooltip(c) ++ words(c))
  end

  defp build("area", data, c) do
    [x: x, y: y] ++ rest = cartesian(c)
    Fude.area(data, [x: x, y: y ++ stack(c)] ++ rest ++ curve(c) ++ tooltip(c) ++ words(c))
  end

  defp build("scatter", data, c),
    do: Fude.scatter(data, cartesian(c) ++ size(c) ++ tooltip(c) ++ words(c))

  # A bubble without a size field is a scatter: the size is what makes it one.
  defp build("bubble", data, c) do
    case size(c) do
      [] -> Fude.scatter(data, cartesian(c) ++ tooltip(c) ++ words(c))
      size -> Fude.bubble(data, cartesian(c) ++ size ++ tooltip(c) ++ words(c))
    end
  end

  defp build("histogram", data, c) do
    x = axis(c, "x_field", :x) ++ format(c, "number_format")

    Fude.histogram(
      data,
      [x: x, bins: bin_count(c["bin_count"])] ++ color(c, c["series_field"]) ++ words(c)
    )
  end

  # The value field (stored as series_field) colors the cells; without one,
  # each cell is colored by how many rows it has.
  defp build("heatmap", data, c) do
    color =
      case present(c["series_field"]) do
        nil -> {:count, c["x_field"]}
        field -> [field: field] ++ format(c, "number_format") ++ value_scheme(c)
      end

    Fude.heatmap(
      data,
      [x: axis(c, "x_field", :x), y: axis(c, "y_field", :y), color: color] ++
        tooltip(c) ++ words(c)
    )
  end

  defp build("pie", data, c), do: Fude.pie(data, slices(c) ++ tooltip(c) ++ words(c))
  defp build("donut", data, c), do: Fude.donut(data, slices(c) ++ tooltip(c) ++ words(c))

  # A region of the map for each row, by its code or name (x_field), colored
  # by its value (y_field).
  defp build("map", data, c) do
    Fude.choropleth(
      data,
      [
        region: c["x_field"],
        color: measure(c, c["y_field"]) ++ value_scheme(c),
        map: map_name(c)
      ] ++ tooltip(c) ++ words(c)
    )
  end

  # A circle at each region, sized by its value, colored by the series.
  defp build("bubble_map", data, c) do
    Fude.bubble_map(
      data,
      [region: c["x_field"], size: measure(c, c["y_field"]), map: map_name(c)] ++
        color(c, c["series_field"]) ++ tooltip(c) ++ words(c)
    )
  end

  # One color, a color for each stage, or each stage lighter than the last;
  # the values beside the bars, in them, or none.
  defp build("funnel", data, c) do
    colors =
      case c["funnel_colors"] do
        "stages" -> [color: :stage]
        "steps" -> [step: true]
        _ -> []
      end

    labels =
      case c["funnel_labels"] do
        "inside" -> [labels: :inside]
        "none" -> [labels: false]
        _ -> []
      end

    Fude.funnel(
      data,
      [x: c["x_field"], y: measure(c, c["y_field"])] ++ colors ++ labels ++ words(c)
    )
  end

  defp build("waterfall", data, c) do
    y = axis(c, "y_field", :y) ++ format(c, "number_format")
    Fude.waterfall(data, [x: axis(c, "x_field", :x), y: y] ++ words(c))
  end

  # A line, or an area under it; a dot on its last value or on its extremes
  # too; and its last value written at its end.
  defp build("sparkline", data, c) do
    points =
      case c["sparkline_points"] do
        "last" -> [points: :last]
        "extremes" -> [points: :extremes]
        _ -> []
      end

    Fude.sparkline(
      data,
      [x: c["x_field"], y: measure(c, c["y_field"])] ++
        curve(c) ++
        [area: on?(c["sparkline_area"], false), value: on?(c["sparkline_value"], false)] ++
        points ++ words(c)
    )
  end

  # Bars of y on the left axis; the line of y2, of its own units, on the right.
  defp build("combo", data, c) do
    bars = Fude.bar(cartesian(c))

    case present(c["y2_field"]) do
      nil ->
        Fude.layers(data, [bars], words(c))

      y2 ->
        line =
          [field: y2, axis: :right] ++
            title(present(c["y2_axis_title"])) ++
            format(c, "y2_number_format") ++ zero(c, "y2_axis_zero")

        Fude.layers(
          data,
          [bars, Fude.line([x: c["x_field"], y: line, points: true] ++ curve(c))],
          words(c)
        )
    end
  end

  defp build("kpi", data, c), do: Fude.number(data, single(c) ++ label(c) ++ words(c))

  # Compared with the comparison field of the first row, or, without one,
  # with the value of the second row.
  defp build("trend", data, c) do
    compare =
      case present(c["comparison_field"]) do
        nil -> []
        field -> [compare: field]
      end

    Fude.trend(data, single(c) ++ compare ++ label(c) ++ words(c))
  end

  defp build("gauge", data, c) do
    Fude.gauge(
      data,
      single(c) ++
        [min: number(c["min_value"], 0), max: number(c["max_value"], 100)] ++
        label(c) ++ words(c)
    )
  end

  defp build("progress", data, c) do
    Fude.progress(
      data,
      single(c) ++ [goal: number(c["goal_value"], 100)] ++ label(c) ++ words(c)
    )
  end

  defp build(_unknown, data, c), do: build("bar", data, c)

  # -- Options -----------------------------------------------------------------

  # A line across the chart at a value of y, with its words: a goal, a limit.
  @reference_types ~w(bar horizontal_bar line area scatter bubble combo)

  defp reference(chart, type, c) when type in @reference_types do
    case number(c["reference_value"], nil) do
      nil -> chart
      value -> Fude.annotate(chart, :line, y: value, text: present(c["reference_label"]))
    end
  end

  defp reference(chart, _type, _c), do: chart

  # Small multiples: the chart once for each value of a field, on the same
  # scales.
  @facet_types ~w(bar horizontal_bar line area scatter bubble)

  defp facet(chart, type, c) when type in @facet_types do
    case present(c["facet_field"]) do
      nil -> chart
      field -> Fude.facet(chart, field, columns: columns(c["facet_columns"]))
    end
  end

  defp facet(chart, _type, _c), do: chart

  # Callouts on the highest and the lowest value, each with its value: the
  # first thing a reader looks for. Not on stacked series, whose marks are
  # not at their values.
  @marks_types ~w(bar line area combo)

  defp marks(chart, type, data, c) when type in @marks_types do
    if stacked?(type, c) do
      chart
    else
      points = points(data, c["x_field"], c["y_field"])

      chart
      |> mark(
        on?(c["mark_max"], false),
        Enum.max_by(points, &elem(&1, 1), fn -> nil end),
        &gettext("Highest: %{value}", value: &1)
      )
      |> mark(
        on?(c["mark_min"], false),
        Enum.min_by(points, &elem(&1, 1), fn -> nil end),
        &gettext("Lowest: %{value}", value: &1)
      )
    end
  end

  defp marks(chart, _type, _data, _c), do: chart

  defp mark(chart, true, {x, y}, text),
    do: Fude.annotate(chart, :label, x: x, y: y, text: text.(short(y)))

  defp mark(chart, _on, _point, _text), do: chart

  defp stacked?("area", c), do: present(c["series_field"]) != nil and c["stack"] != "grouped"

  defp stacked?(type, c) when type in ~w(bar combo),
    do: present(c["series_field"]) != nil and c["stack"] != "grouped"

  defp stacked?(_type, _c), do: false

  # The rows' x and y, where y is a number.
  defp points(%{columns: columns, rows: rows}, x, y) do
    with xi when is_integer(xi) <- Enum.find_index(columns, &(&1 == x)),
         yi when is_integer(yi) <- Enum.find_index(columns, &(&1 == y)) do
      for row <- rows, value = to_number(Enum.at(row, yi)), is_number(value) do
        {Enum.at(row, xi), value}
      end
    else
      _ -> []
    end
  end

  defp to_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_number(value) when is_number(value), do: value
  defp to_number(_value), do: nil

  # A number in a few characters, for a callout: 411.2K, 6.9M, 72.4.
  defp short(value) do
    {scaled, suffix} =
      cond do
        abs(value) >= 1.0e9 -> {value / 1.0e9, "B"}
        abs(value) >= 1.0e6 -> {value / 1.0e6, "M"}
        abs(value) >= 1.0e4 -> {value / 1.0e3, "K"}
        true -> {value, ""}
      end

    rounded = Float.round(scaled * 1.0, 1)

    text =
      if rounded == trunc(rounded),
        do: Integer.to_string(trunc(rounded)),
        else: Float.to_string(rounded)

    text <> suffix
  end

  # A shaded range of x, with its words: a campaign, a holiday, an outage.
  # The range is written as x's values are: dates as 2026-03-01, numbers as
  # numbers, categories by name.
  @band_types ~w(bar line area combo scatter bubble)

  defp band(chart, type, data, c) when type in @band_types do
    with from when not is_nil(from) <- present(c["band_from"]),
         to when not is_nil(to) <- present(c["band_to"]) do
      kind = x_kind(data, c["x_field"])

      Fude.annotate(chart, :band,
        x: {place(from, kind), place(to, kind)},
        text: present(c["band_label"])
      )
    else
      _ -> chart
    end
  end

  defp band(chart, _type, _data, _c), do: chart

  defp x_kind(%{columns: columns, rows: rows}, x) do
    case Enum.find_index(columns, &(&1 == x)) do
      nil ->
        :text

      index ->
        rows
        |> Enum.map(&Enum.at(&1, index))
        |> Enum.find(&(not is_nil(&1)))
        |> case do
          value when is_number(value) -> :number
          %Decimal{} -> :number
          _ -> :text
        end
    end
  end

  defp place(value, :number), do: number(value, value)
  defp place(value, :text), do: String.trim(value)

  # The tooltip's fields beyond the chart's, and what it adds from the
  # series: the change from the point before, the share of the stack or of
  # the total, the rank, and a small history.
  defp tooltip(c) do
    fields = c["tooltip_fields"] |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

    adds =
      c["tooltip_adds"]
      |> List.wrap()
      |> Enum.flat_map(fn
        "change" -> [change: true]
        "share" -> [share: true]
        "rank" -> [rank: true]
        "history" -> [history: true]
        _ -> []
      end)

    case fields ++ adds do
      [] -> []
      tooltip -> [tooltip: tooltip]
    end
  end

  defp map_name(%{"map" => "us-states"}), do: "us-states"
  defp map_name(_c), do: "world"

  defp columns(value) do
    case number(value, nil) do
      n when is_number(n) and n >= 1 -> min(trunc(n), 6)
      _ -> nil
    end
  end

  # The chart's words around it (how it is measured, and where it comes
  # from), and whether it moves when its data changes.
  defp words(c) do
    words =
      Enum.flat_map([subtitle: "subtitle", source: "source"], fn {key, name} ->
        case present(c[name]) do
          nil -> []
          text -> [{key, text}]
        end
      end)

    if on?(c["animate"], true), do: words, else: words ++ [animate: false]
  end

  defp labels(c) do
    [labels: on?(c["show_values"], show_values_default?(c["chart_type"]))]
  end

  defp curve(c), do: if(on?(c["smooth"], false), do: [curve: :monotone], else: [])

  # The measure's format, from the config: Fude's own when there is none.
  # The decimals go with the values' format (not the combo line's).
  defp format(c, "number_format" = key), do: base_format(c, key) ++ digits(c["decimals"])
  defp format(c, key), do: base_format(c, key)

  defp digits(value) do
    case number(value, nil) do
      n when is_number(n) and n >= 0 and n <= 6 -> [digits: trunc(n)]
      _ -> []
    end
  end

  defp base_format(c, key) do
    case present(c[key]) do
      "number" ->
        [format: :number]

      "integer" ->
        [format: :integer]

      "compact" ->
        [format: :compact]

      "percent" ->
        [format: :percent]

      "currency" ->
        currency(c["currency"])

      _ ->
        []
    end
  end

  defp currency(code) when is_binary(code) do
    code = code |> String.trim() |> String.upcase()
    if code =~ ~r/^[A-Z]{3}$/, do: [format: {:currency, code}], else: []
  end

  defp currency(_code), do: []

  defp zero(c, key), do: if(on?(c[key], false), do: [scale: [zero: true]], else: [])

  defp on?(value, _default) when value in [true, "true"], do: true
  defp on?(value, _default) when value in [false, "false"], do: false
  defp on?(_value, default), do: default

  # -- Channels ----------------------------------------------------------------

  # x, y and the series, with the axes' titles and the measure's format.
  defp cartesian(c) do
    y = axis(c, "y_field", :y) ++ format(c, "number_format") ++ zero(c, "y_axis_zero")
    [x: axis(c, "x_field", :x), y: y] ++ color(c, c["series_field"])
  end

  # Bars: sorted and stacked as the config says, their values on them or not.
  defp bars(c) do
    [x: x, y: y] ++ rest = cartesian(c)
    [x: x ++ sort(c["sort"]), y: y ++ stack(c)] ++ rest ++ labels(c)
  end

  defp sort("value_desc"), do: [sort: :"-y"]
  defp sort("value_asc"), do: [sort: :y]
  defp sort("label"), do: [sort: :ascending]
  defp sort(_query_order), do: []

  # Bars and areas of several series: stacked (Fude's default), side by side
  # (overlapping, for areas) or to 100%.
  defp stack(%{"series_field" => series} = c) when series not in [nil, ""] do
    case c["stack"] do
      "grouped" -> [stack: false]
      "normalized" -> [stack: :normalize]
      _ -> []
    end
  end

  defp stack(_c), do: []

  # A field on an axis: its own title, none when its label is hidden, else
  # Fude's: the field's name in words ("total_revenue" is "Total revenue").
  # A title that is the field's name, as the settings used to fill in, is
  # the field's name too.
  defp axis(c, key, axis) do
    field = c[key]

    cond do
      c["#{axis}_axis_show_label"] in [false, "false"] ->
        [field: field, title: false]

      present(c["#{axis}_axis_title"]) not in [nil, field] ->
        [field: field, title: c["#{axis}_axis_title"]]

      true ->
        [field: field]
    end
  end

  # A measure with no axis (a funnel's, a sparkline's): its format.
  defp measure(c, field), do: [field: field] ++ format(c, "number_format")

  defp single(c), do: [value: measure(c, c["value_field"])]

  # A slice of a pie or a donut for each category: the series field when
  # there is one, else the x field.
  defp slices(c) do
    category = present(c["series_field"]) || c["x_field"]
    [value: measure(c, c["y_field"])] ++ color(c, category)
  end

  # The series' color, by the config's scheme: Fude's own, or one that is
  # told apart by people with colour vision deficiencies too.
  defp color(c, field) do
    case present(field) do
      nil ->
        []

      field ->
        case c["color_scheme"] do
          "okabe_ito" -> [color: [field: field, scheme: :okabe_ito]]
          _ -> [color: field]
        end
    end
  end

  # A value's colors: a sequential ramp, or one that diverges through a
  # neutral at `scheme_mid` (0 unless given).
  @sequential %{
    "blue" => :blue,
    "green" => :green,
    "orange" => :orange,
    "purple" => :purple,
    "gray" => :gray,
    "viridis" => :viridis
  }
  @diverging %{"red_blue" => :red_blue, "red_green" => :red_green}

  defp value_scheme(c) do
    name = c["color_scheme"]

    cond do
      scheme = @sequential[name] ->
        [scheme: scheme]

      scheme = @diverging[name] ->
        case number(c["scheme_mid"], nil) do
          nil -> [scheme: scheme]
          mid -> [scheme: scheme, mid: mid]
        end

      true ->
        []
    end
  end

  defp size(c) do
    case present(c["size_field"]) do
      nil -> []
      field -> [size: field]
    end
  end

  defp title(nil), do: []
  defp title(title), do: [title: title]

  # The label under a single value: the config's, else the field's name.
  defp label(c), do: [label: present(c["kpi_label"]) || c["value_field"] || ""]

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  @max_bins 100
  defp bin_count(val) when is_integer(val) and val > 0, do: min(val, @max_bins)

  defp bin_count(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> min(n, @max_bins)
      _ -> 10
    end
  end

  defp bin_count(_), do: 10

  defp number(val, _default) when is_number(val), do: val

  defp number(val, default) when is_binary(val) do
    case Float.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp number(_, default), do: default

  # -- Data --------------------------------------------------------------------

  # The result's rows, each value as Fude reads it: numbers, decimals, dates
  # and times as they are, so that they scale and sort by their type; the
  # rest (UUIDs, JSON, arrays, booleans) as Lotus writes them.
  defp data(%{columns: columns, rows: rows}) do
    %{columns: columns, rows: Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)}
  end

  defp cell(value) when is_nil(value) or is_number(value), do: value
  defp cell(%Decimal{} = value), do: value
  defp cell(%Date{} = value), do: value
  defp cell(%DateTime{} = value), do: value
  defp cell(%NaiveDateTime{} = value), do: value

  defp cell(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Lotus.Value.to_display_string(value)
  end

  defp cell(value), do: Lotus.Value.to_display_string(value)
end
