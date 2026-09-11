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
  """

  @doc """
  Resolve the actor for a user through the given resolver.

  Returns `{context, scope}`. Both are `nil` unless the resolver implements
  `c:Lotus.Web.Resolver.resolve_context/1` or
  `c:Lotus.Web.Resolver.resolve_scope/1`.
  """
  @spec resolve(module() | nil, Lotus.Web.Resolver.user()) :: {term(), term()}
  def resolve(nil, _user), do: {nil, nil}

  def resolve(resolver, user) do
    {
      Lotus.Web.Resolver.call_with_fallback(resolver, :resolve_context, [user]),
      Lotus.Web.Resolver.call_with_fallback(resolver, :resolve_scope, [user])
    }
  end

  @doc """
  Build the `:context` / `:scope` options for a core call.

  Takes either the socket assigns or an explicit `{context, scope}` pair.
  Keys whose value is `nil` are left out.
  """
  @spec opts(map() | {term(), term()}) :: keyword()
  def opts(%{} = assigns), do: opts({assigns[:context], assigns[:scope]})

  def opts({context, scope}) do
    Enum.reject([context: context, scope: scope], fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Merge the actor options into an existing option list.

  Options already present win, so a caller can override the actor for a
  single call.
  """
  @spec merge(keyword(), map() | {term(), term()}) :: keyword()
  def merge(opts, source) when is_list(opts) do
    Keyword.merge(opts(source), opts)
  end
end
