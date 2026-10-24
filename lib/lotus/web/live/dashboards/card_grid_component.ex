defmodule Lotus.Web.Dashboards.CardGridComponent do
  @moduledoc """
  Renders the dashboard card grid: 12 columns, which the DashboardGrid hook
  lays out (see assets/js/hooks/dashboard_grid.js).
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.Dashboards.CardComponent
  alias Lotus.Web.Dashboards.CardVariables
  alias Lotus.Web.Dashboards.ChartFilters

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <%!-- The DashboardGrid hook places the cards, folds them and, in edit
         mode, moves and resizes them; it owns the grid's class and style. --%>
    <div
      id="dashboard-grid"
      class="grid grid-cols-12 gap-4 auto-rows-min"
      phx-hook="DashboardGrid"
      phx-mounted={JS.ignore_attributes(["class", "style"])}
      data-dashboard-id={Map.get(assigns, :dashboard_id) || "new"}
      data-editing={to_string(Map.get(assigns, :can_manage, false))}
      data-target="#dashboard-editor"
    >
      <%= for card <- Enum.sort_by(@cards, & &1.position) do %>
        <.live_component
          module={CardComponent}
          id={"card-#{card.id}"}
          card={card}
          result={Map.get(@card_results, card.id)}
          error={Map.get(@card_errors, card.id)}
          running={MapSet.member?(@running_cards, card.id)}
          selected={card.id == @selected_card_id}
          public={Map.get(assigns, :public, false)}
          can_manage={Map.get(assigns, :can_manage, not Map.get(assigns, :public, false))}
          values={Map.get(assigns, :values, %{})}
          connecting={Map.get(assigns, :connecting)}
          click_filters={click_filters(assigns, card)}
          query_vars={query_vars(assigns, card)}
          tabs={Map.get(assigns, :tabs, [])}
          tab={Map.get(assigns, :tab)}
          pro_info={Map.get(assigns, :pro_info, %{})}
          parent={@parent}
        />
      <% end %>
    </div>
    """
  end

  # The values the card's query runs with, for its "Open the query": the
  # rows behind the card, in the query editor.
  defp query_vars(assigns, %{card_type: :query} = card) do
    card.filter_mappings
    |> CardVariables.build(
      Map.get(assigns, :filters, []),
      Map.get(assigns, :values, %{}),
      Date.utc_today()
    )
    |> Map.new(fn {name, value} -> {name, url_value(value)} end)
  end

  defp query_vars(_assigns, _card), do: %{}

  defp url_value(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp url_value(value), do: to_string(value)

  # Out of edit mode, a click on a chart filters the dashboard by its mark.
  defp click_filters(assigns, card) do
    if Map.get(assigns, :can_manage, not Map.get(assigns, :public, false)),
      do: %{},
      else: ChartFilters.targets(card, Map.get(assigns, :filters, []))
  end
end
