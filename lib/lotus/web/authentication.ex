defmodule Lotus.Web.Authentication do
  @moduledoc """
  `on_mount` hook that applies the access level of the resolver.

  `Lotus.Web.Router.lotus_dashboard/2` adds this hook to the live session
  after the host's own `:on_mount` hooks, so a host never lists it. The hook
  assigns the resolver, the user and the access level that
  `Lotus.Web.Resolver` produced at the session, and stops a `:forbidden`
  mount with a redirect.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    resolver = Map.get(session, "resolver")
    user = Map.get(session, "user")
    access = Map.get(session, "access", :all)

    socket = assign(socket, resolver: resolver, user: user, access: access)

    case access do
      {:forbidden, path} ->
        socket =
          socket
          |> put_flash(:error, "Access forbidden")
          |> push_navigate(to: path)

        {:halt, socket}

      :forbidden ->
        socket =
          socket
          |> put_flash(:error, "Access forbidden")
          |> push_navigate(to: "/")

        {:halt, socket}

      _ ->
        {:cont, socket}
    end
  end
end
