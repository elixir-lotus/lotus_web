defmodule Lotus.Web.Dashboards.CardComponent do
  @moduledoc """
  Renders a single card in the dashboard grid.
  Supports query, text, heading, and link card types.
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.Markdown
  alias Lotus.Web.VegaSpecBuilder

  @impl Phoenix.LiveComponent
  def render(assigns) do
    is_public = Map.get(assigns, :public, false)
    show_header = not (is_public and assigns.card.card_type in [:heading, :text])
    assigns = assign(assigns, show_header: show_header, is_public: is_public)

    ~H"""
    <div
      id={@id}
      class={card_classes(@selected, @card.card_type, @show_header, @is_public)}
      style={grid_position(@card.layout)}
      phx-click="select_card"
      phx-value-card-id={@card.id}
      phx-target={@parent}
    >
      <%= if @show_header do %>
        <div class="flex items-center justify-between px-3 py-2 border-b border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700/50">
          <h3 class="text-sm font-medium text-gray-900 dark:text-white truncate">
            <%= @card.title || default_title(@card) %>
          </h3>
          <%= unless Map.get(assigns, :public, false) do %>
            <div class="flex items-center gap-1">
              <%= if @card.card_type == :query do %>
                <button
                  phx-click="refresh_card"
                  phx-value-card-id={@card.id}
                  phx-target={@parent}
                  class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                  title={gettext("Refresh")}
                >
                  <Icons.rotate_ccw class={["h-4 w-4", @running && "animate-spin"]} />
                </button>
              <% end %>
              <button
                phx-click="open_card_settings"
                phx-value-card-id={@card.id}
                phx-target={@parent}
                class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                title={gettext("Settings")}
              >
                <Icons.cog_6_tooth class="h-4 w-4" />
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class={["flex-1 overflow-hidden", @show_header && "p-3"]}>
        <%= case @card.card_type do %>
          <% :query -> %>
            <.query_content card={@card} result={@result} error={@error} running={@running} />
          <% :text -> %>
            <.text_content content={@card.content} public={Map.get(assigns, :public, false)} />
          <% :heading -> %>
            <.heading_content content={@card.content} public={Map.get(assigns, :public, false)} />
          <% :link -> %>
            <.link_content content={@card.content} />
          <% _ -> %>
            <.text_content content={@card.content} public={Map.get(assigns, :public, false)} />
        <% end %>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("chart_render_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, :error, error)}
  end

  defp grid_position(%{x: x, y: y, w: w, h: h}) do
    min_height = h * 100

    "grid-column: #{x + 1} / span #{w}; grid-row: #{y + 1} / span #{h}; min-height: #{min_height}px;"
  end

  defp grid_position(nil), do: "grid-column: span 6; min-height: 400px;"

  defp grid_position(layout) when is_map(layout) do
    x = Map.get(layout, "x", Map.get(layout, :x, 0))
    y = Map.get(layout, "y", Map.get(layout, :y, 0))
    w = Map.get(layout, "w", Map.get(layout, :w, 6))
    h = Map.get(layout, "h", Map.get(layout, :h, 4))
    min_height = h * 100

    "grid-column: #{x + 1} / span #{w}; grid-row: #{y + 1} / span #{h}; min-height: #{min_height}px;"
  end

  defp card_classes(selected, card_type, show_header, is_public) do
    base =
      "flex flex-col bg-white dark:bg-gray-700 rounded-lg shadow-sm border-2 transition-all overflow-hidden"

    base =
      if is_public do
        base
      else
        "#{base} cursor-pointer"
      end

    base =
      if card_type == :heading and not show_header do
        "#{base} p-4"
      else
        base
      end

    if selected do
      "#{base} border-pink-500 ring-2 ring-pink-500/20"
    else
      hover = if is_public, do: "", else: " hover:border-gray-300 dark:hover:border-gray-500"
      "#{base} border-transparent#{hover}"
    end
  end

  defp default_title(%{card_type: :query, query: query}) when not is_nil(query) do
    query.name || gettext("Query")
  end

  defp default_title(%{card_type: :query}), do: gettext("Query")
  defp default_title(%{card_type: :text}), do: gettext("Text")
  defp default_title(%{card_type: :heading}), do: gettext("Heading")
  defp default_title(%{card_type: :link}), do: gettext("Link")
  defp default_title(_), do: gettext("Card")

  defp query_content(assigns) do
    ~H"""
    <%= cond do %>
      <% @running -> %>
        <div class="flex items-center justify-center h-full">
          <.spinner size="32" />
        </div>

      <% @error -> %>
        <div class="flex items-center justify-center h-full text-red-500 dark:text-red-400 text-sm p-4">
          <Icons.exclamation_circle class="h-5 w-5 mr-2 flex-shrink-0" />
          <span class="truncate"><%= @error %></span>
        </div>

      <% @result && VegaSpecBuilder.valid_config?(@card.visualization_config) -> %>
        <% chart_spec = VegaSpecBuilder.build(@result, @card.visualization_config) %>
        <%= case safe_json_encode(chart_spec) do %>
          <% {:ok, json} -> %>
            <div
              id={"chart-#{@card.id}"}
              phx-hook="VegaChart"
              phx-update="ignore"
              data-spec={json}
              class="w-full h-full min-h-[150px]"
            />
          <% {:error, _reason} -> %>
            <div class="flex items-center justify-center h-full text-red-500 dark:text-red-400 text-sm p-4">
              <Icons.exclamation_circle class="h-5 w-5 mr-2 flex-shrink-0" />
              <span class="truncate"><%= gettext("Chart could not be rendered: result contains values that cannot be displayed") %></span>
            </div>
        <% end %>

      <% @result -> %>
        <.mini_table result={@result} />

      <% true -> %>
        <div class="flex items-center justify-center h-full text-gray-400 text-sm">
          <%= gettext("No data") %>
        </div>
    <% end %>
    """
  end

  defp mini_table(assigns) do
    ~H"""
    <div class="overflow-auto h-full text-xs">
      <table class="min-w-full">
        <thead class="bg-gray-50 dark:bg-gray-600 sticky top-0">
          <tr>
            <%= for col <- Enum.take(@result.columns, 5) do %>
              <th class="px-2 py-1 text-left font-medium text-gray-500 dark:text-gray-300 truncate max-w-[100px]">
                <%= col %>
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 dark:divide-gray-600">
          <%= for row <- Enum.take(@result.rows, 10) do %>
            <tr>
              <%= for {_col, idx} <- Enum.take(Enum.with_index(@result.columns), 5) do %>
                <td class="px-2 py-1 text-gray-600 dark:text-gray-300 truncate max-w-[100px]">
                  <%= format_cell(Enum.at(row, idx)) %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
      <%= if length(@result.rows) > 10 do %>
        <div class="text-center py-2 text-gray-400">
          <%= gettext("+ %{count} more rows", count: length(@result.rows) - 10) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_cell(nil), do: "-"
  defp format_cell(value) when is_binary(value), do: value
  defp format_cell(value) when is_number(value), do: to_string(value)
  defp format_cell(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_cell(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_cell(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  defp format_cell(value), do: inspect(value)

  defp text_content(assigns) do
    text = get_content_text(assigns.content)
    is_public = Map.get(assigns, :public, false)
    html = render_markdown(text)
    assigns = assign(assigns, html: html, is_public: is_public)

    ~H"""
    <div class={["prose prose-sm dark:prose-invert max-w-none", @is_public && "p-3"]}>
      <%= @html %>
    </div>
    """
  end

  defp heading_content(assigns) do
    text = get_content_text(assigns.content)
    is_public = Map.get(assigns, :public, false)
    assigns = assign(assigns, text: text, is_public: is_public)

    ~H"""
    <h2 class={[
      "font-bold text-gray-900 dark:text-white",
      @is_public && "text-2xl",
      !@is_public && "text-xl"
    ]}>
      <%= @text %>
    </h2>
    """
  end

  defp link_content(assigns) do
    url = get_content_url(assigns.content)
    href = normalize_url(url)
    assigns = assign(assigns, url: url, href: href)

    ~H"""
    <div class="flex items-center gap-2">
      <Icons.link_icon class="h-4 w-4 text-gray-400" />
      <a
        href={@href || "#"}
        target="_blank"
        rel="noopener noreferrer"
        class="text-indigo-600 dark:text-indigo-400 hover:underline truncate"
      >
        <%= @url || gettext("No link set") %>
      </a>
    </div>
    """
  end

  defp render_markdown(text), do: Markdown.to_safe_html(text)

  defp get_content_text(nil), do: ""
  defp get_content_text(content) when is_binary(content), do: content
  defp get_content_text(%{"text" => text}), do: text
  defp get_content_text(%{text: text}), do: text
  defp get_content_text(_), do: ""

  defp get_content_url(nil), do: nil
  defp get_content_url(content) when is_binary(content), do: content
  defp get_content_url(%{"url" => url}), do: url
  defp get_content_url(%{url: url}), do: url
  defp get_content_url(_), do: nil

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" -> nil
      String.starts_with?(url, "http://") -> url
      String.starts_with?(url, "https://") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      true -> "https://" <> url
    end
  end
end
