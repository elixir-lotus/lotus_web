defmodule Lotus.Web.Actor do
  @moduledoc """
  Who the dashboard is acting for, in the shape Lotus core expects.

  Core accepts `:context` and `:scope` on every call that runs a query or
  lists schema objects. `:context` reaches middleware and telemetry, `:scope`
  reaches the visibility resolver and the cache key. The dashboard resolves
  both at mount through `Lotus.Web.Resolver` and carries them as assigns;
  this module turns those assigns into the option list core takes.

  A `nil` context and a `nil` scope produce `[]`, so an unscoped dashboard
  calls core exactly as it did before an actor existed — same middleware
  payloads, same cache keys.

  ## Catching an actor that never arrived

  A `Phoenix.LiveComponent` holds only what its parent passes, so a component
  nobody handed the actor to calls core unscoped, and silently. Set

      config :lotus_web, strict_actor: true

  in `dev` and `test` and `opts/1` raises for assigns that carry no `:context`
  key at all, which tells that mistake apart from a dashboard that has no actor
  to give. Leave it off in production, where an unscoped call beats a crash.
  """

  alias Lotus.Web.Resolver

  @typedoc """
  The actor as the dashboard carries it between components: `{context, scope}`.
  """
  @type t :: {term(), term()}

  @doc """
  Resolve the actor for a user through the given resolver.

  Returns `{context, scope}`. Both are `nil` unless the resolver implements
  `c:Lotus.Web.Resolver.resolve_context/1` or
  `c:Lotus.Web.Resolver.resolve_scope/1`.
  """
  @spec resolve(module() | nil, Resolver.user()) :: {term(), term()}
  def resolve(nil, _user), do: {nil, nil}

  def resolve(resolver, user) do
    {
      Resolver.call_with_fallback(resolver, :resolve_context, [user]),
      Resolver.call_with_fallback(resolver, :resolve_scope, [user])
    }
  end

  @doc """
  Build the `:context` / `:scope` options for a core call.

  Takes either the socket assigns or an explicit `{context, scope}` pair.
  Keys whose value is `nil` are left out.
  """
  @spec opts(map() | t()) :: keyword()
  def opts(%{} = assigns) do
    check_actor_arrived!(assigns)

    opts({assigns[:context], assigns[:scope]})
  end

  def opts({context, scope}) do
    Enum.reject([context: context, scope: scope], fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Merge the actor options into an existing option list.

  Options already present win, so a caller can override the actor for a
  single call.
  """
  @spec merge(keyword(), map() | t()) :: keyword()
  def merge(opts, source) when is_list(opts) do
    Keyword.merge(opts(source), opts)
  end

  # A LiveComponent holds only what its parent passes, so assigns that carry no
  # `:context` key at all mean the actor never reached this component. That is a
  # wiring mistake, not an unscoped dashboard, and it is worth a loud failure
  # while developing.
  #
  # Off unless a host asks for it, so a production dashboard degrades to an
  # unscoped call rather than a crash.
  defp check_actor_arrived!(assigns) do
    if strict?() and not Map.has_key?(assigns, :context) do
      raise ArgumentError, """
      Lotus.Web.Actor.opts/1 got assigns that carry no :context key.

      A LiveComponent holds only what its parent passes, so this usually means
      the actor was never handed down. Pass it as a prop:

          <.live_component module={MyComponent} id="my-component" actor={@actor} />

      and call `Actor.opts(@actor)` in the component.

      For a call that is deliberately unscoped, such as a public dashboard,
      pass the actor explicitly as `Actor.opts({nil, nil})`.
      """
    end

    :ok
  end

  # Also read by Lotus.Web.Authorization, which treats missing assigns the same way.
  @doc false
  def strict?, do: Application.get_env(:lotus_web, :strict_actor, false)
end
