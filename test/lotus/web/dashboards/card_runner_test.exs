defmodule Lotus.Web.Dashboards.CardRunnerTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Dashboards.CardRunner
  alias Phoenix.LiveView.Socket

  # A disconnected socket starts no tasks, so the tests see only the runner's
  # bookkeeping and the cards it asks the page to prepare.
  defp socket(limit) do
    %Socket{assigns: %{__changed__: %{}}}
    |> Phoenix.Component.assign(:card_runner, CardRunner.new(limit))
    |> Phoenix.Component.assign(:running_cards, MapSet.new())
  end

  defp prepare do
    test = self()

    fn _socket, card_id ->
      send(test, {:prepared, card_id})
      {:run, fn -> :ok end}
    end
  end

  defp prepared do
    receive do
      {:prepared, card_id} -> [card_id | prepared()]
    after
      0 -> []
    end
  end

  defp active(socket), do: socket.assigns.card_runner.active

  describe "run_all/3" do
    test "starts at most the limit and queues the other cards" do
      socket = CardRunner.run_all(socket(2), [1, 2, 3, 4], prepare())

      assert prepared() == [1, 2]
      assert active(socket) == MapSet.new([1, 2])
      assert socket.assigns.card_runner.queue == [3, 4]
      assert socket.assigns.running_cards == MapSet.new([1, 2, 3, 4])
    end

    test "drops the queue and the active cards of the previous run" do
      socket = CardRunner.run_all(socket(2), [1, 2, 3], prepare())
      _ = prepared()

      socket = CardRunner.run_all(socket, [4, 5], prepare())

      assert prepared() == [4, 5]
      assert active(socket) == MapSet.new([4, 5])
      assert socket.assigns.card_runner.queue == []
      assert socket.assigns.running_cards == MapSet.new([4, 5])
    end

    test "frees the slot of a skipped card" do
      prepare = fn socket, card_id ->
        if card_id == 1, do: {:skip, socket}, else: {:run, fn -> :ok end}
      end

      socket = CardRunner.run_all(socket(1), [1, 2, 3], prepare)

      assert active(socket) == MapSet.new([2])
      assert socket.assigns.card_runner.queue == [3]
      assert socket.assigns.running_cards == MapSet.new([2, 3])
    end
  end

  describe "finish/3" do
    test "starts the next queued card" do
      socket = CardRunner.run_all(socket(1), [1, 2], prepare())
      _ = prepared()

      assert {:ok, socket} = CardRunner.finish(socket, 1, prepare())

      assert prepared() == [2]
      assert active(socket) == MapSet.new([2])
      assert socket.assigns.running_cards == MapSet.new([2])
    end

    test "returns :stale for a card of a cancelled run" do
      socket = CardRunner.run_all(socket(1), [1, 2], prepare())
      socket = CardRunner.run_all(socket, [2], prepare())

      assert CardRunner.finish(socket, 1, prepare()) == :stale
    end

    test "returns :stale for a card that waits in the queue again" do
      socket = CardRunner.run_all(socket(1), [1, 2], prepare())
      socket = CardRunner.run_all(socket, [2, 1], prepare())

      assert active(socket) == MapSet.new([2])
      assert CardRunner.finish(socket, 1, prepare()) == :stale
    end
  end

  describe "run/3" do
    test "puts the card at the front of the queue" do
      socket = CardRunner.run_all(socket(1), [1, 2, 3], prepare())
      _ = prepared()

      socket = CardRunner.run(socket, 3, prepare())

      assert prepared() == []
      assert socket.assigns.card_runner.queue == [3, 2]
    end

    test "starts an active card again" do
      socket = CardRunner.run_all(socket(1), [1, 2], prepare())
      _ = prepared()

      socket = CardRunner.run(socket, 1, prepare())

      assert prepared() == [1]
      assert active(socket) == MapSet.new([1])
      assert socket.assigns.card_runner.queue == [2]
    end
  end
end
