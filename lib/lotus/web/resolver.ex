defmodule Lotus.Web.Resolver do
  @moduledoc """
  Behavior for customizing Lotus Web dashboard access and functionality.
  """

  @type user :: nil | map() | struct()

  @type access_level ::
          :all
          | :read_only
          | :forbidden
          | {:forbidden, String.t()}

  @doc """
  Extract the current user from a Plug.Conn when the dashboard mounts.

  This callback is invoked when the Lotus dashboard is accessed. The returned
  user value will be passed to other callbacks for access control decisions.
  """
  @callback resolve_user(conn :: Plug.Conn.t()) :: user()

  @doc """
  Determine the access level for a user.

  Based on the user returned from `resolve_user/1`, this callback determines
  what operations the user can perform in the Lotus dashboard.

  ## Return Values

  - `:all` - Full access to all Lotus features
  - `:read_only` - Can only view and run queries, no modifications
  - `:forbidden` - No access
  - `{:forbidden, path}` - Redirect to the given path
  """
  @callback resolve_access(user :: user()) :: access_level()

  @doc """
  Build the actor that the dashboard passes to Lotus core as `:context`.

  Core hands `:context` to middleware and to the `:after_discover` telemetry
  event without interpreting it, so this is where a host app says *who* is
  behind a dashboard-driven query. Without it an access-control plug sees
  `nil` for everything the dashboard runs.

  Returns `nil` by default. The value is rebuilt on every mount, so it does
  not need to survive a session round trip.

  ## Examples

      def resolve_context(%{id: id, roles: roles}), do: %{user_id: id, roles: roles}
      def resolve_context(nil), do: nil
  """
  @callback resolve_context(user :: user()) :: term()

  @doc """
  Build the scope that the dashboard passes to Lotus core as `:scope`.

  Core hands `:scope` to the visibility resolver and hashes it into the
  discovery and result cache keys, so two scopes never read each other's
  cached rows. Keep it low-cardinality — a tenant id, not a user id with a
  timestamp — or the caches stop earning their keep.

  Returns `nil` by default, which keeps cache keys identical to an
  unscoped dashboard.

  ## Examples

      def resolve_scope(%{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
      def resolve_scope(nil), do: nil
  """
  @callback resolve_scope(user :: user()) :: term()

  @optional_callbacks resolve_user: 1, resolve_access: 1, resolve_context: 1, resolve_scope: 1

  @doc false
  def call_with_fallback(resolver, fun, args) when is_atom(fun) and is_list(args) do
    resolver =
      if Code.ensure_loaded?(resolver) and function_exported?(resolver, fun, length(args)),
        do: resolver,
        else: __MODULE__

    apply(resolver, fun, args)
  end

  @doc false
  def resolve_user(_conn), do: nil

  @doc false
  def resolve_access(_user), do: :all

  @doc false
  def resolve_context(_user), do: nil

  @doc false
  def resolve_scope(_user), do: nil
end
