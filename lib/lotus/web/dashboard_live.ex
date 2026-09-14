defmodule Lotus.Web.DashboardLive do
  use Lotus.Web, :live_view

  alias Lotus.Web.{Actor, Assets, Authorization}
  alias Lotus.Web.{DashboardEditorPage, PublicDashboardPage, QueriesPage, QueryEditorPage}

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"prefix" => prefix} = session
    %{"live_path" => live_path, "live_transport" => live_transport} = session
    %{"csp_nonces" => csp_nonces} = session

    page = resolve_page(params)
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
      |> assign(:features, features)
      |> assign(:public_view, page.name == :public_dashboard)
      |> assign_permissions()
      |> page.comp.handle_mount()

    {:ok, socket}
  end

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

  @impl Phoenix.LiveView
  def handle_params(_params, uri, %{assigns: %{assets_stale?: true}} = socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    to = if query, do: path <> "?" <> query, else: path
    {:noreply, redirect(socket, to: to)}
  end

  def handle_params(params, uri, socket) do
    page = resolve_page(params)
    socket = assign(socket, page: page)
    socket.assigns.page.comp.handle_params(params, uri, socket)
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
end
