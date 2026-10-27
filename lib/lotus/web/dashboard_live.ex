defmodule Lotus.Web.DashboardLive do
  use Lotus.Web, :live_view

  alias Lotus.Web.{Actor, Assets, Authorization, Branding}
  alias Lotus.Web.{DashboardEditorPage, PublicDashboardPage, QueriesPage, QueryEditorPage}
  alias Lotus.Web.{SchedulesPage, Telemetry}

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"prefix" => prefix} = session
    %{"live_path" => live_path, "live_transport" => live_transport} = session
    %{"csp_nonces" => csp_nonces, "card_concurrency" => card_concurrency} = session

    page = resolve_page(params, session["features"])
    {resolver, user, access, features, page_title} = mount_defaults(page, session)
    {context, scope} = actor = Actor.resolve(resolver, user)

    put_router_prefix(socket, prefix)

    # A tab that stays open across a deploy reconnects to new server code
    # with the previous CSS and JS. Remember that here; handle_params/3 has
    # the URL and issues the full-page redirect that reloads the bundle.
    assets_stale? =
      connected?(socket) and Assets.stale?(get_connect_params(socket)["_track_static"])

    socket =
      socket
      |> assign(:assets_stale?, assets_stale?)
      |> assign(:list_views, list_views(socket))
      |> assign(params: params, page: page)
      |> assign(live_path: live_path, live_transport: live_transport)
      |> assign(:page_title, page_title)
      |> assign(:csp_nonces, csp_nonces)
      |> assign(:resolver, resolver)
      |> assign(:user, user)
      |> assign(:access, access)
      |> assign(:context, context)
      |> assign(:scope, scope)
      |> assign(:actor, actor)
      |> assign(:client, Telemetry.client(socket))
      |> assign(:browser_id, browser_id(socket))
      |> assign(:features, features)
      |> assign(:card_concurrency, card_concurrency)
      |> assign(:theme, Map.get(session, "theme", :lotus))
      |> assign(:themes, Map.get(session, "themes", Lotus.Web.Theme.names()))
      |> assign(:theme_colors, Map.get(session, "theme_colors", %{}))
      |> assign(:public_view, page.name == :public_dashboard)
      |> Branding.assign_branding(%{
        user: user,
        context: context,
        scope: scope,
        public: page.name == :public_dashboard,
        dashboard: nil
      })
      |> title_with_product()
      |> assign_permissions()
      |> mount_palette()
      |> page.comp.handle_mount()

    {:ok, socket}
  end

  # The lists' views (a gallery or a table) the viewer chose, which the
  # browser keeps and sends at each mount, so a list renders as they left
  # it instead of switching after it shows. Before the socket connects,
  # none.
  @lists %{"queries" => :queries, "dashboards" => :dashboards, "schedules" => :schedules}

  defp list_views(socket) do
    case connected?(socket) && get_connect_params(socket)["views"] do
      views when is_map(views) ->
        for {list, "list"} <- views,
            Map.has_key?(@lists, list),
            into: %{},
            do: {@lists[list], :list}

      _none ->
        %{}
    end
  end

  # "Lotus Dashboard" names the product the branding gives.
  defp title_with_product(%{assigns: %{page_title: "Lotus Dashboard"}} = socket),
    do: assign(socket, :page_title, socket.assigns.branding.product_name <> " Dashboard")

  defp title_with_product(socket), do: socket

  # The command palette (⌘K), for the signed-in dashboard only: a public
  # dashboard has no actions to offer.
  defp mount_palette(%{assigns: %{public_view: true}} = socket), do: socket
  defp mount_palette(socket), do: Jumon.Live.mount(socket, Lotus.Web.Commands)

  # The actions of the page in view leave with it.
  defp put_page_actions(%{assigns: %{jumon: _}} = socket) do
    page =
      case socket.assigns.page.comp do
        QueryEditorPage -> :query_editor
        DashboardEditorPage -> :dashboard_editor
        _other -> :other
      end

    Jumon.Live.put_actions(socket, Lotus.Web.Commands.page_actions(page, socket.assigns))
  end

  defp put_page_actions(socket), do: socket

  # The actions without a resource are decided once here, so templates can ask
  # on every render without calling the host each time.
  defp assign_permissions(socket) do
    assign(socket, :permissions, Authorization.permissions(socket.assigns))
  end

  defp mount_defaults(%{name: :public_dashboard}, _session),
    do: {nil, nil, :read_only, [], "Public Dashboard"}

  defp mount_defaults(_page, session),
    do:
      {Map.get(session, "resolver"), Map.get(session, "user"), Map.get(session, "access", :all),
       Map.get(session, "features", []), "Lotus Dashboard"}

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns =
      assigns
      |> Map.put(:id, "page")
      |> Map.drop(~w(csp_nonces flash live_path live_transport refresh socket timer)a)

    ~H"""
    <.live_component id="page" module={@page.comp} {assigns} />
    """
  end

  # The random id the browser keeps for itself (`assets/js/app.js`), sent
  # as it connects: whose pins they are when there is no user to tell.
  defp browser_id(socket) do
    with true <- connected?(socket),
         id when is_binary(id) <- get_connect_params(socket)["browser_id"],
         true <- id =~ ~r/\A[A-Za-z0-9-]{16,64}\z/ do
      "browser:" <> id
    else
      _ -> nil
    end
  end

  @impl Phoenix.LiveView
  def handle_params(_params, uri, %{assigns: %{assets_stale?: true}} = socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    to = if query, do: path <> "?" <> query, else: path
    {:noreply, redirect(socket, to: to)}
  end

  def handle_params(params, uri, socket) do
    page = resolve_page(params, socket.assigns.features)
    socket = assign(socket, page: page)

    case socket.assigns.page.comp.handle_params(params, uri, socket) do
      {:noreply, socket} -> {:noreply, put_page_actions(socket)}
      other -> other
    end
  end

  @impl Phoenix.LiveView
  def handle_event("platform_info", %{"os" => os, "ua" => ua}, socket) do
    os_atom =
      case os do
        "mac" -> :mac
        "windows" -> :windows
        "linux" -> :linux
        _ -> :unknown
      end

    {:noreply, assign(socket, os: os_atom, ua: ua)}
  end

  @impl Phoenix.LiveView
  def handle_info({:put_flash, [type, message]}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  def handle_info(message, socket) do
    socket.assigns.page.comp.handle_info(message, socket)
  end

  @impl Phoenix.LiveView
  def handle_async(name, async_fun_result, socket) do
    socket.assigns.page.comp.handle_async(name, async_fun_result, socket)
  end

  ## Render Helpers

  defp resolve_page(%{"token" => token}),
    do: %{name: :public_dashboard, comp: PublicDashboardPage, token: token}

  defp resolve_page(%{"page" => "queries", "id" => "new"}),
    do: %{name: :query_new, comp: QueryEditorPage, mode: :new}

  defp resolve_page(%{"page" => "queries", "id" => id}),
    do: %{name: :query_edit, comp: QueryEditorPage, mode: :edit, id: id}

  defp resolve_page(%{"page" => "queries"}), do: %{name: :queries, comp: QueriesPage}

  defp resolve_page(%{"page" => "dashboards", "id" => "new"}),
    do: %{name: :dashboard_new, comp: DashboardEditorPage, mode: :new}

  defp resolve_page(%{"page" => "dashboards", "id" => id}),
    do: %{name: :dashboard_edit, comp: DashboardEditorPage, mode: :edit, id: id}

  defp resolve_page(%{"page" => slug}) do
    case Enum.find(Lotus.Web.Pro.extra_pages(), &(&1.slug == slug)) do
      nil -> resolve_page(%{})
      %{name: name, component: comp} -> %{name: name, comp: comp}
    end
  end

  defp resolve_page(_params), do: %{name: :home, comp: QueriesPage}

  # The schedules are shown with `features: [:schedules]`: their list on the
  # home page's Schedules tab, and the editor of one. Without the feature,
  # the home page.
  defp resolve_page(%{"page" => "schedules"} = params, features) do
    cond do
      :schedules not in (features || []) -> resolve_page(Map.drop(params, ["page", "id"]))
      params["id"] == "new" -> %{name: :schedule_new, comp: SchedulesPage, mode: :new}
      params["id"] -> %{name: :schedule_edit, comp: SchedulesPage, mode: :edit, id: params["id"]}
      true -> %{name: :schedules, comp: QueriesPage}
    end
  end

  defp resolve_page(params, _features), do: resolve_page(params)
end
