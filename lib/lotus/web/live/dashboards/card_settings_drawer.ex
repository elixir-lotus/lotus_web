defmodule Lotus.Web.Dashboards.CardSettingsDrawer do
  @moduledoc """
  Drawer component for configuring individual dashboard cards.
  Slides in from the right side.
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.VegaSpecBuilder

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       visible: false,
       card: nil,
       filters: [],
       available_columns: []
     )}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "fixed sm:absolute top-0 right-0 h-full w-full sm:w-80 bg-white dark:bg-gray-800 border-l border-gray-200 dark:border-gray-700 z-20 transition-transform duration-300 ease-in-out overflow-hidden",
        if(@visible, do: "translate-x-0", else: "translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= if @visible && @card do %>
        <div class="h-full flex flex-col">
          <.header card={@card} parent={@parent} />
          <div class="flex-1 overflow-y-auto p-4 space-y-6">
            <.title_section card={@card} parent={@parent} />
            <.layout_section card={@card} parent={@parent} />

            <%= if @card.card_type == :query do %>
              <.query_section card={@card} />
              <.visualization_section card={@card} columns={@available_columns} parent={@parent} />
              <.filter_mapping_section card={@card} filters={@filters} parent={@parent} />
            <% else %>
              <.content_section card={@card} parent={@parent} />
            <% end %>

            <.danger_section card={@card} parent={@parent} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp header(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700/50 flex items-center justify-between">
      <h3 class="font-medium text-gray-900 dark:text-white">
        <%= gettext("Card Settings") %>
      </h3>
      <button
        phx-click="close_card_settings"
        phx-target={@parent}
        class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
      >
        <Icons.x_mark class="h-5 w-5" />
      </button>
    </div>
    """
  end

  defp title_section(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= gettext("Card Title") %>
      </label>
      <form phx-change="update_card_title" phx-target={@parent}>
        <input type="hidden" name="card_id" value={@card.id} />
        <input
          type="text"
          name="title"
          value={@card.title || ""}
          phx-debounce="150"
          placeholder={default_title(@card)}
          class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
        />
      </form>
    </div>
    """
  end

  defp query_section(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= gettext("Query") %>
      </label>
      <%= if @card.query do %>
        <div class="flex items-center justify-between p-2.5 bg-gray-50 dark:bg-gray-700/50 rounded-lg border border-gray-200 dark:border-gray-600">
          <span class="text-sm text-gray-900 dark:text-white truncate">
            <%= @card.query.name %>
          </span>
          <.link
            navigate={lotus_path(["queries", @card.query.id])}
            class="ml-2 shrink-0 text-sm text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300"
          >
            <%= gettext("Edit") %>
          </.link>
        </div>
      <% else %>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("No query assigned") %>
        </p>
      <% end %>
    </div>
    """
  end

  defp layout_section(assigns) do
    layout = assigns.card.layout || %{x: 0, y: 0, w: 6, h: 4}

    assigns =
      assign(assigns,
        layout_x: get_layout_value(layout, :x, 0),
        layout_y: get_layout_value(layout, :y, 0),
        layout_w: get_layout_value(layout, :w, 6),
        layout_h: get_layout_value(layout, :h, 4)
      )

    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= gettext("Layout Position") %>
      </label>
      <form phx-change="update_card_layout" phx-target={@parent}>
        <input type="hidden" name="card_id" value={@card.id} />
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
              <%= gettext("X (0-11)") %>
            </label>
            <input
              type="number"
              name="layout[x]"
              value={@layout_x}
              min="0"
              max="11"
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
              <%= gettext("Y Position") %>
            </label>
            <input
              type="number"
              name="layout[y]"
              value={@layout_y}
              min="0"
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
              <%= gettext("Width (1-12)") %>
            </label>
            <input
              type="number"
              name="layout[w]"
              value={@layout_w}
              min="1"
              max="12"
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
              <%= gettext("Height") %>
            </label>
            <input
              type="number"
              name="layout[h]"
              value={@layout_h}
              min="1"
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
        </div>
      </form>
      <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Grid uses 12 columns. Cards are positioned by column (X) and row (Y).") %>
      </p>
    </div>
    """
  end

  defp get_layout_value(layout, key, default) when is_atom(key) do
    Map.get(layout, key, Map.get(layout, to_string(key), default))
  end

  defp visualization_section(assigns) do
    config = stringify_config(assigns.card.visualization_config || %{})

    assigns =
      assign(assigns,
        chart_type: config["chart_type"],
        x_field: config["x_field"],
        y_field: config["y_field"],
        series_field: config["series_field"],
        value_field: config["value_field"],
        kpi_label: config["kpi_label"] || "",
        bin_count: config["bin_count"] || "10",
        size_field: config["size_field"],
        min_value: config["min_value"] || "0",
        max_value: config["max_value"] || "100",
        goal_value: config["goal_value"] || "100",
        comparison_field: config["comparison_field"],
        y2_field: config["y2_field"],
        y2_axis_title: config["y2_axis_title"] || ""
      )

    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= gettext("Visualization") %>
      </label>
      <form phx-change="update_card_visualization" phx-target={@parent}>
        <input type="hidden" name="card_id" value={@card.id} />

        <div class="space-y-3">
          <div>
            <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
              <%= gettext("Chart Type") %>
            </label>
            <select
              name="visualization[chart_type]"
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            >
              <option value=""><%= gettext("Table (default)") %></option>
              <option :for={type <- VegaSpecBuilder.chart_type_ids()} value={type} selected={@chart_type == type}>
                <%= chart_type_label(type) %>
              </option>
            </select>
          </div>

          <%= if @chart_type in ~w(kpi gauge progress trend) do %>
            <div>
              <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                <%= gettext("Value Field") %>
              </label>
              <select
                name="visualization[value_field]"
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value=""><%= gettext("Select field...") %></option>
                <%= for col <- @columns do %>
                  <option value={col} selected={@value_field == col}><%= col %></option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                <%= gettext("Label") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
              </label>
              <input
                type="text"
                name="visualization[kpi_label]"
                value={@kpi_label}
                placeholder={gettext("e.g. Total Orders")}
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              />
            </div>
            <%= if @chart_type == "gauge" do %>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1"><%= gettext("Min") %></label>
                  <input type="number" name="visualization[min_value]" value={@min_value}
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500" />
                </div>
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1"><%= gettext("Max") %></label>
                  <input type="number" name="visualization[max_value]" value={@max_value}
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500" />
                </div>
              </div>
            <% end %>
            <%= if @chart_type == "progress" do %>
              <div>
                <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1"><%= gettext("Goal Value") %></label>
                <input type="number" name="visualization[goal_value]" value={@goal_value}
                  class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500" />
              </div>
            <% end %>
            <%= if @chart_type == "trend" do %>
              <div>
                <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                  <%= gettext("Comparison Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
                </label>
                <select
                  name="visualization[comparison_field]"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                >
                  <option value=""><%= gettext("Use previous row") %></option>
                  <%= for col <- @columns do %>
                    <option value={col} selected={@comparison_field == col}><%= col %></option>
                  <% end %>
                </select>
              </div>
            <% end %>
          <% else %>
            <%= if @chart_type do %>
              <div>
                <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                  <%= if @chart_type == "histogram", do: gettext("Data Field"), else: gettext("X-Axis Field") %>
                </label>
                <select
                  name="visualization[x_field]"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                >
                  <option value=""><%= gettext("Select field...") %></option>
                  <%= for col <- @columns do %>
                    <option value={col} selected={@x_field == col}><%= col %></option>
                  <% end %>
                </select>
              </div>

              <%= if @chart_type not in ~w(histogram sparkline) do %>
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <%= if @chart_type == "combo", do: gettext("Bar Series (Y-Axis)"), else: gettext("Y-Axis Field") %>
                  </label>
                  <select
                    name="visualization[y_field]"
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                  >
                    <option value=""><%= gettext("Select field...") %></option>
                    <%= for col <- @columns do %>
                      <option value={col} selected={@y_field == col}><%= col %></option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @chart_type == "combo" do %>
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <%= gettext("Line Series") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
                  </label>
                  <select
                    name="visualization[y2_field]"
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                  >
                    <option value=""><%= gettext("None") %></option>
                    <%= for col <- @columns do %>
                      <option value={col} selected={@y2_field == col}><%= col %></option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @chart_type == "histogram" do %>
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <%= gettext("Number of Bins") %>
                  </label>
                  <input
                    type="number"
                    name="visualization[bin_count]"
                    value={@bin_count}
                    min="2"
                    max="100"
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                  />
                </div>
              <% end %>

              <%= if @chart_type == "bubble" do %>
                <div>
                  <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <%= gettext("Size Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
                  </label>
                  <select
                    name="visualization[size_field]"
                    class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                  >
                    <option value=""><%= gettext("None") %></option>
                    <%= for col <- @columns do %>
                      <option value={col} selected={@size_field == col}><%= col %></option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <div>
                <label class="block text-xs text-gray-500 dark:text-gray-400 mb-1">
                  <%= gettext("Color/Series Field") %> <span class="text-gray-400">(<%= gettext("optional") %>)</span>
                </label>
                <select
                  name="visualization[series_field]"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                >
                  <option value=""><%= gettext("None") %></option>
                  <%= for col <- @columns do %>
                    <option value={col} selected={@series_field == col}><%= col %></option>
                  <% end %>
                </select>
              </div>
            <% end %>
          <% end %>
        </div>
      </form>
    </div>
    """
  end

  defp filter_mapping_section(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= gettext("Filter Mappings") %>
      </label>
      <%= if @filters == [] do %>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("No dashboard filters configured.") %>
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for filter <- @filters do %>
            <.filter_mapping_row filter={filter} card={@card} parent={@parent} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp filter_mapping_row(assigns) do
    query = assigns.card.query
    variables = if query, do: query.variables || [], else: []
    entries = mapping_entries(assigns.card.filter_mappings, assigns.filter)

    assigns =
      assign(assigns,
        variables: variables,
        current_mapping: Enum.find_value(entries, & &1.variable_name),
        entries: entries,
        split: Enum.any?(entries, & &1.transform)
      )

    ~H"""
    <div id={"filter-mapping-#{@filter.name}"} class="p-2 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
    <form
      phx-change="update_filter_mapping"
      phx-target={@parent}
      class="flex items-center gap-2"
    >
      <input type="hidden" name="card-id" value={@card.id} />
      <input type="hidden" name="filter-name" value={@filter.name} />
      <span class="text-sm text-gray-700 dark:text-gray-300 min-w-[80px]">
        <%= @filter.label || @filter.name %>
      </span>
      <Icons.chevron_right class="h-4 w-4 text-gray-400" />
      <select
        name={"filter_mapping[#{@filter.name}]"}
        class="flex-1 border border-gray-300 dark:border-gray-600 rounded p-1.5 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      >
        <option value=""><%= gettext("Not mapped") %></option>
        <%= for var <- @variables do %>
          <option value={var.name} selected={@current_mapping == var.name}>
            <%= var.label || var.name %>
          </option>
        <% end %>
      </select>
    </form>
    <p :if={@split} class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
      <%= gettext("Split into %{variables}. A new choice replaces the split.",
        variables: split_description(@entries)
      ) %>
    </p>
    </div>
    """
  end

  defp content_section(assigns) do
    content_value = get_content_value(assigns.card)
    assigns = assign(assigns, :content_value, content_value)

    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        <%= content_label(@card.card_type) %>
      </label>
      <form phx-change="update_card_content" phx-target={@parent}>
        <input type="hidden" name="card_id" value={@card.id} />
        <input type="hidden" name="card_type" value={@card.card_type} />
        <%= if @card.card_type == :link do %>
          <input
            type="url"
            name="content"
            value={@content_value}
            phx-debounce="150"
            placeholder="https://example.com"
            class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
          />
        <% else %>
          <textarea
            name="content"
            phx-debounce="150"
            rows="4"
            placeholder={content_placeholder(@card.card_type)}
            class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
          ><%= @content_value %></textarea>
        <% end %>
      </form>
    </div>
    """
  end

  defp get_content_value(%{card_type: :link, content: content}) do
    case content do
      nil -> ""
      url when is_binary(url) -> url
      %{"url" => url} -> url || ""
      %{url: url} -> url || ""
      _ -> ""
    end
  end

  defp get_content_value(%{card_type: type, content: content}) when type in [:text, :heading] do
    case content do
      nil -> ""
      text when is_binary(text) -> text
      %{"text" => text} -> text || ""
      %{text: text} -> text || ""
      _ -> ""
    end
  end

  defp get_content_value(_), do: ""

  defp content_label(:text), do: gettext("Text Content")
  defp content_label(:heading), do: gettext("Heading Text")
  defp content_label(:link), do: gettext("Link URL")
  defp content_label(_), do: gettext("Content")

  defp content_placeholder(:text), do: gettext("Enter text or markdown content...")
  defp content_placeholder(:heading), do: gettext("Enter heading text...")
  defp content_placeholder(_), do: ""

  defp danger_section(assigns) do
    ~H"""
    <div class="pt-4 border-t border-gray-200 dark:border-gray-700">
      <button
        phx-click="delete_card"
        phx-value-card-id={@card.id}
        phx-target={@parent}
        data-confirm={gettext("Are you sure you want to delete this card?")}
        class="w-full flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
      >
        <Icons.trash class="h-4 w-4" />
        <%= gettext("Delete Card") %>
      </button>
    </div>
    """
  end

  # filter_mappings can be a list of Ecto structs (from DB) or a map of
  # %{filter_name => [%{variable_name: _, transform: _}]} (from editor updates)
  defp mapping_entries(mappings, filter) when is_list(mappings) do
    for mapping <- mappings,
        mapping.filter_id == filter.id,
        do: %{variable_name: mapping.variable_name, transform: mapping.transform}
  end

  defp mapping_entries(mappings, filter) when is_map(mappings),
    do: Map.get(mappings, filter.name, [])

  defp mapping_entries(_, _), do: []

  defp split_description(entries) do
    Enum.map_join(entries, ", ", fn entry ->
      "#{entry.variable_name} (#{transform_label(entry.transform)})"
    end)
  end

  defp transform_label(%{"type" => type}), do: transform_label(type)
  defp transform_label(%{type: type}), do: transform_label(type)
  defp transform_label("date_range_start"), do: gettext("range start")
  defp transform_label("date_range_end"), do: gettext("range end")
  defp transform_label(_transform), do: gettext("whole value")

  defp default_title(%{card_type: :query, query: query}) when not is_nil(query) do
    query.name || gettext("Query")
  end

  defp default_title(%{card_type: :query}), do: gettext("Query")
  defp default_title(%{card_type: :text}), do: gettext("Text")
  defp default_title(%{card_type: :heading}), do: gettext("Heading")
  defp default_title(%{card_type: :link}), do: gettext("Link")
  defp default_title(_), do: gettext("Card")

  defp stringify_config(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp chart_type_label(type), do: VegaSpecBuilder.chart_type_label(type)

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    {:ok, assign(socket, params)}
  end
end
