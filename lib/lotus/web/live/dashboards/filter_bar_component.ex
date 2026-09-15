defmodule Lotus.Web.Dashboards.FilterBarComponent do
  @moduledoc """
  Renders the dashboard filter bar with filter widgets.
  """

  alias Lotus.Web.Dashboards.DateTokens
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
            today={@today}
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
          <.date_picker filter={@filter} value={@value} parent={@parent} today={@today} />
        <% :date_range_picker -> %>
          <.date_range_picker filter={@filter} value={@value} parent={@parent} today={@today} />
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

  defp date_picker(assigns) do
    assigns = assign(assigns, token: token(assigns.filter, assigns.value))

    ~H"""
    <div class="flex items-center gap-2">
      <.date_presets filter={@filter} value={@value} token={@token} parent={@parent} today={@today} />
      <input
        :if={!@token}
        type="date"
        name={"filter[#{@filter.name}]"}
        value={@value || ""}
        class="w-full border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    """
  end

  defp date_range_picker(assigns) do
    token = token(assigns.filter, assigns.value)
    {start_value, end_value} = if token, do: {nil, nil}, else: parse_date_range(assigns.value)
    assigns = assign(assigns, token: token, start_value: start_value, end_value: end_value)

    ~H"""
    <div class="flex items-center gap-2">
      <.date_presets filter={@filter} value={@value} token={@token} parent={@parent} today={@today} />
      <input
        :if={!@token}
        type="date"
        name={"filter[#{@filter.name}][start]"}
        value={@start_value}
        class="flex-1 border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      />
      <span :if={!@token} class="text-gray-400">-</span>
      <input
        :if={!@token}
        type="date"
        name={"filter[#{@filter.name}][end]"}
        value={@end_value}
        class="flex-1 border border-gray-300 dark:border-gray-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
      />
    </div>
    """
  end

  # A token the filter accepts, or nil for a fixed value. A token stays the
  # filter value, so the URL and a shared link stay relative.
  defp token(filter, value), do: if(value in DateTokens.tokens(filter.filter_type), do: value)

  # The relative date tokens of a date filter, and the way back to fixed dates.
  # With a token, the trigger shows its label and the dates it covers today,
  # and a hidden input keeps the token in the posted form.
  defp date_presets(assigns) do
    assigns =
      assign(assigns,
        menu_id: "filter-#{assigns.filter.name}-presets",
        groups: DateTokens.groups(assigns.filter.filter_type),
        fixed_label: fixed_label(assigns.filter.filter_type),
        fixed_value: fixed_value(assigns.token, assigns.filter, assigns.value, assigns.today)
      )

    ~H"""
    <div
      :if={@groups != []}
      class="relative"
      phx-click-away={hide_presets(@menu_id)}
      phx-window-keydown={hide_presets(@menu_id)}
      phx-key="Escape"
    >
      <input :if={@token} type="hidden" name={"filter[#{@filter.name}]"} value={@token} />
      <button
        type="button"
        id={@menu_id <> "-button"}
        phx-click={toggle_presets(@menu_id)}
        aria-haspopup="menu"
        aria-controls={@menu_id}
        title={if !@token, do: gettext("Relative dates")}
        class={[
          "inline-flex items-center gap-2 whitespace-nowrap border border-gray-300 dark:border-gray-600 rounded-lg py-2 text-sm bg-white dark:bg-gray-700 dark:text-white hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500",
          if(@token, do: "px-3", else: "px-2.5")
        ]}
      >
        <Icons.calendar class="h-4 w-4 shrink-0 text-gray-400" />
        <%= if @token do %>
          <span class="font-medium text-gray-900 dark:text-white"><%= DateTokens.label(@token) %></span>
          <span class="text-gray-500 dark:text-gray-400 tabular-nums">
            <%= DateTokens.describe(@token, @today) %>
          </span>
        <% end %>
        <Icons.chevron_down class="h-4 w-4 shrink-0 text-gray-400" />
      </button>

      <div
        id={@menu_id}
        role="menu"
        aria-labelledby={@menu_id <> "-button"}
        class="hidden absolute left-0 mt-2 w-72 max-h-96 overflow-y-auto bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 py-1 z-50"
      >
        <div
          :for={group <- @groups ++ [:fixed]}
          role="group"
          class="py-1 [&:not(:first-child)]:border-t [&:not(:first-child)]:border-gray-100 dark:[&:not(:first-child)]:border-gray-700"
        >
          <%= if group == :fixed do %>
            <.preset_item
              menu_id={@menu_id}
              filter={@filter}
              parent={@parent}
              value={@fixed_value}
              label={@fixed_label}
              selected={!@token}
            />
          <% else %>
            <.preset_item
              :for={token <- group}
              menu_id={@menu_id}
              filter={@filter}
              parent={@parent}
              value={token}
              label={DateTokens.label(token)}
              detail={DateTokens.describe(token, @today)}
              selected={token == @token}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr(:menu_id, :string, required: true)
  attr(:filter, :map, required: true)
  attr(:parent, :any, required: true)
  attr(:value, :string, required: true)
  attr(:label, :string, required: true)
  attr(:detail, :string, default: nil)
  attr(:selected, :boolean, default: false)

  defp preset_item(assigns) do
    ~H"""
    <button
      type="button"
      role="menuitemradio"
      aria-checked={to_string(@selected)}
      phx-click={
        JS.push("filter_preset", value: %{name: @filter.name, value: @value}, target: @parent)
        |> hide_presets(@menu_id)
      }
      class={[
        "flex w-full items-center gap-3 px-3 py-2 text-sm text-left hover:bg-gray-100 dark:hover:bg-gray-700",
        if(@selected,
          do: "font-medium text-pink-600 dark:text-pink-400",
          else: "text-gray-700 dark:text-gray-200"
        )
      ]}
    >
      <Icons.check class={["h-4 w-4 shrink-0", !@selected && "invisible"]} />
      <span class="flex-1"><%= @label %></span>
      <span :if={@detail} class="text-xs font-normal text-gray-400 dark:text-gray-500 tabular-nums">
        <%= @detail %>
      </span>
    </button>
    """
  end

  defp toggle_presets(menu_id) do
    JS.toggle(
      to: "##{menu_id}",
      in: {"transition ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"},
      out: {"transition ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  defp hide_presets(js \\ %JS{}, menu_id) do
    JS.hide(js,
      to: "##{menu_id}",
      transition:
        {"transition ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  defp fixed_label(:date), do: gettext("Fixed date")
  defp fixed_label(_filter_type), do: gettext("Custom range")

  # Leaving a token for fixed dates starts from the dates the token covers today.
  defp fixed_value(nil, _filter, value, _today), do: to_string(value || "")

  defp fixed_value(token, filter, _value, today),
    do: DateTokens.resolve(token, filter.filter_type, today)

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
    {:ok, socket |> assign(params) |> assign(today: Date.utc_today())}
  end
end
