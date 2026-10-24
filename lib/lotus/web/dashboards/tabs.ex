defmodule Lotus.Web.Dashboards.Tabs do
  @moduledoc """
  A dashboard's tabs: its cards in pages, each with its own grid.

  The tabs are the dashboard's `settings["tabs"]`, in order, each
  `%{"id" => id, "name" => name}`; a card's tab is its layout's `tab`, and
  a card with none is on the first tab. A dashboard with no tabs is one
  page, as before tabs: its tab bar shows only in edit mode, to add one.
  """

  use Gettext, backend: Lotus.Web.Gettext

  @doc "The tabs of a dashboard, in order."
  @spec list(map()) :: [map()]
  def list(dashboard) do
    case Map.get(dashboard, :settings) do
      %{"tabs" => [_ | _] = tabs} -> tabs
      _ -> []
    end
  end

  @doc """
  The tab shown: `id` when the dashboard has it, else its first tab; `nil`
  for a dashboard with no tabs.
  """
  @spec current(map(), String.t() | nil) :: String.t() | nil
  def current(dashboard, id) do
    tabs = list(dashboard)

    if Enum.any?(tabs, &(&1["id"] == id)),
      do: id,
      else: tabs |> List.first(%{}) |> Map.get("id")
  end

  @doc "The cards on tab `id`: all of them on a dashboard with no tabs."
  @spec cards(map(), String.t() | nil) :: [map()]
  def cards(dashboard, id) do
    case list(dashboard) do
      [] ->
        dashboard.cards

      [first | _] ->
        Enum.filter(dashboard.cards, &((tab(&1) || first["id"]) == id))
    end
  end

  @doc "The tab of a card, as its layout has it."
  @spec tab(map()) :: String.t() | nil
  def tab(%{layout: %{} = layout}), do: Map.get(layout, :tab) || Map.get(layout, "tab")
  def tab(_card), do: nil

  @doc """
  The dashboard with a new tab at the end, and its id. A dashboard with no
  tabs gets two: its cards on the first, the new one empty.
  """
  @spec add(map()) :: {map(), String.t()}
  def add(dashboard) do
    tabs =
      case list(dashboard) do
        [] -> [%{"id" => new_id(), "name" => gettext("Tab %{count}", count: 1)}]
        tabs -> tabs
      end

    tab = %{"id" => new_id(), "name" => gettext("Tab %{count}", count: length(tabs) + 1)}
    {put(dashboard, tabs ++ [tab]), tab["id"]}
  end

  @doc "The dashboard with tab `id` named `name` (a blank name keeps the old)."
  @spec rename(map(), String.t(), String.t()) :: map()
  def rename(dashboard, id, name) do
    case String.trim(name || "") do
      "" ->
        dashboard

      name ->
        tabs =
          Enum.map(list(dashboard), &if(&1["id"] == id, do: %{&1 | "name" => name}, else: &1))

        put(dashboard, tabs)
    end
  end

  @doc """
  The dashboard without tab `id`: its cards go to the first tab left. With
  one tab left, the dashboard has no tabs, and its cards none.
  """
  @spec delete(map(), String.t()) :: map()
  def delete(dashboard, id) do
    case Enum.reject(list(dashboard), &(&1["id"] == id)) do
      [_] ->
        dashboard
        |> put([])
        |> Map.update!(:cards, fn cards -> Enum.map(cards, &move(&1, nil)) end)

      [first | _] = tabs ->
        cards = Enum.map(dashboard.cards, &if(tab(&1) == id, do: move(&1, first["id"]), else: &1))
        %{put(dashboard, tabs) | cards: cards}

      [] ->
        dashboard
    end
  end

  @doc """
  The dashboard with card `card_id` on tab `id`, under the cards there, at
  the left edge.
  """
  @spec move_card(map(), term(), String.t()) :: map()
  def move_card(dashboard, card_id, id) do
    bottom =
      dashboard
      |> cards(id)
      |> Enum.map(fn card -> layout_value(card, :y, 0) + layout_value(card, :h, 4) end)
      |> Enum.max(fn -> 0 end)

    cards =
      Enum.map(dashboard.cards, fn card ->
        if card.id == card_id and tab(card) != id,
          do: card |> move(id) |> put_y(bottom),
          else: card
      end)

    %{dashboard | cards: cards}
  end

  defp move(card, id) do
    layout = card.layout || %{x: 0, y: 0, w: 6, h: 4}
    %{card | layout: Map.put(layout, :tab, id)}
  end

  defp put_y(card, y), do: %{card | layout: card.layout |> Map.put(:y, y) |> Map.put(:x, 0)}

  defp layout_value(%{layout: %{} = layout}, key, default),
    do: Map.get(layout, key) || Map.get(layout, to_string(key)) || default

  defp layout_value(_card, _key, default), do: default

  defp put(dashboard, tabs) do
    settings = Map.get(dashboard, :settings) || %{}

    settings =
      if tabs == [], do: Map.delete(settings, "tabs"), else: Map.put(settings, "tabs", tabs)

    Map.put(dashboard, :settings, settings)
  end

  defp new_id, do: "tab_" <> Integer.to_string(System.unique_integer([:positive]), 36)
end
