defmodule Lotus.Web.Dashboards.CardRunner do
  @moduledoc false

  # Runs the query cards of a dashboard at most `limit` at a time, so a page
  # load does not put every card on the source's pool at the same instant.
  #
  # The runner lives in the `:card_runner` assign and keeps `:running_cards`
  # current: a card is in it from the moment it is queued until its result
  # arrives. Each card runs as `start_async({:run_card, card_id}, fun)`.
  #
  # The page gives a `prepare` function that the runner calls when a slot is
  # free: `prepare.(socket, card_id)` returns `{:run, fun}` to start the card
  # or `{:skip, socket}` when the card must not run (it was removed, or the
  # user may not query its source).

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2]

  alias Phoenix.LiveView.Socket

  defstruct limit: 1, queue: [], active: MapSet.new()

  @type t :: %__MODULE__{
          limit: pos_integer(),
          queue: [term()],
          active: MapSet.t()
        }

  @type prepare :: (Socket.t(), term() -> {:run, (-> term())} | {:skip, Socket.t()})

  @spec new(pos_integer()) :: t()
  def new(limit) when is_integer(limit) and limit > 0, do: %__MODULE__{limit: limit}

  @doc """
  Starts a new run of `card_ids`. The active cards of the previous run are
  cancelled and its queue is dropped, so fast changes do not stack runs.
  """
  @spec run_all(Socket.t(), [term()], prepare()) :: Socket.t()
  def run_all(socket, card_ids, prepare) do
    runner = socket.assigns.card_runner
    card_ids = Enum.uniq(card_ids)

    runner.active
    |> Enum.reduce(socket, &cancel_async(&2, {:run_card, &1}))
    |> assign(:card_runner, %{runner | queue: card_ids, active: MapSet.new()})
    |> assign(:running_cards, MapSet.new(card_ids))
    |> fill(prepare)
  end

  @doc """
  Runs one card again. An active run of the card is cancelled, and the card
  goes to the front of the queue.
  """
  @spec run(Socket.t(), term(), prepare()) :: Socket.t()
  def run(socket, card_id, prepare) do
    runner = socket.assigns.card_runner

    socket =
      if MapSet.member?(runner.active, card_id),
        do: cancel_async(socket, {:run_card, card_id}),
        else: socket

    runner = %{
      runner
      | queue: [card_id | List.delete(runner.queue, card_id)],
        active: MapSet.delete(runner.active, card_id)
    }

    socket
    |> assign(:card_runner, runner)
    |> assign(:running_cards, MapSet.put(socket.assigns.running_cards, card_id))
    |> fill(prepare)
  end

  @doc """
  Frees the slot of a card whose async result arrived and starts the next
  queued card. Returns `:stale` for a result of a cancelled run, which the page
  ignores.
  """
  @spec finish(Socket.t(), term(), prepare()) :: {:ok, Socket.t()} | :stale
  def finish(socket, card_id, prepare) do
    runner = socket.assigns.card_runner

    if MapSet.member?(runner.active, card_id) do
      socket =
        socket
        |> assign(:card_runner, %{runner | active: MapSet.delete(runner.active, card_id)})
        |> assign(:running_cards, MapSet.delete(socket.assigns.running_cards, card_id))
        |> fill(prepare)

      {:ok, socket}
    else
      :stale
    end
  end

  defp fill(socket, prepare) do
    runner = socket.assigns.card_runner

    case runner.queue do
      [card_id | rest] ->
        if MapSet.size(runner.active) < runner.limit do
          socket
          |> assign(:card_runner, %{runner | queue: rest})
          |> start(card_id, prepare)
          |> fill(prepare)
        else
          socket
        end

      [] ->
        socket
    end
  end

  defp start(socket, card_id, prepare) do
    case prepare.(socket, card_id) do
      {:run, fun} ->
        runner = socket.assigns.card_runner

        socket
        |> assign(:card_runner, %{runner | active: MapSet.put(runner.active, card_id)})
        |> start_async({:run_card, card_id}, fun)

      {:skip, socket} ->
        assign(socket, :running_cards, MapSet.delete(socket.assigns.running_cards, card_id))
    end
  end
end
