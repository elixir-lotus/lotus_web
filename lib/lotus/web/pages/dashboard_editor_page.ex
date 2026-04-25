defmodule Lotus.Web.DashboardEditorPage do
  @moduledoc """
  Main dashboard editor page for creating and editing dashboards.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Dashboards.AddCardModal
  alias Lotus.Web.Dashboards.CardGridComponent
  alias Lotus.Web.Dashboards.CardSettingsDrawer
  alias Lotus.Web.Dashboards.FilterBarComponent
  alias Lotus.Web.Dashboards.SettingsDrawer
  alias Lotus.Web.Page
  alias Lotus.Web.VegaSpecBuilder

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="dashboard-editor" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full flex flex-col">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg h-full flex flex-col overflow-hidden">

          <%!-- Header Bar --%>
          <.header_bar
            dashboard={@dashboard}
            mode={@page.mode}
            running={MapSet.size(@running_cards) > 0}
            parent={@myself}
          />

          <%!-- Filter Bar --%>
          <.live_component
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            parent={@myself}
          />

          <%!-- Main Content Area --%>
          <div class="relative flex-1 min-h-0 overflow-hidden">
            <%!-- Overlay for mobile drawers --%>
            <%= if @settings_visible or @card_settings_visible do %>
              <div
                class="fixed inset-0 bg-black/50 z-10 sm:hidden"
                phx-click={if @card_settings_visible, do: "close_card_settings", else: "close_settings"}
                phx-target={@myself}
              >
              </div>
            <% end %>

            <%!-- Settings Drawer (slides from right) --%>
            <.live_component
              module={SettingsDrawer}
              id="settings-drawer"
              visible={@settings_visible}
              dashboard={@dashboard}
              uri={@current_uri}
              parent={@myself}
            />

            <%!-- Card Settings Drawer --%>
            <.live_component
              module={CardSettingsDrawer}
              id="card-settings-drawer"
              visible={@card_settings_visible}
              card={@selected_card}
              filters={@dashboard.filters}
              available_columns={@selected_card_columns}
              parent={@myself}
            />

            <%!-- Grid Content --%>
            <div class={[
              "h-full overflow-y-auto p-4 transition-all duration-300",
              (@settings_visible || @card_settings_visible) && "sm:mr-80"
            ]}>
              <%= if @dashboard.cards != [] do %>
                <.live_component
                  module={CardGridComponent}
                  id="card-grid"
                  cards={@dashboard.cards}
                  card_results={@card_results}
                  card_errors={@card_errors}
                  running_cards={@running_cards}
                  selected_card_id={@selected_card && @selected_card.id}
                  parent={@myself}
                />
              <% end %>

              <%!-- Add Card Button --%>
              <button
                phx-click="show_add_card_modal"
                phx-target={@myself}
                class="mt-4 w-full border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg p-8 text-center hover:border-pink-500 hover:bg-pink-50/50 dark:hover:bg-pink-900/20 transition-all group"
              >
                <Icons.plus class="mx-auto h-8 w-8 text-gray-400 group-hover:text-pink-500" />
                <span class="mt-2 block text-sm text-gray-500 dark:text-gray-400 group-hover:text-pink-600">
                  <%= gettext("Add Card") %>
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Modals --%>
      <.live_component
        :if={@add_card_modal_open}
        module={AddCardModal}
        id="add-card-modal"
        queries={@available_queries}
        parent={@myself}
      />

      <.save_modal
        :if={@save_modal_open}
        dashboard_form={@dashboard_form}
        mode={@page.mode}
        parent={@myself}
      />

      <.delete_modal
        :if={@delete_modal_open}
        dashboard={@dashboard}
        parent={@myself}
      />

      <.filter_modal
        :if={@filter_modal_open}
        filter={@editing_filter}
        parent={@myself}
      />

      <%!-- Auto-refresh hook --%>
      <%= if @dashboard.auto_refresh_seconds do %>
        <div
          id="auto-refresh-timer"
          phx-hook="AutoRefresh"
          data-seconds={@dashboard.auto_refresh_seconds}
        />
      <% end %>
    </div>
    """
  end

  defp header_bar(assigns) do
    ~H"""
    <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
      <div class="flex items-center gap-3">
        <.link navigate={lotus_path("", %{tab: "dashboards"})} class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
          <Icons.chevron_left class="h-5 w-5" />
        </.link>
        <h2 class="text-xl font-semibold text-text-light dark:text-text-dark">
          <%= if @mode == :new do %>
            <%= gettext("New Dashboard") %>
          <% else %>
            <%= @dashboard.name || gettext("Untitled") %>
          <% end %>
        </h2>
      </div>
      <div class="flex items-center gap-3">
        <%= if @running do %>
          <span class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <.spinner size="16" />
            <%= gettext("Running...") %>
          </span>
        <% end %>

        <button
          type="button"
          phx-click="refresh_all_cards"
          phx-target={@parent}
          class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
          title={gettext("Refresh all cards")}
        >
          <Icons.rotate_ccw class="h-5 w-5" />
        </button>

        <button
          type="button"
          phx-click="toggle_settings"
          phx-target={@parent}
          class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
          title={gettext("Dashboard settings")}
        >
          <Icons.cog_6_tooth class="h-5 w-5" />
        </button>

        <%= if @mode == :edit do %>
          <.button
            type="button"
            variant="light"
            phx-click="show_delete_modal"
            phx-target={@parent}
            class="text-red-600 hover:text-red-700 border-transparent hover:bg-red-50 dark:text-red-400 dark:hover:text-red-300 dark:border-transparent dark:hover:bg-white/10"
          >
            <%= gettext("Delete") %>
          </.button>
        <% end %>
        <.button
          type="button"
          phx-click="show_save_modal"
          phx-target={@parent}
        >
          <%= gettext("Save") %>
        </.button>
      </div>
    </div>
    """
  end

  defp save_modal(assigns) do
    ~H"""
    <.modal id="save-dashboard-modal" show on_cancel={JS.push("close_save_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        <%= if @mode == :new, do: gettext("Save Dashboard"), else: gettext("Update Dashboard") %>
      </h3>

      <.form for={@dashboard_form}
             phx-submit="save_dashboard"
             phx-change="validate_save"
             phx-target={@parent}>
        <div class="space-y-4">
          <.input
            field={@dashboard_form[:name]}
            type="text"
            label={gettext("Name")}
            placeholder={gettext("Enter dashboard name")}
            required
          />
          <.input
            field={@dashboard_form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter dashboard description (optional)")}
            rows="3"
          />
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <.button
            type="button"
            variant="light"
            phx-click="close_save_modal"
            phx-target={@parent}
          >
            <%= gettext("Cancel") %>
          </.button>
          <.button
            type="submit"
            disabled={String.trim(Phoenix.HTML.Form.input_value(@dashboard_form, :name) || "") == ""}
          >
            <%= gettext("Save Dashboard") %>
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp delete_modal(assigns) do
    ~H"""
    <.modal id="delete-dashboard-modal" show on_cancel={JS.push("close_delete_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        <%= gettext("Delete Dashboard") %>
      </h3>
      <p class="text-sm text-gray-500 dark:text-gray-400 mb-6">
        <%= gettext("Are you sure you want to delete this dashboard? This action cannot be undone.") %>
      </p>
      <div class="flex justify-end gap-3">
        <.button
          type="button"
          variant="light"
          phx-click="close_delete_modal"
          phx-target={@parent}
        >
          <%= gettext("Cancel") %>
        </.button>
        <.button
          type="button"
          phx-click="delete_dashboard"
          phx-target={@parent}
          class="bg-red-600 hover:bg-red-700 focus-visible:outline-red-600"
        >
          <%= gettext("Delete") %>
        </.button>
      </div>
    </.modal>
    """
  end

  defp filter_modal(assigns) do
    is_new = is_binary(assigns.filter.id)

    assigns =
      assign(assigns,
        is_new: is_new,
        filter_type: to_string(assigns.filter.filter_type),
        widget: to_string(assigns.filter.widget),
        options_text: format_options(assigns.filter.config)
      )

    ~H"""
    <.modal id="filter-modal" show on_cancel={JS.push("close_filter_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        <%= if @is_new, do: gettext("Add Filter"), else: gettext("Edit Filter") %>
      </h3>

      <form phx-submit="save_filter" phx-target={@parent}>
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Label") %>
            </label>
            <input
              type="text"
              name="filter[label]"
              value={@filter.label}
              placeholder={gettext("e.g. Region, Date Range")}
              required
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Name") %>
            </label>
            <input
              type="text"
              name="filter[name]"
              value={@filter.name}
              placeholder={gettext("e.g. region, date_range")}
              required
              pattern="[A-Za-z_][A-Za-z0-9_]*"
              title={gettext("Must start with a letter or underscore, followed by letters, numbers, or underscores")}
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500 font-mono text-sm"
            />
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              <%= gettext("Used as the URL parameter name (e.g. ?region=US)") %>
            </p>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                <%= gettext("Type") %>
              </label>
              <select
                name="filter[filter_type]"
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value="text" selected={@filter_type == "text"}><%= gettext("Text") %></option>
                <option value="number" selected={@filter_type == "number"}><%= gettext("Number") %></option>
                <option value="date" selected={@filter_type == "date"}><%= gettext("Date") %></option>
                <option value="date_range" selected={@filter_type == "date_range"}><%= gettext("Date Range") %></option>
                <option value="select" selected={@filter_type == "select"}><%= gettext("Select") %></option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                <%= gettext("Widget") %>
              </label>
              <select
                name="filter[widget]"
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value="input" selected={@widget == "input"}><%= gettext("Input") %></option>
                <option value="select" selected={@widget == "select"}><%= gettext("Select") %></option>
                <option value="date_picker" selected={@widget == "date_picker"}><%= gettext("Date Picker") %></option>
                <option value="date_range_picker" selected={@widget == "date_range_picker"}><%= gettext("Date Range Picker") %></option>
              </select>
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Default Value") %>
            </label>
            <input
              type="text"
              name="filter[default_value]"
              value={@filter.default_value || ""}
              placeholder={gettext("Optional")}
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              <%= gettext("Options") %>
              <span class="font-normal text-gray-400">(<%= gettext("for select widgets, one per line") %>)</span>
            </label>
            <textarea
              name="filter[options]"
              rows="3"
              placeholder={"us\neu\napac"}
              class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500 font-mono text-sm"
            ><%= @options_text %></textarea>
          </div>
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <.button
            type="button"
            variant="light"
            phx-click="close_filter_modal"
            phx-target={@parent}
          >
            <%= gettext("Cancel") %>
          </.button>
          <.button type="submit">
            <%= if @is_new, do: gettext("Add Filter"), else: gettext("Save Filter") %>
          </.button>
        </div>
      </form>
    </.modal>
    """
  end

  # Page Callbacks

  @impl Page
  def handle_mount(socket) do
    socket
    |> assign(
      dashboard: new_dashboard(),
      dashboard_form: nil,
      filter_values: %{},
      card_results: %{},
      card_errors: %{},
      running_cards: MapSet.new(),
      settings_visible: false,
      card_settings_visible: false,
      selected_card: nil,
      selected_card_columns: [],
      add_card_modal_open: false,
      filter_modal_open: false,
      editing_filter: nil,
      save_modal_open: false,
      delete_modal_open: false,
      available_queries: Lotus.list_queries(),
      auto_refresh_ref: nil,
      current_uri: nil
    )
  end

  @impl Page
  def handle_params(params, uri, socket) do
    socket = assign(socket, current_uri: uri)

    case socket.assigns.page do
      %{mode: :new} ->
        dashboard = new_dashboard()
        {:noreply, assign_dashboard(socket, dashboard)}

      %{mode: :edit, id: id} ->
        case load_dashboard(id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Dashboard not found"))
             |> push_navigate(to: lotus_path("", %{tab: "dashboards"}))}

          dashboard ->
            filter_values = extract_filter_values(params, dashboard.filters)

            {:noreply,
             socket
             |> assign_dashboard(dashboard)
             |> assign(filter_values: filter_values)
             |> run_all_cards()}
        end
    end
  end

  # Event Handlers

  @impl Phoenix.LiveComponent
  def handle_event("show_add_card_modal", _params, socket) do
    {:noreply, assign(socket, add_card_modal_open: true)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_add_card_modal", _params, socket) do
    {:noreply, assign(socket, add_card_modal_open: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("confirm_add_card", %{"type" => type} = params, socket) do
    case parse_card_type(type) do
      nil ->
        {:noreply, assign(socket, add_card_modal_open: false)}

      card_type ->
        query_id = Map.get(params, "query-id")
        query_id = if query_id && query_id != "", do: String.to_integer(query_id), else: nil

        socket = add_card(socket, card_type, query_id)
        {:noreply, assign(socket, add_card_modal_open: false)}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_card", %{"card-id" => card_id}, socket) do
    card_id = parse_id(card_id)
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    columns =
      if card && card.card_type == :query do
        case Map.get(socket.assigns.card_results, card_id) do
          %{columns: cols} -> cols
          _ -> []
        end
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_card: card,
       selected_card_columns: columns,
       card_settings_visible: card != nil
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("open_card_settings", %{"card-id" => card_id}, socket) do
    card_id = parse_id(card_id)
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    columns =
      if card && card.card_type == :query do
        case Map.get(socket.assigns.card_results, card_id) do
          %{columns: cols} -> cols
          _ -> []
        end
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_card: card,
       selected_card_columns: columns,
       card_settings_visible: true,
       settings_visible: false
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_card_settings", _params, socket) do
    {:noreply, assign(socket, card_settings_visible: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_card", %{"card-id" => card_id}, socket) do
    card_id = parse_id(card_id)
    dashboard = socket.assigns.dashboard
    updated_cards = Enum.reject(dashboard.cards, &(&1.id == card_id))
    updated_dashboard = %{dashboard | cards: updated_cards}

    {:noreply,
     socket
     |> assign(dashboard: updated_dashboard)
     |> assign(card_settings_visible: false, selected_card: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_card_title", %{"title" => title, "card_id" => card_id}, socket) do
    card_id = parse_id(card_id)
    socket = update_card_and_selection(socket, card_id, fn card -> %{card | title: title} end)
    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_card_content",
        %{"content" => content, "card_id" => card_id} = params,
        socket
      ) do
    case parse_card_type(params["card_type"]) do
      nil ->
        {:noreply, socket}

      card_type ->
        card_id = parse_id(card_id)

        formatted_content =
          case card_type do
            :link -> %{"url" => content}
            :text -> %{"text" => content}
            :heading -> %{"text" => content}
            :query -> content
          end

        socket =
          update_card_and_selection(socket, card_id, fn card ->
            %{card | content: formatted_content}
          end)

        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_card_layout", %{"card_id" => card_id, "layout" => layout}, socket) do
    card_id = parse_id(card_id)

    layout = %{
      x: parse_int(layout["x"], 0),
      y: parse_int(layout["y"], 0),
      w: parse_int(layout["w"], 6),
      h: parse_int(layout["h"], 4)
    }

    socket = update_card_and_selection(socket, card_id, fn card -> %{card | layout: layout} end)
    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_card_visualization",
        %{"card_id" => card_id, "visualization" => viz},
        socket
      ) do
    card_id = parse_id(card_id)

    socket =
      update_card_and_selection(socket, card_id, fn card ->
        existing =
          (card.visualization_config || %{})
          |> Map.new(fn {k, v} -> {to_string(k), v} end)

        config = VegaSpecBuilder.build_config(Map.merge(existing, viz))
        %{card | visualization_config: config}
      end)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_filter_mapping",
        %{"card-id" => card_id, "filter-name" => filter_name} = params,
        socket
      ) do
    card_id = parse_id(card_id)
    variable_name = params["filter_mapping"]["#{filter_name}"]

    socket =
      update_card_and_selection(socket, card_id, fn card ->
        mappings = normalize_mappings(card.filter_mappings, socket.assigns.dashboard.filters)
        updated_mappings = Map.put(mappings, filter_name, variable_name)
        %{card | filter_mappings: updated_mappings}
      end)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("refresh_card", %{"card-id" => card_id}, socket) do
    card_id = parse_id(card_id)
    {:noreply, run_card(socket, card_id)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("refresh_all_cards", _params, socket) do
    {:noreply, run_all_cards(socket)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("auto_refresh_tick", _params, socket) do
    {:noreply, run_all_cards(socket)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("filter_changed", %{"filter" => filter_values}, socket) do
    socket =
      socket
      |> assign(filter_values: filter_values)
      |> run_all_cards()
      |> push_filter_params_to_url(filter_values)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_filter", _params, socket) do
    next_position = length(socket.assigns.dashboard.filters)

    new_filter = %{
      id: "new_#{System.unique_integer([:positive])}",
      name: "",
      label: "",
      filter_type: :text,
      widget: :input,
      default_value: nil,
      config: %{},
      position: next_position
    }

    {:noreply, assign(socket, filter_modal_open: true, editing_filter: new_filter)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("edit_filter", %{"filter-id" => filter_id}, socket) do
    filter_id = maybe_parse_id(filter_id)
    filter = Enum.find(socket.assigns.dashboard.filters, &(&1.id == filter_id))

    if filter do
      {:noreply, assign(socket, filter_modal_open: true, editing_filter: filter)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_filter_modal", _params, socket) do
    {:noreply, assign(socket, filter_modal_open: false, editing_filter: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("save_filter", %{"filter" => filter_params}, socket) do
    editing = socket.assigns.editing_filter
    dashboard = socket.assigns.dashboard

    filter = %{
      editing
      | name: filter_params["name"] || "",
        label: filter_params["label"] || "",
        filter_type: parse_filter_type(filter_params["filter_type"]),
        widget: parse_filter_widget(filter_params["widget"]),
        default_value: nullify(filter_params["default_value"]),
        config: build_filter_config(filter_params)
    }

    filters = upsert_filter(dashboard.filters, filter)

    dashboard = %{dashboard | filters: filters}

    {:noreply,
     socket
     |> assign(dashboard: dashboard, filter_modal_open: false, editing_filter: nil)
     |> run_all_cards()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_filter", %{"filter-id" => filter_id}, socket) do
    filter_id = maybe_parse_id(filter_id)
    dashboard = socket.assigns.dashboard
    filters = Enum.reject(dashboard.filters, &(&1.id == filter_id))
    dashboard = %{dashboard | filters: filters}

    filter_values =
      Map.drop(socket.assigns.filter_values, [
        Enum.find_value(socket.assigns.dashboard.filters, fn f ->
          if f.id == filter_id, do: f.name
        end)
      ])

    {:noreply,
     socket
     |> assign(dashboard: dashboard, filter_values: filter_values)
     |> run_all_cards()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_settings", _params, socket) do
    {:noreply,
     assign(socket,
       settings_visible: not socket.assigns.settings_visible,
       card_settings_visible: false
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, settings_visible: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_auto_refresh", %{"auto_refresh_seconds" => seconds}, socket) do
    seconds = if seconds == "", do: nil, else: String.to_integer(seconds)
    dashboard = %{socket.assigns.dashboard | auto_refresh_seconds: seconds}
    {:noreply, assign(socket, dashboard: dashboard)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("enable_sharing", _params, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to modify dashboards")]}
      )

      {:noreply, socket}
    else
      do_enable_sharing(socket)
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("disable_sharing", _params, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to modify dashboards")]}
      )

      {:noreply, socket}
    else
      do_disable_sharing(socket)
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("show_save_modal", _params, socket) do
    changeset = build_dashboard_changeset(socket.assigns.dashboard, %{})
    form = to_form(changeset, as: "dashboard")
    {:noreply, assign(socket, save_modal_open: true, dashboard_form: form)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_save_modal", _params, socket) do
    {:noreply, assign(socket, save_modal_open: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate_save", %{"dashboard" => params}, socket) do
    changeset = build_dashboard_changeset(socket.assigns.dashboard, params)
    form = to_form(changeset, as: "dashboard")
    {:noreply, assign(socket, dashboard_form: form)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("save_dashboard", %{"dashboard" => params}, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to save dashboards")]}
      )

      {:noreply, assign(socket, save_modal_open: false)}
    else
      do_save_dashboard(socket, params)
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, delete_modal_open: true, settings_visible: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, delete_modal_open: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_dashboard", _params, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to delete dashboards")]}
      )

      {:noreply, assign(socket, delete_modal_open: false)}
    else
      do_delete_dashboard(socket)
    end
  end

  @impl Page
  def handle_info({:card_result, card_id, result}, socket) do
    running_cards = MapSet.delete(socket.assigns.running_cards, card_id)
    card_results = Map.put(socket.assigns.card_results, card_id, result)
    card_errors = Map.delete(socket.assigns.card_errors, card_id)

    # Update selected card columns if this is the selected card
    socket =
      if socket.assigns.selected_card && socket.assigns.selected_card.id == card_id do
        columns = Map.get(result, :columns, [])
        assign(socket, selected_card_columns: columns)
      else
        socket
      end

    {:noreply,
     assign(socket,
       running_cards: running_cards,
       card_results: card_results,
       card_errors: card_errors
     )}
  end

  def handle_info({:card_error, card_id, error}, socket) do
    running_cards = MapSet.delete(socket.assigns.running_cards, card_id)
    card_errors = Map.put(socket.assigns.card_errors, card_id, error)
    card_results = Map.delete(socket.assigns.card_results, card_id)

    {:noreply,
     assign(socket,
       running_cards: running_cards,
       card_results: card_results,
       card_errors: card_errors
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveComponent
  def handle_async({:run_card, card_id}, {:ok, {:ok, result}}, socket) do
    running_cards = MapSet.delete(socket.assigns.running_cards, card_id)
    card_results = Map.put(socket.assigns.card_results, card_id, result)
    card_errors = Map.delete(socket.assigns.card_errors, card_id)

    # Update selected card columns if this is the selected card
    socket =
      if socket.assigns.selected_card && socket.assigns.selected_card.id == card_id do
        columns = Map.get(result, :columns, [])
        assign(socket, selected_card_columns: columns)
      else
        socket
      end

    {:noreply,
     assign(socket,
       running_cards: running_cards,
       card_results: card_results,
       card_errors: card_errors
     )}
  end

  def handle_async({:run_card, card_id}, {:ok, {:error, error}}, socket) do
    running_cards = MapSet.delete(socket.assigns.running_cards, card_id)
    card_errors = Map.put(socket.assigns.card_errors, card_id, to_string(error))
    card_results = Map.delete(socket.assigns.card_results, card_id)

    {:noreply,
     assign(socket,
       running_cards: running_cards,
       card_results: card_results,
       card_errors: card_errors
     )}
  end

  def handle_async({:run_card, card_id}, {:exit, reason}, socket) do
    running_cards = MapSet.delete(socket.assigns.running_cards, card_id)
    error_msg = gettext("Query execution failed: %{reason}", reason: inspect(reason))
    card_errors = Map.put(socket.assigns.card_errors, card_id, error_msg)
    card_results = Map.delete(socket.assigns.card_results, card_id)

    {:noreply,
     assign(socket,
       running_cards: running_cards,
       card_results: card_results,
       card_errors: card_errors
     )}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    if socket.assigns[:initialized] do
      # Component already initialized - only accept specific assigns from parent:
      # - Core routing/auth assigns
      # - Async task results (running_cards, card_results, card_errors) that are
      #   updated by handle_async on the LiveView level
      keys_from_parent = [
        :page,
        :params,
        :user,
        :access,
        :running_cards,
        :card_results,
        :card_errors
      ]

      {:ok, assign(socket, Map.take(assigns, keys_from_parent))}
    else
      # First update - accept all assigns from parent and mark as initialized
      {:ok,
       socket
       |> assign(assigns)
       |> assign(initialized: true)}
    end
  end

  # Private Helpers

  defp do_enable_sharing(socket) do
    token = generate_public_token()
    dashboard = %{socket.assigns.dashboard | public_token: token}

    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = existing <- Lotus.get_dashboard(id),
         {:ok, _saved} <- Lotus.update_dashboard(existing, %{"public_token" => token}) do
      send(self(), {:put_flash, [:info, gettext("Public sharing enabled")]})

      send_update(SettingsDrawer,
        id: "settings-drawer",
        dashboard: dashboard,
        visible: true
      )

      {:noreply, assign(socket, dashboard: dashboard)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Dashboard not found"))}

      {:error, _} ->
        send(self(), {:put_flash, [:error, gettext("Failed to enable sharing")]})
        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, dashboard: dashboard)}
    end
  end

  defp do_disable_sharing(socket) do
    dashboard = %{socket.assigns.dashboard | public_token: nil}

    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = existing <- Lotus.get_dashboard(id),
         {:ok, _saved} <- Lotus.update_dashboard(existing, %{"public_token" => nil}) do
      send(self(), {:put_flash, [:info, gettext("Public sharing disabled")]})

      send_update(SettingsDrawer,
        id: "settings-drawer",
        dashboard: dashboard,
        visible: true
      )

      {:noreply, assign(socket, dashboard: dashboard)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Dashboard not found"))}

      {:error, _} ->
        send(self(), {:put_flash, [:error, gettext("Failed to disable sharing")]})
        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, dashboard: dashboard)}
    end
  end

  defp do_save_dashboard(socket, params) do
    dashboard = socket.assigns.dashboard

    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      "auto_refresh_seconds" => dashboard.auto_refresh_seconds,
      "public_token" => dashboard.public_token
    }

    result = perform_save_dashboard(socket.assigns.page, attrs, dashboard)

    case result do
      {:ok, saved_dashboard} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Dashboard saved successfully!"))
         |> assign(save_modal_open: false)
         |> push_patch(to: lotus_path(["dashboards", saved_dashboard.id]), replace: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: "dashboard")
        send(self(), {:put_flash, [:error, gettext("Failed to save dashboard")]})
        {:noreply, assign(socket, dashboard_form: form)}

      {:error, _reason} ->
        send(self(), {:put_flash, [:error, gettext("Failed to save dashboard")]})
        {:noreply, socket}
    end
  end

  defp perform_save_dashboard(%{mode: :new}, attrs, dashboard) do
    with {:ok, saved} <- Lotus.create_dashboard(attrs),
         :ok <- sync_cards(saved, dashboard.cards),
         :ok <- sync_filters(saved, dashboard.filters),
         :ok <- sync_card_filter_mappings(saved, dashboard.cards) do
      {:ok, saved}
    end
  end

  defp perform_save_dashboard(%{mode: :edit, id: id}, attrs, dashboard) do
    with %{} = existing <- Lotus.get_dashboard(id),
         {:ok, saved} <- Lotus.update_dashboard(existing, attrs),
         :ok <- sync_cards(saved, dashboard.cards),
         :ok <- sync_filters(saved, dashboard.filters),
         :ok <- sync_card_filter_mappings(saved, dashboard.cards) do
      {:ok, saved}
    else
      nil -> {:error, "Dashboard not found"}
      error -> error
    end
  end

  defp do_delete_dashboard(socket) do
    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = dashboard <- Lotus.get_dashboard(id),
         {:ok, _} <- Lotus.delete_dashboard(dashboard) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Dashboard deleted successfully"))
       |> push_navigate(to: lotus_path("", %{tab: "dashboards"}))}
    else
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Dashboard not found"))
         |> push_navigate(to: lotus_path("", %{tab: "dashboards"}))}

      {:error, _} ->
        send(self(), {:put_flash, [:error, gettext("Failed to delete dashboard")]})
        {:noreply, assign(socket, delete_modal_open: false)}

      _ ->
        {:noreply, push_navigate(socket, to: lotus_path(""))}
    end
  end

  defp should_run_card?(card) do
    card && card.card_type == :query && card.query
  end

  defp execute_card_query(socket, card_id, card) do
    query = card.query
    vars = build_card_variables(socket, card)
    running_cards = MapSet.put(socket.assigns.running_cards, card_id)

    socket
    |> assign(running_cards: running_cards)
    |> start_async({:run_card, card_id}, fn ->
      Lotus.run_query(query, vars: vars)
    end)
  end

  defp build_card_variables(socket, card) do
    filter_values = socket.assigns.filter_values
    dashboard_filters = socket.assigns.dashboard.filters || []
    mappings = card.filter_mappings

    build_vars_from_mappings(mappings, dashboard_filters, filter_values)
  end

  # Map format: %{filter_name => variable_name} (in-memory after editing)
  defp build_vars_from_mappings(mappings, _dashboard_filters, filter_values)
       when is_map(mappings) do
    Enum.reduce(mappings, %{}, fn {filter_name, variable_name}, acc ->
      put_filter_var(acc, variable_name, Map.get(filter_values, filter_name))
    end)
  end

  # List format: [%DashboardCardFilterMapping{}] (from DB preload)
  defp build_vars_from_mappings(mappings, dashboard_filters, filter_values)
       when is_list(mappings) do
    Enum.reduce(mappings, %{}, fn mapping, acc ->
      filter = Enum.find(dashboard_filters, &(&1.id == mapping.filter_id))
      value = if filter, do: Map.get(filter_values, filter.name)
      put_filter_var(acc, mapping.variable_name, value)
    end)
  end

  defp build_vars_from_mappings(_, _, _), do: %{}

  defp put_filter_var(acc, var_name, value)
       when is_binary(var_name) and var_name != "" and not is_nil(value) do
    Map.put(acc, var_name, value)
  end

  defp put_filter_var(acc, _, _), do: acc

  defp new_dashboard do
    %{
      id: nil,
      name: "",
      description: "",
      cards: [],
      filters: [],
      auto_refresh_seconds: nil,
      public_token: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp load_dashboard(id) do
    case Lotus.get_dashboard(id) do
      nil ->
        nil

      dashboard ->
        cards = Lotus.list_dashboard_cards(dashboard.id, preload: [:query, :filter_mappings])
        filters = Lotus.list_dashboard_filters(dashboard.id)
        %{dashboard | cards: cards, filters: filters}
    end
  end

  defp assign_dashboard(socket, dashboard) do
    changeset = build_dashboard_changeset(dashboard, %{})
    form = to_form(changeset, as: "dashboard")
    assign(socket, dashboard: dashboard, dashboard_form: form)
  end

  defp build_dashboard_changeset(dashboard, params) do
    types = %{name: :string, description: :string}

    {dashboard, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name])
  end

  defp add_card(socket, card_type, query_id) do
    dashboard = socket.assigns.dashboard

    # Calculate next position index
    next_position = length(dashboard.cards)

    # Find the next available layout position that doesn't overlap
    layout = find_next_available_position(dashboard.cards, card_type)

    query =
      if query_id do
        Lotus.get_query(query_id)
      else
        nil
      end

    new_card = %{
      id: generate_temp_id(),
      card_type: card_type,
      title: nil,
      position: next_position,
      layout: layout,
      query_id: query_id,
      query: query,
      visualization_config: nil,
      filter_mappings: %{},
      content: nil
    }

    updated_dashboard = %{dashboard | cards: dashboard.cards ++ [new_card]}

    socket
    |> assign(
      dashboard: updated_dashboard,
      selected_card: new_card,
      card_settings_visible: true,
      settings_visible: false
    )
    |> maybe_run_card(new_card)
  end

  # Find the next available position in the grid that doesn't overlap with existing cards
  defp find_next_available_position(cards, card_type) do
    # Default dimensions based on card type
    {default_w, default_h} =
      case card_type do
        :query -> {6, 4}
        :heading -> {12, 1}
        :text -> {6, 2}
        :link -> {6, 1}
      end

    if cards == [] do
      %{x: 0, y: 0, w: default_w, h: default_h}
    else
      # Build a grid of occupied cells
      occupied = build_occupied_grid(cards)

      # Find the lowest Y position where we can fit the new card
      find_free_position(occupied, default_w, default_h)
    end
  end

  defp build_occupied_grid(cards) do
    Enum.reduce(cards, MapSet.new(), fn card, acc ->
      layout = card.layout || %{x: 0, y: 0, w: 6, h: 4}
      x = Map.get(layout, :x, Map.get(layout, "x", 0))
      y = Map.get(layout, :y, Map.get(layout, "y", 0))
      w = Map.get(layout, :w, Map.get(layout, "w", 6))
      h = Map.get(layout, :h, Map.get(layout, "h", 4))

      # Mark all cells occupied by this card
      for cx <- x..(x + w - 1), cy <- y..(y + h - 1), reduce: acc do
        acc -> MapSet.put(acc, {cx, cy})
      end
    end)
  end

  defp find_free_position(occupied, width, height) do
    # Try each row starting from 0
    Enum.reduce_while(0..100, nil, fn y, _acc ->
      # Try each column position (0 to 12-width)
      result =
        Enum.find(0..(12 - width), fn x ->
          # Check if all cells for this position are free
          cells_free?(occupied, x, y, width, height)
        end)

      case result do
        nil -> {:cont, nil}
        x -> {:halt, %{x: x, y: y, w: width, h: height}}
      end
    end) || %{x: 0, y: 0, w: width, h: height}
  end

  defp cells_free?(occupied, x, y, width, height) do
    Enum.all?(x..(x + width - 1), fn cx ->
      Enum.all?(y..(y + height - 1), fn cy ->
        not MapSet.member?(occupied, {cx, cy})
      end)
    end)
  end

  defp update_card(socket, card_id, update_fn) do
    dashboard = socket.assigns.dashboard

    updated_cards =
      Enum.map(dashboard.cards, fn card ->
        if card.id == card_id do
          update_fn.(card)
        else
          card
        end
      end)

    updated_dashboard = %{dashboard | cards: updated_cards}
    assign(socket, dashboard: updated_dashboard)
  end

  defp update_card_and_selection(socket, card_id, update_fn) do
    socket = update_card(socket, card_id, update_fn)

    # Also update selected_card if this is the currently selected card
    if socket.assigns.selected_card && socket.assigns.selected_card.id == card_id do
      updated_card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))
      assign(socket, selected_card: updated_card)
    else
      socket
    end
  end

  defp parse_card_type("query"), do: :query
  defp parse_card_type("text"), do: :text
  defp parse_card_type("link"), do: :link
  defp parse_card_type("heading"), do: :heading
  defp parse_card_type(_), do: nil

  defp parse_filter_type("text"), do: :text
  defp parse_filter_type("number"), do: :number
  defp parse_filter_type("date"), do: :date
  defp parse_filter_type("date_range"), do: :date_range
  defp parse_filter_type("select"), do: :select
  defp parse_filter_type(_), do: :text

  defp parse_filter_widget("input"), do: :input
  defp parse_filter_widget("select"), do: :select
  defp parse_filter_widget("date_picker"), do: :date_picker
  defp parse_filter_widget("date_range_picker"), do: :date_range_picker
  defp parse_filter_widget(_), do: :input

  defp maybe_run_card(socket, card) do
    if card.card_type == :query && card.query_id do
      run_card(socket, card.id)
    else
      socket
    end
  end

  defp run_card(socket, card_id) do
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    if should_run_card?(card) do
      execute_card_query(socket, card_id, card)
    else
      socket
    end
  end

  defp run_all_cards(socket) do
    query_cards =
      socket.assigns.dashboard.cards
      |> Enum.filter(&(&1.card_type == :query && &1.query_id))

    Enum.reduce(query_cards, socket, fn card, acc ->
      run_card(acc, card.id)
    end)
  end

  defp generate_temp_id do
    :erlang.unique_integer([:positive])
  end

  defp generate_public_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  # Sync cards: delete removed, update existing, create new
  defp sync_cards(saved_dashboard, cards) do
    existing_cards = Lotus.list_dashboard_cards(saved_dashboard.id)
    existing_ids = MapSet.new(existing_cards, & &1.id)

    # Cards with integer IDs are existing, others are new (temp IDs)
    {existing_card_updates, new_cards} =
      Enum.split_with(cards, fn card ->
        is_integer(card.id) and MapSet.member?(existing_ids, card.id)
      end)

    current_ids = MapSet.new(existing_card_updates, & &1.id)

    # Delete cards that are no longer present
    cards_to_delete = Enum.reject(existing_cards, &MapSet.member?(current_ids, &1.id))

    Enum.each(cards_to_delete, fn card ->
      Lotus.delete_dashboard_card(card)
    end)

    # Update existing cards
    update_results =
      Enum.map(existing_card_updates, fn card ->
        existing_card = Enum.find(existing_cards, &(&1.id == card.id))

        if existing_card do
          Lotus.update_dashboard_card(existing_card, card_to_attrs(card))
        else
          {:ok, nil}
        end
      end)

    # Create new cards
    create_results =
      Enum.map(new_cards, fn card ->
        Lotus.create_dashboard_card(saved_dashboard.id, card_to_attrs(card))
      end)

    # Check for errors
    all_results = update_results ++ create_results

    case Enum.find(all_results, &match?({:error, _}, &1)) do
      {:error, changeset} -> {:error, changeset}
      nil -> :ok
    end
  end

  defp sync_filters(saved_dashboard, filters) do
    existing_filters = Lotus.list_dashboard_filters(saved_dashboard.id)
    existing_ids = MapSet.new(existing_filters, & &1.id)

    {existing_filter_updates, new_filters} =
      Enum.split_with(filters, fn filter ->
        is_integer(filter.id) and MapSet.member?(existing_ids, filter.id)
      end)

    current_ids = MapSet.new(existing_filter_updates, & &1.id)

    # Delete filters that are no longer present
    filters_to_delete = Enum.reject(existing_filters, &MapSet.member?(current_ids, &1.id))

    Enum.each(filters_to_delete, fn filter ->
      Lotus.delete_dashboard_filter(filter)
    end)

    # Update existing filters
    Enum.each(existing_filter_updates, fn filter ->
      existing_filter = Enum.find(existing_filters, &(&1.id == filter.id))

      if existing_filter do
        Lotus.update_dashboard_filter(existing_filter, filter_to_attrs(filter))
      end
    end)

    # Create new filters
    Enum.each(new_filters, fn filter ->
      Lotus.create_dashboard_filter(saved_dashboard, filter_to_attrs(filter))
    end)

    :ok
  end

  defp sync_card_filter_mappings(saved_dashboard, cards) do
    saved_cards = Lotus.list_dashboard_cards(saved_dashboard.id)
    saved_filters = Lotus.list_dashboard_filters(saved_dashboard.id)
    filter_by_name = Map.new(saved_filters, &{&1.name, &1})

    cards
    |> Enum.filter(&is_map(&1.filter_mappings))
    |> Enum.each(&sync_single_card_mappings(&1, saved_cards, filter_by_name))

    :ok
  end

  defp sync_single_card_mappings(card, saved_cards, filter_by_name) do
    saved_card = Enum.find(saved_cards, &match_card?(&1, card))
    if saved_card, do: replace_card_mappings(saved_card, card.filter_mappings, filter_by_name)
  end

  defp replace_card_mappings(saved_card, mappings, filter_by_name) do
    existing_mappings = Lotus.list_card_filter_mappings(saved_card.id)
    Enum.each(existing_mappings, &Lotus.delete_filter_mapping/1)

    Enum.each(mappings, fn {filter_name, variable_name} ->
      filter = Map.get(filter_by_name, filter_name)

      if filter && variable_name && variable_name != "" do
        Lotus.create_filter_mapping(saved_card.id, filter.id, variable_name)
      end
    end)
  end

  defp match_card?(saved_card, card) do
    if is_integer(card.id),
      do: saved_card.id == card.id,
      else: saved_card.query_id == card.query_id
  end

  defp card_to_attrs(card) do
    %{
      card_type: card.card_type,
      title: card.title,
      position: card.position,
      layout: layout_to_map(card.layout),
      query_id: card.query_id,
      visualization_config: card.visualization_config || %{},
      content: card.content || %{}
    }
  end

  defp layout_to_map(nil), do: nil
  defp layout_to_map(%{x: x, y: y, w: w, h: h}), do: %{x: x, y: y, w: w, h: h}

  defp normalize_mappings(mappings, _filters) when is_map(mappings), do: mappings

  defp normalize_mappings(mappings, filters) when is_list(mappings) do
    filter_by_id = Map.new(filters, fn f -> {f.id, f.name} end)

    Map.new(mappings, fn mapping ->
      filter_name = Map.get(filter_by_id, mapping.filter_id, "unknown")
      {filter_name, mapping.variable_name}
    end)
  end

  defp normalize_mappings(_, _), do: %{}

  defp push_filter_params_to_url(socket, filter_values) do
    params =
      filter_values
      |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
      |> Map.new()

    push_event(socket, "update-query-params", %{params: params})
  end

  defp extract_filter_values(params, filters) do
    for filter <- filters,
        value = present(Map.get(params, filter.name)) || present(filter.default_value),
        into: %{},
        do: {filter.name, value}
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil

  defp upsert_filter(filters, filter) do
    if Enum.any?(filters, &(&1.id == filter.id)) do
      Enum.map(filters, &if(&1.id == filter.id, do: filter, else: &1))
    else
      filters ++ [filter]
    end
  end

  defp nullify(""), do: nil
  defp nullify(val), do: val

  defp maybe_parse_id(id) when is_integer(id), do: id

  defp maybe_parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp build_filter_config(%{"options" => options}) when is_binary(options) do
    opts =
      options
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if opts == [], do: %{}, else: %{"options" => Enum.map(opts, &%{"value" => &1, "label" => &1})}
  end

  defp build_filter_config(_), do: %{}

  defp format_options(%{"options" => options}) when is_list(options) do
    Enum.map_join(options, "\n", fn
      %{"value" => v} -> v
      v when is_binary(v) -> v
      _ -> ""
    end)
  end

  defp format_options(_), do: ""

  defp filter_to_attrs(filter) do
    %{
      name: filter.name,
      label: filter.label,
      filter_type: filter.filter_type,
      widget: filter.widget,
      default_value: filter.default_value,
      position: filter.position,
      config: filter.config
    }
  end
end
