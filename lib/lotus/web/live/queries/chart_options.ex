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
        <.switch
          :if={"show_values" in @keys}
          config={@config}
          prefix={@prefix}
          key="show_values"
          default={Charts.show_values_default?(@type)}
          label={gettext("Show values on the bars")}
        />
      </section>

      <section :if={Enum.any?(~w(stack sort smooth y_axis_zero), &(&1 in @keys))} class="space-y-3">
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
