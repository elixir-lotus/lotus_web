defmodule Lotus.Web.Telemetry do
  @moduledoc """
  Telemetry events emitted by the dashboard.

  Lotus core emits the events of the work itself (each query run, each AI
  request; see `Lotus.Telemetry`). These say what people did in the
  dashboard that led to it: which dashboards they opened, which cards ran,
  what they exported and which AI action they asked for. Each carries the
  `:context` the resolver gave (`c:Lotus.Web.Resolver.resolve_context/1`),
  `nil` on a public dashboard or without one, and the `:client`.

  ## The client

  `:client` is who is on the other end: `%{ip: ip, user_agent: user_agent}`,
  each a string or `nil`. The address is the first one in `X-Forwarded-For`,
  else the peer's. A LiveView knows them only when the host's socket shares
  them:

      socket "/live", Phoenix.LiveView.Socket,
        websocket: [connect_info: [:peer_data, :user_agent, :x_headers, session: @session_options]]

  The CSV export reads them from the request.

  ## `[:lotus_web, :dashboard, :view]`

  A dashboard was opened: once per page load of a connected LiveView, not
  again when its filters or tab change.

  **Measurements:** `:system_time`.

  **Metadata:**

    * `:dashboard` - The `Lotus.Storage.Dashboard`, with its cards and filters
    * `:public` - `true` when it was opened through its share link
    * `:context` - The resolver's context, `nil` when `:public`
    * `:client` - Who opened it

  ## `[:lotus_web, :query, :view]`

  A saved query was opened in the editor: once per page load of a connected
  LiveView.

  **Measurements:** `:system_time`.

  **Metadata:**

    * `:query` - The `Lotus.Storage.Query`
    * `:context` - The resolver's context
    * `:client` - Who opened it

  ## `[:lotus_web, :public_link, :refused]`

  A public dashboard link opened nothing: no dashboard has it (never, or no
  longer: sharing was turned off or the link changed), or Lotus Pro refused
  it (`Lotus.Web.Pro.authorize_public_dashboard/2`, an expired link). Once
  per page load of a connected LiveView.

  **Measurements:** `:system_time`.

  **Metadata:**

    * `:token` - The link's token. It opened nothing, but hash it before you
      keep it
    * `:dashboard` - The dashboard Lotus Pro refused, `nil` when no
      dashboard has the link
    * `:message` - What the page told the visitor
    * `:client` - Who opened it

  ## `[:lotus_web, :card, :run, :start | :stop | :exception]`

  A query card of a dashboard ran: when the dashboard opens, a filter
  changes or a card is refreshed. The span runs in the process that runs the
  card.

  **Measurements:** `:system_time` on start, `:duration` on stop and
  exception.

  **Metadata:**

    * `:dashboard_id`, `:card_id`
    * `:query` - The card's `Lotus.Storage.Query`
    * `:public`, `:context` - As for `:view`
    * `:status` - On stop: `:ok`, or `:error` when the query failed
    * `:result` - On stop: `{:ok, Lotus.Result.t()}` or `{:error, reason}`

  ## `[:lotus_web, :export, :start | :stop | :exception]`

  A CSV export was downloaded. The span covers the whole download.

  **Measurements:** `:system_time` on start; `:duration` and `:bytes` (sent)
  on stop; `:duration` on exception.

  **Metadata:**

    * `:query` - The `Lotus.Storage.Query` exported: a saved one, or the
      statement of an unsaved one
    * `:source` - The data source
    * `:format` - `:csv`
    * `:context` - The resolver's context
    * `:client` - Who downloaded it
    * `:status` - On stop: `:ok`, or `:closed` when the client went away
      before the end

  ## `[:lotus_web, :ai, :start | :stop | :exception]`

  Someone asked the query editor's AI for something. The span runs in the
  process that makes the request; core's `[:lotus, :ai, :request, ...]`
  events inside it carry the model and the tokens.

  **Measurements:** `:system_time` on start, `:duration` on stop and
  exception.

  **Metadata:**

    * `:action` - `:generate` (a query from a prompt), `:optimize`,
      `:explain` (the query) or `:explain_fragment` (a part of it)
    * `:source` - The data source
    * `:context` - The resolver's context
    * `:client` - Who asked
    * `:status` - On stop: `:ok`, or `:error` when the request failed
  """

  @typedoc "Who is on the other end of a request (see \"The client\")."
  @type client :: %{ip: String.t() | nil, user_agent: String.t() | nil}

  @doc false
  @spec dashboard_view(map(), boolean(), term(), client() | nil) :: :ok
  def dashboard_view(dashboard, public?, context, client \\ nil) do
    execute([:lotus_web, :dashboard, :view], %{
      dashboard: dashboard,
      public: public?,
      context: context,
      client: client || unknown()
    })
  end

  @doc false
  @spec query_view(map(), term(), client() | nil) :: :ok
  def query_view(query, context, client) do
    execute([:lotus_web, :query, :view], %{
      query: query,
      context: context,
      client: client || unknown()
    })
  end

  @doc false
  @spec public_link_refused(String.t(), map() | nil, String.t() | nil, client() | nil) :: :ok
  def public_link_refused(token, dashboard, message, client) do
    execute([:lotus_web, :public_link, :refused], %{
      token: token,
      dashboard: dashboard,
      message: message,
      client: client || unknown()
    })
  end

  defp execute(event, metadata),
    do: :telemetry.execute(event, %{system_time: System.system_time()}, metadata)

  @doc false
  # The client of a request (`Plug.Conn`) or of a connected LiveView.
  @spec client(Plug.Conn.t() | Phoenix.LiveView.Socket.t()) :: client()
  def client(%Plug.Conn{} = conn) do
    %{
      ip: forwarded(conn.req_headers) || address(conn.remote_ip),
      user_agent: conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
    }
  end

  def client(%Phoenix.LiveView.Socket{} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      peer = Phoenix.LiveView.get_connect_info(socket, :peer_data)

      %{
        ip:
          forwarded(Phoenix.LiveView.get_connect_info(socket, :x_headers) || []) ||
            address(peer && peer.address),
        user_agent: Phoenix.LiveView.get_connect_info(socket, :user_agent)
      }
    else
      unknown()
    end
  end

  defp unknown, do: %{ip: nil, user_agent: nil}

  defp forwarded(headers) do
    Enum.find_value(headers, fn
      {"x-forwarded-for", value} ->
        value |> String.split(",") |> List.first() |> String.trim() |> blank_nil()

      _other ->
        nil
    end)
  end

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  defp address(nil), do: nil
  defp address(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()

  @doc false
  # Runs `fun` in a span; the stop event says whether it returned `{:ok, _}`.
  @spec span([atom()], map(), (-> result)) :: result when result: term()
  def span(event, metadata, fun) do
    :telemetry.span(event, metadata, fn ->
      result = fun.()
      {result, Map.put(metadata, :status, status(result))}
    end)
  end

  @doc false
  # The span of a card's run: the stop event has its result, too.
  @spec card_span(map(), (-> result)) :: result when result: term()
  def card_span(metadata, fun) do
    :telemetry.span([:lotus_web, :card, :run], metadata, fn ->
      result = fun.()
      {result, Map.merge(metadata, %{status: status(result), result: result})}
    end)
  end

  defp status({:ok, _result}), do: :ok
  defp status(:ok), do: :ok
  defp status(_error), do: :error
end
