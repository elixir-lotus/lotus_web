defmodule Lotus.Web.Dashboards.FilterConnections do
  @moduledoc """
  What a dashboard filter sets in its cards: the query variable of each card
  it is connected to.

  A card keeps its connections, its filter mappings, in one of two forms:

  - the `%Lotus.Storage.DashboardCardFilterMapping{}` structs of a saved card
  - the map the dashboard editor keeps while a card changes,
    `%{filter_name => [%{variable_name: name, transform: transform}]}`
  """

  @doc """
  The variables `filter` sets in a card with `mappings`, as
  `%{variable_name: name, transform: transform}`: one, or a date range's two.
  """
  @spec entries(term(), map()) :: [%{variable_name: String.t(), transform: map() | nil}]
  def entries(mappings, filter) when is_list(mappings) do
    for mapping <- mappings,
        mapping.filter_id == filter.id,
        do: %{variable_name: mapping.variable_name, transform: mapping.transform}
  end

  def entries(mappings, filter) when is_map(mappings), do: Map.get(mappings, filter.name, [])
  def entries(_mappings, _filter), do: []

  @doc """
  How many of `cards` each filter sets something in, by filter name.
  """
  @spec counts([map()], [map()]) :: %{optional(String.t()) => non_neg_integer()}
  def counts(filters, cards) do
    Map.new(filters, fn filter ->
      {filter.name, Enum.count(cards, &(entries(&1.filter_mappings, filter) != []))}
    end)
  end

  @doc """
  The variables a new filter connects to by itself in a card's query: one
  of its name; for a date range, also its start and end (`<name>_start` and
  `<name>_end`, or `start_date` and `end_date`). `[]` when none fits.

      iex> filter = %{name: "region", filter_type: :text}
      iex> Lotus.Web.Dashboards.FilterConnections.suggest(filter, [%{name: "region"}])
      [%{variable_name: "region", transform: nil}]

      iex> filter = %{name: "period", filter_type: :date_range}
      iex> Lotus.Web.Dashboards.FilterConnections.suggest(filter, [%{name: "start_date"}, %{name: "end_date"}])
      [
        %{variable_name: "start_date", transform: %{"type" => "date_range_start"}},
        %{variable_name: "end_date", transform: %{"type" => "date_range_end"}}
      ]
  """
  @spec suggest(map(), [map()]) :: [%{variable_name: String.t(), transform: map() | nil}]
  def suggest(%{name: name} = filter, variables) when is_binary(name) and name != "" do
    names = MapSet.new(variables, & &1.name)

    cond do
      MapSet.member?(names, name) ->
        [%{variable_name: name, transform: nil}]

      filter.filter_type == :date_range ->
        [{"#{name}_start", "#{name}_end"}, {"start_date", "end_date"}]
        |> Enum.find(fn {first, last} -> first in names and last in names end)
        |> split()

      true ->
        []
    end
  end

  def suggest(_filter, _variables), do: []

  defp split(nil), do: []

  defp split({first, last}) do
    [
      %{variable_name: first, transform: %{"type" => "date_range_start"}},
      %{variable_name: last, transform: %{"type" => "date_range_end"}}
    ]
  end
end
