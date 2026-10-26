defmodule Lotus.Web.PublicDashboardPage do
  @moduledoc """
  Read-only public view of a shared dashboard.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Branding
  alias Lotus.Web.Components.Icons
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
            :if={@dashboard.filters != []}
            module={FilterBarComponent}
            id="filter-bar"
            filters={@dashboard.filters}
            filter_values={@filter_values}
            filter_options={@filter_options}
            parent={@myself}
            public={true}
          />

          <Components.tab_bar
            tabs={Tabs.list(@dashboard)}
            current={Tabs.current(@dashboard, @tab)}
            target={@myself}
          />

          <%!-- Grid Content --%>
          <div class="flex-1 overflow-y-auto px-4 sm:px-6 pt-2 pb-6">
            <%= cond do %>
              <% @ask -> %>
                <.ask_form ask={@ask} target={@myself} />
              <% @dashboard.cards != [] -> %>
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
                pro_info={Lotus.Web.Pro.request_info(%{})}
                parent={@myself}
                downloads={@downloads}
              />
              <% true -> %>
              <div
                :if={@unavailable}
                id="public-dashboard-unavailable"
                class="flex h-full flex-col items-center justify-center gap-3 px-6 text-center"
              >
                <Icons.globe class="h-10 w-10 text-gray-300 dark:text-gray-600" />
                <p class="text-base font-medium text-gray-900 dark:text-white"><%= @unavailable %></p>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  <%= gettext("Ask whoever shared it with you for a new link.") %>
                </p>
              </div>
              <div :if={!@unavailable} class="flex items-center justify-center h-full text-gray-500 dark:text-gray-400">
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
      unavailable: nil,
      ask: nil,
      asked: nil,
      link_params: %{},
      run_context: nil,
      kept_params: %{},
      downloads: true,
      filter_values: %{},
      filter_options: %{},
      card_results: %{},
      tab: nil,
      card_errors: %{},
      running_cards: MapSet.new(),
      card_runner: CardRunner.new(socket.assigns.card_concurrency, public: true),
      refreshed_at: nil
    )
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    case socket.assigns.page do
      %{token: token} ->
        case Lotus.get_dashboard_by_token(token) do
          nil ->
            {title, message} = missing(token)
            report_refused(socket, token, nil, message)
            {:noreply, assign(socket, dashboard: empty_dashboard(title), unavailable: message)}

          dashboard ->
            open(socket, dashboard, params)
        end

      _ ->
        {:noreply, assign(socket, dashboard: empty_dashboard())}
    end
  end

  # What the visitor filled in on Lotus Pro's form (`{:ask, ask}`).
  @impl Phoenix.LiveComponent
  def handle_event("answer_link", params, socket) do
    %{ask: ask, asked: dashboard, link_params: link_params} = socket.assigns

    if dashboard do
      answers = answers(ask, Map.get(params, "answers"))

      answer(
        socket,
        dashboard,
        link_params,
        Pro.answer_public_dashboard(dashboard, answers, link_params)
      )
    else
      {:noreply, socket}
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

  # The asked fields' answers, as text; nothing else the browser sends.
  defp answers(%{fields: fields}, %{} = given) do
    for %{key: key} <- fields, is_binary(given[key]), into: %{}, do: {key, given[key]}
  end

  defp answers(_ask, _given), do: %{}

  # Lotus Pro's form, shown instead of the dashboard until it allows the link.
  attr(:ask, :map, required: true)
  attr(:target, :any, required: true)

  defp ask_form(assigns) do
    ~H"""
    <div id="public-dashboard-ask" class="flex h-full items-center justify-center px-6">
      <form
        id="public-dashboard-ask-form"
        phx-submit="answer_link"
        phx-target={@target}
        class="w-full max-w-md space-y-4"
      >
        <div class="flex flex-col items-center gap-3 text-center">
          <Icons.lock class="h-10 w-10 text-gray-300 dark:text-gray-600" />
          <p :if={@ask.message} class="text-sm text-gray-600 dark:text-gray-300"><%= @ask.message %></p>
        </div>
        <p
          :if={@ask.error}
          id="public-dashboard-ask-error"
          role="alert"
          class="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300"
        >
          <%= @ask.error %>
        </p>
        <div :for={{field, index} <- Enum.with_index(@ask.fields)} class="space-y-1">
          <label for={"ask-#{field.key}"} class="block text-sm font-medium text-gray-700 dark:text-gray-200">
            <%= field.label %>
          </label>
          <input
            id={"ask-#{field.key}"}
            name={"answers[#{field.key}]"}
            type={Atom.to_string(field.type)}
            required
            autofocus={index == 0}
            autocomplete={autocomplete(field.type)}
            class="block w-full rounded-md border-0 px-3 py-2 text-sm text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-pink-600 dark:bg-input-dark dark:text-white dark:ring-gray-600"
          />
        </div>
        <button
          :if={@ask.fields != []}
          type="submit"
          class="w-full rounded-md bg-pink-600 px-3 py-2 text-sm font-semibold text-white hover:bg-pink-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-pink-600"
        >
          <%= @ask.submit || gettext("Continue") %>
        </button>
      </form>
    </div>
    """
  end

  defp autocomplete(:password), do: "current-password"
  defp autocomplete(:email), do: "email"
  defp autocomplete(:text), do: "off"

  # A link to no dashboard: Lotus Pro's words when it knows the link
  # (`Lotus.Web.Pro.public_link_message/1`), else not found.
  defp missing(token) do
    case Pro.public_link_message(token) do
      nil -> {gettext("Dashboard Not Found"), gettext("Dashboard not found or no longer public")}
      message -> {gettext("Dashboard Unavailable"), message}
    end
  end

  # Lotus Pro may refuse the link (`Lotus.Web.Pro.authorize_public_dashboard/2`).
  defp open(socket, dashboard, params),
    do: answer(socket, dashboard, params, Pro.authorize_public_dashboard(dashboard, params))

  defp answer(socket, dashboard, params, answer) do
    case answer do
      :allow ->
        show(socket, dashboard, params, %{context: nil, downloads: true, params: %{}})

      {:allow, opts} ->
        show(socket, dashboard, Map.merge(params, opts.params), opts)

      {:ask, ask} ->
        title = ask.title || gettext("This dashboard is protected")

        {:noreply,
         assign(socket,
           dashboard: empty_dashboard(title),
           unavailable: nil,
           ask: ask,
           asked: dashboard,
           link_params: params
         )}

      {:deny, message} ->
        report_refused(socket, dashboard.public_token, dashboard, message)

        {:noreply,
         assign(socket,
           dashboard: empty_dashboard(gettext("Dashboard Unavailable")),
           unavailable: message || gettext("This dashboard is not available")
         )}
    end
  end

  defp show(socket, dashboard, params, opts) do
    cards = Lotus.list_dashboard_cards(dashboard.id, preload: [:query, :filter_mappings])
    filters = Lotus.list_dashboard_filters(dashboard.id)
    dashboard = %{dashboard | cards: cards, filters: filters}
    filter_values = extract_filter_values(params, filters)

    report_view(socket, dashboard)

    {:noreply,
     socket
     |> assign(
       unavailable: nil,
       ask: nil,
       asked: nil,
       downloads: opts.downloads,
       run_context: opts.context
     )
     |> Branding.assign_branding(%{
       user: nil,
       context: nil,
       scope: nil,
       public: true,
       dashboard: dashboard
     })
     |> assign(dashboard: dashboard, filter_values: filter_values)
     |> keep_params(opts.params)
     |> watch()
     |> assign_filter_options()
     |> run_all_cards()}
  end

  # A view is counted once per connected page load, not on each patch.
  defp report_view(socket, %{id: id} = dashboard) do
    if connected?(socket) and not match?(%{id: ^id}, socket.assigns.dashboard),
      do: Telemetry.dashboard_view(dashboard, true, nil, socket.assigns[:client])
  end

  # A link that opened nothing, once per connected page load.
  defp report_refused(socket, token, dashboard, message) do
    if connected?(socket) and is_nil(socket.assigns.unavailable),
      do: Telemetry.public_link_refused(token, dashboard, message, socket.assigns[:client])
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
      vars = build_card_variables(socket, card)
      query = card.query
      opts = run_opts(socket)
      {:run, fn -> Lotus.run_query(query, [vars: vars] ++ opts) end}
    else
      {:skip, socket}
    end
  end

  # A public dashboard has no viewer: its cards and the filters' source
  # queries run as whoever Lotus Pro names for the link, or with no
  # :context.
  defp run_opts(socket) do
    case socket.assigns.run_context do
      nil -> []
      context -> [context: context]
    end
  end

  defp assign_filter_options(socket) do
    {filter_options, filter_values} =
      FilterOptions.resolve(socket.assigns.dashboard.filters, socket.assigns.filter_values,
        run_opts: run_opts(socket)
      )

    assign(socket, filter_options: filter_options, filter_values: filter_values)
  end

  defp push_filter_params_to_url(socket, filter_values) do
    params = Map.merge(FilterValues.to_params(filter_values), socket.assigns.kept_params)
    push_event(socket, "update-query-params", %{params: params})
  end

  # The params Lotus Pro keeps in the link's URL (a grant after a password,
  # say), written now and kept when the filters change the URL.
  defp keep_params(socket, kept) when kept == %{}, do: assign(socket, kept_params: kept)

  defp keep_params(socket, kept) do
    socket = assign(socket, kept_params: kept)
    params = Map.merge(FilterValues.to_params(socket.assigns.filter_values), kept)

    if connected?(socket),
      do: push_event(socket, "update-query-params", %{params: params}),
      else: socket
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
