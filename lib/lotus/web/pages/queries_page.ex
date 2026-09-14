defmodule Lotus.Web.QueriesPage do
  @moduledoc """
  Landing page with tabs for Queries and Dashboards.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Authorization
  alias Lotus.Web.Page

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="queries-page" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg h-full flex flex-col overflow-hidden">
          <%!-- Header with tabs --%>
          <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <%!-- Tabs --%>
            <div class="flex border-b border-gray-200 dark:border-gray-600">
              <button
                phx-click="switch_tab"
                phx-value-tab="queries"
                phx-target={@myself}
                class={tab_class(@active_tab == :queries)}
              >
                <%= gettext("Queries") %>
                <span class="ml-2 px-2 py-0.5 text-xs bg-gray-100 dark:bg-gray-700 rounded-full">
                  <%= length(@queries) %>
                </span>
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="dashboards"
                phx-target={@myself}
                class={tab_class(@active_tab == :dashboards)}
              >
                <%= gettext("Dashboards") %>
                <span class="ml-2 px-2 py-0.5 text-xs bg-gray-100 dark:bg-gray-700 rounded-full">
                  <%= length(@dashboards) %>
                </span>
              </button>
            </div>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto px-4 sm:px-6 lg:px-8">
            <%= if @active_tab == :queries do %>
              <.queries_table
                queries={@queries}
                can_create={Authorization.allowed?(assigns, :create_query)}
              />
            <% else %>
              <.dashboards_table
                dashboards={@dashboards}
                can_create={Authorization.allowed?(assigns, :manage_dashboard)}
              />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tab_class(active) do
    base = "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors flex items-center"

    if active do
      "#{base} border-pink-500 text-pink-600 dark:text-pink-400"
    else
      "#{base} border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
    end
  end

  defp queries_table(assigns) do
    ~H"""
    <%= if @queries == [] do %>
      <div class="py-12 text-center text-gray-500 dark:text-gray-400">
        <Icons.terminal class="mx-auto h-12 w-12 text-gray-300 dark:text-gray-600 mb-4" />
        <p><%= gettext("No saved queries yet.") %></p>
        <.link
          :if={@can_create}
          navigate={lotus_path(["queries", "new"])}
          class="mt-2 inline-block text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300"
        >
          <%= gettext("Create your first query") %>
        </.link>
      </div>
    <% else %>
      <div class="mt-8">
        <.table id="queries-table" rows={@queries}>
          <:col :let={query} label={gettext("Name")}>
            <.link
              navigate={lotus_path(["queries", query.id])}
              class="text-indigo-600 dark:text-indigo-400 hover:text-indigo-800 dark:hover:text-indigo-300 font-medium"
            >
              <%= query.name %>
            </.link>
          </:col>
          <:col :let={query} label={gettext("Description")}>
            <%= query.description || "-" %>
          </:col>
          <:col :let={query} label={gettext("Created")}>
            <%= Calendar.strftime(query.inserted_at, "%b %d, %Y") %>
          </:col>
        </.table>
      </div>
    <% end %>
    """
  end

  defp dashboards_table(assigns) do
    ~H"""
    <%= if @dashboards == [] do %>
      <div class="py-12 text-center text-gray-500 dark:text-gray-400">
        <Icons.squares_2x2 class="mx-auto h-12 w-12 text-gray-300 dark:text-gray-600 mb-4" />
        <p><%= gettext("No dashboards yet.") %></p>
        <.link
          :if={@can_create}
          navigate={lotus_path(["dashboards", "new"])}
          class="mt-2 inline-block text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300"
        >
          <%= gettext("Create your first dashboard") %>
        </.link>
      </div>
    <% else %>
      <div class="mt-8">
        <.table id="dashboards-table" rows={@dashboards}>
          <:col :let={dashboard} label={gettext("Name")}>
            <.link
              navigate={lotus_path(["dashboards", dashboard.id])}
              class="text-indigo-600 dark:text-indigo-400 hover:text-indigo-800 dark:hover:text-indigo-300 font-medium"
            >
              <%= dashboard.name %>
            </.link>
          </:col>
          <:col :let={dashboard} label={gettext("Description")}>
            <%= dashboard.description || "-" %>
          </:col>
          <:col :let={dashboard} label={gettext("Cards")}>
            <%= length(dashboard.cards) %>
          </:col>
          <:col :let={dashboard} label={gettext("Created")}>
            <%= Calendar.strftime(dashboard.inserted_at, "%b %d, %Y") %>
          </:col>
        </.table>
      </div>
    <% end %>
    """
  end

  @impl Page
  def handle_mount(socket) do
    queries = Lotus.list_queries()
    dashboards = Lotus.list_dashboards(preload: [:cards])

    socket
    |> assign(
      queries: queries,
      dashboards: dashboards,
      active_tab: :queries
    )
  end

  @impl Page
  def handle_params(%{"tab" => "dashboards"}, _uri, socket) do
    {:noreply, assign(socket, active_tab: :dashboards)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl Phoenix.LiveComponent
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    active_tab =
      case tab do
        "queries" -> :queries
        "dashboards" -> :dashboards
        _ -> :queries
      end

    {:noreply, assign(socket, active_tab: active_tab)}
  end

  @impl Page
  def handle_info(_msg, socket), do: {:noreply, socket}
end
