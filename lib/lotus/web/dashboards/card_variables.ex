defmodule Lotus.Web.Dashboards.CardVariables do
  @moduledoc """
  Builds the query variables of a dashboard card with
  `Lotus.card_variables/4`, the rule `Lotus.Dashboards.run_dashboard_card/2`
  uses: the filter value or else the default value, the relative date token
  resolved against `today`, and the transform of each mapping.

  The dashboard pages run cards themselves, for bounded concurrency,
  cancellation and a `:query` check per card, so they cannot call
  `run_dashboard_card/2`. They call `build/4` with one `today` per run.

  A card has its mappings in one of two forms:

  - the `%Lotus.Storage.DashboardCardFilterMapping{}` structs of a saved card
  - the map the dashboard editor keeps while a card changes,
    `%{filter_name => [%{variable_name: name, transform: transform}]}`
  """

  @type entry :: %{variable_name: String.t() | nil, transform: map() | nil}
  @type mappings :: [struct()] | %{optional(String.t()) => [entry()]}

  @doc """
  Returns the `vars` for a card with `mappings` on a dashboard with `filters`.
  """
  @spec build(mappings() | nil, [map()], map(), Date.t()) :: %{optional(String.t()) => term()}
  def build(mappings, filters, filter_values, today) do
    mappings
    |> core_mappings(filters)
    |> Lotus.card_variables(filters, filter_values, today: today)
  end

  defp core_mappings(mappings, _filters) when is_list(mappings), do: mappings

  defp core_mappings(mappings, filters) when is_map(mappings) do
    filter_id_by_name = Map.new(filters, &{&1.name, &1.id})

    for {filter_name, entries} <- mappings,
        Map.has_key?(filter_id_by_name, filter_name),
        entry <- entries,
        entry.variable_name not in [nil, ""] do
      %{
        filter_id: Map.fetch!(filter_id_by_name, filter_name),
        variable_name: entry.variable_name,
        transform: entry.transform
      }
    end
  end

  defp core_mappings(_mappings, _filters), do: []
end
