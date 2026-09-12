defmodule Lotus.Web.Router do
  @moduledoc """
  Mounts the dashboard in a host router.

  Import the module and call `lotus_dashboard/2` inside a scope:

      import Lotus.Web.Router

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]

        lotus_dashboard "/lotus"
      end

  The macro defines the live sessions, the routes of the dashboard pages, the
  public dashboard route, the CSV export route, and the asset routes. See
  `lotus_dashboard/2` for the options.
  """

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
    and access control. The module must exist: a resolver that cannot be loaded fails the compile,
    because Lotus would otherwise fall back to its permissive defaults and give every visitor full
    access.

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

      Lotus.Web.Router.__register_resolver_check__(__MODULE__, opts)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]
        import Phoenix.Router, only: [get: 4]

        {session_name, session_opts, public_session_opts, route_opts, export_opts} =
          Lotus.Web.Router.__options__(prefix, opts)

        # Compiled CSS and JS, served with immutable caching under a content
        # hash. Named so hosts get `lotus_asset_path/3` rather than a generic
        # `assets_path` that could collide with their own routes.
        get("/css-:md5", Lotus.Web.Assets, :css, as: :lotus_asset)
        get("/js-:md5", Lotus.Web.Assets, :js, as: :lotus_asset)

        # Export endpoint - does not require LiveView session, so it carries the
        # resolver in the route's private data to resolve the actor itself.
        get("/export/csv", Lotus.Web.ExportController, :csv, export_opts)

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
  def __register_resolver_check__(module, opts) do
    resolver = Keyword.get(opts, :resolver, @default_opts[:resolver])

    if resolver not in [nil, Lotus.Web.Resolver] do
      # The resolver may not be compiled yet, and it cannot be compiled on
      # demand here: a resolver that uses `~p` depends on the router, so
      # `Code.ensure_compiled/1` would deadlock. `@after_verify` runs once the
      # router is compiled, when the resolver is available.
      unless Module.has_attribute?(module, :lotus_resolvers) do
        Module.register_attribute(module, :lotus_resolvers, accumulate: true, persist: true)
        Module.put_attribute(module, :after_verify, {__MODULE__, :__verify_resolvers__})
      end

      Module.put_attribute(module, :lotus_resolvers, resolver)
    end
  end

  @doc false
  def __verify_resolvers__(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:lotus_resolvers)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.each(&verify_resolver!(&1, module))
  end

  defp verify_resolver!(resolver, module) do
    unless Code.ensure_loaded?(resolver) do
      raise ArgumentError, """
      the :resolver given to lotus_dashboard in #{inspect(module)} does not exist:

          #{inspect(resolver)}

      Check the module name for a typo. Lotus falls back to its own permissive \
      defaults for a resolver it cannot load, which would give every visitor \
      full access to the dashboard.
      """
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

    export_opts = [private: %{lotus_resolver: opts[:resolver]}]

    {session_name, session_opts, public_session_opts, [as: session_name], export_opts}
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
