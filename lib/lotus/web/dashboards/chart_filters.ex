defmodule Lotus.Web.Dashboards.ChartFilters do
  @moduledoc """
  A click on a chart's mark filters the dashboard by it: the bar of a
  region sets the Region filter, and a click on the same bar again clears
  it.

  A chart filters by the fields it draws: its categories (`x_field`, the
  slices of a pie, the regions of a map) and its series (`series_field`).
  A field sets the filter of its name, or the filter that sets a variable
  of its name in the card's query. Fude sends the mark's values by
  channel (`select` on its chart), as the data has them.
  """

  alias Lotus.Web.Dashboards.FilterConnections

  # The filters a click can set: one value, as the mark has it.
  @types [:text, :number, :select, :date]

  @doc """
  The filters a click on a card's chart sets, by the channel of the mark's
  value that each takes: `%{"x" => filter}`. Empty for a chart a click
  does not filter.
  """
  @spec targets(map(), [map()]) :: %{optional(String.t()) => map()}
  def targets(%{card_type: :query, visualization_config: %{} = config} = card, filters) do
    for {channel, field} <- channels(config),
        field not in [nil, ""],
        filter = target(card, filters, field),
        into: %{},
        do: {channel, filter}
  end

  def targets(_card, _filters), do: %{}

  @doc """
  The filter values after a click on a mark with `values` (Fude's, by
  channel): each target's filter takes the mark's value, or no value when
  it already has it.

      iex> filter = %{name: "region", filter_type: :text}
      iex> targets = %{"x" => filter}
      iex> Lotus.Web.Dashboards.ChartFilters.select(%{}, targets, %{"x" => "North"})
      %{"region" => "North"}
      iex> Lotus.Web.Dashboards.ChartFilters.select(%{"region" => "North"}, targets, %{"x" => "North"})
      %{"region" => ""}
  """
  @spec select(map(), %{optional(String.t()) => map()}, map()) :: map()
  def select(filter_values, targets, values) do
    Enum.reduce(targets, filter_values, fn {channel, filter}, acc ->
      toggle(acc, filter.name, value(filter, Map.get(values, channel)))
    end)
  end

  # The mark's value, or none when the filter already has it.
  defp toggle(filter_values, _name, nil), do: filter_values

  defp toggle(filter_values, name, value) do
    if to_string(Map.get(filter_values, name)) == value,
      do: Map.put(filter_values, name, ""),
      else: Map.put(filter_values, name, value)
  end

  @doc """
  The filter values after a click on the chart of one of `cards`: Fude's
  `params`, with the chart's id (`chart-<card id>`). `:none` when the click
  changes no filter.
  """
  @spec click([map()], [map()], map(), map()) :: {:ok, map()} | :none
  def click(cards, filters, filter_values, %{"id" => "chart-" <> id} = params) do
    with %{} = card <- Enum.find(cards, &(to_string(&1.id) == id)),
         values when values != filter_values <-
           select(filter_values, targets(card, filters), params) do
      {:ok, values}
    else
      _ -> :none
    end
  end

  def click(_cards, _filters, _filter_values, _params), do: :none

  # The channels of the mark that carry each field, by chart type.
  defp channels(%{"chart_type" => type} = c) when type in ~w(bar line area combo),
    do: [{"x", c["x_field"]}, {"color", c["series_field"]}]

  defp channels(%{"chart_type" => "horizontal_bar"} = c),
    do: [{"y", c["x_field"]}, {"color", c["series_field"]}]

  defp channels(%{"chart_type" => type} = c) when type in ~w(pie donut),
    do: [{"color", present(c["series_field"]) || c["x_field"]}]

  defp channels(%{"chart_type" => "map"} = c), do: [{"region", c["x_field"]}]
  defp channels(_config), do: []

  defp target(card, filters, field) do
    key = String.downcase(field)

    Enum.find(filters, fn filter ->
      filter.filter_type in @types and
        (String.downcase(filter.name) == key or sets?(card, filter, key))
    end)
  end

  defp sets?(card, filter, key) do
    card.filter_mappings
    |> FilterConnections.entries(filter)
    |> Enum.any?(&(String.downcase(&1.variable_name || "") == key))
  end

  defp value(_filter, nil), do: nil
  defp value(%{filter_type: :date}, value) when is_binary(value), do: String.slice(value, 0, 10)
  defp value(_filter, value), do: to_string(value)

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end
