defmodule Lotus.Web.Dashboards.CardComponent do
  @moduledoc """
  Renders a single card in the dashboard grid.
  Supports query, text, heading, and link card types.
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.Charts
  alias Lotus.Web.Dashboards.ChartFilters
  alias Lotus.Web.Dashboards.FilterConnections
  alias Lotus.Web.Dashboards.TextCard
  alias Lotus.Web.Queries.MasuResults

  @impl Phoenix.LiveComponent
  def render(assigns) do
    is_public = Map.get(assigns, :public, false)
    # Selecting a card opens its settings: in edit mode, for a user who may
    # manage the dashboard (the page passes `can_manage` only then).
    can_manage = Map.get(assigns, :can_manage, true)
    card_type = assigns.card.card_type
    heading = TextCard.heading?(assigns.card)

    assigns =
      assign(assigns,
        is_public: is_public,
        can_manage: can_manage,
        heading: heading,
        values: Map.get(assigns, :values, %{}),
        # A heading is its text, with no frame; a text or a link has a
        # title bar when it has a title. A card being edited always has one,
        # for its settings.
        framed: can_manage or not heading,
        show_header:
          can_manage or card_type == :query or
            (card_type in [:text, :link] and present?(assigns.card.title)),
        chart?:
          card_type == :query and assigns.result != nil and
            Charts.valid_config?(assigns.card.visualization_config),
        maximized: Map.get(assigns, :maximized, false),
        place: place(assigns.card.layout),
        folds?: not heading,
        folded: layout_value(assigns.card.layout || %{}, :folded, false) == true,
        connecting: can_manage && Map.get(assigns, :connecting),
        click_filters: Map.get(assigns, :click_filters, %{}),
        query_vars: Map.get(assigns, :query_vars, %{})
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
      data-heading={to_string(@heading)}
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
        <.pro_slot name={:card_header} slot_assigns={%{card: @card}} />
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
            query_vars={@query_vars}
            other_tabs={Enum.reject(Map.get(assigns, :tabs, []), &(&1["id"] == Map.get(assigns, :tab)))}
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
            <.query_content
              card={@card}
              result={@result}
              error={@error}
              running={@running}
              click_filters={@click_filters}
              values={@values}
              parent={@parent}
            />
          <% :text -> %>
            <TextCard.editor :if={@can_manage} card={@card} target={@parent} />
            <.text_content :if={not @can_manage} card={@card} values={@values} heading={@heading} />
          <% :heading -> %>
            <.heading_content content={@card.content} public={@is_public} />
          <% :link -> %>
            <.link_content content={@card.content} />
          <% _ -> %>
            <.text_content card={@card} values={@values} heading={false} />
        <% end %>
      </div>

      <.connect :if={@connecting} card={@card} filter={@connecting} parent={@parent} />

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

  # Over the card while a filter is being connected: what the filter sets in
  # the card's query. Its clicks stay in it (they do not pick the card).
  attr(:card, :map, required: true)
  attr(:filter, :map, required: true)
  attr(:parent, :any, required: true)

  defp connect(assigns) do
    query = assigns.card.query
    entries = FilterConnections.entries(assigns.card.filter_mappings, assigns.filter)

    assigns =
      assign(assigns,
        variables: (query && query.variables) || [],
        current: Enum.find_value(entries, & &1.variable_name),
        split: Enum.any?(entries, & &1.transform),
        label: assigns.filter.label || assigns.filter.name
      )

    ~H"""
    <div
      id={"card-#{@card.id}-connect"}
      class={[
        "lotus-card-connect absolute inset-0 z-10 flex flex-col items-center justify-center gap-2 rounded-lg p-4 text-center backdrop-blur-[2px]",
        @current && "bg-pink-50/90 ring-2 ring-pink-500 dark:bg-pink-950/80",
        !@current && "bg-white/85 dark:bg-gray-900/85"
      ]}
      phx-click={%JS{}}
      data-connected={to_string(@current != nil)}
    >
      <%= case @card.card_type do %>
        <% :query -> %>
          <%= if @variables == [] do %>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              <%= gettext("Its query has no variables for a filter to set.") %>
            </p>
          <% else %>
            <form
              id={"card-#{@card.id}-connect-form"}
              phx-change="update_filter_mapping"
              phx-target={@parent}
              class="w-full max-w-[14rem]"
            >
              <input type="hidden" name="card-id" value={@card.id} />
              <input type="hidden" name="filter-name" value={@filter.name} />
              <label
                for={"card-#{@card.id}-connect-select"}
                class="mb-1 block text-xs font-medium text-gray-600 dark:text-gray-300"
              >
                <%= gettext("%{filter} sets", filter: @label) %>
              </label>
              <select
                id={"card-#{@card.id}-connect-select"}
                name={"filter_mapping[#{@filter.name}]"}
                class="w-full rounded-md border border-gray-300 bg-white p-1.5 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              >
                <option value=""><%= gettext("Nothing in this card") %></option>
                <option :for={var <- @variables} value={var.name} selected={@current == var.name}>
                  <%= var.label || var.name %>
                </option>
              </select>
              <p :if={@split} class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                <%= gettext("Its start and end set two variables; a choice here sets one.") %>
              </p>
            </form>
          <% end %>
        <% :text -> %>
          <p class="text-sm text-gray-600 dark:text-gray-300">
            <%= gettext("A text shows the filter's value where it says %{name}.",
              name: "{{#{@filter.name}}}"
            ) %>
          </p>
        <% _ -> %>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            <%= gettext("A filter sets nothing in this card.") %>
          </p>
      <% end %>
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
  attr(:query_vars, :map, default: %{})
  attr(:other_tabs, :list, default: [])
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
          navigate={lotus_path(["queries", @card.query_id], query_params(@query_vars))}
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
        <%!-- The other tabs, in edit mode: the card moves to one. --%>
        <div :if={@can_manage and @other_tabs != []} class="border-t border-gray-100 py-1 dark:border-gray-700">
          <p class="px-3 pb-0.5 text-xs text-gray-500 dark:text-gray-400"><%= gettext("Move to") %></p>
          <.menu_item
            :for={tab <- @other_tabs}
            phx-click={
              @close
              |> JS.push("move_card_to_tab", value: %{"card-id" => @card.id, "tab" => tab["id"]}, target: @parent)
            }
          >
            <Icons.corner_down_right class="h-4 w-4" /> <%= tab["name"] %>
          </.menu_item>
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

  # The card's values in the query editor's URL (`?vars[region]=North`).
  defp query_params(vars) when vars == %{}, do: %{}
  defp query_params(vars), do: %{vars: vars}

  # What a click on the chart does, for the pointer that rests on it.
  defp click_hint(targets) when targets == %{}, do: nil

  defp click_hint(targets) do
    names =
      targets
      |> Map.values()
      |> Enum.uniq_by(& &1.name)
      |> Enum.map_join(", ", &(&1.label || &1.name))

    gettext("Click the chart to filter by %{filters}", filters: names)
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
      <% @running and is_nil(@result) -> %>
        <.placeholder chart?={Charts.valid_config?(@card.visualization_config)} />

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
            select={@click_filters != %{} && "chart_select"}
            selected={ChartFilters.selected(@click_filters, @values)}
            phx-target={@parent}
            title={click_hint(@click_filters)}
            class="lotus-card-chart"
          />
        </div>

      <% @result -> %>
        <div class={["h-full transition-opacity", @running && "opacity-50"]} aria-busy={to_string(@running)}>
          <MasuResults.card id={"table-#{@card.id}"} result={@result} label={@card.title} />
        </div>

      <% true -> %>
        <div class="flex items-center justify-center h-full text-gray-400 text-sm">
          <%= gettext("No data") %>
        </div>
    <% end %>
    """
  end

  # Its Markdown, with the dashboard's filter values in it. A heading sits at
  # the foot of its row, over the cards it names.
  # While a card reads its data the first time: the shape of what comes, a
  # chart's bars or a table's rows, softly pulsing (still with reduced
  # motion), in place of a spinner.
  attr(:chart?, :boolean, required: true)

  defp placeholder(assigns) do
    ~H"""
    <div
      class="lotus-card-placeholder h-full motion-safe:animate-pulse"
      role="status"
      aria-label={gettext("Reading the data…")}
    >
      <div :if={@chart?} class="flex h-full items-end gap-3 border-b border-gray-200 pb-1 pl-1 dark:border-gray-700">
        <div
          :for={height <- [55, 80, 40, 95, 65, 30, 75]}
          class="flex-1 rounded-t bg-gray-200/80 dark:bg-gray-700"
          style={"height: #{height}%"}
        >
        </div>
      </div>
      <div :if={not @chart?} class="space-y-2.5 pt-1">
        <div class="h-3 w-full rounded bg-gray-200 dark:bg-gray-700"></div>
        <div :for={width <- [92, 78, 85, 64, 88, 72]} class="h-3 rounded bg-gray-100 dark:bg-gray-700/60" style={"width: #{width}%"}></div>
      </div>
    </div>
    """
  end

  defp text_content(assigns) do
    assigns =
      assign(assigns,
        html:
          assigns.card |> TextCard.text() |> TextCard.fill(assigns.values) |> render_markdown()
      )

    ~H"""
    <div class={[
      "prose prose-sm dark:prose-invert max-w-none prose-headings:tracking-tight prose-p:text-gray-600 dark:prose-p:text-gray-300",
      @heading && "flex h-full items-end prose-headings:m-0 prose-h1:text-2xl prose-h2:text-xl prose-h3:text-lg"
    ]}>
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
