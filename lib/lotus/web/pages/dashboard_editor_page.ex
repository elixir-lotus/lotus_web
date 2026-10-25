defmodule Lotus.Web.DashboardEditorPage do
  @moduledoc """
  Main dashboard editor page for creating and editing dashboards.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Actor
  alias Lotus.Web.Authorization
  alias Lotus.Web.Charts
  alias Lotus.Web.Dashboards.AddCardModal
  alias Lotus.Web.Dashboards.CardGridComponent
  alias Lotus.Web.Dashboards.CardRunner
  alias Lotus.Web.Dashboards.CardSettingsDrawer
  alias Lotus.Web.Dashboards.CardVariables
  alias Lotus.Web.Dashboards.ChartFilters
  alias Lotus.Web.Dashboards.Components
  alias Lotus.Web.Dashboards.DateTokens
  alias Lotus.Web.Dashboards.Duplicate
  alias Lotus.Web.Dashboards.FilterBarComponent
  alias Lotus.Web.Dashboards.FilterConnections
  alias Lotus.Web.Dashboards.FilterOptions
  alias Lotus.Web.Dashboards.FilterValues
  alias Lotus.Web.Dashboards.SettingsDrawer
  alias Lotus.Web.Dashboards.Tabs
  alias Lotus.Web.Dashboards.TextCard
  alias Lotus.Web.Page
  alias Lotus.Web.Pro
  alias Lotus.Web.RichText
  alias Lotus.Web.Telemetry

  @impl Phoenix.LiveComponent
  def render(assigns) do
    resource = dashboard_resource(assigns.page, assigns.dashboard)

    assigns =
      assign(assigns,
        can_manage: Authorization.allowed?(assigns, :manage_dashboard, resource),
        can_share: resource != nil and Authorization.allowed?(assigns, :share_dashboard, resource)
      )

    ~H"""
    <div id="dashboard-editor" class={["flex flex-col h-full overflow-hidden", @editing && "lotus-dashboard-editing"]}>
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full flex flex-col">
        <div class="lotus-dashboard bg-gray-50 dark:bg-gray-900 shadow-sm ring-1 ring-black/5 dark:ring-white/10 rounded-lg h-full flex flex-col overflow-hidden">

          <%!-- Edit mode: what can be added, Cancel and Save --%>
          <Components.edit_bar
            :if={@editing}
            name={@page.mode == :edit && @dashboard.name}
            target={@myself}
          />

          <%!-- Its name and description, when its data was read, and what a
               viewer may do: refresh, share, edit --%>
          <Components.dashboard_head
            dashboard={@dashboard}
            title={@page.mode == :new && blank?(@dashboard.name) && gettext("New Dashboard")}
            back={lotus_path("", %{tab: "dashboards"})}
            refreshed_at={@refreshed_at}
            running={MapSet.size(@running_cards) > 0}
          >
            <:actions :if={not @editing}>
              <.pro_slot
                :if={@page.mode == :edit}
                name={:dashboard_header}
                slot_assigns={%{dashboard: @dashboard, info: Lotus.Web.Pro.request_info(assigns)}}
              />
              <button
                type="button"
                phx-click="refresh_all_cards"
                phx-target={@myself}
                class="p-2 rounded-lg text-gray-500 hover:text-gray-700 hover:bg-gray-200/60 dark:text-gray-400 dark:hover:text-gray-200 dark:hover:bg-gray-700"
                title={gettext("Refresh all cards")}
                aria-label={gettext("Refresh all cards")}
              >
                <Icons.rotate_ccw class="h-5 w-5" />
              </button>
              <Components.fullscreen_button :if={@dashboard.cards != []} />
              <.link
                :if={@dashboard.id && :schedules in (@features || []) && Authorization.allowed?(assigns, :manage_schedule)}
                id="schedule-dashboard"
                navigate={lotus_path(["schedules", "new"], %{"dashboard_id" => @dashboard.id})}
                class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-white px-3 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50 hover:text-gray-900 dark:bg-gray-800 dark:text-gray-200 dark:ring-gray-700 dark:hover:bg-gray-700"
              >
                <Icons.clock class="h-4 w-4" /> <%= gettext("Send on a schedule") %>
              </.link>
              <Components.head_button :if={@can_share} phx-click="toggle_settings" phx-target={@myself}>
                <Icons.share class="h-4 w-4" /> <%= gettext("Share") %>
              </Components.head_button>
              <Components.head_button
                :if={@can_manage and @page.mode == :edit}
                id="dashboard-duplicate"
                phx-click="duplicate"
                phx-target={@myself}
                title={gettext("A copy of this dashboard, to change on its own")}
              >
                <Icons.clipboard_copy class="h-4 w-4" /> <%= gettext("Duplicate") %>
              </Components.head_button>
              <Components.head_button
                :if={@can_manage}
                id="dashboard-edit"
                phx-click="edit"
                phx-target={@myself}
              >
                <Icons.pencil class="h-4 w-4" /> <%= gettext("Edit") %>
              </Components.head_button>
            </:actions>
          </Components.dashboard_head>

          <%!-- Filter Bar. `public` hides the controls that edit filters. --%>
          <.live_component
            :if={@editing or @dashboard.filters != []}
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            filter_options={@filter_options}
            public={not @editing}
            connecting={@connecting}
            connections={FilterConnections.counts(@dashboard.filters, @dashboard.cards)}
            parent={@myself}
          />

          <Components.tab_bar
            tabs={Tabs.list(@dashboard)}
            current={Tabs.current(@dashboard, @tab)}
            editing={@editing}
            target={@myself}
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
              info={Pro.request_info(assigns)}
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
              "h-full overflow-y-auto px-4 sm:px-6 pt-2 pb-6 transition-all duration-300",
              (@settings_visible || @card_settings_visible) && "sm:mr-80"
            ]}>
              <%= if Tabs.cards(@dashboard, Tabs.current(@dashboard, @tab)) != [] do %>
                <.live_component
                  module={CardGridComponent}
                  id="card-grid"
                  dashboard_id={@dashboard.id}
                  values={text_values(@dashboard.filters, @filter_values)}
                  cards={Tabs.cards(@dashboard, Tabs.current(@dashboard, @tab))}
                  tabs={Tabs.list(@dashboard)}
                  tab={Tabs.current(@dashboard, @tab)}
                  card_results={@card_results}
                  card_errors={@card_errors}
                  running_cards={@running_cards}
                  selected_card_id={@selected_card && @selected_card.id}
                  can_manage={@can_manage and @editing}
                  connecting={@editing && Enum.find(@dashboard.filters, &(&1.name == @connecting))}
                  filters={@dashboard.filters}
                  pro_info={Pro.request_info(assigns)}
                  parent={@myself}
                />
              <% end %>

              <%!-- Add Card Button --%>
              <button
                :if={@can_manage and @editing}
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
        type={@add_card_type}
        pro_info={Pro.request_info(assigns)}
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

  defp save_modal(assigns) do
    ~H"""
    <.modal id="save-dashboard-modal" show on_cancel={JS.push("close_save_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        <%= if @mode == :new, do: gettext("Save Dashboard"), else: gettext("Update Dashboard") %>
      </h3>

      <.form for={@dashboard_form}
             id="save-dashboard-form"
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
          <div>
            <label
              id="dashboard-description-label"
              class="block text-sm font-semibold leading-6 text-text-light dark:text-text-dark"
            >
              <%= gettext("Description") %>
            </label>
            <div class="mt-2">
              <Kotoba.Components.kotoba
                field={description_field(@dashboard_form[:description])}
                id="dashboard-description-editor"
                label_id="dashboard-description-label"
                placeholder={gettext("Describe the dashboard (optional)")}
                features={RichText.features(:description, nil)}
              />
            </div>
          </div>
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
        default_value: FilterValues.range_value(assigns.filter.default_value),
        locale: Gettext.get_locale(Lotus.Web.Gettext),
        parent_choices: Enum.reject(assigns.filters, &(&1.id == assigns.filter.id))
      )

    ~H"""
    <.modal id="filter-modal" show on_cancel={JS.push("close_filter_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
        <%= if @is_new, do: gettext("Add Filter"), else: gettext("Edit Filter") %>
      </h3>

      <form
        id="dashboard-filter-form"
        phx-change="filter_form_changed"
        phx-submit="save_filter"
        phx-target={@parent}
      >
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
            <.filter_field_error errors={@errors} field={:name} />
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
            <label
              id="filter-default-label"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
            >
              <%= gettext("Default Value") %>
            </label>
            <%= case @filter.filter_type do %>
              <% :date -> %>
                <Koyomi.Components.date_picker
                  id="filter-default-date"
                  name="filter[default_value]"
                  value={@filter.default_value}
                  label_id="filter-default-label"
                  relative
                  presets={DateTokens.presets(:date)}
                  first_day={1}
                  locale={@locale}
                />
              <% :date_range -> %>
                <Koyomi.Components.date_range_picker
                  id="filter-default-range"
                  name="filter[default_value]"
                  value={@default_value}
                  label_id="filter-default-label"
                  keys={{"start", "end"}}
                  relative
                  presets={DateTokens.presets(:date_range)}
                  first_day={1}
                  locale={@locale}
                />
              <% _ -> %>
                <input
                  type="text"
                  name="filter[default_value]"
                  value={@filter.default_value || ""}
                  placeholder={gettext("Optional")}
                  aria-labelledby="filter-default-label"
                  class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
                />
            <% end %>
            <.filter_field_error errors={@errors} field={:default_value} />
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
      run_date: Date.utc_today(),
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
      available_queries: socket.assigns |> Pro.request_info() |> Pro.list_queries(),
      auto_refresh_ref: nil,
      current_uri: nil,
      # View mode, unless the dashboard is new; Edit keeps the dashboard as
      # it was, for Cancel.
      editing: false,
      saved_dashboard: nil,
      add_card_type: :query,
      refreshed_at: nil,
      # The filter being connected to the cards, by name.
      connecting: nil,
      # The tab shown, by its id: the first when nil.
      tab: nil
    )
  end

  @impl Page
  def handle_params(params, uri, socket) do
    socket = assign(socket, current_uri: uri)

    case socket.assigns.page do
      %{mode: :new} ->
        case Authorization.authorize(socket.assigns, :manage_dashboard) do
          :allow ->
            {:noreply,
             socket
             |> assign_dashboard(new_dashboard())
             |> assign(editing: true, saved_dashboard: nil)}

          {:deny, reason} ->
            {:noreply, leave(socket, reason)}
        end

      %{mode: :edit, id: id} ->
        with %{} = dashboard <- load_dashboard(id, Actor.opts(socket.assigns)),
             :allow <- Authorization.authorize(socket.assigns, :view_dashboard, dashboard) do
          filter_values = extract_filter_values(params, dashboard.filters)
          report_view(socket, dashboard)

          {:noreply,
           socket
           |> assign_dashboard(dashboard)
           |> watch()
           |> assign(filter_values: filter_values, editing: false, saved_dashboard: nil)
           |> close_editors()
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
  def handle_event("show_add_card_modal", params, socket) do
    type = parse_card_type(params["type"] || "query") || :query
    {:noreply, assign(socket, add_card_modal_open: true, add_card_type: type)}
  end

  # Edit mode: the dashboard as it is now is kept, for Cancel.
  @impl Phoenix.LiveComponent
  def handle_event("edit", _params, socket) do
    authorize_manage(socket, fn ->
      %{dashboard: dashboard} = socket.assigns

      # A heading card from before is edited as a text card with a heading.
      editing = %{dashboard | cards: Enum.map(dashboard.cards, &TextCard.as_text/1)}

      {:noreply, assign(socket, editing: true, saved_dashboard: dashboard, dashboard: editing)}
    end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("cancel_edit", _params, socket) do
    case socket.assigns do
      %{page: %{mode: :new}} ->
        {:noreply, push_navigate(socket, to: lotus_path("", %{tab: "dashboards"}))}

      %{saved_dashboard: %{} = saved} ->
        {:noreply,
         socket
         |> assign_dashboard(saved)
         |> assign(editing: false, saved_dashboard: nil)
         |> close_editors()
         |> run_all_cards()}

      _ ->
        {:noreply, assign(socket, editing: false)}
    end
  end

  # Save: a new dashboard asks for its name; one that has it saves at once.
  @impl Phoenix.LiveComponent
  def handle_event("save", _params, %{assigns: %{page: %{mode: :new}}} = socket) do
    handle_event("show_save_modal", %{}, socket)
  end

  def handle_event("save", _params, socket) do
    %{dashboard: dashboard} = socket.assigns

    handle_event(
      "save_dashboard",
      %{"dashboard" => %{"name" => dashboard.name, "description" => dashboard.description}},
      socket
    )
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

      socket =
        case card_type do
          {:pro, kind} -> add_pro_card(socket, kind)
          card_type -> add_card(socket, card_type, query_id)
        end

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

  # The Kotoba editor of a text card pushes its document on each change; the
  # card keeps its text as Markdown.
  @impl Phoenix.LiveComponent
  def handle_event("kotoba:change", %{"id" => "card-text-" <> card_id, "doc" => doc}, socket) do
    authorize_manage(socket, fn ->
      do_update_card_content(socket, card_id, RichText.to_markdown(doc), "text")
    end)
  end

  def handle_event("kotoba:change", _params, socket), do: {:noreply, socket}

  # The grid moved or resized cards (`DashboardGrid`): their new places.
  @impl Phoenix.LiveComponent
  def handle_event("update_layouts", %{"layouts" => layouts}, socket) when is_map(layouts) do
    authorize_manage(socket, fn -> {:noreply, update_layouts(socket, layouts)} end)
  end

  # How a card starts, folded to its title or open, for everyone.
  @impl Phoenix.LiveComponent
  def handle_event("fold_card", %{"card_id" => card_id, "folded" => folded}, socket) do
    authorize_manage(socket, fn ->
      {:noreply,
       update_card_and_selection(socket, parse_id(card_id), fn card ->
         %{card | layout: Map.put(card_layout(card), :folded, folded == true)}
       end)}
    end)
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

  # A click on a chart's mark filters the dashboard by it.
  @impl Phoenix.LiveComponent
  def handle_event("chart_select", params, socket) do
    %{dashboard: dashboard, filter_values: filter_values} = socket.assigns

    case ChartFilters.click(dashboard.cards, dashboard.filters, filter_values, params) do
      {:ok, values} -> {:noreply, apply_filter_values(socket, values)}
      :none -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("filter_changed", %{"filter" => filter_values}, socket) do
    {:noreply, apply_filter_values(socket, FilterValues.normalize(filter_values))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_filter", _params, socket) do
    authorize_manage(socket, fn -> do_add_filter(socket) end)
  end

  # Tabs: a tab shows its cards; in edit mode they are added, renamed,
  # removed, and a card moves to another.
  @impl Phoenix.LiveComponent
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> close_editors() |> assign(tab: tab)}
  end

  def handle_event("add_tab", _params, socket) do
    authorize_manage(socket, fn ->
      {dashboard, tab} = Tabs.add(socket.assigns.dashboard)
      {:noreply, socket |> close_editors() |> assign(dashboard: dashboard, tab: tab)}
    end)
  end

  def handle_event("rename_tab", %{"tab" => tab, "name" => name}, socket) do
    authorize_manage(socket, fn ->
      {:noreply, assign(socket, dashboard: Tabs.rename(socket.assigns.dashboard, tab, name))}
    end)
  end

  def handle_event("delete_tab", %{"tab" => tab}, socket) do
    authorize_manage(socket, fn ->
      {:noreply,
       socket
       |> close_editors()
       |> assign(dashboard: Tabs.delete(socket.assigns.dashboard, tab), tab: nil)}
    end)
  end

  def handle_event("move_card_to_tab", %{"card-id" => card_id, "tab" => tab}, socket) do
    authorize_manage(socket, fn ->
      dashboard = Tabs.move_card(socket.assigns.dashboard, parse_id(card_id), tab)
      {:noreply, socket |> close_editors() |> assign(dashboard: dashboard)}
    end)
  end

  # A copy of the saved dashboard, opened at once.
  @impl Phoenix.LiveComponent
  def handle_event("duplicate", _params, socket) do
    authorize_manage(socket, fn ->
      with %{mode: :edit, id: id} <- socket.assigns.page,
           {:ok, copy} <- Duplicate.copy(id, Actor.opts(socket.assigns)) do
        {:noreply,
         socket
         |> put_flash(:info, gettext("A copy of the dashboard, to change on its own."))
         |> push_navigate(to: lotus_path(["dashboards", copy.id]))}
      else
        _ -> {:noreply, put_flash(socket, :error, gettext("The dashboard could not be copied."))}
      end
    end)
  end

  # Connecting a filter: each card shows what the filter sets in it.
  @impl Phoenix.LiveComponent
  def handle_event("connect_filter", %{"filter-name" => name}, socket) do
    authorize_manage(socket, fn ->
      connecting = if socket.assigns.connecting == name, do: nil, else: name

      {:noreply,
       socket
       |> close_editors()
       |> assign(connecting: connecting)}
    end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("stop_connecting", _params, socket) do
    {:noreply, assign(socket, connecting: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("edit_filter", %{"filter-id" => filter_id}, socket) do
    authorize_manage(socket, fn -> do_edit_filter(socket, filter_id) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("close_filter_modal", _params, socket) do
    {:noreply,
     assign(socket,
       filter_modal_open: false,
       editing_filter: nil,
       filter_errors: %{}
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("filter_form_changed", %{"filter" => filter_params}, socket) do
    authorize_manage(socket, fn -> do_change_filter_form(socket, filter_params) end)
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
     socket
     |> assign(running_cards: running_cards, card_results: card_results, card_errors: card_errors)
     |> mark_refreshed()}
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
      {:ok, socket} -> {:noreply, socket |> put_card_result(card_id, result) |> mark_refreshed()}
      :stale -> {:noreply, socket}
    end
  end

  # A view is counted once per connected page load, not on each patch.
  defp report_view(socket, %{id: id} = dashboard) do
    if connected?(socket) and not match?(%{id: ^id}, socket.assigns.dashboard),
      do:
        Telemetry.dashboard_view(
          dashboard,
          false,
          socket.assigns[:context],
          socket.assigns[:client]
        )
  end

  # Pro's live updates of the dashboard's cards (`Lotus.Web.Pro.watch_dashboard/2`).
  defp watch(socket) do
    if connected?(socket), do: Pro.watch_dashboard(socket.assigns.dashboard, self())
    socket
  end

  # When the last card running has its result, the dashboard was read.
  defp mark_refreshed(socket) do
    if MapSet.size(socket.assigns.running_cards) == 0,
      do: assign(socket, refreshed_at: DateTime.utc_now()),
      else: socket
  end

  # Leaving edit mode closes what edits.
  defp close_editors(socket) do
    assign(socket,
      selected_card: nil,
      selected_card_columns: [],
      card_settings_visible: false,
      settings_visible: false,
      add_card_modal_open: false,
      filter_modal_open: false,
      connecting: nil
    )
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    if socket.assigns[:initialized] do
      # Component already initialized - only accept specific assigns from parent:
      # - Core routing/auth assigns
      # - Async task results (running_cards, card_results, card_errors, and
      #   refreshed_at, when the last of them came) that are
      #   updated by handle_async on the LiveView level
      keys_from_parent = [
        :page,
        :params,
        :user,
        :access,
        :running_cards,
        :card_results,
        :card_errors,
        :refreshed_at
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
         %{} = existing <- Lotus.get_dashboard(id, Actor.opts(socket.assigns)),
         {:ok, saved} <- Lotus.enable_public_sharing(existing, Actor.opts(socket.assigns)) do
      sharing_changed(socket, saved.public_token, gettext("Public sharing enabled"))
    else
      error -> sharing_failed(socket, error, gettext("Failed to enable sharing"))
    end
  end

  defp do_disable_sharing(socket) do
    with %{mode: :edit, id: id} <- socket.assigns.page,
         %{} = existing <- Lotus.get_dashboard(id, Actor.opts(socket.assigns)),
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

  defp description_param(value) do
    case RichText.to_markdown(value) do
      "" -> nil
      markdown -> markdown
    end
  end

  defp do_save_dashboard(socket, params) do
    dashboard = socket.assigns.dashboard

    attrs = %{
      "name" => params["name"],
      "description" => description_param(params["description"]),
      # No "public_token": only the sharing handlers, which ask for
      # :share_dashboard, write it. A save from a page opened before the link was
      # turned off must not turn it back on.
      "auto_refresh_seconds" => dashboard.auto_refresh_seconds,
      "settings" => Map.get(dashboard, :settings) || %{}
    }

    result = perform_save_dashboard(socket, attrs, dashboard)

    case result do
      {:ok, saved_dashboard} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Dashboard saved successfully!"))
         |> assign(save_modal_open: false, editing: false, saved_dashboard: nil)
         |> close_editors()
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
    with %{} = existing <- Lotus.get_dashboard(id, opts) || {:error, :not_found},
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
         %{} = dashboard <- Lotus.get_dashboard(id, Actor.opts(socket.assigns)),
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
    CardVariables.build(
      card.filter_mappings,
      socket.assigns.dashboard.filters || [],
      socket.assigns.filter_values,
      socket.assigns.run_date
    )
  end

  defp blank?(name), do: name in [nil, ""]

  # The values a text card writes for `{{name}}`: each filter's, or its
  # default.
  defp text_values(filters, filter_values) do
    Map.new(filters, &{&1.name, Map.get(filter_values, &1.name, &1.default_value)})
  end

  defp new_dashboard do
    %{
      id: nil,
      name: "",
      description: "",
      cards: [],
      filters: [],
      auto_refresh_seconds: nil,
      settings: %{},
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

  defp update_layouts(socket, layouts) do
    Enum.reduce(layouts, socket, fn {card_id, place}, socket ->
      update_card(socket, parse_id(card_id), fn card ->
        layout = card_layout(card)

        %{
          card
          | layout:
              Map.merge(layout, %{
                x: parse_int(place["x"], layout.x) |> clamp(0, 11),
                y: parse_int(place["y"], layout.y) |> max(0),
                w: parse_int(place["w"], layout.w) |> clamp(1, 12),
                h: parse_int(place["h"], layout.h) |> clamp(1, 24)
              })
        }
      end)
    end)
  end

  # A card's layout with atom keys: its place, and whether it starts folded.
  defp card_layout(%{layout: layout}) do
    layout = layout || %{}

    for {key, default} <- [x: 0, y: 0, w: 6, h: 4, folded: false], into: %{} do
      {key, Map.get(layout, key, Map.get(layout, Atom.to_string(key), default))}
    end
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp do_update_card_visualization(socket, card_id, viz) do
    socket =
      update_card_and_selection(socket, parse_id(card_id), fn card ->
        existing =
          (card.visualization_config || %{})
          |> Map.new(fn {k, v} -> {to_string(k), v} end)

        config = Charts.build_config(Map.merge(existing, viz))
        %{card | visualization_config: config}
      end)

    {:noreply, socket}
  end

  defp do_update_filter_mapping(socket, card_id, filter_name, variable_name) do
    socket =
      update_card_and_selection(socket, parse_id(card_id), fn card ->
        mappings = normalize_mappings(card.filter_mappings, socket.assigns.dashboard.filters)
        updated_mappings = Map.put(mappings, filter_name, mapping_entries(variable_name))
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
     assign(socket,
       filter_modal_open: true,
       editing_filter: new_filter,
       filter_errors: %{}
     )}
  end

  defp do_edit_filter(socket, filter_id) do
    filter_id = maybe_parse_id(filter_id)

    case Enum.find(socket.assigns.dashboard.filters, &(&1.id == filter_id)) do
      nil ->
        {:noreply, socket}

      filter ->
        {:noreply,
         assign(socket,
           filter_modal_open: true,
           editing_filter: filter,
           filter_errors: %{}
         )}
    end
  end

  # The filter editor renders again as its fields change, so a new type shows
  # the default value control of that type.
  defp do_change_filter_form(socket, filter_params) do
    editing = socket.assigns.editing_filter
    filter = editing |> build_editing_filter(filter_params) |> fit_widget(editing)

    errors =
      socket.assigns.filter_errors
      |> Map.delete(:default_value)
      |> Map.merge(default_value_errors(filter))

    {:noreply,
     assign(socket,
       editing_filter: filter,
       filter_errors: errors
     )}
  end

  defp do_save_filter(socket, filter_params) do
    dashboard = socket.assigns.dashboard
    filter = build_editing_filter(socket.assigns.editing_filter, filter_params)

    errors =
      filter
      |> filter_dependency_errors(dashboard.filters)
      |> Map.merge(default_value_errors(filter))
      |> Map.merge(name_errors(filter, dashboard.filters))

    case errors do
      errors when errors == %{} ->
        new? = not Enum.any?(dashboard.filters, &(&1.id == filter.id))
        dashboard = %{dashboard | filters: upsert_filter(dashboard.filters, filter)}
        # A new filter connects to the cards with a variable of its name, and
        # shows them, for the others.
        dashboard = if new?, do: auto_connect(dashboard, filter), else: dashboard

        {:noreply,
         socket
         |> assign(
           dashboard: dashboard,
           filter_modal_open: false,
           editing_filter: nil,
           connecting: if(new?, do: filter.name, else: socket.assigns.connecting)
         )
         |> assign_filter_options()
         |> run_all_cards()}

      errors ->
        {:noreply,
         assign(socket,
           editing_filter: filter,
           filter_errors: errors
         )}
    end
  end

  defp build_editing_filter(editing, filter_params) do
    filter_type = parse_filter_type(filter_params["filter_type"])

    filter = %{
      editing
      | name: filter_params["name"] || "",
        label: filter_params["label"] || "",
        filter_type: filter_type,
        widget: parse_filter_widget(filter_params["widget"]),
        default_value: default_value_param(filter_params, filter_type),
        config: build_filter_config(filter_params)
    }

    Map.merge(filter, %{
      source_query_id: parse_optional_id(filter_params["source_query_id"]),
      depends_on_filter_id: parse_optional_id(filter_params["depends_on_filter_id"])
    })
  end

  # A date range picker posts fixed dates as start and end, which
  # FilterValues joins; a token, a date and text post as they are.
  defp default_value_param(params, _filter_type) do
    case params["default_value"] do
      %{} = range -> FilterValues.normalize(%{"default" => range})["default"] |> nullify()
      value -> nullify(value)
    end
  end

  # The check core runs when the dashboard saves, run here so the filter
  # editor shows the error next to the field.
  defp default_value_errors(%{filter_type: :date, default_value: value}) do
    if DateTokens.token?(value) and value not in DateTokens.tokens(:date) do
      %{
        default_value:
          gettext(
            "%{label} is a date range. A Date filter takes Today, Yesterday or a fixed date.",
            label: DateTokens.label(value)
          )
      }
    else
      %{}
    end
  end

  defp default_value_errors(_filter), do: %{}

  # Core checks it when the dashboard saves; a card's connections and the
  # URL name a filter by its name.
  defp name_errors(filter, filters) do
    if Enum.any?(filters, &(&1.id != filter.id and &1.name == filter.name)),
      do: %{name: gettext("is the name of another filter")},
      else: %{}
  end

  # A new type picks the first widget it accepts when the current widget does
  # not fit, so a Date Range filter gets the picker with its presets.
  defp fit_widget(%{filter_type: type} = filter, %{filter_type: type}), do: filter

  defp fit_widget(filter, _previous) do
    widgets = widgets_for_type(filter.filter_type)

    if filter.widget in widgets,
      do: filter,
      else: %{filter | widget: hd(widgets)}
  end

  defp widgets_for_type(:text), do: [:input, :select]
  defp widgets_for_type(:number), do: [:input, :select]
  defp widgets_for_type(:date), do: [:date_picker, :input]
  defp widgets_for_type(:date_range), do: [:date_range_picker]
  defp widgets_for_type(:select), do: [:select]

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
        Lotus.get_query(query_id, Actor.opts(socket.assigns))

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

    connecting =
      if socket.assigns.connecting == filter_name, do: nil, else: socket.assigns.connecting

    {:noreply,
     socket
     |> assign(dashboard: dashboard, filter_values: filter_values, connecting: connecting)
     |> assign_filter_options()
     |> run_all_cards()}
  end

  defp do_update_auto_refresh(socket, seconds) do
    seconds = if seconds == "", do: nil, else: String.to_integer(seconds)
    dashboard = %{socket.assigns.dashboard | auto_refresh_seconds: seconds}
    {:noreply, assign(socket, dashboard: dashboard)}
  end

  defp load_dashboard(id, opts) do
    case Lotus.get_dashboard(id, opts) do
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

  # The description is Markdown; its editor posts its document, which the
  # save writes back as Markdown.
  defp description_field(field),
    do: %{field | value: RichText.editor_value(field.value, RichText.features(:description, nil))}

  defp build_dashboard_changeset(dashboard, params) do
    types = %{name: :string, description: :string}

    {dashboard, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name])
  end

  # A card of a kind Lotus Pro offers to this request; another kind is not
  # added.
  defp add_pro_card(socket, kind) do
    offered = Enum.map(Pro.card_kinds(Pro.request_info(socket.assigns)), & &1.kind)

    if kind in offered,
      do: add_card(socket, :pro, nil, %{"kind" => kind}),
      else: socket
  end

  defp add_card(socket, card_type, query_id, content \\ nil) do
    dashboard = socket.assigns.dashboard

    # Calculate next position index
    next_position = length(dashboard.cards)

    # The next free place on the tab shown, where the card goes
    tab = Tabs.current(dashboard, socket.assigns.tab)

    layout =
      dashboard
      |> Tabs.cards(tab)
      |> find_next_available_position(card_type)
      |> Map.put(:tab, tab)

    query =
      if query_id do
        Lotus.get_query(query_id, Actor.opts(socket.assigns))
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
      content: content
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
        :pro -> {6, 4}
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
  defp parse_card_type("pro:" <> kind), do: {:pro, kind}
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

  defp apply_filter_values(socket, filter_values) do
    socket =
      socket
      |> assign(filter_values: filter_values)
      |> assign_filter_options()

    socket
    |> run_all_cards()
    |> push_filter_params_to_url(socket.assigns.filter_values)
  end

  # Each run takes today once, so every card of the run resolves a relative
  # date token against the same day.
  defp run_card(socket, card_id) do
    socket
    |> assign(:run_date, Date.utc_today())
    |> CardRunner.run(card_id, &prepare_card/2)
  end

  defp run_all_cards(socket) do
    card_ids =
      for card <- socket.assigns.dashboard.cards,
          card.card_type == :query && card.query_id,
          do: card.id

    socket
    |> assign(:run_date, Date.utc_today())
    |> CardRunner.run_all(card_ids, &prepare_card/2)
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

    entries =
      for {filter_name, filter_entries} <- mappings,
          entry <- filter_entries,
          do: {Map.get(filter_by_name, filter_name), entry}

    with :ok <- each_write(existing_mappings, &Lotus.delete_filter_mapping(&1, opts)) do
      each_write(entries, fn {filter, entry} ->
        create_mapping(saved_card, filter, entry, opts)
      end)
    end
  end

  defp create_mapping(_card, nil, _entry, _opts), do: :ok

  defp create_mapping(_card, _filter, %{variable_name: variable_name}, _opts)
       when variable_name in [nil, ""],
       do: :ok

  defp create_mapping(card, filter, entry, opts) do
    opts = Keyword.put(opts, :transform, entry.transform)
    Lotus.create_filter_mapping(card.id, filter.id, entry.variable_name, opts)
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

  defp layout_to_map(%{x: x, y: y, w: w, h: h} = layout),
    do: %{
      x: x,
      y: y,
      w: w,
      h: h,
      folded: Map.get(layout, :folded, false),
      tab: Map.get(layout, :tab)
    }

  # The editor keeps a changed card's mappings as
  # %{filter_name => [%{variable_name: _, transform: _}]}. A filter can map to
  # more than one variable, a date range split by the date_range_start and
  # date_range_end transforms, so each filter keeps a list and every transform.
  defp normalize_mappings(mappings, _filters) when is_map(mappings), do: mappings

  defp normalize_mappings(mappings, filters) when is_list(mappings) do
    filter_name_by_id = Map.new(filters, &{&1.id, &1.name})

    mappings
    |> Enum.filter(&Map.has_key?(filter_name_by_id, &1.filter_id))
    |> Enum.group_by(
      &Map.fetch!(filter_name_by_id, &1.filter_id),
      &%{variable_name: &1.variable_name, transform: &1.transform}
    )
  end

  defp normalize_mappings(_, _), do: %{}

  defp auto_connect(dashboard, filter) do
    cards =
      Enum.map(dashboard.cards, fn card ->
        variables = (card.card_type == :query && card.query && card.query.variables) || []

        case FilterConnections.suggest(filter, variables) do
          [] ->
            card

          entries ->
            mappings = normalize_mappings(card.filter_mappings, dashboard.filters)
            %{card | filter_mappings: Map.put(mappings, filter.name, entries)}
        end
      end)

    %{dashboard | cards: cards}
  end

  defp mapping_entries(variable_name) when variable_name in [nil, ""], do: []
  defp mapping_entries(variable_name), do: [%{variable_name: variable_name, transform: nil}]

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
