defmodule Lotus.Web.Authorization do
  @moduledoc """
  Asks the host whether the current user may perform an action.

  The dashboard asks one question in one place: **may this user do this
  action, on this resource?** It asks before a control renders, so a control
  the user may not use is not shown, and again in the event handler, so a
  crafted event is refused too.

  The host answers through `c:Lotus.Web.Resolver.authorize/3`. A resolver
  that does not implement it gets a decision derived from
  `c:Lotus.Web.Resolver.resolve_access/1`, see `default_decision/2`.

  ## Actions and resources

  | Action | Resource |
  |---|---|
  | `:query` | the data source name |
  | `:export` | the data source name |
  | `:ai_generate` | the data source name |
  | `:discover` | the data source name |
  | `:create_query` | `nil` |
  | `:update_query` | the stored `%Lotus.Storage.Query{}` |
  | `:delete_query` | the `%Lotus.Storage.Query{}` |
  | `:share_query` | the `%Lotus.Storage.Query{}` (no dashboard control asks it yet) |
  | `:share_dashboard` | the `%Lotus.Storage.Dashboard{}` whose public link changes |
  | `:view_dashboard` | the `%Lotus.Storage.Dashboard{}` |
  | `:manage_dashboard` | `nil` for a new dashboard, else the `%Lotus.Storage.Dashboard{}` |
  | `:manage_source` | `nil` |
  | `:manage_cache` | `nil` |

  ## Cost

  Templates ask on every render. At mount the dashboard computes the actions
  that take no resource once, into the `:permissions` assign, and
  `allowed?/3` reads that map. Actions with a resource are asked on demand, so
  the callback must not do I/O per call; cache the policy in the host.
  """

  use Gettext, backend: Lotus.Web.Gettext

  require Logger

  alias Lotus.Web.Actor
  alias Lotus.Web.Resolver

  @actions [
    :query,
    :export,
    :discover,
    :create_query,
    :update_query,
    :delete_query,
    :share_query,
    :share_dashboard,
    :view_dashboard,
    :manage_dashboard,
    :ai_generate,
    :manage_source,
    :manage_cache
  ]

  @read_only_actions [:query, :export, :discover, :view_dashboard]

  @resourceless_actions [:create_query, :manage_dashboard, :manage_source, :manage_cache]

  @typedoc "A decision: allow, or deny with a reason the dashboard shows the user."
  @type decision :: :allow | {:deny, String.t()}

  @doc """
  The action vocabulary, in a fixed order.
  """
  @spec actions() :: [Resolver.action(), ...]
  def actions, do: @actions

  @doc """
  Return `true` when the user in `assigns` may perform `action` on `resource`.

  For an action without a resource, reads the `:permissions` assign when the
  dashboard computed it at mount. Use it in templates.
  """
  @spec allowed?(map(), Resolver.action(), term()) :: boolean()
  def allowed?(assigns, action, resource \\ nil)

  def allowed?(%{permissions: %{} = permissions}, action, nil)
      when is_map_key(permissions, action),
      do: Map.fetch!(permissions, action)

  def allowed?(assigns, action, resource), do: authorize(assigns, action, resource) == :allow

  @doc """
  Decide whether the user in `assigns` may perform `action` on `resource`.

  Reads `:resolver`, `:user`, `:access` and `:public_view` from `assigns`.
  Always asks, and never reads the `:permissions` cache. Use it in event
  handlers, and show the reason of a `{:deny, reason}` to the user.

  A public dashboard has no user, so the host is not asked: the decision
  derives from `:read_only` access.

  Assigns with no `:resolver` or `:access` key mean the dashboard never handed
  them down. The error is logged and the decision derives from `:read_only`
  access, so the mistake fails closed. Under
  `config :lotus_web, strict_actor: true` it raises instead, the same as
  `Lotus.Web.Actor.opts/1` does for a missing actor.
  """
  @spec authorize(map(), Resolver.action(), term()) :: decision()
  def authorize(assigns, action, resource \\ nil)

  def authorize(%{public_view: true}, action, _resource) when action in @actions,
    do: default_decision(:read_only, action)

  def authorize(%{} = assigns, action, resource) do
    decide(assigns[:resolver], assigns[:user], access(assigns), action, resource)
  end

  @doc """
  Decide for an explicit resolver, user and access level.

  Calls `c:Lotus.Web.Resolver.authorize/3` when the resolver implements it,
  else returns `default_decision/2` for `access`. Use it where no socket
  assigns exist, such as a controller.
  """
  @spec decide(
          module() | nil,
          Resolver.user(),
          Resolver.access_level(),
          Resolver.action(),
          term()
        ) ::
          decision()
  def decide(resolver, user, access, action, resource) when action in @actions do
    if resolver && Resolver.implements?(resolver, :authorize, 3) do
      resolver
      |> apply(:authorize, [user, action, resource])
      |> check_decision(resolver, action)
    else
      default_decision(access, action)
    end
  end

  @doc """
  The decision for an access level when the resolver does not implement
  `c:Lotus.Web.Resolver.authorize/3`.

  | Access | Decision |
  |---|---|
  | `:all` | `:allow` for every action |
  | `:read_only` | `:allow` for `:query`, `:export`, `:discover` and `:view_dashboard`, `{:deny, reason}` for the rest |
  | `:forbidden`, `{:forbidden, path}` | `{:deny, reason}` for every action |

  A host resolver can call it to keep the default for some actions.
  """
  @spec default_decision(Resolver.access_level(), Resolver.action()) :: decision()
  def default_decision(:all, action) when action in @actions, do: :allow

  def default_decision(:read_only, action) when action in @read_only_actions, do: :allow

  def default_decision(_access, action) when action in @actions, do: {:deny, reason(action)}

  @doc """
  Return `true` when the user in `assigns` may browse `source`: see it in the
  source list, and see its schemas, tables and columns.

  Browsing needs `:discover` or `:query` on the source. Running a query on it
  still needs `:query`.
  """
  @spec discoverable?(map(), String.t()) :: boolean()
  def discoverable?(assigns, source),
    do: allowed?(assigns, :discover, source) or allowed?(assigns, :query, source)

  @doc """
  Compute the decisions for the actions without a resource, as a map of
  action to boolean. The dashboard stores it as the `:permissions` assign.
  """
  @spec permissions(map()) :: %{Resolver.action() => boolean()}
  def permissions(assigns) do
    assigns = Map.delete(assigns, :permissions)
    Map.new(@resourceless_actions, &{&1, authorize(assigns, &1, nil) == :allow})
  end

  @doc """
  The reason the dashboard shows when it denies `action`.
  """
  @spec reason(Resolver.action()) :: String.t()
  def reason(:query), do: gettext("You don't have permission to run queries")
  def reason(:export), do: gettext("You don't have permission to export query results")
  def reason(:discover), do: gettext("You don't have permission to browse this data source")
  def reason(:create_query), do: gettext("You don't have permission to save queries")
  def reason(:update_query), do: gettext("You don't have permission to edit queries")
  def reason(:delete_query), do: gettext("You don't have permission to delete queries")
  def reason(:share_query), do: gettext("You don't have permission to share queries")
  def reason(:share_dashboard), do: gettext("You don't have permission to share dashboards")
  def reason(:view_dashboard), do: gettext("You don't have permission to view this dashboard")
  def reason(:manage_dashboard), do: gettext("You don't have permission to modify dashboards")
  def reason(:ai_generate), do: gettext("You don't have permission to use the AI assistant")
  def reason(:manage_source), do: gettext("You don't have permission to manage data sources")
  def reason(:manage_cache), do: gettext("You don't have permission to manage the cache")

  defp access(%{resolver: _resolver, access: access}), do: access

  defp access(_assigns) do
    message = """
    Lotus.Web.Authorization got assigns with no :resolver or :access key.

    A LiveComponent holds only what its parent passes, so this usually means
    the dashboard assigns were never handed down. Pass them from the page, or
    call Lotus.Web.Authorization.decide/5 with explicit values.
    """

    if Actor.strict?(), do: raise(ArgumentError, message)

    Logger.error(message <> "\nDeciding with :read_only access.")
    :read_only
  end

  # A host callback that returns something other than a decision is a bug in
  # the host. Refuse, so the mistake fails closed, and say why in the log.
  defp check_decision(:allow, _resolver, _action), do: :allow
  defp check_decision({:deny, reason} = deny, _resolver, _action) when is_binary(reason), do: deny

  defp check_decision(other, resolver, action) do
    Logger.error(
      "#{inspect(resolver)}.authorize/3 returned #{inspect(other)} for #{inspect(action)}; " <>
        "expected :allow or {:deny, reason}. Denying."
    )

    {:deny, reason(action)}
  end
end
