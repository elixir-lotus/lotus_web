defmodule Lotus.Web.Queries.ChartOptions do
  @moduledoc false
  # The options of a chart, beyond its fields: how its numbers read, its
  # values on the marks, stacking and order, a reference line, small
  # multiples, and its words. The query editor's settings and a dashboard
  # card's settings both draw them, from `Lotus.Web.Charts.option_keys/1`:
  # a type shows the options it has, and nothing else.
  #
  # The inputs are named as the form around them names its fields: `name`
  # as it is, or `visualization[name]` with `prefix="visualization"`. A
  # switch sends "false" when off (a hidden input before it), so that
  # turning one off is a change the form reports.

  use Phoenix.Component
  use Gettext, backend: Lotus.Web.Gettext

  alias Lotus.Web.Charts

  @input "w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"

  attr(:config, :map, required: true)
  attr(:columns, :list, default: [])
  attr(:prefix, :string, default: nil)

  def options(assigns) do
    type = assigns.config["chart_type"]
    keys = Charts.option_keys(type)

    assigns =
      assign(assigns,
        type: type,
        keys: keys,
        input: @input,
        series?: (assigns.config["series_field"] || "") != ""
      )

    ~H"""
    <div :if={@keys != []} class="pt-4 space-y-5 border-t border-gray-200 dark:border-gray-600">
      <section :if={"number_format" in @keys} class="space-y-3">
        <.heading>{gettext("Numbers")}</.heading>
        <.number_format config={@config} prefix={@prefix} key="number_format" label={format_label(@type)} input={@input} />
        <.number_format
          :if={"y2_number_format" in @keys}
          config={@config}
          prefix={@prefix}
          key="y2_number_format"
          label={gettext("Line's format")}
          input={@input}
          currency={false}
        />
        <.choice
          :if={"decimals" in @keys}
          config={@config}
          prefix={@prefix}
          key="decimals"
          label={gettext("Decimals")}
          input={@input}
          options={[
            {"", gettext("Automatic")},
            {"0", "0"},
            {"1", "1"},
            {"2", "2"},
            {"3", "3"}
          ]}
        />
        <.switch
          :if={"show_values" in @keys}
          config={@config}
          prefix={@prefix}
          key="show_values"
          default={Charts.show_values_default?(@type)}
          label={gettext("Show values on the bars")}
        />
      </section>

      <section :if={"color_scheme" in @keys} class="space-y-3">
        <.heading>{gettext("Colors")}</.heading>
        <%= if "scheme_mid" in @keys do %>
          <div class="grid grid-cols-3 gap-2">
            <div class={if diverging?(@config["color_scheme"]), do: "col-span-2", else: "col-span-3"}>
              <.choice config={@config} prefix={@prefix} key="color_scheme" label={gettext("Scheme")} input={@input} options={value_schemes()} />
            </div>
            <div :if={diverging?(@config["color_scheme"])}>
              <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Neutral at")}</label>
              <input
                type="number"
                step="any"
                name={name(@prefix, "scheme_mid")}
                value={@config["scheme_mid"]}
                placeholder="0"
                class={@input}
              />
            </div>
          </div>
        <% else %>
          <.choice config={@config} prefix={@prefix} key="color_scheme" label={gettext("Scheme")} input={@input} options={series_schemes()} />
        <% end %>
      </section>

      <section :if={"funnel_colors" in @keys} class="space-y-3">
        <.heading>{gettext("Stages")}</.heading>
        <.choice
          config={@config}
          prefix={@prefix}
          key="funnel_colors"
          label={gettext("Colors")}
          input={@input}
          options={[
            {"", gettext("One color")},
            {"stages", gettext("A color for each stage")},
            {"steps", gettext("Lighter at each stage")}
          ]}
        />
        <.choice
          config={@config}
          prefix={@prefix}
          key="funnel_labels"
          label={gettext("Values")}
          input={@input}
          options={[
            {"", gettext("Beside the bars")},
            {"inside", gettext("In the bars")},
            {"none", gettext("None")}
          ]}
        />
      </section>

      <section :if={"sparkline_area" in @keys} class="space-y-3">
        <.heading>{gettext("Sparkline")}</.heading>
        <.switch config={@config} prefix={@prefix} key="sparkline_area" label={gettext("Fill under the line")} />
        <.choice
          config={@config}
          prefix={@prefix}
          key="sparkline_points"
          label={gettext("Dots")}
          input={@input}
          options={[
            {"", gettext("None")},
            {"last", gettext("On the last value")},
            {"extremes", gettext("On the last, lowest and highest")}
          ]}
        />
        <.switch config={@config} prefix={@prefix} key="sparkline_value" label={gettext("Write the last value")} />
      </section>

      <section :if={Enum.any?(~w(stack sort smooth y_axis_zero animate), &(&1 in @keys))} class="space-y-3">
        <.heading>{gettext("Layout")}</.heading>
        <.choice
          :if={"stack" in @keys and @series?}
          config={@config}
          prefix={@prefix}
          key="stack"
          label={gettext("Series")}
          input={@input}
          options={stack_options(@type)}
        />
        <.choice
          :if={"sort" in @keys}
          config={@config}
          prefix={@prefix}
          key="sort"
          label={gettext("Order")}
          input={@input}
          options={[
            {"query", gettext("As the query returns them")},
            {"value_desc", gettext("Largest first")},
            {"value_asc", gettext("Smallest first")},
            {"label", gettext("By name")}
          ]}
        />
        <.switch :if={"smooth" in @keys} config={@config} prefix={@prefix} key="smooth" label={gettext("Smooth lines")} />
        <.switch
          :if={"animate" in @keys}
          config={@config}
          prefix={@prefix}
          key="animate"
          default={true}
          label={gettext("Animate changes")}
        />
        <.switch
          :if={"y_axis_zero" in @keys}
          config={@config}
          prefix={@prefix}
          key="y_axis_zero"
          label={if @type == "combo", do: gettext("Start the bars' axis at zero"), else: gettext("Start the axis at zero")}
        />
        <.switch
          :if={"y2_axis_zero" in @keys}
          config={@config}
          prefix={@prefix}
          key="y2_axis_zero"
          label={gettext("Start the line's axis at zero")}
        />
      </section>

      <section :if={"tooltip_fields" in @keys and @columns != []} class="space-y-2">
        <.heading>{gettext("Tooltip")}</.heading>
        <p class="text-xs text-gray-500 dark:text-gray-400">{gettext("More fields to show on hover")}</p>
        <input type="hidden" name={name(@prefix, "tooltip_fields") <> "[]"} value="" />
        <div class="grid grid-cols-2 gap-x-3 gap-y-1">
          <label :for={col <- @columns} class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 min-w-0">
            <input
              type="checkbox"
              name={name(@prefix, "tooltip_fields") <> "[]"}
              value={col}
              checked={col in List.wrap(@config["tooltip_fields"])}
              class="rounded border-gray-300 dark:border-gray-600 text-pink-500 focus:ring-pink-500"
            />
            <span class="truncate">{col}</span>
          </label>
        </div>
        <div :if={"tooltip_adds" in @keys} class="pt-2 space-y-1">
          <p class="text-xs text-gray-500 dark:text-gray-400">{gettext("And from the series")}</p>
          <input type="hidden" name={name(@prefix, "tooltip_adds") <> "[]"} value="" />
          <label
            :for={{value, label} <- tooltip_adds()}
            class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300"
          >
            <input
              type="checkbox"
              name={name(@prefix, "tooltip_adds") <> "[]"}
              value={value}
              checked={value in List.wrap(@config["tooltip_adds"])}
              class="rounded border-gray-300 dark:border-gray-600 text-pink-500 focus:ring-pink-500"
            />
            <span>{label}</span>
          </label>
        </div>
      </section>

      <section :if={"mark_max" in @keys or "band_from" in @keys} class="space-y-3">
        <.heading>{gettext("Callouts")}</.heading>
        <.switch :if={"mark_max" in @keys} config={@config} prefix={@prefix} key="mark_max" label={gettext("Mark the highest value")} />
        <.switch :if={"mark_min" in @keys} config={@config} prefix={@prefix} key="mark_min" label={gettext("Mark the lowest value")} />
        <div :if={"band_from" in @keys} class="space-y-2">
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {gettext("Shade a range of the horizontal axis: dates as 2026-03-01, categories by name.")}
          </p>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("From")}</label>
              <input type="text" name={name(@prefix, "band_from")} value={@config["band_from"]} class={@input} />
            </div>
            <div>
              <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("To")}</label>
              <input type="text" name={name(@prefix, "band_to")} value={@config["band_to"]} class={@input} />
            </div>
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Label")}</label>
            <input
              type="text"
              name={name(@prefix, "band_label")}
              value={@config["band_label"]}
              placeholder={gettext("e.g. Holiday sale")}
              class={@input}
            />
          </div>
        </div>
      </section>

      <section :if={"reference_value" in @keys} class="space-y-3">
        <.heading>{gettext("Reference line")}</.heading>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("At")}</label>
            <input
              type="number"
              step="any"
              name={name(@prefix, "reference_value")}
              value={@config["reference_value"]}
              placeholder={gettext("e.g. 5000")}
              class={@input}
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Label")}</label>
            <input
              type="text"
              name={name(@prefix, "reference_label")}
              value={@config["reference_label"]}
              placeholder={gettext("e.g. Goal")}
              class={@input}
            />
          </div>
        </div>
      </section>

      <section :if={"facet_field" in @keys} class="space-y-3">
        <.heading>{gettext("Small multiples")}</.heading>
        <div class="grid grid-cols-3 gap-2">
          <div class="col-span-2">
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("A chart for each")}</label>
            <select name={name(@prefix, "facet_field")} class={@input}>
              <option value="">{gettext("None")}</option>
              <option :for={col <- @columns} value={col} selected={@config["facet_field"] == col}>{col}</option>
            </select>
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Columns")}</label>
            <input
              type="number"
              min="1"
              max="6"
              name={name(@prefix, "facet_columns")}
              value={@config["facet_columns"]}
              placeholder={gettext("Auto")}
              class={@input}
            />
          </div>
        </div>
      </section>

      <section :if={"subtitle" in @keys} class="space-y-3">
        <.heading>{gettext("Words")}</.heading>
        <div>
          <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Subtitle")}</label>
          <input
            type="text"
            name={name(@prefix, "subtitle")}
            value={@config["subtitle"]}
            placeholder={gettext("e.g. Monthly revenue by channel")}
            class={@input}
          />
        </div>
        <div>
          <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Source")}</label>
          <input
            type="text"
            name={name(@prefix, "source")}
            value={@config["source"]}
            placeholder={gettext("e.g. Billing, updated daily")}
            class={@input}
          />
        </div>
      </section>
    </div>
    """
  end

  slot(:inner_block, required: true)

  defp heading(assigns) do
    ~H"""
    <h4 class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
      {render_slot(@inner_block)}
    </h4>
    """
  end

  attr(:config, :map, required: true)
  attr(:prefix, :string, default: nil)
  attr(:key, :string, required: true)
  attr(:label, :string, required: true)
  attr(:input, :string, required: true)
  attr(:currency, :boolean, default: true)

  defp number_format(assigns) do
    assigns = assign(assigns, value: assigns.config[assigns.key] || "")

    ~H"""
    <div class="grid grid-cols-3 gap-2">
      <div class={if @value == "currency" and @currency, do: "col-span-2", else: "col-span-3"}>
        <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{@label}</label>
        <select name={name(@prefix, @key)} class={@input}>
          <option :for={{value, label} <- format_options(@currency)} value={value} selected={@value == value}>
            {label}
          </option>
        </select>
      </div>
      <div :if={@value == "currency" and @currency}>
        <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{gettext("Currency")}</label>
        <input
          type="text"
          maxlength="3"
          name={name(@prefix, "currency")}
          value={@config["currency"] || "USD"}
          placeholder="USD"
          class={[@input, "uppercase"]}
        />
      </div>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:prefix, :string, default: nil)
  attr(:key, :string, required: true)
  attr(:label, :string, required: true)
  attr(:input, :string, required: true)
  attr(:options, :list, required: true)

  defp choice(assigns) do
    ~H"""
    <div>
      <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">{@label}</label>
      <select name={name(@prefix, @key)} class={@input}>
        <option :for={{value, label} <- @options} value={value} selected={(@config[@key] || "") == value}>
          {label}
        </option>
      </select>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:prefix, :string, default: nil)
  attr(:key, :string, required: true)
  attr(:label, :string, required: true)
  attr(:default, :boolean, default: false)

  defp switch(assigns) do
    assigns =
      assign(assigns,
        id: "chart-option-#{assigns.prefix || "query"}-#{assigns.key}",
        checked: on?(assigns.config[assigns.key], assigns.default)
      )

    ~H"""
    <div class="flex items-center justify-between">
      <label for={@id} class="text-sm text-gray-700 dark:text-gray-300">{@label}</label>
      <label class="relative inline-flex items-center cursor-pointer">
        <input type="hidden" name={name(@prefix, @key)} value="false" />
        <input type="checkbox" id={@id} name={name(@prefix, @key)} value="true" checked={@checked} class="sr-only peer" />
        <div class="w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-pink-300 dark:peer-focus:ring-pink-800 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all dark:border-gray-500 peer-checked:bg-pink-500">
        </div>
      </label>
    </div>
    """
  end

  defp name(nil, key), do: key
  defp name(prefix, key), do: "#{prefix}[#{key}]"

  defp on?(value, _default) when value in [true, "true"], do: true
  defp on?(value, _default) when value in [false, "false"], do: false
  defp on?(_value, default), do: default

  defp format_label(type) when type in ~w(kpi trend gauge progress), do: gettext("Format")
  defp format_label("combo"), do: gettext("Bars' format")
  defp format_label(_type), do: gettext("Values' format")

  defp format_options(currency?) do
    [
      {"", gettext("Automatic")},
      {"number", gettext("Exact (1,234,567.8)")},
      {"integer", gettext("Whole (1,234,568)")},
      {"compact", gettext("Compact (1.2M)")},
      {"percent", gettext("Percent (0.42 → 42%)")}
    ] ++ if(currency?, do: [{"currency", gettext("Currency")}], else: [])
  end

  defp tooltip_adds do
    [
      {"change", gettext("Change from the point before")},
      {"share", gettext("Share of the stack or of the total")},
      {"rank", gettext("Rank")},
      {"history", gettext("A small history of the series")}
    ]
  end

  defp diverging?(scheme), do: scheme in ~w(red_blue red_green)

  defp value_schemes do
    [
      {"", gettext("Blue")},
      {"green", gettext("Green")},
      {"orange", gettext("Orange")},
      {"purple", gettext("Purple")},
      {"gray", gettext("Gray")},
      {"viridis", gettext("Viridis (many hues)")},
      {"red_blue", gettext("Red to blue, through a neutral")},
      {"red_green", gettext("Red to green, through a neutral")}
    ]
  end

  defp series_schemes do
    [
      {"", gettext("Default")},
      {"okabe_ito", gettext("Colorblind-safe (Okabe–Ito)")}
    ]
  end

  defp stack_options("area") do
    [
      {"stacked", gettext("Stacked")},
      {"grouped", gettext("Overlapping")},
      {"normalized", gettext("Stacked to 100%")}
    ]
  end

  defp stack_options(_bars) do
    [
      {"stacked", gettext("Stacked")},
      {"grouped", gettext("Side by side")},
      {"normalized", gettext("Stacked to 100%")}
    ]
  end
end
