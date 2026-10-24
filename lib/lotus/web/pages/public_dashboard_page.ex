defmodule Lotus.Web.PublicDashboardPage do
  @moduledoc """
  Read-only public view of a shared dashboard.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Actor
  alias Lotus.Web.Branding
  alias Lotus.Web.Dashboards.CardGridComponent
  alias Lotus.Web.Dashboards.CardRunner
  alias Lotus.Web.Dashboards.CardVariables
  alias Lotus.Web.Dashboards.ChartFilters
  alias Lotus.Web.Dashboards.Components
  alias Lotus.Web.Dashboards.FilterBarComponent
  alias Lotus.Web.Dashboards.FilterOptions
  alias Lotus.Web.Dashboards.FilterValues
  alias Lotus.Web.Dashboards.Tabs
  alias Lotus.Web.Page
  alias Lotus.Web.Pro
  alias Lotus.Web.Telemetry

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="public-dashboard" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full flex flex-col">
        <div class="lotus-dashboard bg-gray-50 dark:bg-gray-900 shadow-sm ring-1 ring-black/5 dark:ring-white/10 rounded-lg h-full flex flex-col overflow-hidden">
          <Components.dashboard_head
            :if={is_nil(@single_card)}
            dashboard={@dashboard}
            refreshed_at={@refreshed_at}
            running={MapSet.size(@running_cards) > 0}
          >
            <:actions :if={@dashboard.cards != []}>
              <Components.fullscreen_button />
            </:actions>
          </Components.dashboard_head>

          <%!-- Filter Bar --%>
          <.live_component
            :if={@dashboard.filters != [] and is_nil(@single_card)}
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            filter_options={@filter_options}
            parent={@myself}
            public={true}
          />

          <Components.tab_bar
            :if={is_nil(@single_card)}
            tabs={Tabs.list(@dashboard)}
            current={Tabs.current(@dashboard, @tab)}
            target={@myself}
          />

          <%!-- Grid Content --%>
          <div class="flex-1 overflow-y-auto px-4 sm:px-6 pt-2 pb-6">
            <%= if @dashboard.cards != [] do %>
              <.live_component
                module={CardGridComponent}
                id="card-grid"
                dashboard_id={@dashboard.id}
                values={Map.new(@dashboard.filters, &{&1.name, Map.get(@filter_values, &1.name, &1.default_value)})}
                cards={Tabs.cards(@dashboard, Tabs.current(@dashboard, @tab))}
                card_results={@card_results}
                card_errors={@card_errors}
                running_cards={@running_cards}
                selected_card_id={nil}
                public={true}
                filters={@dashboard.filters}
                pro_info={Lotus.Web.Pro.request_info(%{context: @context, scope: @scope})}
                parent={@myself}
              />
            <% else %>
              <div class="flex items-center justify-center h-full text-gray-500 dark:text-gray-400">
                <p><%= gettext("This dashboard has no cards.") %></p>
              </div>
            <% end %>
          </div>

          <%!-- Footer --%>
          <div class="px-6 py-3 text-center text-xs text-gray-500 dark:text-gray-400">
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
      tab: nil,
      card_errors: %{},
      running_cards: MapSet.new(),
      card_runner: CardRunner.new(socket.assigns.card_concurrency, public: true),
      refreshed_at: nil,
      single_card: nil
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
            open(socket, dashboard, params)
        end

      %{grant: grant} ->
        open_embed(socket, grant, params)

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

  @impl Phoenix.LiveComponent
  def handle_event("select_tab", %{"tab" => tab}, socket),
    do: {:noreply, assign(socket, tab: tab)}

  # A click on a chart's mark filters the dashboard by it.
  @impl Phoenix.LiveComponent
  def handle_event("chart_select", params, socket) do
    %{dashboard: dashboard, filter_values: filter_values} = socket.assigns

    case ChartFilters.click(dashboard.cards, dashboard.filters, filter_values, params) do
      {:ok, values} -> {:noreply, apply_filter_values(socket, values)}
      :none -> {:noreply, socket}
    end
  end

  def handle_event("filter_changed", %{"filter" => filter_values}, socket) do
    {:noreply, apply_filter_values(socket, FilterValues.normalize(filter_values))}
  end

  # A card's new result from Pro's live updates (`Lotus.Web.Pro.watch_dashboard/2`).
  @impl Page
  def handle_info({:card_result, card_id, result}, socket) do
    {:noreply, socket |> put_card_result(card_id, {:ok, {:ok, result}}) |> mark_refreshed()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Lotus Pro may refuse the link (`Lotus.Web.Pro.authorize_public_dashboard/2`).
  defp open(socket, dashboard, params) do
    case Pro.authorize_public_dashboard(dashboard, params) do
      :allow ->
        show(socket, dashboard, params)

      {:deny, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message || gettext("This dashboard is not available"))
         |> assign(dashboard: empty_dashboard(gettext("Dashboard Unavailable")))}
    end
  end

  # An embed (`Lotus.Web.EmbedLive`): the dashboard, or the one card, of the
  # grant Lotus Pro gave. Its cards run as the grant's viewer, with the
  # host's filters first and the viewer's changes over them.
  defp open_embed(socket, %{resource: {:dashboard, id}} = grant, params) do
    case Lotus.get_dashboard(id) do
      nil -> {:noreply, assign(socket, dashboard: empty_dashboard())}
      dashboard -> show(socket, dashboard, params, grant)
    end
  end

  defp open_embed(socket, %{resource: {:card, id}} = grant, params) do
    with %{} = card <- Lotus.get_dashboard_card(id),
         %{} = dashboard <- Lotus.get_dashboard(card.dashboard_id) do
      show(assign(socket, single_card: card.id), dashboard, params, grant)
    else
      _ -> {:noreply, assign(socket, dashboard: empty_dashboard())}
    end
  end

  defp show(socket, dashboard, params, grant \\ nil) do
    cards = Lotus.list_dashboard_cards(dashboard.id, preload: [:query, :filter_mappings])
    filters = Lotus.list_dashboard_filters(dashboard.id)
    dashboard = %{dashboard | cards: only(cards, socket.assigns.single_card), filters: filters}

    filter_values =
      Map.merge(host_filters(grant, filters), extract_filter_values(params, filters))

    report_view(socket, dashboard)

    {:noreply,
     socket
     |> Branding.assign_branding(%{
       user: nil,
       context: socket.assigns.context,
       scope: socket.assigns.scope,
       public: true,
       dashboard: dashboard
     })
     |> assign(dashboard: dashboard, filter_values: filter_values)
     |> watch()
     |> assign_filter_options()
     |> run_all_cards()}
  end

  # The one card of a card embed, across the whole width.
  defp only(cards, nil), do: cards

  defp only(cards, card_id) do
    for %{id: ^card_id} = card <- cards,
        do: %{card | layout: Map.merge(card.layout || %{}, %{x: 0, w: 12, tab: nil})}
  end

  # The filter values an embed's host sets, for the dashboard's filters.
  defp host_filters(nil, _filters), do: %{}

  defp host_filters(grant, filters) do
    names = MapSet.new(filters, & &1.name)
    Map.filter(grant.filters, fn {name, _value} -> MapSet.member?(names, name) end)
  end

  # A view is counted once per connected page load, not on each patch.
  defp report_view(socket, %{id: id} = dashboard) do
    if connected?(socket) and not match?(%{id: ^id}, socket.assigns.dashboard),
      do: Telemetry.dashboard_view(dashboard, true, socket.assigns.context)
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

  @impl Phoenix.LiveComponent
  def handle_async({:run_card, card_id}, result, socket) do
    case CardRunner.finish(socket, card_id, &prepare_card/2) do
      {:ok, socket} -> {:noreply, socket |> put_card_result(card_id, result) |> mark_refreshed()}
      :stale -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # Private

  defp empty_dashboard(name \\ gettext("Dashboard Not Found")) do
    %{
      id: nil,
      name: name,
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

  defp prepare_card(socket, card_id) do
    card = Enum.find(socket.assigns.dashboard.cards, &(&1.id == card_id))

    if card && card.card_type == :query && card.query do
      opts = Actor.merge([vars: build_card_variables(socket, card)], socket.assigns)
      query = card.query
      {:run, fn -> Lotus.run_query(query, opts) end}
    else
      {:skip, socket}
    end
  end

  # The source queries run like the cards: a public dashboard has no actor,
  # an embed has the one Lotus Pro gave.
  defp assign_filter_options(socket) do
    {filter_options, filter_values} =
      FilterOptions.resolve(
        socket.assigns.dashboard.filters,
        socket.assigns.filter_values,
        Actor.opts(socket.assigns)
      )

    assign(socket, filter_options: filter_options, filter_values: filter_values)
  end

  defp push_filter_params_to_url(socket, filter_values) do
    push_event(socket, "update-query-params", %{params: FilterValues.to_params(filter_values)})
  end

  defp extract_filter_values(params, filters), do: FilterValues.from_params(params, filters)

  defp build_card_variables(socket, card) do
    CardVariables.build(
      card.filter_mappings,
      socket.assigns.dashboard.filters || [],
      socket.assigns.filter_values,
      socket.assigns.run_date
    )
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
end
