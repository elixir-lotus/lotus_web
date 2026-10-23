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
        "goal_value" => number (progress)
      }
  """

  use Phoenix.Component
  use Gettext, backend: Lotus.Web.Gettext

  @chart_type_ids ~w(bar horizontal_bar line area combo scatter bubble histogram heatmap pie donut funnel waterfall kpi trend gauge progress sparkline)

  @doc "Returns the ordered list of chart type ID strings."
  def chart_type_ids, do: @chart_type_ids

  @doc "Returns chart types organized into display groups for the UI grid."
  def chart_type_groups do
    [
      {gettext("Charts"), ~w(bar horizontal_bar line area combo)},
      {gettext("Distribution"), ~w(scatter bubble histogram heatmap)},
      {gettext("Part of whole"), ~w(pie donut funnel waterfall)},
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
        val -> Map.put(acc, key, val)
      end
    end)
  end

  defp config_fields("kpi"), do: ~w(value_field kpi_label)
  defp config_fields("gauge"), do: ~w(value_field kpi_label min_value max_value)
  defp config_fields("progress"), do: ~w(value_field kpi_label goal_value)
  defp config_fields("trend"), do: ~w(value_field kpi_label comparison_field)
  defp config_fields("histogram"), do: ~w(x_field bin_count series_field)
  defp config_fields("bubble"), do: ~w(x_field y_field series_field size_field)
  defp config_fields("combo"), do: ~w(x_field y_field y2_field series_field y2_axis_title)
  defp config_fields(_), do: ~w(x_field y_field series_field)

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
    build(type, data(result), config)
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

  defp build("bar", data, c), do: Fude.bar(data, cartesian(c))
  defp build("horizontal_bar", data, c), do: Fude.bar(data, cartesian(c) ++ [horizontal: true])
  defp build("line", data, c), do: Fude.line(data, cartesian(c) ++ [points: true])
  defp build("area", data, c), do: Fude.area(data, cartesian(c))
  defp build("scatter", data, c), do: Fude.scatter(data, cartesian(c) ++ size(c))

  # A bubble without a size field is a scatter: the size is what makes it one.
  defp build("bubble", data, c) do
    case size(c) do
      [] -> Fude.scatter(data, cartesian(c))
      size -> Fude.bubble(data, cartesian(c) ++ size)
    end
  end

  defp build("histogram", data, c) do
    Fude.histogram(
      data,
      [x: axis(c, "x_field", :x), bins: bin_count(c["bin_count"])] ++ color(c["series_field"])
    )
  end

  # The value field (stored as series_field) colors the cells; without one,
  # each cell is colored by how many rows it has.
  defp build("heatmap", data, c) do
    color =
      case present(c["series_field"]) do
        nil -> {:count, c["x_field"]}
        field -> field
      end

    Fude.heatmap(data, x: axis(c, "x_field", :x), y: axis(c, "y_field", :y), color: color)
  end

  defp build("pie", data, c), do: Fude.pie(data, slices(c))
  defp build("donut", data, c), do: Fude.donut(data, slices(c))

  defp build("funnel", data, c), do: Fude.funnel(data, x: c["x_field"], y: c["y_field"])

  defp build("waterfall", data, c),
    do: Fude.waterfall(data, x: axis(c, "x_field", :x), y: axis(c, "y_field", :y))

  defp build("sparkline", data, c), do: Fude.sparkline(data, x: c["x_field"], y: c["y_field"])

  # Bars of y on the left axis; the line of y2, of its own units, on the right.
  defp build("combo", data, c) do
    bars = Fude.bar(cartesian(c))

    case present(c["y2_field"]) do
      nil ->
        Fude.layers(data, [bars])

      y2 ->
        line = [field: y2, axis: :right] ++ title(present(c["y2_axis_title"]))
        Fude.layers(data, [bars, Fude.line(x: c["x_field"], y: line, points: true)])
    end
  end

  defp build("kpi", data, c), do: Fude.number(data, [value: c["value_field"]] ++ label(c))

  # Compared with the comparison field of the first row, or, without one,
  # with the value of the second row.
  defp build("trend", data, c) do
    compare =
      case present(c["comparison_field"]) do
        nil -> []
        field -> [compare: field]
      end

    Fude.trend(data, [value: c["value_field"]] ++ compare ++ label(c))
  end

  defp build("gauge", data, c) do
    Fude.gauge(
      data,
      [
        value: c["value_field"],
        min: number(c["min_value"], 0),
        max: number(c["max_value"], 100)
      ] ++ label(c)
    )
  end

  defp build("progress", data, c) do
    Fude.progress(data, [value: c["value_field"], goal: number(c["goal_value"], 100)] ++ label(c))
  end

  defp build(_unknown, data, c), do: build("bar", data, c)

  # -- Channels ----------------------------------------------------------------

  # x, y and the series, with the axes' titles of the config.
  defp cartesian(c) do
    [x: axis(c, "x_field", :x), y: axis(c, "y_field", :y)] ++ color(c["series_field"])
  end

  # A field on an axis: its own title, none when its label is hidden, else
  # the field's name (as Lotus has always shown it, not in words).
  defp axis(c, key, axis) do
    field = c[key]

    title =
      cond do
        c["#{axis}_axis_show_label"] == false -> false
        present(c["#{axis}_axis_title"]) -> c["#{axis}_axis_title"]
        true -> field
      end

    [field: field, title: title]
  end

  # A slice of a pie or a donut for each category: the series field when
  # there is one, else the x field.
  defp slices(c), do: [value: c["y_field"], color: present(c["series_field"]) || c["x_field"]]

  defp color(field) do
    case present(field) do
      nil -> []
      field -> [color: field]
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
