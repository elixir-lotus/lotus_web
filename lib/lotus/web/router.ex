defmodule Lotus.Web.Router do
  @moduledoc false

  @default_opts [
    socket_path: "/live",
    transport: "websocket",
    csp_nonce_assign_key: nil,
    resolver: Lotus.Web.Resolver,
    features: []
  ]

  @transport_values ~w(longpoll websocket)

  @doc """
  Defines an lotus dashboard route.

  It requires a path where to mount the dashboard at and allows options to customize routing.

  ## Options

  * `:as` — override the route name; otherwise defaults to `:lotus_dashboard`

  * `:on_mount` — declares additional module callbacks to be invoked when the dashboard mounts

  * `:socket_path` — a phoenix socket path for live communication, defaults to `"/live"`.

  * `:transport` — a phoenix socket transport, either `"websocket"` or `"longpoll"`, defaults to
    `"websocket"`.

  * `:resolver` — a module implementing the `Lotus.Web.Resolver` behaviour for custom authentication
    and access control.

  * `:features` — a list of optional feature flags to enable. Defaults to `[]`.
    Supported features:
    * `:timeout_options` — shows a per-query timeout selector in the query editor toolbar.

  ## Examples

  Mount a `lotus` dashboard at the path "/lotus":

      defmodule MyAppWeb.Router do
        use Phoenix.Router

        import Lotus.Web.Router

        scope "/", MyAppWeb do
          pipe_through [:browser]

          lotus_dashboard "/lotus"
        end
      end
  """
  defmacro lotus_dashboard(path, opts \\ []) do
    quote bind_quoted: binding() do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]
        import Phoenix.Router, only: [get: 3]

        {session_name, session_opts, public_session_opts, route_opts} =
          Lotus.Web.Router.__options__(prefix, opts)

        get("/css-:md5", Lotus.Web.Assets, :css)
        get("/js-:md5", Lotus.Web.Assets, :js)

        # Export endpoint - does not require LiveView session
        get("/export/csv", Lotus.Web.ExportController, :csv)

        # Public dashboard - separate live_session without authentication
        live_session :"#{session_name}_public", public_session_opts do
          live("/public/:token", Lotus.Web.DashboardLive, :show)
        end

        live_session session_name, session_opts do
          live("/", Lotus.Web.DashboardLive, :home, route_opts)
          live("/:page", Lotus.Web.DashboardLive, :index, route_opts)
          live("/:page/:id", Lotus.Web.DashboardLive, :show, route_opts)
        end
      end
    end
  end

  @doc false
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    on_mount =
      Keyword.get(opts, :on_mount, []) ++ [Lotus.Web.Locale, Lotus.Web.Authentication]

    session_args = [
      prefix,
      opts[:socket_path],
      opts[:transport],
      opts[:csp_nonce_assign_key],
      opts[:resolver],
      opts[:features]
    ]

    session_opts = [
      on_mount: on_mount,
      session: {__MODULE__, :__session__, session_args},
      root_layout: {Lotus.Web.Layouts, :root}
    ]

    # Public session - no authentication on_mount
    public_session_args = [
      prefix,
      opts[:socket_path],
      opts[:transport],
      opts[:csp_nonce_assign_key]
    ]

    public_session_opts = [
      on_mount: [Lotus.Web.Locale],
      session: {__MODULE__, :__public_session__, public_session_args},
      root_layout: {Lotus.Web.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :lotus_dashboard)

    {session_name, session_opts, public_session_opts, as: session_name}
  end

  @doc false
  def __session__(conn, prefix, live_path, live_transport, csp_key, resolver, features) do
    csp_keys = expand_csp_nonce_keys(csp_key)

    user = Lotus.Web.Resolver.call_with_fallback(resolver, :resolve_user, [conn])
    access = Lotus.Web.Resolver.call_with_fallback(resolver, :resolve_access, [user])

    %{
      "prefix" => prefix,
      "live_path" => live_path,
      "live_transport" => live_transport,
      "resolver" => resolver,
      "user" => user,
      "access" => access,
      "features" => features || [],
      "csp_nonces" => %{
        style: conn.assigns[csp_keys[:style]],
        script: conn.assigns[csp_keys[:script]]
      }
    }
  end

  @doc false
  def __public_session__(conn, prefix, live_path, live_transport, csp_key) do
    csp_keys = expand_csp_nonce_keys(csp_key)

    %{
      "prefix" => prefix,
      "live_path" => live_path,
      "live_transport" => live_transport,
      "csp_nonces" => %{
        style: conn.assigns[csp_keys[:style]],
        script: conn.assigns[csp_keys[:script]]
      }
    }
  end

  defp expand_csp_nonce_keys(nil), do: %{style: nil, script: nil}
  defp expand_csp_nonce_keys(key) when is_atom(key), do: %{style: key, script: key}
  defp expand_csp_nonce_keys(map) when is_map(map), do: map

  defp validate_opt!({_key, _value} = opt) do
    unless valid_opt?(opt) do
      raise ArgumentError, "invalid option for lotus_dashboard: #{inspect(opt)}"
    end
  end

  defp valid_opt?({:as, value}) when is_atom(value), do: true
  defp valid_opt?({:on_mount, _}), do: true
  defp valid_opt?({:socket_path, value}) when is_binary(value), do: true
  defp valid_opt?({:transport, value}) when value in @transport_values, do: true
  defp valid_opt?({:csp_nonce_assign_key, _}), do: true
  defp valid_opt?({:resolver, value}) when is_atom(value) or is_nil(value), do: true
  defp valid_opt?({:features, value}) when is_list(value), do: true
  defp valid_opt?(_), do: false
end
