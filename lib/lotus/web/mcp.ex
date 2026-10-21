if Code.ensure_loaded?(Sake.Server) do
  defmodule Lotus.Web.MCP do
    @moduledoc """
    Lotus's MCP server with Lotus Web on top: every tool of `Lotus.MCP`, the
    `show_chart` tool, whose chart an MCP App draws inside the conversation
    (in hosts that render apps, such as Claude), and your
    `Lotus.Web.Resolver` deciding who may do what, as it does in the
    dashboard.

    Compiled only when the host depends on `:sake`. Serve it instead of
    `Lotus.MCP`:

        # router.ex
        sake_endpoint "/lotus/mcp", server: Lotus.Web.MCP, auth: true

        # config/config.exs
        config :lotus_web, Lotus.Web.MCP, resolver: MyApp.LotusResolver

    That's all: this server tells `Lotus.MCP` to ask `authorize?/1` and
    `actor/1` (with `Lotus.MCP.Host`), so `config :lotus, :mcp` needs neither
    `authorize:` nor `actor:`. Where it sets one, it still wins.

    `authorize?/1` lets in whoever the resolver's `resolve_access/1` gives
    `:all` or `:read_only` access; `actor/1` gives Lotus the
    `resolve_context/1` and `resolve_scope/1` the dashboard would. Each tool
    then needs the dashboard action it stands for (see
    `Lotus.Web.MCP.Access`), decided by the resolver's `authorize/3`, or by
    the access level without one.

    See the MCP guide.
    """

    alias Lotus.Web.{Actor, Resolver}

    require Logger

    use Sake.Server,
      name: "lotus",
      version: Mix.Project.config()[:version],
      instructions: """
      To show a result as a chart, use show_chart with a saved query (its own chart, or
      chart_type and fields) or a statement: hosts that render apps draw it in the
      conversation, others get its data.
      """

    mount Lotus.MCP

    tools [Lotus.Web.MCP.ShowChart]
    resources [Lotus.Web.MCP.ChartApp]

    # Who may use Lotus and as which actor: this server's resolver.
    middleware :before_request, [
      {Lotus.MCP.Host, authorize: {__MODULE__, :authorize?}, actor: {__MODULE__, :actor}}
    ]

    # Lotus.MCP's own gate covers only the components it declares: run it
    # on this server's list too, so show_chart is behind it as well.
    middleware :after_list, [Lotus.MCP.Authorize, Lotus.Web.MCP.Access]
    middleware :before_call, [Lotus.Web.MCP.Access]
    middleware :after_call, [Lotus.Web.MCP.Access]
    middleware :before_read, [Lotus.Web.MCP.Access]

    @doc """
    Whether `user` may use Lotus over MCP: the resolver's `resolve_access/1`
    gives `:all` or `:read_only`. `Lotus.MCP` asks it on every request.

    A resolver that does not implement `resolve_access/1` lets nobody in,
    rather than everybody, as the dashboard's default would: an MCP endpoint
    has no router pipeline in front of it to keep strangers out.
    """
    @spec authorize?(Resolver.user()) :: boolean()
    def authorize?(user) do
      resolver = resolver()

      if resolver && Resolver.implements?(resolver, :resolve_access, 1) do
        resolver.resolve_access(user) in [:all, :read_only]
      else
        Logger.warning(
          "Lotus.Web.MCP refused a request: set `config :lotus_web, Lotus.Web.MCP, resolver: ...` " <>
            "to a resolver that implements resolve_access/1"
        )

        false
      end
    end

    @doc """
    The `:context` and `:scope` the dashboard would give Lotus for `user`,
    the actor `Lotus.MCP` runs its tools with.
    """
    @spec actor(Resolver.user()) :: nonempty_list({:context, term()} | {:scope, term()})
    def actor(user) do
      {context, scope} = Actor.resolve(resolver(), user)
      [context: context, scope: scope]
    end

    @doc false
    @spec resolver() :: module() | nil
    def resolver, do: Application.get_env(:lotus_web, __MODULE__, [])[:resolver]
  end
end
