defmodule Lotus.Web.Queries.VisualizationSettingsComponent do
  @moduledoc """
  A drawer component for configuring result visualizations.
  Slides in from the left side.
  """
  use Lotus.Web, :live_component

  alias Lotus.Web.VegaSpecBuilder

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "fixed sm:absolute top-0 left-0 h-full w-full sm:w-80 bg-white dark:bg-gray-800 border-r-0 sm:border-r border-gray-200 dark:border-gray-700 z-20 transition-transform duration-300 ease-in-out overflow-hidden",
        if(@visible, do: "translate-x-0", else: "-translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= if @visible do %>
        <div class="h-full flex flex-col">
          <.header parent={@parent} drawer_tab={@drawer_tab} config={@config} />
          <div class="flex-1 overflow-y-auto">
            <%= case @drawer_tab do %>
              <% :types -> %>
                <.chart_type_grid parent={@parent} config={@config} />
              <% :config -> %>
                <.config_panel parent={@parent} config={@config} columns={@columns} />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:drawer_tab, :atom, required: true)
  attr(:config, :map, default: nil)

  defp header(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-medium text-text-light dark:text-text-dark"><%= gettext("Visualization") %></h3>
        <button
          type="button"
          phx-click="close_visualization_settings"
          phx-target={@parent}
          class="p-1 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
        >
          <Icons.x_mark class="h-4 w-4" />
        </button>
      </div>

      <%!-- Tab switcher --%>
      <div class="flex mt-3 border-b border-gray-200 dark:border-gray-600">
        <button
          type="button"
          phx-click="switch_visualization_tab"
          phx-value-tab="types"
          phx-target={@parent}
          class={[
            "px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
            if(@drawer_tab == :types,
              do: "border-pink-500 text-pink-600 dark:text-pink-400",
              else: "border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
            )
          ]}
        >
          <%= gettext("Chart Type") %>
        </button>
        <button
          type="button"
          phx-click="switch_visualization_tab"
          phx-value-tab="config"
          phx-target={@parent}
          disabled={@config == nil}
          class={[
            "px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
            if(@drawer_tab == :config,
              do: "border-pink-500 text-pink-600 dark:text-pink-400",
              else: "border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
            ),
            if(@config == nil, do: "opacity-50 cursor-not-allowed")
          ]}
        >
          <%= gettext("Configure") %>
        </button>
      </div>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:config, :map, default: nil)

  defp chart_type_grid(assigns) do
    selected_type = get_chart_type(assigns.config)
    assigns = assign(assigns, :selected_type, selected_type)

    ~H"""
    <div class="p-4">
      <p class="text-xs text-gray-500 dark:text-gray-400 mb-4">
        <%= gettext("Choose a chart type to visualize your data.") %>
      </p>
      <div :for={{group_label, types} <- VegaSpecBuilder.chart_type_groups()} class="mb-4">
        <h4 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
          <%= group_label %>
        </h4>
        <div class="grid grid-cols-3 gap-2">
          <.chart_type_option
            :for={type <- types}
            type={type}
            label={chart_type_label(type)}
            parent={@parent}
            selected={@selected_type == type}
          />
        </div>
      </div>
    </div>
    """
  end

  defp get_chart_type(nil), do: nil
  defp get_chart_type(config), do: Map.get(config, "chart_type")

  attr(:type, :string, required: true)
  attr(:label, :string, required: true)
  attr(:parent, :any, required: true)
  attr(:selected, :boolean, default: false)

  defp chart_type_option(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="select_chart_type"
      phx-value-type={@type}
      phx-target={@parent}
      class={[
        "flex flex-col items-center justify-center p-3 border rounded-lg transition-colors",
        if(@selected,
          do: "border-pink-500 bg-pink-50 dark:bg-pink-900/20",
          else: "border-gray-200 dark:border-gray-600 hover:border-pink-300 dark:hover:border-pink-600 hover:bg-pink-50 dark:hover:bg-pink-900/20"
        )
      ]}
    >
      <.chart_icon type={@type} selected={@selected} />
      <span class={[
        "text-xs mt-1",
        if(@selected, do: "text-pink-600 dark:text-pink-400 font-medium", else: "text-gray-600 dark:text-gray-400")
      ]}><%= @label %></span>
    </button>
    """
  end

  attr(:type, :string, required: true)
  attr(:selected, :boolean, default: false)

  defp chart_icon(%{type: "bar"} = assigns) do
    ~H"""
    <Icons.chart_bar class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "horizontal_bar"} = assigns) do
    ~H"""
    <Icons.chart_horizontal_bar class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "line"} = assigns) do
    ~H"""
    <Icons.chart_line class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "area"} = assigns) do
    ~H"""
    <Icons.chart_area class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "scatter"} = assigns) do
    ~H"""
    <Icons.chart_scatter class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "bubble"} = assigns) do
    ~H"""
    <Icons.chart_bubble class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "pie"} = assigns) do
    ~H"""
    <Icons.chart_pie class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "donut"} = assigns) do
    ~H"""
    <Icons.chart_donut class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "funnel"} = assigns) do
    ~H"""
    <Icons.chart_funnel class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "waterfall"} = assigns) do
    ~H"""
    <Icons.chart_waterfall class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "heatmap"} = assigns) do
    ~H"""
    <Icons.chart_heatmap class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "histogram"} = assigns) do
    ~H"""
    <Icons.chart_histogram class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "kpi"} = assigns) do
    ~H"""
    <Icons.chart_kpi class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "trend"} = assigns) do
    ~H"""
    <Icons.chart_trend class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "gauge"} = assigns) do
    ~H"""
    <Icons.chart_gauge class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "progress"} = assigns) do
    ~H"""
    <Icons.chart_progress class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "combo"} = assigns) do
    ~H"""
    <Icons.chart_combined class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(%{type: "sparkline"} = assigns) do
    ~H"""
    <Icons.chart_sparkline class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp chart_icon(assigns) do
    ~H"""
    <Icons.chart_bar class={["h-6 w-6 mb-1", icon_color(@selected)]} />
    """
  end

  defp icon_color(true), do: "text-pink-500 dark:text-pink-400"
  defp icon_color(false), do: "text-gray-400 dark:text-gray-500"

  attr(:parent, :any, required: true)
  attr(:config, :map, default: nil)
  attr(:columns, :list, default: [])

  defp config_panel(assigns) do
    chart_type = get_chart_type(assigns.config)
    assigns = assign(assigns, :chart_type, chart_type)

    ~H"""
    <div class="p-4 space-y-4">
      <%!-- Current chart type indicator --%>
      <%= if @config do %>
        <div class="flex items-center justify-between p-2 bg-gray-50 dark:bg-gray-700/50 rounded-md">
          <div class="flex items-center gap-2">
            <.chart_icon type={@config["chart_type"] || "bar"} selected={true} />
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300 capitalize">
              <%= chart_type_label(@config["chart_type"]) %>
            </span>
          </div>
          <button
            type="button"
            phx-click="switch_visualization_tab"
            phx-value-tab="types"
            phx-target={@parent}
            class="text-xs text-pink-600 dark:text-pink-400 hover:text-pink-700 dark:hover:text-pink-300"
          >
            <%= gettext("Change") %>
          </button>
        </div>
      <% end %>

      <%!-- Field selectors wrapped in form --%>
      <form id="visualization-settings-form" phx-change="update_visualization_config" phx-target={@parent}>
        <div class="space-y-4">
          <%= case @chart_type do %>
            <% "kpi" -> %>
              <.kpi_fields config={@config} columns={@columns} />
            <% "gauge" -> %>
              <.gauge_fields config={@config} columns={@columns} />
            <% "progress" -> %>
              <.progress_fields config={@config} columns={@columns} />
            <% "trend" -> %>
              <.trend_fields config={@config} columns={@columns} />
            <% "combo" -> %>
              <.combo_fields config={@config} columns={@columns} />
            <% "histogram" -> %>
              <.histogram_fields config={@config} columns={@columns} />
            <% "heatmap" -> %>
              <.heatmap_fields config={@config} columns={@columns} />
            <% _ -> %>
              <.standard_fields config={@config} columns={@columns} chart_type={@chart_type} />
          <% end %>
        </div>
      </form>

      <%!-- Config preview --%>
      <.config_status config={@config} chart_type={@chart_type} />
    </div>
    """
  end

  defp chart_type_label(type), do: VegaSpecBuilder.chart_type_label(type)

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp kpi_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Value Field") %>
      </label>
      <select
        name="value_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["value_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The numeric field to display as a big number") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <input
        type="text"
        name="kpi_label"
        value={@config && @config["kpi_label"]}
        placeholder={gettext("e.g. Total Orders")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Custom text displayed below the number") %>
      </p>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp gauge_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Value Field") %>
      </label>
      <select
        name="value_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["value_field"] == col}><%= col %></option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <input
        type="text"
        name="kpi_label"
        value={@config && @config["kpi_label"]}
        placeholder={gettext("e.g. Completion Rate")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    <div class="grid grid-cols-2 gap-3">
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          <%= gettext("Min Value") %>
        </label>
        <input
          type="number"
          name="min_value"
          value={Map.get(@config || %{}, "min_value", "0")}
          class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
        />
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          <%= gettext("Max Value") %>
        </label>
        <input
          type="number"
          name="max_value"
          value={Map.get(@config || %{}, "max_value", "100")}
          class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
        />
      </div>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp progress_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Value Field") %>
      </label>
      <select
        name="value_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["value_field"] == col}><%= col %></option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <input
        type="text"
        name="kpi_label"
        value={@config && @config["kpi_label"]}
        placeholder={gettext("e.g. Quota")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Goal Value") %>
      </label>
      <input
        type="number"
        name="goal_value"
        value={Map.get(@config || %{}, "goal_value", "100")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Target value (100%% mark)") %>
      </p>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp trend_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Value Field") %>
      </label>
      <select
        name="value_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["value_field"] == col}><%= col %></option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <input
        type="text"
        name="kpi_label"
        value={@config && @config["kpi_label"]}
        placeholder={gettext("e.g. Revenue")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Comparison Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <select
        name="comparison_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Use previous row") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["comparison_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Field to compare against for trend calculation") %>
      </p>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp combo_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("X-Axis Field") %>
      </label>
      <select
        name="x_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["x_field"] == col}><%= col %></option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Bar Series (Y-Axis)") %>
      </label>
      <select
        name="y_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["y_field"] == col}><%= col %></option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Line Series") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <select
        name="y2_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("None") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["y2_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Second field rendered as a line on the right Y-axis") %>
      </p>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Right Y-Axis Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <input
        type="text"
        name="y2_axis_title"
        value={@config && @config["y2_axis_title"]}
        placeholder={gettext("e.g. Revenue")}
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp histogram_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Data Field") %>
      </label>
      <select
        name="x_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["x_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The numeric field to compute frequency distribution for") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Number of Bins") %>
      </label>
      <input
        type="number"
        name="bin_count"
        value={Map.get(@config || %{}, "bin_count", "10")}
        min="2"
        max="100"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      />
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Maximum number of bins for the distribution (default: 10)") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Color/Series Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <select
        name="series_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("None") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["series_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Group data by this field using different colors") %>
      </p>
    </div>

    <%!-- Axis display options --%>
    <.axis_display_options config={@config} />
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)

  defp heatmap_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Column Field") %>
      </label>
      <select
        name="x_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["x_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The categorical field for columns (X-axis)") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Row Field") %>
      </label>
      <select
        name="y_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["y_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The categorical field for rows (Y-axis)") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Value Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <select
        name="series_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("None (use Row Field)") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["series_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The numeric field for color intensity") %>
      </p>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:columns, :list, required: true)
  attr(:chart_type, :string, default: nil)

  defp standard_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("X-Axis Field") %>
      </label>
      <select
        name="x_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["x_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The field to use for the horizontal axis") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Y-Axis Field") %>
      </label>
      <select
        name="y_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Select field...") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["y_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("The field to use for the vertical axis (should be numeric)") %>
      </p>
    </div>

    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Color/Series Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
      </label>
      <select
        name="series_field"
        class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("None") %></option>
        <%= for col <- @columns do %>
          <option value={col} selected={@config && @config["series_field"] == col}><%= col %></option>
        <% end %>
      </select>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Group data by this field using different colors") %>
      </p>
    </div>

    <%!-- Bubble size field --%>
    <%= if @chart_type == "bubble" do %>
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          <%= gettext("Size Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
        </label>
        <select
          name="size_field"
          class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
        >
          <option value=""><%= gettext("None") %></option>
          <%= for col <- @columns do %>
            <option value={col} selected={@config && @config["size_field"] == col}><%= col %></option>
          <% end %>
        </select>
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          <%= gettext("Numeric field to control bubble size") %>
        </p>
      </div>
    <% end %>

    <%!-- Axis display options (only for cartesian charts) --%>
    <%= if @config && @chart_type in ~w(bar line area scatter horizontal_bar bubble) do %>
      <.axis_display_options config={@config} />
    <% end %>
    """
  end

  attr(:config, :map, required: true)

  defp axis_display_options(assigns) do
    ~H"""
    <div class="pt-4 border-t border-gray-200 dark:border-gray-600">
      <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
        <%= gettext("Axis Display") %>
      </h4>

      <%!-- X-Axis options --%>
      <div class="mb-4 p-3 bg-gray-50 dark:bg-gray-700/50 rounded-md">
        <span class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          <%= gettext("X-Axis") %>
        </span>
        <div class="mt-2 space-y-2">
          <div class="flex items-center justify-between">
            <label for="x_axis_show_label" class="text-sm text-gray-700 dark:text-gray-300">
              <%= gettext("Show label") %>
            </label>
            <label class="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                name="x_axis_show_label"
                id="x_axis_show_label"
                value="true"
                checked={Map.get(@config, "x_axis_show_label", true)}
                class="sr-only peer"
              />
              <div class="w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-pink-300 dark:peer-focus:ring-pink-800 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all dark:border-gray-500 peer-checked:bg-pink-500"></div>
            </label>
          </div>
          <div>
            <label for="x_axis_title" class="block text-sm text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Label") %>
            </label>
            <input
              type="text"
              name="x_axis_title"
              id="x_axis_title"
              value={Map.get(@config, "x_axis_title", @config["x_field"] || "")}
              placeholder={@config["x_field"] || gettext("Enter label...")}
              class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
        </div>
      </div>

      <%!-- Y-Axis options --%>
      <div class="p-3 bg-gray-50 dark:bg-gray-700/50 rounded-md">
        <span class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          <%= gettext("Y-Axis") %>
        </span>
        <div class="mt-2 space-y-2">
          <div class="flex items-center justify-between">
            <label for="y_axis_show_label" class="text-sm text-gray-700 dark:text-gray-300">
              <%= gettext("Show label") %>
            </label>
            <label class="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                name="y_axis_show_label"
                id="y_axis_show_label"
                value="true"
                checked={Map.get(@config, "y_axis_show_label", true)}
                class="sr-only peer"
              />
              <div class="w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-pink-300 dark:peer-focus:ring-pink-800 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all dark:border-gray-500 peer-checked:bg-pink-500"></div>
            </label>
          </div>
          <div>
            <label for="y_axis_title" class="block text-sm text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Label") %>
            </label>
            <input
              type="text"
              name="y_axis_title"
              id="y_axis_title"
              value={Map.get(@config, "y_axis_title", @config["y_field"] || "")}
              placeholder={@config["y_field"] || gettext("Enter label...")}
              class="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:config, :map, required: true)
  attr(:chart_type, :string, default: nil)

  defp config_status(assigns) do
    configured = VegaSpecBuilder.valid_config?(assigns.config)
    assigns = assign(assigns, :configured, configured)

    ~H"""
    <%= if @configured do %>
      <div class="mt-6 p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-md">
        <div class="flex items-center gap-2">
          <Icons.check class="h-4 w-4 text-green-600 dark:text-green-400" />
          <span class="text-sm font-medium text-green-700 dark:text-green-400">
            <%= gettext("Visualization configured") %>
          </span>
        </div>
        <p class="mt-1 text-xs text-green-600 dark:text-green-500">
          <%= gettext("Use the chart icon in the bottom bar to view.") %>
        </p>
      </div>
    <% else %>
      <div class="mt-6 p-3 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-md">
        <div class="flex items-center gap-2">
          <Icons.exclamation_triangle class="h-4 w-4 text-amber-600 dark:text-amber-400" />
          <span class="text-sm font-medium text-amber-700 dark:text-amber-400">
            <%= gettext("Configuration incomplete") %>
          </span>
        </div>
        <p class="mt-1 text-xs text-amber-600 dark:text-amber-500">
          <%= config_incomplete_hint(@chart_type) %>
        </p>
      </div>
    <% end %>
    """
  end

  defp config_incomplete_hint("kpi"), do: gettext("Select a Value Field to display the KPI card.")
  defp config_incomplete_hint("gauge"), do: gettext("Select a Value Field to display the gauge.")

  defp config_incomplete_hint("progress"),
    do: gettext("Select a Value Field to display the progress bar.")

  defp config_incomplete_hint("trend"), do: gettext("Select a Value Field to display the trend.")

  defp config_incomplete_hint("histogram"),
    do: gettext("Select a Data Field to show the histogram.")

  defp config_incomplete_hint("heatmap"),
    do: gettext("Select Column and Row fields to enable the heatmap.")

  defp config_incomplete_hint(_),
    do: gettext("Select both X-Axis and Y-Axis fields to enable the chart view.")

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       visible: false,
       drawer_tab: :types,
       config: nil,
       columns: []
     )}
  end

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    {:ok, assign(socket, params)}
  end
end
