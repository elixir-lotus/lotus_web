defmodule Lotus.Web.Dashboards.LiveCards do
  @moduledoc false

  # Live cards: charts that take their new rows as they come, rather than
  # drawing again whole at each refresh.
  #
  # A live card is a line, area or scatter chart (its marks are its rows)
  # whose query reads `{{since}}`, its visualization saying `"live"`. Its
  # first run is the card's usual run, with no `since`: the query keeps it
  # in an optional block, `[[AND created_at > {{since}}]]`, or gives it a
  # default. The chart keeps the last `live_window` rows of it, and the
  # page remembers the last x value it shows: the card's cursor.
  #
  # Every `tick_seconds/0`, the page runs each live card again with `since`
  # set to its cursor (`{:live_card, card_id}` asyncs, apart from the
  # dashboard's runner, so the chart is not dimmed), and sends only the rows
  # after it to the chart (`Fude.Live.append/5`). The card's result in the
  # page's assigns stays the one of its last full run, so the chart is not
  # sent again whole; a full refresh (a filter, the refresh button, the
  # dashboard's auto-refresh) draws it again and moves the cursor.
  #
  # The live state lives in the LiveView's assigns (`:live_cursors`,
  # `:live_running`), where the dashboard's first runs land: a page is a
  # component of `Lotus.Web.DashboardLive`, which hands it its `handle_info`
  # and `handle_async`. The timer's tick reaches the component, which sends
  # it on (`forward_tick/1`); a live card's full result that lands in the
  # component (the refresh button) goes to the LiveView too. So there is one
  # cursor per card, and no point is sent twice.

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Lotus.Storage.Query
  alias Lotus.Web.Charts

  @variable "since"
  @kinds ~w(line area scatter)
  @windows [30, 60, 120, 300]
  @default_window 60
  @tick_seconds 10

  @doc "The variable a live card's query reads: the last x value the chart has."
  def variable, do: @variable

  @doc "The chart types that can be live: their marks are their rows."
  def kinds, do: @kinds

  @doc "The windows (rows kept) a live card offers."
  def windows, do: @windows

  @doc "Seconds between two runs of a dashboard's live cards."
  def tick_seconds, do: @tick_seconds

  @doc "Whether a card is live: switched on, of a kind that can be, reading `{{since}}`."
  def live?(card), do: on?(card) and can_be_live?(card)

  @doc "Whether a card could be live: a line, area or scatter chart whose query reads `{{since}}`."
  def can_be_live?(%{card_type: :query, query: %{statement: statement}} = card)
      when is_binary(statement) do
    config = config(card)

    config["chart_type"] in @kinds and present?(config["x_field"]) and
      @variable in Query.extract_variables_from_statement(statement)
  end

  def can_be_live?(_card), do: false

  @doc "Whether a card's chart type is one that can be live, whatever its query."
  def kind?(card), do: config(card)["chart_type"] in @kinds

  @doc "Whether a card's query reads `{{since}}`."
  def reads_since?(%{query: %{statement: statement}}) when is_binary(statement),
    do: @variable in Query.extract_variables_from_statement(statement)

  def reads_since?(_card), do: false

  @doc "The rows a live card keeps."
  def window(card) do
    case Integer.parse(to_string(config(card)["live_window"] || "")) do
      {n, ""} when n > 0 -> n
      _ -> @default_window
    end
  end

  @doc "Whether any card of a list is live."
  def any?(cards), do: Enum.any?(cards, &live?/1)

  @doc """
  The full result of a live card, as the chart shows it: its last
  `window/1` rows. Any other card's result is unchanged.
  """
  def trim(result, card) do
    if live?(card), do: %{result | rows: Enum.take(result.rows, -window(card))}, else: result
  end

  @doc """
  The last x value of a result: the cursor the next run of the card asks
  rows after. `nil` when the result has no rows, or no column of that name.
  """
  def cursor(%{columns: columns, rows: rows}, card) do
    case Enum.find_index(columns, &(&1 == config(card)["x_field"])) do
      nil ->
        nil

      index ->
        rows
        |> Enum.map(&Enum.at(&1, index))
        |> Enum.reject(&is_nil/1)
        |> Enum.max(&after_or_same?/2, fn -> nil end)
    end
  end

  def cursor(_result, _card), do: nil

  @doc "The rows of a result whose x value is after the cursor, in order."
  def after_cursor(%{columns: columns, rows: rows}, card, cursor) do
    case Enum.find_index(columns, &(&1 == config(card)["x_field"])) do
      nil ->
        []

      index ->
        Enum.filter(rows, fn row ->
          value = Enum.at(row, index)
          value != nil and (cursor == nil or compare(value, cursor) == :gt)
        end)
    end
  end

  # -- On a page ---------------------------------------------------------------
  #
  # The page keeps `:live_cursors` (card id => last x value) and
  # `:live_running` (the cards whose live run is on its way).

  @doc """
  The full result of a card arrived: a live card's is trimmed to its window,
  and its cursor moves to the result's last x value.

  In the LiveView, the cursor is set here. In the component (a refresh it
  ran), the result goes to the LiveView (`{:card_result, id, result}`), so
  that the result and the cursor of a live card are kept in one place: the
  component's own copy would be replaced by the LiveView's on its next
  render.
  """
  def put_result(socket, card, result) do
    cond do
      not (card && live?(card)) ->
        {socket, result}

      component?(socket) ->
        result = trim(result, card)
        send(self(), {:card_result, card.id, result})
        {socket, result}

      true ->
        result = trim(result, card)
        {put_cursor(socket, card.id, cursor(result, card)), result}
    end
  end

  @doc "A card's run failed: it has no cursor until its next full result."
  def drop(socket, card_id) do
    if component?(socket), do: socket, else: put_cursor(socket, card_id, nil)
  end

  @doc "Where a card's chart is up to, in the LiveView: `nil` when it has none."
  def put_cursor(socket, card_id, nil),
    do: assign(socket, :live_cursors, Map.delete(socket.assigns.live_cursors, card_id))

  def put_cursor(socket, card_id, cursor),
    do: assign(socket, :live_cursors, Map.put(socket.assigns.live_cursors, card_id, cursor))

  @doc "The timer's tick, from the component to the LiveView, where the live state is."
  def forward_tick(socket) do
    send(self(), :live_tick)
    socket
  end

  @doc """
  Runs each live card of `cards` with `since` at its cursor, apart from
  those that have no full result yet, are running, or have a live run on
  its way. `run.(socket, card, extra_vars)` returns `{:run, fun}` or
  `:skip`, as the page runs a card.
  """
  def tick(socket, cards, run) do
    %{live_cursors: cursors, live_running: live_running, running_cards: running} =
      socket.assigns

    Enum.reduce(cards, socket, fn card, socket ->
      with true <- live?(card),
           {:ok, cursor} when not is_nil(cursor) <- Map.fetch(cursors, card.id),
           false <- MapSet.member?(running, card.id),
           false <- MapSet.member?(live_running, card.id),
           {:run, fun} <- run.(socket, card, %{@variable => cursor}) do
        socket
        |> assign(:live_running, MapSet.put(socket.assigns.live_running, card.id))
        |> start_async({:live_card, card.id}, fun)
      else
        _ -> socket
      end
    end)
  end

  @doc """
  The live run of a card came back: the rows after its cursor go to its
  chart (`Fude.Live.append/5`, keeping the window), and the cursor moves to
  the last of them. A failed run leaves the chart as it is, for the next
  tick to try again.
  """
  def receive(socket, card, outcome) do
    socket =
      assign(socket, :live_running, MapSet.delete(socket.assigns.live_running, card && card.id))

    with %{} <- card,
         true <- live?(card),
         {:ok, {:ok, result}} <- outcome,
         {:ok, cursor} <- Map.fetch(socket.assigns.live_cursors, card.id),
         [_ | _] = rows <- after_cursor(result, card, cursor),
         new = %{result | rows: rows},
         {:ok, chart} <- Charts.build_chart(new, config(card)) do
      socket
      |> Fude.Live.append("chart-#{card.id}", chart, chart.datasets[chart.data],
        max: window(card)
      )
      |> assign(:live_cursors, Map.put(socket.assigns.live_cursors, card.id, cursor(new, card)))
    else
      _ -> socket
    end
  end

  # -- Values ------------------------------------------------------------------

  defp after_or_same?(a, b), do: compare(a, b) != :lt

  # The order of two x values of one column: dates and times by their time,
  # numbers by their value, the rest as text.
  defp compare(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b)
  defp compare(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b)
  defp compare(%Date{} = a, %Date{} = b), do: Date.compare(a, b)
  defp compare(%Time{} = a, %Time{} = b), do: Time.compare(a, b)
  defp compare(%Decimal{} = a, b), do: Decimal.compare(a, decimal(b))
  defp compare(a, %Decimal{} = b), do: Decimal.compare(decimal(a), b)
  defp compare(a, b) when is_number(a) and is_number(b), do: order(a, b)
  defp compare(a, b), do: order(to_string(a), to_string(b))

  defp order(a, b) when a > b, do: :gt
  defp order(a, b) when a < b, do: :lt
  defp order(_a, _b), do: :eq

  defp decimal(%Decimal{} = d), do: d
  defp decimal(n) when is_integer(n), do: Decimal.new(n)
  defp decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp decimal(n), do: Decimal.new(to_string(n))

  defp config(%{visualization_config: config}) when is_map(config),
    do: Map.new(config, fn {k, v} -> {to_string(k), v} end)

  defp config(_card), do: %{}

  defp on?(card), do: config(card)["live"] in [true, "true"]

  defp present?(value), do: is_binary(value) and value != ""

  defp component?(socket), do: Map.has_key?(socket.assigns, :myself)
end
