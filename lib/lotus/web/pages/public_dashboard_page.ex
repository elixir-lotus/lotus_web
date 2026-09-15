defmodule Lotus.Web.PublicDashboardPage do
  @moduledoc """
  Read-only public view of a shared dashboard.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Dashboards.CardGridComponent
  alias Lotus.Web.Dashboards.CardRunner
  alias Lotus.Web.Dashboards.FilterBarComponent
  alias Lotus.Web.Dashboards.FilterOptions
  alias Lotus.Web.Dashboards.FilterValues
  alias Lotus.Web.Page

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="public-dashboard" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full flex flex-col">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg h-full flex flex-col overflow-hidden">
          <%!-- Header --%>
          <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              <%= @dashboard.name %>
            </h1>
            <%= if @dashboard.description do %>
              <p class="mt-1 text-gray-600 dark:text-gray-400">
                <%= @dashboard.description %>
              </p>
            <% end %>
          </div>

          <%!-- Filter Bar --%>
          <.live_component
            :if={@dashboard.filters != []}
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            filter_options={@filter_options}
            parent={@myself}
            public={true}
          />

          <%!-- Grid Content --%>
          <div class="flex-1 overflow-y-auto p-4">
            <%= if @dashboard.cards != [] do %>
              <.live_component
                module={CardGridComponent}
                id="card-grid"
                cards={@dashboard.cards}
                card_results={@card_results}
                card_errors={@card_errors}
                running_cards={@running_cards}
                selected_card_id={nil}
                public={true}
                parent={@myself}
              />
            <% else %>
              <div class="flex items-center justify-center h-full text-gray-500 dark:text-gray-400">
                <p><%= gettext("This dashboard has no cards.") %></p>
              </div>
            <% end %>
          </div>

          <%!-- Footer --%>
          <div class="px-6 py-3 border-t border-gray-200 dark:border-gray-700 text-center text-sm text-gray-500 dark:text-gray-400">
            <%= gettext("Powered by") %>
            <a href="https://github.com/elixir-lotus/lotus" class="text-pink-600 hover:text-pink-700 dark:text-pink-400">
              Lotus
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) do
    socket
    |> assign(
      dashboard: nil,
      filter_values: %{},
      filter_options: %{},
      card_results: %{},
      card_errors: %{},
      running_cards: MapSet.new(),
      card_runner: CardRunner.new(socket.assigns.card_concurrency)
    )
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    case socket.assigns.page do
      %{token: token} ->
        case Lotus.get_dashboard_by_token(token) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Dashboard not found or no longer public"))
             |> assign(dashboard: empty_dashboard())}

          dashboard ->
            cards = Lotus.list_dashboard_cards(dashboard.id, preload: [:query, :filter_mappings])
            filters = Lotus.list_dashboard_filters(dashboard.id)
            dashboard = %{dashboard | cards: cards, filters: filters}
            filter_values = extract_filter_values(params, filters)

            {:noreply,
             socket
             |> assign(dashboard: dashboard, filter_values: filter_values)
             |> assign_filter_options()
             |> run_all_cards()}
        end

      _ ->
        {:noreply, assign(socket, dashboard: empty_dashboard())}
    end
  end

  # Card click is a no-op for public dashboards
  @impl Phoenix.LiveComponent
  def handle_event("select_card", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("open_card_settings", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("refresh_card", %{"card-id" => card_id}, socket) do
    card_id = parse_id(card_id)
    {:noreply, run_card(socket, card_id)}
  end

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

  @impl Page
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
    {:ok, assign(socket, assigns)}
  end

  # Private

  defp empty_dashboard do
    %{
      id: nil,
      name: gettext("Dashboard Not Found"),
      description: nil,
      cards: [],
      filters: []
    }
  end

  defp put_card_result(socket, card_id, {:ok, {:ok, result}}) do
    assign(socket,
      card_results: Map.put(socket.assigns.card_results, card_id, result),
      card_errors: Map.delete(socket.assigns.card_errors, card_id)
    )
  end

  defp put_card_result(socket, card_id, {:ok, {:error, error}}) do
    put_card_error(socket, card_id, to_string(error))
  end

  defp put_card_result(socket, card_id, {:exit, _reason}) do
    put_card_error(socket, card_id, gettext("Query execution failed"))
  end

  defp put_card_error(socket, card_id, message) do
    assign(socket,
      card_errors: Map.put(socket.assigns.card_errors, card_id, message),
      card_results: Map.delete(socket.assigns.card_results, card_id)
    )
  end

  defp run_card(socket, card_id), do: CardRunner.run(socket, card_id, &prepare_card/2)

  defp run_all_cards(socket) do
    card_ids =
      for card <- socket.assigns.dashboard.cards,
          card.card_type == :query && card.query_id,
          do: card.id

    CardRunner.run_all(socket, card_ids, &prepare_card/2)
  end

  defp prepare_card(socket, card_id) do
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    if card && card.card_type == :query && card.query do
      vars = build_card_variables(socket, card)
      query = card.query
      {:run, fn -> Lotus.run_query(query, vars: vars) end}
    else
      {:skip, socket}
    end
  end

  # A public dashboard has no actor, so the source queries run like its cards:
  # with no :context or :scope.
  defp assign_filter_options(socket) do
    {filter_options, filter_values} =
      FilterOptions.resolve(socket.assigns.dashboard.filters, socket.assigns.filter_values)

    assign(socket, filter_options: filter_options, filter_values: filter_values)
  end

  defp push_filter_params_to_url(socket, filter_values) do
    push_event(socket, "update-query-params", %{params: FilterValues.to_params(filter_values)})
  end

  defp extract_filter_values(params, filters), do: FilterValues.from_params(params, filters)

  defp build_card_variables(socket, card) do
    filter_values = socket.assigns.filter_values
    dashboard_filters = socket.assigns.dashboard.filters || []

    Enum.reduce(card.filter_mappings || [], %{}, fn mapping, acc ->
      add_filter_variable(acc, mapping, dashboard_filters, filter_values)
    end)
  end

  defp add_filter_variable(acc, mapping, dashboard_filters, filter_values) do
    filter = Enum.find(dashboard_filters, &(&1.id == mapping.filter_id))

    if filter && mapping.variable_name && mapping.variable_name != "" do
      value = Map.get(filter_values, filter.name)
      if value, do: Map.put(acc, mapping.variable_name, value), else: acc
    else
      acc
    end
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
end
