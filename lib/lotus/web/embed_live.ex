defmodule Lotus.Web.EmbedLive do
  # A dashboard, or one card, in another app's page: the routes of
  # `Lotus.Web.Router.lotus_embed/2`. Embedding is a Lotus Pro feature: Pro
  # checks the token (`Lotus.Web.Pro.verify_embed/2`) and gives the viewer's
  # context and scope, under which the cards run. Without Pro the page says
  # embedding needs Lotus Pro.
  use Lotus.Web, :embed_live_view

  alias Lotus.Web.{Branding, Pro, PublicDashboardPage}

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    %{"prefix" => prefix, "live_path" => live_path, "live_transport" => live_transport} = session

    put_router_prefix(socket, prefix)

    socket =
      socket
      |> assign(live_path: live_path, live_transport: live_transport)
      |> assign(:csp_nonces, session["csp_nonces"])
      |> assign(:card_concurrency, session["card_concurrency"])
      |> assign(:theme, session["theme"] || :lotus)
      |> assign(:themes, session["themes"] || Lotus.Web.Theme.names())
      |> assign(:theme_colors, session["theme_colors"] || %{})
      |> assign(:page_title, "Lotus")
      |> assign(resolver: nil, user: nil, access: :read_only, features: [])
      |> assign(context: nil, scope: nil, actor: {nil, nil}, public_view: true)
      |> assign(:embed_error, nil)
      |> assign(:page, %{name: :embed, comp: PublicDashboardPage})
      |> PublicDashboardPage.handle_mount()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"token" => token} = params, uri, socket) do
    kind = socket.assigns.live_action

    case Pro.verify_embed(token, %{kind: kind, params: params}) do
      {:ok, grant} ->
        socket =
          socket
          |> assign(context: grant.context, scope: grant.scope)
          |> assign(:actor, {grant.context, grant.scope})
          |> assign(:page, %{name: :embed, comp: PublicDashboardPage, grant: grant})
          |> Branding.assign_branding(%{
            user: nil,
            context: grant.context,
            scope: grant.scope,
            public: true,
            dashboard: nil
          })

        PublicDashboardPage.handle_params(params, uri, socket)

      {:error, reason} ->
        {:noreply, assign(socket, :embed_error, message(reason))}
    end
  end

  defp message(:no_pro), do: gettext("Embedding needs Lotus Pro")
  defp message(message) when is_binary(message), do: message
  defp message(_reason), do: gettext("This embed is not available")

  @impl Phoenix.LiveView
  def render(%{embed_error: message} = assigns) when is_binary(message) do
    ~H"""
    <div id="embed-unavailable" class="flex h-full items-center justify-center p-6 text-sm text-gray-500 dark:text-gray-400">
      {@embed_error}
    </div>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> Map.put(:id, "page")
      |> Map.drop(~w(csp_nonces flash live_path live_transport socket)a)

    ~H"""
    <.live_component id="page" module={@page.comp} {assigns} />
    """
  end

  @impl Phoenix.LiveView
  def handle_info(message, socket), do: PublicDashboardPage.handle_info(message, socket)

  @impl Phoenix.LiveView
  def handle_async(name, result, socket),
    do: PublicDashboardPage.handle_async(name, result, socket)
end
