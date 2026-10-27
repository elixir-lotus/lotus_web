defmodule Lotus.Web.Pro do
  @moduledoc false

  alias Lotus.Web.Actor

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
  Lotus Pro's tabs of the home page, after Queries and Dashboards, for the
  request's `info` (`request_info/1`), or `[]` without it: each `%{id:,
  label:, component:}` (and `:count`), `id` a string (`?tab=<id>` opens
  it) and `component` a LiveComponent, given the request's `:info`,
  `:context` and `:scope`, that draws the tab's content.
  """
  @spec home_tabs(map()) :: [map()]
  def home_tabs(info) do
    if available?() and function_exported?(pro_web(), :home_tabs, 1),
      do: apply(pro_web(), :home_tabs, [info]),
      else: []
  end

  @doc """
  What Lotus Pro adds to the command palette for the request's assigns, or
  `%{}` without it:

    * `:create`: what the user may create, each `%{id:, label:, path:}`
      (and `:params`), under "Create", and in the header's New menu, as
      `:menu_label` (else `:label`) with `:icon` (a palette icon's name);
    * `:sources`: what the palette searches, each `%{id:, label:, icon:,
      search:}` (`id` an atom of its own, not `:queries` or `:dashboards`),
      `search` a function of the typed text returning results,
      each `%{id:, label:, path:}` (and `:subtitle`, `:params`).

  Its pages are in the palette already, as its header links them
  (`nav_items/1`), under "Go to".
  """
  @spec palette(map()) :: %{optional(:create) => [map()], optional(:sources) => [map()]}
  def palette(assigns) do
    if available?() and function_exported?(pro_web(), :palette, 1),
      do: apply(pro_web(), :palette, [assigns]),
      else: %{}
  end

  @doc """
  A short line Lotus Pro adds about a saved query or dashboard where the
  lists describe it ("Created by Ana"), or `nil` without it.
  """
  @spec byline(map()) :: String.t() | nil
  def byline(record) do
    if available?() and function_exported?(pro_web(), :byline, 1),
      do: apply(pro_web(), :byline, [record]),
      else: nil
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

  @typedoc """
  What Lotus Pro answers about a share link:

    * `:allow`, or `{:allow, opts}`: `context` is who the dashboard's
      cards and filter options run as (the link's owner, say; with none
      they run with no `:context`), `downloads: false` hides the download
      controls (a chart's "Save as PNG") on the public page, and `params`
      are kept in the link's URL when the filters change it (a grant that
      lets a reload in);
    * `{:deny, message}` to show the message instead of the dashboard;
    * `{:ask, ask}` to ask the visitor something first, such as a password
      or an email address, before the dashboard shows (`t:ask/0`).
  """
  @type public_answer ::
          :allow
          | {:allow,
             %{context: term(), downloads: boolean(), params: %{String.t() => String.t()}}}
          | {:deny, String.t() | nil}
          | {:ask, ask()}

  @typedoc """
  A form shown instead of the dashboard: an optional `:title`, `:message`,
  `:error` (the last answer was wrong) and `:submit` label, and the
  `:fields` to fill, each a `:key`, a `:label` and a `:type` (`:password`,
  `:email` or `:text`). No fields shows the message only, such as "We sent
  you a link".
  """
  @type ask :: %{
          title: String.t() | nil,
          message: String.t() | nil,
          error: String.t() | nil,
          submit: String.t() | nil,
          fields: [%{key: String.t(), label: String.t(), type: :password | :email | :text}]
        }

  @doc """
  Whether a public dashboard may be shown through its share link, asked on
  every load of the link with the URL's params (`t:public_answer/0`).
  Without Pro, or when Pro does not decide, every link is allowed, as
  before. An answer it does not understand denies.
  """
  @spec authorize_public_dashboard(map(), map()) :: public_answer()
  def authorize_public_dashboard(dashboard, params) do
    if available?() and function_exported?(pro_web(), :authorize_public_dashboard, 2) do
      public_answer(apply(pro_web(), :authorize_public_dashboard, [dashboard, params]))
    else
      :allow
    end
  end

  @doc """
  Lotus Pro's answer to what the visitor filled in on a share link's form
  (`{:ask, ask}`): `answers` by field key, with the URL's `params`. Pro
  answers as `authorize_public_dashboard/2` does, and `{:allow, opts}` may
  also give `params` to add to the link's URL, so that a reload keeps the
  access (a signed grant, say). Without Pro's callback, denies.
  """
  @spec answer_public_dashboard(map(), %{String.t() => String.t()}, map()) :: public_answer()
  def answer_public_dashboard(dashboard, answers, params) do
    if available?() and function_exported?(pro_web(), :answer_public_dashboard, 3) do
      public_answer(apply(pro_web(), :answer_public_dashboard, [dashboard, answers, params]))
    else
      {:deny, nil}
    end
  end

  defp public_answer(:allow), do: :allow

  defp public_answer({:allow, opts}) when is_list(opts),
    do: public_answer({:allow, Map.new(opts)})

  defp public_answer({:allow, %{} = opts}) do
    {:allow,
     %{
       context: Map.get(opts, :context),
       downloads: Map.get(opts, :downloads, true) != false,
       params: grant_params(Map.get(opts, :params))
     }}
  end

  defp public_answer({:deny, message}) when is_binary(message), do: {:deny, message}

  defp public_answer({:ask, %{} = ask}) do
    given = List.wrap(Map.get(ask, :fields))

    case Enum.flat_map(given, &ask_field/1) do
      fields when length(fields) == length(given) ->
        {:ask,
         %{
           title: ask_text(ask[:title]),
           message: ask_text(ask[:message]),
           error: ask_text(ask[:error]),
           submit: ask_text(ask[:submit]),
           fields: fields
         }}

      _invalid ->
        {:deny, nil}
    end
  end

  defp public_answer(_other), do: {:deny, nil}

  defp ask_field(%{key: key, label: label} = field)
       when is_binary(key) and key != "" and is_binary(label) do
    type = Map.get(field, :type, :text)
    if type in [:password, :email, :text], do: [%{key: key, label: label, type: type}], else: []
  end

  defp ask_field(_field), do: []

  defp ask_text(text) when is_binary(text) and text != "", do: text
  defp ask_text(_text), do: nil

  defp grant_params(%{} = params) do
    for {key, value} <- params, is_binary(key) and is_binary(value), into: %{}, do: {key, value}
  end

  defp grant_params(_params), do: %{}

  @doc """
  What to tell whoever opens a public link to no dashboard, given its
  token: Lotus Pro's words when it knows the link (one its owner turned
  off), or `nil` for the free version's "not found or no longer public".
  """
  @spec public_link_message(String.t()) :: String.t() | nil
  def public_link_message(token) do
    with true <- available?() and function_exported?(pro_web(), :public_link_message, 1),
         message when is_binary(message) <- apply(pro_web(), :public_link_message, [token]) do
      message
    else
      _ -> nil
    end
  end

  @doc """
  The branding of a request, asked when the dashboard mounts and when a
  public dashboard is loaded. `info` has the `:user`, `:context` and
  `:scope` of the request, `:public` and, on a public dashboard, the
  `:dashboard`. Pro answers a map with any of `:product_name`, `:logo` (an
  image URL), `:assistant_name`, `:theme`, `:theme_colors`, `:favicon` (an
  image URL), `:font` (a CSS font family list, such as
  `"Acme Sans", sans-serif`), `:font_url` (an `https` stylesheet that loads
  it), `:radius` (`:none`, `:small`, `:medium` or `:large`) and `:locale` (a
  language Lotus speaks, used when the host chose none for the person). The
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
  request (`request_info/1`; the home page's lists add `list: :home`): `:owner_id` and `:tenant_id`, as
  `Lotus.Storage.list_queries_by/1` and `Lotus.list_dashboards_by/1` take
  them, for a tenant's content or "mine", and `:filter`, which Lotus hands
  to Pro's `:list_content` plug ("shared with me"). Other keys are ignored.
  `[]` without Pro: every query and dashboard is listed.
  """
  @spec list_options(:queries | :dashboards, map()) :: keyword()
  def list_options(kind, info) when kind in [:queries, :dashboards] do
    with true <- available?() and function_exported?(pro_web(), :list_options, 2),
         options when is_list(options) <- apply(pro_web(), :list_options, [kind, info]) do
      options
      |> Keyword.take([:owner_id, :tenant_id, :filter])
      |> Enum.reject(&is_nil(elem(&1, 1)))
    else
      _ -> []
    end
  end

  @doc """
  The queries listed for the request: those its `:context` may read, as
  the `:list_content` middleware narrows them. All of them without Pro or
  such middleware.
  """
  @spec list_queries(map()) :: [Lotus.Storage.Query.t()]
  def list_queries(info) do
    actor = actor_opts(info)

    case list_options(:queries, info) do
      [] -> Lotus.list_queries(actor)
      options -> Lotus.Storage.list_queries_by(options ++ actor)
    end
  end

  @doc """
  The dashboards listed for the request, with `opts` (`:preload`), narrowed
  as `list_queries/1`.
  """
  @spec list_dashboards(map(), keyword()) :: [Lotus.Storage.Dashboard.t()]
  def list_dashboards(info, opts \\ []) do
    opts = opts ++ actor_opts(info)

    case list_options(:dashboards, info) do
      [] -> Lotus.list_dashboards(opts)
      options -> Lotus.list_dashboards_by(opts ++ options)
    end
  end

  defp actor_opts(info), do: Actor.opts({info[:context], info[:scope]})

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

  @download_salt "lotus_pro_download"
  @download_max_age 300

  @doc """
  The path of a file Lotus Pro makes (`download/3`), for a page of its
  own: `name` says which, `params` (a map with string keys) what to put in
  it. The path holds both, signed; it is good for five minutes, and only
  for whoever Pro lets have the file.
  """
  @spec download_path(module(), String.t(), map()) :: String.t()
  def download_path(endpoint, name, params \\ %{}) when is_binary(name) do
    token = Phoenix.Token.encrypt(endpoint, @download_salt, %{"name" => name, "params" => params})
    Lotus.Web.Helpers.lotus_path("pro/download", %{token: token})
  end

  @doc false
  @spec verify_download(module(), String.t()) ::
          {:ok, String.t(), map()} | {:error, :expired | :invalid}
  def verify_download(endpoint, token) do
    case Phoenix.Token.decrypt(endpoint, @download_salt, token, max_age: @download_max_age) do
      {:ok, %{"name" => name, "params" => params}} -> {:ok, name, params}
      {:error, :expired} -> {:error, :expired}
      _invalid -> {:error, :invalid}
    end
  end

  @doc """
  A file Lotus Pro makes, by the `name` and `params` of `download_path/3`,
  for the request's `info` (`:user`, `:context`, `:scope` and the
  `:params`): `{:ok, %{filename: String.t(), content_type: String.t(),
  body: iodata()}}`, `{:error, :forbidden}`, or `nil` for a file it does not
  make (and without Pro).
  """
  @spec download(String.t(), map(), map()) :: {:ok, map()} | {:error, :forbidden} | nil
  def download(name, params, info) do
    with true <- available?() and function_exported?(pro_web(), :download, 3),
         {:ok, %{filename: _, content_type: _, body: _}} = file <-
           apply(pro_web(), :download, [name, params, info]) do
      file
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> nil
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""
end
