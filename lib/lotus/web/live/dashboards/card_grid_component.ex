defmodule Lotus.Web.Dashboards.CardGridComponent do
  @moduledoc """
  Renders the dashboard card grid using a 12-column CSS grid layout.
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.Dashboards.CardComponent

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id="dashboard-grid"
      class="grid grid-cols-12 gap-4 auto-rows-min"
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
          can_manage={Map.get(assigns, :can_manage, true)}
          parent={@parent}
        />
      <% end %>
    </div>
    """
  end
end
