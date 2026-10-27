defmodule Lotus.Web.Dashboards.AddCardModal do
  @moduledoc """
  Modal component for adding new cards to a dashboard.
  Supports query, text and link card types (a heading is a text card), and
  the kinds of card Lotus Pro adds (`Lotus.Web.Pro.card_kinds/1`).
  """

  use Lotus.Web, :live_component

  import Lotus.Web.Components.QueryPicker

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, selected_type: :query, selected_query_id: nil)}
  end

  # The type it opens on: the one the edit bar's button asked for.
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, Map.delete(assigns, :type))

    socket =
      if Map.has_key?(socket.assigns, :opened),
        do: socket,
        else: assign(socket, selected_type: assigns[:type] || :query, opened: true)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    card_types = [
      %{
        type: :query,
        icon: :chart_bar,
        label: gettext("Query"),
        desc: gettext("Display query results as table or chart")
      },
      %{
        type: :text,
        icon: :document_text,
        label: gettext("Text"),
        desc: gettext("Rich text, headings and filter values")
      },
      %{type: :link, icon: :link_icon, label: gettext("Link"), desc: gettext("External link")}
    ]

    pro_types =
      for kind <- Lotus.Web.Pro.card_kinds(assigns[:pro_info] || %{}),
          do: %{type: "pro:" <> kind.kind, icon: :pro, label: kind.label, desc: kind.description}

    card_types = card_types ++ pro_types

    assigns = assign(assigns, card_types: card_types)

    ~H"""
    <div>
      <.modal id="add-card-modal" show on_cancel={JS.push("close_add_card_modal", target: @parent)}>
      <h3 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
        <%= gettext("Add Card") %>
      </h3>

      <%!-- Card Type Selection --%>
      <div class="grid grid-cols-2 gap-3 mb-6">
        <%= for ct <- @card_types do %>
          <button
            type="button"
            phx-click="select_card_type"
            phx-value-type={ct.type}
            phx-target={@myself}
            class={type_button_class(@selected_type == ct.type)}
          >
            <.dynamic_icon name={ct.icon} class="h-6 w-6 mb-2" />
            <span class="font-medium"><%= ct.label %></span>
            <span class="text-xs text-gray-500 dark:text-gray-400 mt-1"><%= ct.desc %></span>
          </button>
        <% end %>
      </div>

      <%!-- Query Selector (only for query type) --%>
      <%= if @selected_type == :query do %>
        <div class="mb-6">
          <div id="add-card-query-label" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            <%= gettext("Select Query") %>
          </div>
          <form id="add-card-query-form" phx-change="select_query" phx-target={@myself}>
            <.query_picker
              id="add-card-query"
              name="query_id"
              value={@selected_query_id}
              queries={@queries}
              label_id="add-card-query-label"
            />
          </form>
        </div>
      <% end %>

      <%!-- Actions --%>
      <div class="flex justify-end gap-3">
        <.button variant="light" phx-click="close_add_card_modal" phx-target={@parent}>
          <%= gettext("Cancel") %>
        </.button>
        <.button
          phx-click="confirm_add_card"
          phx-target={@parent}
          phx-value-type={@selected_type}
          phx-value-query-id={@selected_query_id}
          disabled={@selected_type == :query && !@selected_query_id}
        >
          <%= gettext("Add Card") %>
        </.button>
      </div>
    </.modal>
    </div>
    """
  end

  defp type_button_class(active) do
    base =
      "flex flex-col items-center p-4 rounded-lg border-2 transition-all text-center"

    if active do
      "#{base} border-pink-500 bg-pink-50 dark:bg-pink-900/20 text-pink-600 dark:text-pink-400"
    else
      "#{base} border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500 text-gray-600 dark:text-gray-300"
    end
  end

  defp dynamic_icon(%{name: :chart_bar} = assigns), do: ~H"<Icons.chart_bar class={@class} />"

  defp dynamic_icon(%{name: :document_text} = assigns),
    do: ~H"<Icons.document_text class={@class} />"

  defp dynamic_icon(%{name: :heading} = assigns), do: ~H"<Icons.heading class={@class} />"
  defp dynamic_icon(%{name: :link_icon} = assigns), do: ~H"<Icons.link_icon class={@class} />"
  defp dynamic_icon(%{name: :pro} = assigns), do: ~H"<Icons.sparkles class={@class} />"
  defp dynamic_icon(assigns), do: ~H"<Icons.squares_2x2 class={@class} />"

  @impl Phoenix.LiveComponent
  def handle_event("select_card_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_type: parse_card_type(type))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_query", %{"query_id" => id}, socket) do
    query_id = if id == "", do: nil, else: String.to_integer(id)
    {:noreply, assign(socket, selected_query_id: query_id)}
  end

  defp parse_card_type("query"), do: :query
  defp parse_card_type("text"), do: :text
  defp parse_card_type("link"), do: :link
  defp parse_card_type("heading"), do: :heading
  defp parse_card_type("pro:" <> _kind = type), do: type
  defp parse_card_type(_), do: :query
end
