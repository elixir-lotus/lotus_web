defmodule Lotus.Web.DashboardEditorPage do
  @moduledoc """
  Main dashboard editor page for creating and editing dashboards.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Actor
  alias Lotus.Web.Authorization
  alias Lotus.Web.Dashboards.AddCardModal
  alias Lotus.Web.Dashboards.CardGridComponent
  alias Lotus.Web.Dashboards.CardRunner
  alias Lotus.Web.Dashboards.CardSettingsDrawer
  alias Lotus.Web.Dashboards.FilterBarComponent
  alias Lotus.Web.Dashboards.FilterOptions
  alias Lotus.Web.Dashboards.FilterValues
  alias Lotus.Web.Dashboards.SettingsDrawer
  alias Lotus.Web.Page
  alias Lotus.Web.VegaSpecBuilder

  @impl Phoenix.LiveComponent
  def render(assigns) do
    resource = dashboard_resource(assigns.page, assigns.dashboard)

    assigns =
      assign(assigns,
        can_manage: Authorization.allowed?(assigns, :manage_dashboard, resource),
        can_share: resource != nil and Authorization.allowed?(assigns, :share_dashboard, resource)
      )

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
            can_manage={@can_manage}
          />

          <%!-- Filter Bar. `public` hides the controls that edit filters. --%>
          <.live_component
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            filter_options={@filter_options}
            public={not @can_manage}
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
              can_share={@can_share}
              can_manage={@can_manage}
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
                  can_manage={@can_manage}
                  parent={@myself}
                />
              <% end %>

              <%!-- Add Card Button --%>
              <button
                :if={@can_manage}
                id="add-card-btn"
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
        filters={@dashboard.filters}
        queries={@available_queries}
        errors={@filter_errors}
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

        <%= if @mode == :edit and @can_manage do %>
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
          :if={@can_manage}
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
        options_text: format_options(assigns.filter.config),
        source_query_id: Map.get(assigns.filter, :source_query_id),
        depends_on_filter_id: Map.get(assigns.filter, :depends_on_filter_id),
        parent_choices: Enum.reject(assigns.filters, &(&1.id == assigns.filter.id))
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
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                <%= gettext("Source Query") %>
              </label>
              <select
                name="filter[source_query_id]"
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value=""><%= gettext("None (use the options above)") %></option>
                <%= for query <- @queries do %>
                  <option value={query.id} selected={query.id == @source_query_id}>
                    <%= query.name %>
                  </option>
                <% end %>
              </select>
              <.filter_field_error errors={@errors} field={:source_query_id} />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                <%= gettext("Depends On") %>
              </label>
              <select
                name="filter[depends_on_filter_id]"
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value=""><%= gettext("None") %></option>
                <%= for parent <- @parent_choices do %>
                  <option value={parent.id} selected={parent.id == @depends_on_filter_id}>
                    <%= parent.label || parent.name %>
                  </option>
                <% end %>
              </select>
              <.filter_field_error errors={@errors} field={:depends_on_filter_id} />
            </div>
          </div>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            <%= gettext("For select widgets. The source query lists the options: the first column is the value and the second is the label. The value of the filter it depends on goes to the query as the variable with that filter's name.") %>
          </p>
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

  defp filter_field_error(assigns) do
    ~H"""
    <p :if={@errors[@field]} class="mt-1 text-xs text-red-600 dark:text-red-400">
      <%= @errors[@field] %>
    </p>
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
      filter_options: %{},
      filter_errors: %{},
      card_results: %{},
      card_errors: %{},
      running_cards: MapSet.new(),
      card_runner: CardRunner.new(socket.assigns.card_concurrency),
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
        case Authorization.authorize(socket.assigns, :manage_dashboard) do
          :allow -> {:noreply, assign_dashboard(socket, new_dashboard())}
          {:deny, reason} -> {:noreply, leave(socket, reason)}
        end

      %{mode: :edit, id: id} ->
        with %{} = dashboard <- load_dashboard(id),
             :allow <- Authorization.authorize(socket.assigns, :view_dashboard, dashboard) do
          filter_values = extract_filter_values(params, dashboard.filters)

          {:noreply,
           socket
           |> assign_dashboard(dashboard)
           |> assign(filter_values: filter_values)
           |> assign_filter_options()
           |> run_all_cards()}
        else
          nil -> {:noreply, leave(socket, gettext("Dashboard not found"))}
          {:deny, reason} -> {:noreply, leave(socket, reason)}
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
    resource = dashboard_resource(socket.assigns.page, socket.assigns.dashboard)

    with :allow <- Authorization.authorize(socket.assigns, :manage_dashboard, resource),
         card_type when not is_nil(card_type) <- parse_card_type(type) do
      query_id = Map.get(params, "query-id")
      query_id = if query_id && query_id != "", do: String.to_integer(query_id), else: nil

      socket = add_card(socket, card_type, query_id)
      {:noreply, assign(socket, add_card_modal_open: false)}
    else
      {:deny, reason} ->
        {:noreply, socket |> deny(reason) |> assign(add_card_modal_open: false)}

      nil ->
        {:noreply, assign(socket, add_card_modal_open: false)}
    end
  end

  # Card, filter and auto-refresh edits change only the page until Save, but a
  # user who may not manage the dashboard gets no editor: each handler asks.

  @impl Phoenix.LiveComponent
  def handle_event("select_card", %{"card-id" => card_id}, socket) do
    authorize_manage(socket, fn -> do_select_card(socket, card_id) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("open_card_settings", %{"card-id" => card_id}, socket) do
    authorize_manage(socket, fn -> do_open_card_settings(socket, card_id) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_card_settings", _params, socket) do
    {:noreply, assign(socket, card_settings_visible: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_card", %{"card-id" => card_id}, socket) do
    authorize_manage(socket, fn -> do_delete_card(socket, card_id) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_card_title", %{"title" => title, "card_id" => card_id}, socket) do
    authorize_manage(socket, fn ->
      {:noreply, update_card_and_selection(socket, parse_id(card_id), &%{&1 | title: title})}
    end)
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_card_content",
        %{"content" => content, "card_id" => card_id} = params,
        socket
      ) do
    authorize_manage(socket, fn ->
      do_update_card_content(socket, card_id, content, params["card_type"])
    end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_card_layout", %{"card_id" => card_id, "layout" => layout}, socket) do
    authorize_manage(socket, fn -> do_update_card_layout(socket, card_id, layout) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_card_visualization",
        %{"card_id" => card_id, "visualization" => viz},
        socket
      ) do
    authorize_manage(socket, fn -> do_update_card_visualization(socket, card_id, viz) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event(
        "update_filter_mapping",
        %{"card-id" => card_id, "filter-name" => filter_name} = params,
        socket
      ) do
    variable_name = params["filter_mapping"]["#{filter_name}"]

    authorize_manage(socket, fn ->
      do_update_filter_mapping(socket, card_id, filter_name, variable_name)
    end)
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
    filter_values = FilterValues.normalize(filter_values)

    socket =
      socket
      |> assign(filter_values: filter_values)
      |> assign_filter_options()

    {:noreply,
     socket
     |> run_all_cards()
     |> push_filter_params_to_url(socket.assigns.filter_values)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_filter", _params, socket) do
    authorize_manage(socket, fn -> do_add_filter(socket) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("edit_filter", %{"filter-id" => filter_id}, socket) do
    authorize_manage(socket, fn -> do_edit_filter(socket, filter_id) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_filter_modal", _params, socket) do
    {:noreply, assign(socket, filter_modal_open: false, editing_filter: nil, filter_errors: %{})}
  end

  @impl Phoenix.LiveComponent
  def handle_event("save_filter", %{"filter" => filter_params}, socket) do
    authorize_manage(socket, fn -> do_save_filter(socket, filter_params) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_filter", %{"filter-id" => filter_id}, socket) do
    authorize_manage(socket, fn -> do_delete_filter(socket, filter_id) end)
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
    authorize_manage(socket, fn -> do_update_auto_refresh(socket, seconds) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("enable_sharing", _params, socket) do
    case Authorization.authorize(socket.assigns, :share_dashboard, socket.assigns.dashboard) do
      :allow -> do_enable_sharing(socket)
      {:deny, reason} -> {:noreply, deny(socket, reason)}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("disable_sharing", _params, socket) do
    case Authorization.authorize(socket.assigns, :share_dashboard, socket.assigns.dashboard) do
      :allow -> do_disable_sharing(socket)
      {:deny, reason} -> {:noreply, deny(socket, reason)}
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
    resource = dashboard_resource(socket.assigns.page, socket.assigns.dashboard)

    case Authorization.authorize(socket.assigns, :manage_dashboard, resource) do
      :allow -> do_save_dashboard(socket, params)
      {:deny, reason} -> {:noreply, socket |> deny(reason) |> assign(save_modal_open: false)}
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
    case Authorization.authorize(socket.assigns, :manage_dashboard, socket.assigns.dashboard) do
      :allow -> do_delete_dashboard(socket)
      {:deny, reason} -> {:noreply, socket |> deny(reason) |> assign(delete_modal_open: false)}
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
  def handle_async({:run_card, card_id}, result, socket) do
    case CardRunner.finish(socket, card_id, &prepare_card/2) do
      {:ok, socket} -> {:noreply, put_card_result(socket, card_id, result)}
      :stale -> {:noreply, socket}
    end
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
    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = existing <- Lotus.get_dashboard(id),
         {:ok, saved} <- Lotus.enable_public_sharing(existing, Actor.opts(socket.assigns)) do
      sharing_changed(socket, saved.public_token, gettext("Public sharing enabled"))
    else
      error -> sharing_failed(socket, error, gettext("Failed to enable sharing"))
    end
  end

  defp do_disable_sharing(socket) do
    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = existing <- Lotus.get_dashboard(id),
         {:ok, saved} <- Lotus.disable_public_sharing(existing, Actor.opts(socket.assigns)) do
      sharing_changed(socket, saved.public_token, gettext("Public sharing disabled"))
    else
      error -> sharing_failed(socket, error, gettext("Failed to disable sharing"))
    end
  end

  defp sharing_changed(socket, token, message) do
    dashboard = %{socket.assigns.dashboard | public_token: token}
    send(self(), {:put_flash, [:info, message]})
    send_update(SettingsDrawer, id: "settings-drawer", dashboard: dashboard, visible: true)
    {:noreply, assign(socket, dashboard: dashboard)}
  end

  defp sharing_failed(socket, nil, _message),
    do: {:noreply, put_flash(socket, :error, gettext("Dashboard not found"))}

  defp sharing_failed(socket, {:error, {:halted, reason}}, _message),
    do: {:noreply, deny(socket, refused_message(reason))}

  defp sharing_failed(socket, {:error, _reason}, message), do: {:noreply, deny(socket, message)}

  # A dashboard that is not saved yet has no link to change.
  defp sharing_failed(socket, _unsaved, _message), do: {:noreply, socket}

  defp do_save_dashboard(socket, params) do
    dashboard = socket.assigns.dashboard

    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      # No "public_token": only the sharing handlers, which ask for
      # :share_dashboard, write it. A save from a page opened before the link was
      # turned off must not turn it back on.
      "auto_refresh_seconds" => dashboard.auto_refresh_seconds
    }

    result = perform_save_dashboard(socket, attrs, dashboard)

    case result do
      {:ok, saved_dashboard} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Dashboard saved successfully!"))
         |> assign(save_modal_open: false)
         |> push_patch(to: lotus_path(["dashboards", saved_dashboard.id]), replace: true)}

      {:error, %Ecto.Changeset{data: %Lotus.Storage.Dashboard{}} = changeset} ->
        form = to_form(changeset, as: "dashboard")
        send(self(), {:put_flash, [:error, gettext("Failed to save dashboard")]})
        {:noreply, assign(socket, dashboard_form: form)}

      {:error, %Ecto.Changeset{data: %Lotus.Storage.DashboardFilter{}} = changeset} ->
        send(self(), {:put_flash, [:error, filter_save_error(changeset)]})
        {:noreply, socket}

      {:error, {:halted, reason}} ->
        send(self(), {:put_flash, [:error, refused_message(reason)]})
        {:noreply, socket}

      {:error, _reason} ->
        send(self(), {:put_flash, [:error, gettext("Failed to save dashboard")]})
        {:noreply, socket}
    end
  end

  defp filter_save_error(changeset) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
      |> Enum.map_join("; ", fn {field, messages} ->
        "#{field} #{Enum.join(messages, ", ")}"
      end)

    name = Ecto.Changeset.get_field(changeset, :name)
    gettext("Failed to save filter %{name}: %{errors}", name: name, errors: errors)
  end

  # The dashboard, its cards, filters and filter mappings save in one
  # transaction, so a refused or failed write part way leaves nothing saved.
  defp perform_save_dashboard(socket, attrs, dashboard) do
    opts = Actor.opts(socket.assigns)

    Lotus.repo().transaction(fn ->
      case write_dashboard(socket.assigns.page, attrs, dashboard, opts) do
        {:ok, saved} -> saved
        {:error, reason} -> Lotus.repo().rollback(reason)
      end
    end)
  end

  defp write_dashboard(%{mode: :new}, attrs, dashboard, opts) do
    with {:ok, saved} <- Lotus.create_dashboard(attrs, opts),
         :ok <- sync_contents(saved, dashboard, opts),
         do: {:ok, saved}
  end

  defp write_dashboard(%{mode: :edit, id: id}, attrs, dashboard, opts) do
    with %{} = existing <- Lotus.get_dashboard(id) || {:error, :not_found},
         {:ok, saved} <- Lotus.update_dashboard(existing, attrs, opts),
         :ok <- sync_contents(saved, dashboard, opts),
         do: {:ok, saved}
  end

  defp sync_contents(saved, dashboard, opts) do
    with :ok <- sync_cards(saved, dashboard.cards, opts),
         :ok <- sync_filters(saved, dashboard.filters, opts) do
      sync_card_filter_mappings(saved, dashboard.cards, opts)
    end
  end

  defp do_delete_dashboard(socket) do
    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = dashboard <- Lotus.get_dashboard(id),
         {:ok, _} <- Lotus.delete_dashboard(dashboard, Actor.opts(socket.assigns)) do
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

      {:error, {:halted, reason}} ->
        send(self(), {:put_flash, [:error, refused_message(reason)]})
        {:noreply, assign(socket, delete_modal_open: false)}

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

  # Every card run goes through here when the runner has a free slot: the first
  # load, refresh, auto-refresh and a filter change. Viewing a dashboard does
  # not grant running its queries.
  defp prepare_card(socket, card_id) do
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    if should_run_card?(card) do
      authorize_card_query(socket, card_id, card)
    else
      {:skip, socket}
    end
  end

  defp authorize_card_query(socket, card_id, card) do
    source = card.query.data_source || elem(Lotus.default_data_source(), 0)

    case Authorization.authorize(socket.assigns, :query, source) do
      :allow ->
        query = card.query
        opts = Actor.merge([vars: build_card_variables(socket, card)], socket.assigns)
        {:run, fn -> Lotus.run_query(query, opts) end}

      {:deny, reason} ->
        {:skip, put_card_error(socket, card_id, reason)}
    end
  end

  defp put_card_result(socket, card_id, {:ok, {:ok, result}}) do
    socket =
      if socket.assigns.selected_card && socket.assigns.selected_card.id == card_id do
        assign(socket, selected_card_columns: Map.get(result, :columns, []))
      else
        socket
      end

    assign(socket,
      card_results: Map.put(socket.assigns.card_results, card_id, result),
      card_errors: Map.delete(socket.assigns.card_errors, card_id)
    )
  end

  defp put_card_result(socket, card_id, {:ok, {:error, error}}) do
    put_card_error(socket, card_id, to_string(error))
  end

  defp put_card_result(socket, card_id, {:exit, reason}) do
    put_card_error(
      socket,
      card_id,
      gettext("Query execution failed: %{reason}", reason: inspect(reason))
    )
  end

  defp put_card_error(socket, card_id, message) do
    assign(socket,
      card_errors: Map.put(socket.assigns.card_errors, card_id, message),
      card_results: Map.delete(socket.assigns.card_results, card_id)
    )
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

  defp leave(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: lotus_path("", %{tab: "dashboards"}))
  end

  # A dashboard that is not saved yet has no resource to authorize against.
  defp dashboard_resource(%{mode: :edit}, dashboard), do: dashboard
  defp dashboard_resource(_page, _dashboard), do: nil

  # The flash belongs to the parent LiveView, so a component asks it to set one.
  defp deny(socket, reason) do
    send(self(), {:put_flash, [:error, reason]})
    socket
  end

  defp authorize_manage(socket, fun) do
    resource = dashboard_resource(socket.assigns.page, socket.assigns.dashboard)

    case Authorization.authorize(socket.assigns, :manage_dashboard, resource) do
      :allow -> fun.()
      {:deny, reason} -> {:noreply, deny(socket, reason)}
    end
  end

  defp do_select_card(socket, card_id) do
    card_id = parse_id(card_id)
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    {:noreply,
     assign(socket,
       selected_card: card,
       selected_card_columns: card_columns(socket, card),
       card_settings_visible: card != nil
     )}
  end

  defp do_open_card_settings(socket, card_id) do
    card_id = parse_id(card_id)
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    {:noreply,
     assign(socket,
       selected_card: card,
       selected_card_columns: card_columns(socket, card),
       card_settings_visible: true,
       settings_visible: false
     )}
  end

  defp card_columns(socket, %{card_type: :query, id: card_id}) do
    case Map.get(socket.assigns.card_results, card_id) do
      %{columns: cols} -> cols
      _ -> []
    end
  end

  defp card_columns(_socket, _card), do: []

  defp do_delete_card(socket, card_id) do
    card_id = parse_id(card_id)
    dashboard = socket.assigns.dashboard
    updated_cards = Enum.reject(dashboard.cards, &(&1.id == card_id))
    updated_dashboard = %{dashboard | cards: updated_cards}

    {:noreply,
     socket
     |> assign(dashboard: updated_dashboard)
     |> assign(card_settings_visible: false, selected_card: nil)}
  end

  defp do_update_card_content(socket, card_id, content, card_type) do
    case parse_card_type(card_type) do
      nil ->
        {:noreply, socket}

      card_type ->
        formatted_content =
          case card_type do
            :link -> %{"url" => content}
            :text -> %{"text" => content}
            :heading -> %{"text" => content}
            :query -> content
          end

        socket =
          update_card_and_selection(socket, parse_id(card_id), fn card ->
            %{card | content: formatted_content}
          end)

        {:noreply, socket}
    end
  end

  defp do_update_card_layout(socket, card_id, layout) do
    layout = %{
      x: parse_int(layout["x"], 0),
      y: parse_int(layout["y"], 0),
      w: parse_int(layout["w"], 6),
      h: parse_int(layout["h"], 4)
    }

    {:noreply,
     update_card_and_selection(socket, parse_id(card_id), fn card -> %{card | layout: layout} end)}
  end

  defp do_update_card_visualization(socket, card_id, viz) do
    socket =
      update_card_and_selection(socket, parse_id(card_id), fn card ->
        existing =
          (card.visualization_config || %{})
          |> Map.new(fn {k, v} -> {to_string(k), v} end)

        config = VegaSpecBuilder.build_config(Map.merge(existing, viz))
        %{card | visualization_config: config}
      end)

    {:noreply, socket}
  end

  defp do_update_filter_mapping(socket, card_id, filter_name, variable_name) do
    socket =
      update_card_and_selection(socket, parse_id(card_id), fn card ->
        mappings = normalize_mappings(card.filter_mappings, socket.assigns.dashboard.filters)
        updated_mappings = Map.put(mappings, filter_name, variable_name)
        %{card | filter_mappings: updated_mappings}
      end)

    {:noreply, socket}
  end

  defp do_add_filter(socket) do
    next_position = length(socket.assigns.dashboard.filters)

    new_filter = %{
      id: "new_#{System.unique_integer([:positive])}",
      name: "",
      label: "",
      filter_type: :text,
      widget: :input,
      default_value: nil,
      config: %{},
      position: next_position,
      source_query_id: nil,
      depends_on_filter_id: nil
    }

    {:noreply,
     assign(socket, filter_modal_open: true, editing_filter: new_filter, filter_errors: %{})}
  end

  defp do_edit_filter(socket, filter_id) do
    filter_id = maybe_parse_id(filter_id)

    case Enum.find(socket.assigns.dashboard.filters, &(&1.id == filter_id)) do
      nil ->
        {:noreply, socket}

      filter ->
        {:noreply,
         assign(socket, filter_modal_open: true, editing_filter: filter, filter_errors: %{})}
    end
  end

  defp do_save_filter(socket, filter_params) do
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

    filter =
      Map.merge(filter, %{
        source_query_id: parse_optional_id(filter_params["source_query_id"]),
        depends_on_filter_id: parse_optional_id(filter_params["depends_on_filter_id"])
      })

    case filter_dependency_errors(filter, dashboard.filters) do
      errors when errors == %{} ->
        dashboard = %{dashboard | filters: upsert_filter(dashboard.filters, filter)}

        {:noreply,
         socket
         |> assign(dashboard: dashboard, filter_modal_open: false, editing_filter: nil)
         |> assign_filter_options()
         |> run_all_cards()}

      errors ->
        {:noreply, assign(socket, editing_filter: filter, filter_errors: errors)}
    end
  end

  # The checks core runs when the dashboard saves, run here on the filters not
  # saved yet, so the filter editor shows the error next to the field.
  defp filter_dependency_errors(filter, filters) do
    parent_id = filter.depends_on_filter_id

    cond do
      filter.source_query_id != nil and filter.widget != :select ->
        %{source_query_id: gettext("needs the select widget")}

      parent_id == nil ->
        %{}

      filter.source_query_id == nil ->
        %{depends_on_filter_id: gettext("needs a source query")}

      parent_id == filter.id ->
        %{depends_on_filter_id: gettext("cannot be the filter itself")}

      not Enum.any?(filters, &(&1.id == parent_id)) ->
        %{depends_on_filter_id: gettext("must be a filter of the same dashboard")}

      dependency_reaches?(parent_id, filter.id, filters, length(filters)) ->
        %{depends_on_filter_id: gettext("would create a dependency cycle")}

      true ->
        %{}
    end
  end

  defp dependency_reaches?(nil, _target_id, _filters, _steps_left), do: false
  defp dependency_reaches?(target_id, target_id, _filters, _steps_left), do: true
  defp dependency_reaches?(_id, _target_id, _filters, 0), do: false

  defp dependency_reaches?(id, target_id, filters, steps_left) do
    parent_id =
      Enum.find_value(filters, fn filter ->
        if filter.id == id, do: Map.get(filter, :depends_on_filter_id)
      end)

    dependency_reaches?(parent_id, target_id, filters, steps_left - 1)
  end

  defp parse_optional_id(id) when id in [nil, ""], do: nil
  defp parse_optional_id(id), do: maybe_parse_id(id)

  defp assign_filter_options(socket) do
    {filter_options, filter_values} =
      FilterOptions.resolve(socket.assigns.dashboard.filters, socket.assigns.filter_values,
        run_opts: Actor.opts(socket.assigns),
        authorize: &authorize_source_query(socket, &1)
      )

    assign(socket, filter_options: filter_options, filter_values: filter_values)
  end

  # A source query runs like a card query, so it needs :query on its source.
  defp authorize_source_query(socket, query_id) do
    query =
      Enum.find(socket.assigns.available_queries, &(&1.id == query_id)) ||
        Lotus.get_query(query_id)

    case query do
      nil ->
        {:deny, gettext("Source query not found")}

      query ->
        source = query.data_source || elem(Lotus.default_data_source(), 0)
        Authorization.authorize(socket.assigns, :query, source)
    end
  end

  defp do_delete_filter(socket, filter_id) do
    filter_id = maybe_parse_id(filter_id)
    dashboard = socket.assigns.dashboard

    # Core sets the dependency to nil when the parent is deleted, so the
    # filters not saved yet do the same.
    filters =
      for filter <- dashboard.filters, filter.id != filter_id do
        if Map.get(filter, :depends_on_filter_id) == filter_id,
          do: Map.put(filter, :depends_on_filter_id, nil),
          else: filter
      end

    dashboard = %{dashboard | filters: filters}

    filter_name =
      Enum.find_value(socket.assigns.dashboard.filters, fn f ->
        if f.id == filter_id, do: f.name
      end)

    filter_values = Map.drop(socket.assigns.filter_values, [filter_name])

    {:noreply,
     socket
     |> assign(dashboard: dashboard, filter_values: filter_values)
     |> assign_filter_options()
     |> run_all_cards()}
  end

  defp do_update_auto_refresh(socket, seconds) do
    seconds = if seconds == "", do: nil, else: String.to_integer(seconds)
    dashboard = %{socket.assigns.dashboard | auto_refresh_seconds: seconds}
    {:noreply, assign(socket, dashboard: dashboard)}
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

  defp run_card(socket, card_id), do: CardRunner.run(socket, card_id, &prepare_card/2)

  defp run_all_cards(socket) do
    card_ids =
      for card <- socket.assigns.dashboard.cards,
          card.card_type == :query && card.query_id,
          do: card.id

    CardRunner.run_all(socket, card_ids, &prepare_card/2)
  end

  defp generate_temp_id do
    :erlang.unique_integer([:positive])
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

  # Runs each write in turn and stops at the first error, so the save can roll
  # back and report it. A write returns `{:ok, _}`, `:ok` or `{:error, _}`.
  defp each_write(items, write) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case write.(item) do
        {:error, _reason} = error -> {:halt, error}
        _written -> {:cont, :ok}
      end
    end)
  end

  # Sync cards: delete removed, update existing, create new
  defp sync_cards(saved_dashboard, cards, opts) do
    existing_cards = Lotus.list_dashboard_cards(saved_dashboard.id)
    existing_ids = MapSet.new(existing_cards, & &1.id)

    # Cards with integer IDs are existing, others are new (temp IDs)
    {existing_card_updates, new_cards} =
      Enum.split_with(cards, fn card ->
        is_integer(card.id) and MapSet.member?(existing_ids, card.id)
      end)

    current_ids = MapSet.new(existing_card_updates, & &1.id)
    cards_to_delete = Enum.reject(existing_cards, &MapSet.member?(current_ids, &1.id))

    with :ok <- each_write(cards_to_delete, &Lotus.delete_dashboard_card(&1, opts)),
         :ok <- each_write(existing_card_updates, &write_stored_card(&1, existing_cards, opts)) do
      each_write(new_cards, fn card ->
        Lotus.create_dashboard_card(saved_dashboard.id, card_to_attrs(card), opts)
      end)
    end
  end

  defp write_stored_card(card, existing_cards, opts) do
    case Enum.find(existing_cards, &(&1.id == card.id)) do
      nil -> :ok
      existing_card -> Lotus.update_dashboard_card(existing_card, card_to_attrs(card), opts)
    end
  end

  defp sync_filters(saved_dashboard, filters, opts) do
    existing_filters = Lotus.list_dashboard_filters(saved_dashboard.id)
    existing_ids = MapSet.new(existing_filters, & &1.id)

    {existing_filter_updates, new_filters} =
      Enum.split_with(filters, fn filter ->
        is_integer(filter.id) and MapSet.member?(existing_ids, filter.id)
      end)

    current_ids = MapSet.new(existing_filter_updates, & &1.id)
    filters_to_delete = Enum.reject(existing_filters, &MapSet.member?(current_ids, &1.id))

    with :ok <- each_write(filters_to_delete, &Lotus.delete_dashboard_filter(&1, opts)),
         :ok <- each_write(existing_filter_updates, &update_filter(&1, existing_filters, opts)),
         {:ok, saved_ids} <- create_filters(saved_dashboard, new_filters, opts) do
      link_filter_dependencies(saved_dashboard, filters, saved_ids, opts)
    end
  end

  # A new or changed dependency is written in a second pass: the parent can be
  # a filter created in this save, and two filters can swap their dependency.
  defp update_filter(filter, existing_filters, opts) do
    case Enum.find(existing_filters, &(&1.id == filter.id)) do
      nil ->
        :ok

      existing ->
        attrs = filter_to_attrs(filter)

        attrs =
          if filter.depends_on_filter_id == existing.depends_on_filter_id,
            do: attrs,
            else: %{attrs | depends_on_filter_id: nil}

        Lotus.update_dashboard_filter(existing, attrs, opts)
    end
  end

  defp create_filters(saved_dashboard, new_filters, opts) do
    Enum.reduce_while(new_filters, {:ok, %{}}, fn filter, {:ok, saved_ids} ->
      attrs = %{filter_to_attrs(filter) | depends_on_filter_id: nil}

      case Lotus.create_dashboard_filter(saved_dashboard, attrs, opts) do
        {:ok, saved} -> {:cont, {:ok, Map.put(saved_ids, filter.id, saved.id)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp link_filter_dependencies(saved_dashboard, filters, saved_ids, opts) do
    saved_filters = Map.new(Lotus.list_dashboard_filters(saved_dashboard.id), &{&1.id, &1})

    each_write(filters, fn filter ->
      saved = Map.get(saved_filters, Map.get(saved_ids, filter.id, filter.id))
      parent_id = filter.depends_on_filter_id
      parent_id = Map.get(saved_ids, parent_id, parent_id)

      if saved == nil or saved.depends_on_filter_id == parent_id,
        do: :ok,
        else: Lotus.update_dashboard_filter(saved, %{depends_on_filter_id: parent_id}, opts)
    end)
  end

  defp sync_card_filter_mappings(saved_dashboard, cards, opts) do
    saved_cards = Lotus.list_dashboard_cards(saved_dashboard.id)
    saved_filters = Lotus.list_dashboard_filters(saved_dashboard.id)
    filter_by_name = Map.new(saved_filters, &{&1.name, &1})

    cards
    |> Enum.filter(&is_map(&1.filter_mappings))
    |> each_write(&sync_single_card_mappings(&1, saved_cards, filter_by_name, opts))
  end

  defp sync_single_card_mappings(card, saved_cards, filter_by_name, opts) do
    case Enum.find(saved_cards, &match_card?(&1, card)) do
      nil -> :ok
      saved_card -> replace_card_mappings(saved_card, card.filter_mappings, filter_by_name, opts)
    end
  end

  defp replace_card_mappings(saved_card, mappings, filter_by_name, opts) do
    existing_mappings = Lotus.list_card_filter_mappings(saved_card.id)

    with :ok <- each_write(existing_mappings, &Lotus.delete_filter_mapping(&1, opts)) do
      each_write(mappings, fn {filter_name, variable_name} ->
        create_mapping(saved_card, Map.get(filter_by_name, filter_name), variable_name, opts)
      end)
    end
  end

  defp create_mapping(_card, nil, _variable_name, _opts), do: :ok

  defp create_mapping(_card, _filter, variable_name, _opts) when variable_name in [nil, ""],
    do: :ok

  defp create_mapping(card, filter, variable_name, opts),
    do: Lotus.create_filter_mapping(card.id, filter.id, variable_name, opts)

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
    push_event(socket, "update-query-params", %{params: FilterValues.to_params(filter_values)})
  end

  defp extract_filter_values(params, filters), do: FilterValues.from_params(params, filters)

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
      config: filter.config,
      source_query_id: Map.get(filter, :source_query_id),
      depends_on_filter_id: Map.get(filter, :depends_on_filter_id)
    }
  end
end
