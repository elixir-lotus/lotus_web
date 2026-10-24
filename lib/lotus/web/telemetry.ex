defmodule Lotus.Web.Telemetry do
  @moduledoc """
  Telemetry events emitted by the dashboard.

  Lotus core emits the events of the work itself (each query run, each AI
  request; see `Lotus.Telemetry`). These say what people did in the
  dashboard that led to it: which dashboards they opened, which cards ran,
  what they exported and which AI action they asked for. Each carries the
  `:context` the resolver gave (`c:Lotus.Web.Resolver.resolve_context/1`),
  `nil` on a public dashboard or without one.

  ## `[:lotus_web, :dashboard, :view]`

  A dashboard was opened: once per page load of a connected LiveView, not
  again when its filters or tab change.

  **Measurements:** `:system_time`.

  **Metadata:**

    * `:dashboard` - The `Lotus.Storage.Dashboard`, with its cards and filters
    * `:public` - `true` when it was opened through its share link
    * `:context` - The resolver's context, `nil` when `:public`

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
    * `:status` - On stop: `:ok`, or `:error` when the request failed
  """

  @doc false
  @spec dashboard_view(map(), boolean(), term()) :: :ok
  def dashboard_view(dashboard, public?, context) do
    :telemetry.execute(
      [:lotus_web, :dashboard, :view],
      %{system_time: System.system_time()},
      %{dashboard: dashboard, public: public?, context: context}
    )
  end

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
