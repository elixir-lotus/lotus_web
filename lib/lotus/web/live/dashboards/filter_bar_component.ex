defmodule Lotus.Web.Dashboards.FilterBarComponent do
  @moduledoc """
  Renders the dashboard filter bar with filter widgets.
  """

  alias Lotus.Web.Dashboards.FilterValues

  use Lotus.Web, :live_component

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, filters: [], filter_values: %{}, filter_options: %{}, public: false)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="filter-bar" class="px-4 sm:px-6 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700/50">
      <form phx-change="filter_changed" phx-submit="filter_changed" phx-target={@parent} class="flex flex-wrap items-end gap-4">
        <%= for filter <- Enum.sort_by(@filters, & &1.position) do %>
          <.filter_widget
            filter={filter}
            value={Map.get(@filter_values, filter.name, filter.default_value)}
            options_state={Map.get(@filter_options, filter.name)}
            public={@public}
            parent={@parent}
          />
        <% end %>

        <button
          :if={!@public}
          type="button"
          phx-click="add_filter"
          phx-target={@parent}
          class="inline-flex items-center gap-1 text-sm text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300 pb-2"
        >
          <Icons.plus class="h-4 w-4" />
          <%= gettext("Add Filter") %>
        </button>
      </form>
    </div>
    """
  end

  defp filter_widget(assigns) do
    ~H"""
    <div class="min-w-[150px]">
      <div class="flex items-center justify-between mb-1">
        <label class="block text-xs font-medium text-gray-500 dark:text-gray-400">
          <%= @filter.label || @filter.name %>
        </label>
        <div :if={!@public} class="flex items-center gap-0.5">
          <button
            type="button"
            phx-click="edit_filter"
            phx-value-filter-id={@filter.id}
            phx-target={@parent}
            class="p-0.5 text-gray-400 hover:text-pink-600 dark:hover:text-pink-400"
            title={gettext("Edit filter")}
          >
            <Icons.cog_6_tooth class="h-3 w-3" />
          </button>
          <button
            type="button"
            phx-click="delete_filter"
            phx-value-filter-id={@filter.id}
            phx-target={@parent}
            class="p-0.5 text-gray-400 hover:text-red-600 dark:hover:text-red-400"
            title={gettext("Remove filter")}
          >
            <Icons.x_mark class="h-3 w-3" />
          </button>
        </div>
      </div>
      <%= case @filter.widget do %>
        <% :input -> %>
          <input
            type={input_type(@filter.filter_type)}
            name={"filter[#{@filter.name}]"}
            value={@value || ""}
            placeholder={@filter.label || @filter.name}
            phx-debounce="500"
            class="w-full border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
          />
        <% :select -> %>
          <.select_widget filter={@filter} value={@value} state={@options_state} />
        <% :date_picker -> %>
          <input
            type="date"
            name={"filter[#{@filter.name}]"}
            value={@value || ""}
            class="w-full border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
          />
        <% :date_range_picker -> %>
          <.date_range_picker filter={@filter} value={@value} />
        <% _ -> %>
          <input
            type="text"
            name={"filter[#{@filter.name}]"}
            value={@value || ""}
            placeholder={@filter.label || @filter.name}
            phx-debounce="500"
            class="w-full border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
          />
      <% end %>
    </div>
    """
  end

  # `state` comes from `Lotus.Web.Dashboards.FilterOptions`. With no state the
  # select lists its static options.
  defp select_widget(assigns) do
    assigns =
      assign(assigns,
        options: select_options(assigns.state, assigns.filter),
        waiting: assigns.state == :waiting,
        error: select_error(assigns.state)
      )

    ~H"""
    <select
      name={"filter[#{@filter.name}]"}
      disabled={@waiting}
      title={if @waiting, do: gettext("Choose a value in the filter this one depends on")}
      class="w-full border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500 disabled:opacity-50 disabled:cursor-not-allowed"
    >
      <option value=""><%= gettext("All") %></option>
      <%= for opt <- @options do %>
        <option value={option_value(opt)} selected={to_string(@value) == option_value(opt)}>
          <%= option_label(opt) %>
        </option>
      <% end %>
    </select>
    <p
      :if={@error}
      id={"filter-#{@filter.name}-error"}
      title={@error}
      class="mt-1 max-w-xs truncate text-xs text-red-600 dark:text-red-400"
    >
      <%= @error %>
    </p>
    """
  end

  defp select_options({:ok, options}, _filter), do: options
  defp select_options(nil, filter), do: filter.config["options"] || []
  defp select_options(_state, _filter), do: []

  defp select_error({:error, reason}) when is_binary(reason), do: reason
  defp select_error({:error, reason}), do: inspect(reason)
  defp select_error(_state), do: nil

  defp date_range_picker(assigns) do
    {start_value, end_value} = parse_date_range(assigns.value)
    assigns = assign(assigns, start_value: start_value, end_value: end_value)

    ~H"""
    <div class="flex items-center gap-2">
      <input
        type="date"
        name={"filter[#{@filter.name}][start]"}
        value={@start_value}
        class="flex-1 border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      />
      <span class="text-gray-400">-</span>
      <input
        type="date"
        name={"filter[#{@filter.name}][end]"}
        value={@end_value}
        class="flex-1 border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    """
  end

  defp input_type(:text), do: "text"
  defp input_type(:integer), do: "number"
  defp input_type(:float), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(:datetime), do: "datetime-local"
  defp input_type(_), do: "text"

  # Options from a source query keep the column types, and a filter value is a
  # string, so both sides compare as strings.
  defp option_value(%{"value" => value}), do: to_string(value)
  defp option_value(%{value: value}), do: to_string(value)
  defp option_value(value), do: to_string(value)

  defp option_label(%{"label" => label}), do: to_string(label)
  defp option_label(%{label: label}), do: to_string(label)
  defp option_label(%{"value" => value}), do: to_string(value)
  defp option_label(%{value: value}), do: to_string(value)
  defp option_label(value), do: to_string(value)

  defp parse_date_range(value), do: FilterValues.split_date_range(value)

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    {:ok, assign(socket, params)}
  end
end
