defmodule Lotus.Web.Dashboards.CardComponent do
  @moduledoc """
  Renders a single card in the dashboard grid.
  Supports query, text, heading, and link card types.
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.CellFormatter
  alias Lotus.Web.Charts

  @impl Phoenix.LiveComponent
  def render(assigns) do
    is_public = Map.get(assigns, :public, false)
    # Selecting a card opens its settings: in edit mode, for a user who may
    # manage the dashboard (the page passes `can_manage` only then).
    can_manage = Map.get(assigns, :can_manage, true)
    card_type = assigns.card.card_type

    assigns =
      assign(assigns,
        is_public: is_public,
        can_manage: can_manage,
        # A heading is its text, with no frame; a text or a link has a
        # title bar when it has a title. A card being edited always has one,
        # for its settings.
        framed: can_manage or card_type != :heading,
        show_header:
          can_manage or card_type == :query or
            (card_type in [:text, :link] and present?(assigns.card.title)),
        chart?:
          card_type == :query and assigns.result != nil and
            Charts.valid_config?(assigns.card.visualization_config),
        maximized: Map.get(assigns, :maximized, false),
        place: place(assigns.card.layout),
        folds?: card_type != :heading,
        folded: layout_value(assigns.card.layout || %{}, :folded, false) == true
      )

    ~H"""
    <div
      id={@id}
      class={card_classes(@selected, @framed, @can_manage)}
      style={grid_position(@place, @framed)}
      phx-click={@can_manage && "select_card"}
      phx-value-card-id={@card.id}
      phx-target={@parent}
      phx-mounted={JS.ignore_attributes(["style", "data-folded"])}
      tabindex={@can_manage && "0"}
      aria-roledescription={@can_manage && gettext("card: Alt and the arrow keys move it, with Shift resize it")}
      data-card-id={@card.id}
      data-card-type={@card.card_type}
      data-x={@place.x}
      data-y={@place.y}
      data-w={@place.w}
      data-h={@place.h}
      data-folded-default={to_string(@folded)}
      data-folded={to_string(@folded and not @can_manage)}
    >
      <div
        :if={@show_header}
        class={["flex items-center gap-1.5 pl-2 pr-2 pt-2.5 pb-0.5 min-h-[2.5rem]", @can_manage && "cursor-grab"]}
        data-card-handle={@can_manage}
      >
        <button
          :if={@folds?}
          type="button"
          class="p-1 rounded-md text-gray-400 hover:text-gray-700 hover:bg-gray-100 dark:hover:text-gray-200 dark:hover:bg-gray-700"
          data-card-fold
          aria-expanded="true"
          aria-controls={"#{@id}-body"}
          title={if @can_manage, do: gettext("Starts folded or open"), else: gettext("Fold or open")}
          aria-label={if @can_manage, do: gettext("Starts folded or open"), else: gettext("Fold or open")}
        >
          <Icons.chevron_down class="h-4 w-4 transition-transform" />
        </button>
        <h3 class={["min-w-0 flex-1 truncate text-sm font-semibold text-gray-900 dark:text-gray-100", not @folds? && "pl-2"]}>
          <%= @card.title || default_title(@card) %>
        </h3>
        <span
          :if={@can_manage and @folded}
          class="shrink-0 rounded-full bg-pink-50 px-2 py-0.5 text-[11px] font-medium text-pink-700 dark:bg-pink-900/30 dark:text-pink-300"
        >
          <%= gettext("Starts folded") %>
        </span>
        <div class={[
          "lotus-card-actions flex items-center gap-0.5 transition-opacity",
          not @can_manage && "opacity-0 group-hover/card:opacity-100 focus-within:opacity-100"
        ]}>
          <.card_button :if={@chart?} id={"#{@id}-maximize"} phx-click="maximize" phx-target={@myself} label={gettext("Maximize")}>
            <Icons.maximize class="h-4 w-4" />
          </.card_button>
          <.card_button
            :if={@can_manage}
            phx-click="open_card_settings"
            phx-value-card-id={@card.id}
            phx-target={@parent}
            label={gettext("Settings")}
          >
            <Icons.cog_6_tooth class="h-4 w-4" />
          </.card_button>
          <.card_menu
            :if={@chart? or (@card.card_type == :query and not @is_public) or @can_manage}
            id={"#{@id}-menu"}
            card={@card}
            chart?={@chart?}
            public={@is_public}
            can_manage={@can_manage}
            running={@running}
            parent={@parent}
          />
        </div>
      </div>

      <div
        id={"#{@id}-body"}
        class={["lotus-card-body flex-1 min-h-0 overflow-hidden", @show_header && "px-4 pt-1 pb-3", not @show_header && @framed && "p-4"]}
      >
        <%= case @card.card_type do %>
          <% :query -> %>
            <.query_content card={@card} result={@result} error={@error} running={@running} />
          <% :text -> %>
            <.text_content content={@card.content} public={@is_public} />
          <% :heading -> %>
            <.heading_content content={@card.content} public={@is_public} />
          <% :link -> %>
            <.link_content content={@card.content} />
          <% _ -> %>
            <.text_content content={@card.content} public={@is_public} />
        <% end %>
      </div>

      <%!-- Its corner: drag it to resize the card (edit mode). --%>
      <span
        :if={@can_manage}
        class="absolute right-1 bottom-1 h-4 w-4 cursor-se-resize rounded-br-lg border-r-2 border-b-2 border-gray-300 hover:border-pink-500 dark:border-gray-500"
        data-card-resize
        aria-hidden="true"
      >
      </span>

      <.maximized :if={@maximized and @chart?} id={@id} card={@card} result={@result} target={@myself} />
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:rest, :global, include: ~w(id))
  slot(:inner_block, required: true)

  defp card_button(assigns) do
    ~H"""
    <button
      type="button"
      class="p-1.5 rounded-md text-gray-400 hover:text-gray-700 hover:bg-gray-100 dark:hover:text-gray-200 dark:hover:bg-gray-700"
      title={@label}
      aria-label={@label}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # The card's ⋯: what a viewer may do with it (refresh it, save its chart,
  # open its query) and, in edit mode, remove it.
  attr(:id, :string, required: true)
  attr(:card, :map, required: true)
  attr(:chart?, :boolean, required: true)
  attr(:public, :boolean, required: true)
  attr(:can_manage, :boolean, required: true)
  attr(:running, :boolean, required: true)
  attr(:parent, :any, required: true)

  defp card_menu(assigns) do
    assigns =
      assign(assigns,
        close: JS.hide(to: "##{assigns.id}-items"),
        width: place(assigns.card.layout).w
      )

    ~H"""
    <div class="relative">
      <.card_button
        id={"#{@id}-button"}
        phx-click={JS.toggle(to: "##{@id}-items") |> JS.focus_first(to: "##{@id}-items")}
        label={gettext("More")}
        aria-haspopup="menu"
        aria-controls={"#{@id}-items"}
      >
        <Icons.ellipsis class="h-4 w-4" />
      </.card_button>
      <div
        id={"#{@id}-items"}
        role="menu"
        class="absolute right-0 top-full z-30 mt-1 hidden w-56 rounded-lg bg-white py-1 text-sm shadow-lg ring-1 ring-black/10 dark:bg-gray-800 dark:ring-white/10"
        phx-click-away={@close}
        phx-window-keydown={@close}
        phx-key="Escape"
      >
        <.menu_item
          :if={@card.card_type == :query and not @public}
          phx-click={@close |> JS.push("refresh_card", value: %{"card-id" => @card.id}, target: @parent)}
        >
          <Icons.rotate_ccw class={["h-4 w-4", @running && "animate-spin"]} /> <%= gettext("Refresh") %>
        </.menu_item>
        <.menu_item
          :if={@chart?}
          phx-click={@close |> JS.dispatch("click", to: "#chart-#{@card.id} [data-fude-export=png]")}
        >
          <Icons.download class="h-4 w-4" /> <%= gettext("Save as PNG") %>
        </.menu_item>
        <.link
          :if={@card.card_type == :query and @card.query_id != nil and not @public}
          navigate={lotus_path(["queries", @card.query_id])}
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-1.5 text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700"
        >
          <Icons.code_braces class="h-4 w-4" /> <%= gettext("Open the query") %>
        </.link>
        <%!-- Its width, in edit mode: the slots it snaps to. --%>
        <div :if={@can_manage} class="px-3 py-1.5">
          <p class="mb-1 text-xs text-gray-500 dark:text-gray-400"><%= gettext("Size") %></p>
          <div class="grid grid-cols-6 gap-1" role="group" aria-label={gettext("Size")}>
            <button
              :for={{w, label} <- [{3, "¼"}, {4, "⅓"}, {6, "½"}, {8, "⅔"}, {9, "¾"}, {12, "1"}]}
              type="button"
              role="menuitem"
              class={[
                "rounded px-1 py-0.5 text-xs font-medium",
                @width == w && "bg-pink-100 text-pink-700 dark:bg-pink-900/40 dark:text-pink-300",
                @width != w && "text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700"
              ]}
              aria-pressed={to_string(@width == w)}
              title={gettext("%{count} of 12 columns", count: w)}
              phx-click={@close |> JS.dispatch("lotus:size", to: "#dashboard-grid", detail: %{card: @card.id, w: w})}
            >
              <%= label %>
            </button>
          </div>
        </div>
        <.menu_item
          :if={@can_manage}
          class="text-red-600 dark:text-red-400"
          phx-click={@close |> JS.push("delete_card", value: %{"card-id" => @card.id}, target: @parent)}
        >
          <Icons.trash class="h-4 w-4" /> <%= gettext("Remove from dashboard") %>
        </.menu_item>
      </div>
    </div>
    """
  end

  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  defp menu_item(assigns) do
    ~H"""
    <button
      type="button"
      role="menuitem"
      class={[
        "flex w-full items-center gap-2 px-3 py-1.5 text-left hover:bg-gray-100 dark:hover:bg-gray-700",
        @class || "text-gray-700 dark:text-gray-200"
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("chart_render_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, :error, error)}
  end

  def handle_event("maximize", _params, socket), do: {:noreply, assign(socket, :maximized, true)}
  def handle_event("restore", _params, socket), do: {:noreply, assign(socket, :maximized, false)}

  # A card's chart over the whole page, drawn again at its size. Its clicks
  # stay in it: the card under it selects on a click (`select_card`).
  attr(:id, :string, required: true)
  attr(:card, :map, required: true)
  attr(:result, :map, required: true)
  attr(:target, :any, required: true)

  defp maximized(assigns) do
    assigns =
      assign(assigns,
        restore:
          JS.push("restore", target: assigns.target) |> JS.focus(to: "##{assigns.id}-maximize")
      )

    ~H"""
    <div
      id={"#{@id}-maximized"}
      class="fixed inset-0 z-50 flex bg-black/40 p-0 sm:p-6 cursor-default"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-maximized-title"}
      phx-click={@restore}
      phx-window-keydown={@restore}
      phx-key="Escape"
      phx-mounted={JS.focus(to: "##{@id}-restore")}
    >
      <div
        class="flex flex-1 flex-col overflow-hidden bg-white dark:bg-gray-800 shadow-xl sm:rounded-lg"
        phx-click={%JS{}}
      >
        <div class="flex items-center justify-between gap-4 px-4 py-3 border-b border-gray-200 dark:border-gray-700">
          <h3 id={"#{@id}-maximized-title"} class="text-sm font-medium text-gray-900 dark:text-white truncate">
            <%= @card.title || default_title(@card) %>
          </h3>
          <button
            id={"#{@id}-restore"}
            type="button"
            phx-click={@restore}
            class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
            title={gettext("Close")}
            aria-label={gettext("Close")}
          >
            <Icons.x_mark class="h-4 w-4" />
          </button>
        </div>
        <div class="flex-1 overflow-auto p-4">
          <Charts.draw
            id={"chart-max-#{@card.id}"}
            result={@result}
            config={@card.visualization_config}
            export
            class="lotus-chart-max"
          />
        </div>
      </div>
    </div>
    """
  end

  # Its place on the 12 columns: x, y, w and h (a row is 100px).
  defp place(nil), do: %{x: 0, y: 0, w: 6, h: 4}

  defp place(layout) when is_map(layout) do
    Map.new([x: 0, y: 0, w: 6, h: 4], fn {key, default} ->
      {key, layout_value(layout, key, default)}
    end)
  end

  # Its place on a CSS grid, before the DashboardGrid hook places it, and
  # with no JavaScript. A heading, with no frame, is as high as its text.
  defp grid_position(%{x: x, y: y, w: w, h: h}, framed) do
    min_height = if framed, do: " min-height: #{h * 100 - 16}px;"
    "grid-column: #{x + 1} / span #{w}; grid-row: #{y + 1} / span #{h};#{min_height}"
  end

  defp layout_value(layout, key, default),
    do: Map.get(layout, key, Map.get(layout, Atom.to_string(key), default))

  # A card on the dashboard's canvas: white, with a soft edge. A heading is
  # its text alone. In edit mode a card is picked by a click, and the picked
  # one is outlined.
  defp card_classes(selected, framed, editing) do
    [
      "group/card relative flex flex-col rounded-xl transition-shadow",
      framed && "bg-white dark:bg-gray-800 shadow-sm ring-1 ring-black/[0.06] dark:ring-white/10",
      editing && "cursor-pointer",
      editing && not selected && "hover:ring-gray-300 dark:hover:ring-gray-500",
      selected && "ring-2 ring-pink-500 dark:ring-pink-400"
    ]
  end

  defp present?(nil), do: false
  defp present?(text) when is_binary(text), do: String.trim(text) != ""

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
      <% @running and is_nil(@result) -> %>
        <div class="flex items-center justify-center h-full">
          <.spinner size="32" />
        </div>

      <% @error -> %>
        <div class="flex items-center justify-center h-full text-red-500 dark:text-red-400 text-sm p-4">
          <Icons.exclamation_circle class="h-5 w-5 mr-2 flex-shrink-0" />
          <span class="truncate"><%= @error %></span>
        </div>

      <%!-- While a refresh runs, the chart stays, dimmed, so that its marks move to the new rows. --%>
      <% @result && Charts.valid_config?(@card.visualization_config) -> %>
        <div class={["h-full transition-opacity", @running && "opacity-50"]} aria-busy={to_string(@running)}>
          <Charts.draw
            id={"chart-#{@card.id}"}
            result={@result}
            config={@card.visualization_config}
            height={:fill}
            export
            class="lotus-card-chart"
          />
        </div>

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

  # The same formatter as the query editor's results table, so a Decimal, a
  # map from jsonb or a time renders as a value and never as its inspect form.
  defp format_cell(nil), do: "-"
  defp format_cell(value), do: CellFormatter.format(value)

  defp text_content(assigns) do
    assigns = assign(assigns, html: render_markdown(get_content_text(assigns.content)))

    ~H"""
    <div class="prose prose-sm dark:prose-invert max-w-none prose-headings:tracking-tight prose-p:text-gray-600 dark:prose-p:text-gray-300">
      <%= @html %>
    </div>
    """
  end

  # A heading sits at the foot of its row, over the cards it names.
  defp heading_content(assigns) do
    assigns = assign(assigns, text: get_content_text(assigns.content))

    ~H"""
    <div class="flex h-full items-end">
      <h2 class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">
        <%= @text %>
      </h2>
    </div>
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

  defp render_markdown(text), do: Lotus.Web.Markdown.to_safe_html(text)

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
