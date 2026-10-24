defmodule Lotus.Web.Pro do
  @moduledoc false

  # The module, a setting only so that tests can stand in for it.
  defp pro_web, do: Application.get_env(:lotus_web, :__pro_web__, Lotus.Pro.Web)

  @doc """
  Returns `true` if `Lotus.Pro.Web` is available at runtime.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(pro_web())
  end

  @doc """
  Returns Pro page descriptors, or `[]` if Pro is not installed.
  """
  @spec extra_pages() :: [map()]
  def extra_pages do
    if available?(), do: apply(pro_web(), :pages, []), else: []
  end

  @doc """
  Returns Pro nav item descriptors for the given assigns, or `[]` if Pro is not installed.
  """
  @spec nav_items(map()) :: [map()]
  def nav_items(assigns) do
    if available?(), do: apply(pro_web(), :nav_items, [assigns]), else: []
  end

  @doc """
  Renders Pro slot content, or `nil` if Pro is not installed.
  """
  @spec render_slot(atom(), map()) :: term() | nil
  def render_slot(name, assigns) do
    if available?(), do: apply(pro_web(), :render_slot, [name, assigns]), else: nil
  end

  @doc """
  Lets Pro watch a dashboard that a LiveView shows, for live updates: Pro
  sends the LiveView `{:card_result, card_id, result}` when a card's data
  changes, as a card that ran does. Does nothing without Pro.
  """
  @spec watch_dashboard(map(), pid()) :: :ok
  def watch_dashboard(dashboard, pid) do
    if available?() and function_exported?(pro_web(), :watch_dashboard, 2),
      do: apply(pro_web(), :watch_dashboard, [dashboard, pid])

    :ok
  end

  @doc """
  Whether a public dashboard may be shown through its share link, asked on
  every load of the link with the URL's params: `:allow`, or
  `{:deny, message}` to show the message instead of the dashboard. Without
  Pro, or when Pro does not decide, every link is allowed, as before. An
  answer it does not understand denies.
  """
  @spec authorize_public_dashboard(map(), map()) :: :allow | {:deny, String.t() | nil}
  def authorize_public_dashboard(dashboard, params) do
    if available?() and function_exported?(pro_web(), :authorize_public_dashboard, 2) do
      case apply(pro_web(), :authorize_public_dashboard, [dashboard, params]) do
        :allow -> :allow
        {:deny, message} when is_binary(message) -> {:deny, message}
        _other -> {:deny, nil}
      end
    else
      :allow
    end
  end

  @doc """
  The branding of a request, asked when the dashboard mounts and when a
  public dashboard is loaded. `info` has the `:user`, `:context` and
  `:scope` of the request, `:public` and, on a public dashboard, the
  `:dashboard`. Pro answers a map with any of `:product_name`, `:logo` (an
  image URL), `:assistant_name`, `:theme` and `:theme_colors`. The
  "Powered by Lotus" footer is not part of it: it always shows. `%{}` without Pro: the dashboard
  is Lotus.
  """
  @spec branding(map()) :: map()
  def branding(info) do
    with true <- available?() and function_exported?(pro_web(), :branding, 1),
         %{} = branding <- apply(pro_web(), :branding, [info]) do
      branding
    else
      _ -> %{}
    end
  end

  @doc """
  The request as Lotus Pro sees it in `list_options/2` and the slots: the
  `:user`, `:context`, `:scope` and URL `:params` of the assigns.
  """
  @spec request_info(map()) :: map()
  def request_info(assigns) do
    %{
      user: assigns[:user],
      context: assigns[:context],
      scope: assigns[:scope],
      params: assigns[:params] || %{}
    }
  end

  @doc """
  The options Lotus Pro adds to a list of `:queries` or `:dashboards` for a
  request (`request_info/1`): `:owner_id` and `:tenant_id`, as
  `Lotus.Storage.list_queries_by/1` and `Lotus.list_dashboards_by/1` take
  them, for a tenant's content or "mine". Other keys are ignored. `[]`
  without Pro: every query and dashboard is listed.
  """
  @spec list_options(:queries | :dashboards, map()) :: keyword()
  def list_options(kind, info) when kind in [:queries, :dashboards] do
    with true <- available?() and function_exported?(pro_web(), :list_options, 2),
         options when is_list(options) <- apply(pro_web(), :list_options, [kind, info]) do
      options |> Keyword.take([:owner_id, :tenant_id]) |> Enum.reject(&is_nil(elem(&1, 1)))
    else
      _ -> []
    end
  end

  @doc "The queries listed for the request: all of them without Pro."
  @spec list_queries(map()) :: [Lotus.Storage.Query.t()]
  def list_queries(info) do
    case list_options(:queries, info) do
      [] -> Lotus.list_queries()
      options -> Lotus.Storage.list_queries_by(options)
    end
  end

  @doc "The dashboards listed for the request, with `opts` (`:preload`): all of them without Pro."
  @spec list_dashboards(map(), keyword()) :: [Lotus.Storage.Dashboard.t()]
  def list_dashboards(info, opts \\ []) do
    case list_options(:dashboards, info) do
      [] -> Lotus.list_dashboards(opts)
      options -> Lotus.list_dashboards_by(opts ++ options)
    end
  end

  @doc """
  The kinds of card Lotus Pro adds to a dashboard (`card_type: :pro`), for
  the request: maps with `:kind`, `:label` and `:description`. A card of a
  kind keeps it in its `content` (`%{"kind" => kind}`). `[]` without Pro:
  the free version adds no Pro cards.
  """
  @spec card_kinds(map()) :: [%{kind: String.t(), label: String.t(), description: String.t()}]
  def card_kinds(info) do
    with true <- available?() and function_exported?(pro_web(), :card_kinds, 1),
         kinds when is_list(kinds) <- apply(pro_web(), :card_kinds, [info]) do
      for %{kind: kind, label: label} = given <- kinds,
          is_binary(kind) and kind != "",
          is_binary(label),
          do: %{kind: kind, label: label, description: text(given[:description])}
    else
      _ -> []
    end
  end

  @doc """
  Lotus Pro's drawing of a Pro card, given the card and `assigns` (`:info`,
  as `request_info/1`, `:public`, `:can_manage`). `nil` without Pro, or
  when Pro does not draw it: the card then says it needs Lotus Pro.
  """
  @spec render_card(map(), map()) :: term() | nil
  def render_card(card, assigns) do
    if available?() and function_exported?(pro_web(), :render_card, 2),
      do: apply(pro_web(), :render_card, [card, assigns])
  end

  @doc """
  The actions Lotus Pro offers on each row of a query card's table, for the
  request: maps with a `:label` and either `:on_action`, a function of the
  row's context called in the LiveView (`Masu.Action`), or `:navigate`, a
  function of the row giving a path. `[]` without Pro.
  """
  @spec row_actions(map(), map()) :: [map()]
  def row_actions(card, info) do
    with true <- available?() and function_exported?(pro_web(), :row_actions, 2),
         actions when is_list(actions) <- apply(pro_web(), :row_actions, [card, info]) do
      Enum.filter(actions, fn
        %{label: label, on_action: fun} when is_binary(label) -> is_function(fun, 1)
        %{label: label, navigate: fun} when is_binary(label) -> is_function(fun, 1)
        _other -> false
      end)
    else
      _ -> []
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  @doc """
  Lotus Pro's check of an embed token, asked on every load of an embed
  route (`Lotus.Web.Router.lotus_embed/2`) and by `Lotus.Web.EmbedFrame`.
  `info` has the route's `:kind` (`:dashboard` or `:card`) and the URL's
  `:params`.

  Pro answers `{:ok, grant}` or `{:error, message}`. A grant has the
  `:resource` the token opens, `{:dashboard, id}` or `{:card, id}` (of the
  route's kind), and may have the viewer's `:context` and `:scope`, the
  `:filters` the host sets (`%{"region" => "north"}`), and the
  `:frame_ancestors` that may frame the page (`["https://app.example.com"]`).
  Without Pro, `{:error, :no_pro}`: embedding is a Lotus Pro feature.
  """
  @spec verify_embed(String.t(), map()) :: {:ok, map()} | {:error, String.t() | :no_pro | nil}
  def verify_embed(token, %{kind: kind} = info) when kind in [:dashboard, :card] do
    if available?() and function_exported?(pro_web(), :verify_embed, 2) do
      case apply(pro_web(), :verify_embed, [token, info]) do
        {:ok, %{resource: {^kind, id}} = grant} when not is_nil(id) -> {:ok, grant(grant)}
        {:error, message} when is_binary(message) -> {:error, message}
        _other -> {:error, nil}
      end
    else
      {:error, :no_pro}
    end
  end

  defp grant(grant) do
    filters = if is_map(grant[:filters]), do: grant[:filters], else: %{}
    ancestors = for origin <- List.wrap(grant[:frame_ancestors]), is_binary(origin), do: origin

    %{
      resource: grant.resource,
      context: grant[:context],
      scope: grant[:scope],
      filters: Map.new(filters, fn {name, value} -> {to_string(name), value} end),
      frame_ancestors: ancestors
    }
  end
end
