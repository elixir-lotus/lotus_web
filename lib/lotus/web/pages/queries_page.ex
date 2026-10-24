defmodule Lotus.Web.QueriesPage do
  @moduledoc """
  Landing page with tabs for Queries and Dashboards.
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Web.Actor
  alias Lotus.Web.Authorization
  alias Lotus.Web.Dashboards.Duplicate
  alias Lotus.Web.Dashboards.Sketch
  alias Lotus.Web.Dashboards.Tabs
  alias Lotus.Web.Dashboards.TextCard
  alias Lotus.Web.Page
  alias Lotus.Web.Pro
  alias Lotus.Web.Queries.QueryList
  alias Lotus.Web.RichText

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="queries-page" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg h-full flex flex-col overflow-hidden">
          <%!-- Header with tabs --%>
          <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <%!-- Tabs --%>
            <div class="flex border-b border-gray-200 dark:border-gray-600">
              <button
                phx-click="switch_tab"
                phx-value-tab="queries"
                phx-target={@myself}
                class={tab_class(@active_tab == :queries)}
              >
                <%= gettext("Queries") %>
                <span class="ml-2 px-2 py-0.5 text-xs bg-gray-100 dark:bg-gray-700 rounded-full">
                  <%= length(@queries) %>
                </span>
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="dashboards"
                phx-target={@myself}
                class={tab_class(@active_tab == :dashboards)}
              >
                <%= gettext("Dashboards") %>
                <span class="ml-2 px-2 py-0.5 text-xs bg-gray-100 dark:bg-gray-700 rounded-full">
                  <%= length(@dashboards) %>
                </span>
              </button>
            </div>
            <.pro_slot name={:list_toolbar} slot_assigns={Map.put(assigns, :tab, @active_tab)} />
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto px-4 sm:px-6 lg:px-8">
            <%= if @active_tab == :queries do %>
              <.queries_list
                entries={shown_queries(@query_entries, @query_search, @query_source)}
                any?={@query_entries != []}
                sources={@query_entries |> Enum.map(&{&1.source, &1.dialect}) |> Enum.uniq()}
                view={@query_view}
                search={@query_search}
                source={@query_source}
                can_create={Authorization.allowed?(assigns, :create_query)}
                target={@myself}
              />
            <% else %>
              <.dashboards_list
                dashboards={shown_dashboards(@dashboards, @dashboard_search, @dashboard_sort)}
                any?={@dashboards != []}
                view={@dashboard_view}
                search={@dashboard_search}
                sort={@dashboard_sort}
                can_create={Authorization.allowed?(assigns, :manage_dashboard)}
                target={@myself}
              />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tab_class(active) do
    base = "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors flex items-center"

    if active do
      "#{base} border-pink-500 text-pink-600 dark:text-pink-400"
    else
      "#{base} border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
    end
  end

  # The queries: a gallery of tiles, each with its saved chart sketched or
  # the first lines of its SQL, or a list, a line a query; as the
  # dashboards, the viewer's choice is kept in their browser.
  attr(:entries, :list, required: true)
  attr(:any?, :boolean, required: true)
  attr(:sources, :list, required: true)
  attr(:view, :atom, required: true)
  attr(:search, :string, required: true)
  attr(:source, :string, required: true)
  attr(:can_create, :boolean, required: true)
  attr(:target, :any, required: true)

  defp queries_list(assigns) do
    ~H"""
    <%= if not @any? do %>
      <div class="py-12 text-center text-gray-500 dark:text-gray-400">
        <Icons.terminal class="mx-auto h-12 w-12 text-gray-300 dark:text-gray-600 mb-4" />
        <p><%= gettext("No saved queries yet.") %></p>
        <.link
          :if={@can_create}
          navigate={lotus_path(["queries", "new"])}
          class="mt-2 inline-block text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300"
        >
          <%= gettext("Create your first query") %>
        </.link>
      </div>
    <% else %>
      <div
        id="queries-list"
        phx-hook="ListView"
        data-store="queries_view"
        data-list="queries"
        data-view={@view}
        phx-target={@target}
        class="pb-8"
      >
        <div class="flex flex-wrap items-center gap-3 pt-6 pb-5">
          <form id="queries-search" phx-change="search_queries" phx-submit="search_queries" phx-target={@target} class="w-full max-w-xs">
            <input type="hidden" name="source" value={@source} />
            <div class="relative">
              <Icons.magnifying_glass class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input
                type="search"
                name="search"
                value={@search}
                placeholder={gettext("Search queries…")}
                phx-debounce="200"
                aria-label={gettext("Search queries")}
                class="w-full rounded-lg border border-gray-300 bg-white py-2 pl-9 pr-3 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              />
            </div>
          </form>
          <div :if={length(@sources) > 1} class="flex flex-wrap items-center gap-2" role="group" aria-label={gettext("Source")}>
            <.source_chip source="" label={gettext("All sources")} current={@source} search={@search} target={@target} />
            <.source_chip
              :for={{source, dialect} <- @sources}
              source={source}
              dialect={dialect}
              label={source}
              current={@source}
              search={@search}
              target={@target}
            />
          </div>
          <div class="flex-1"></div>
          <.view_toggle list="queries" view={@view} target={@target} />
          <.link
            :if={@can_create}
            navigate={lotus_path(["queries", "new"])}
            class="inline-flex items-center gap-1.5 rounded-lg bg-pink-600 px-3 py-2 text-sm font-medium text-white hover:bg-pink-500"
          >
            <Icons.plus class="h-4 w-4" /> <%= gettext("New query") %>
          </.link>
        </div>

        <p :if={@entries == []} class="py-12 text-center text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("No query has these words.") %>
        </p>

        <div
          :if={@view == :grid and @entries != []}
          id="queries-gallery"
          class="grid grid-cols-[repeat(auto-fill,minmax(270px,1fr))] gap-5"
        >
          <.query_tile :for={entry <- @entries} entry={entry} />
          <.link
            :if={@can_create}
            navigate={lotus_path(["queries", "new"])}
            class="flex min-h-[14rem] flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-gray-300 text-sm text-gray-500 hover:border-pink-400 hover:bg-pink-50/40 hover:text-pink-600 dark:border-gray-600 dark:text-gray-400 dark:hover:bg-pink-900/10"
          >
            <Icons.plus class="h-7 w-7" /> <%= gettext("New query") %>
          </.link>
        </div>

        <div :if={@view == :list and @entries != []} id="queries-table" class="divide-y divide-gray-100 dark:divide-gray-700">
          <.link
            :for={entry <- @entries}
            id={"query-row-#{entry.query.id}"}
            navigate={lotus_path(["queries", entry.query.id])}
            class="grid grid-cols-[2.25rem_minmax(0,1.2fr)_minmax(0,1.6fr)_10rem_8rem] items-center gap-4 px-2 py-3 hover:bg-gray-50 dark:hover:bg-gray-700/40"
          >
            <span class="flex h-9 w-9 items-center justify-center rounded-lg border border-gray-200 bg-gray-50 p-1.5 dark:border-gray-600 dark:bg-gray-900">
              <Sketch.chart_sketch type={entry.chart || "table"} size={:icon} />
            </span>
            <span class="min-w-0">
              <span class="flex items-center gap-1.5">
                <span class="truncate font-medium text-indigo-600 dark:text-indigo-400"><%= entry.query.name %></span>
                <.pro_slot name={:query_badges} slot_assigns={%{query: entry.query}} />
              </span>
              <span class="block truncate text-xs text-gray-500 dark:text-gray-400"><%= entry.query.description %></span>
            </span>
            <code class="truncate rounded-md border border-gray-100 bg-gray-50 px-2 py-1 font-mono text-xs text-gray-600 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300">
              <.sql tokens={QueryList.tokens(entry.query.statement, :one_line)} />
            </code>
            <span><.source_badge source={entry.source} dialect={entry.dialect} /></span>
            <span class="text-sm text-gray-500 dark:text-gray-400">
              <.updated id={"query-#{entry.query.id}-updated-row"} at={to_datetime(entry.query.updated_at)} />
            </span>
          </.link>
        </div>
      </div>
    <% end %>
    """
  end

  attr(:entry, :map, required: true)

  defp query_tile(assigns) do
    ~H"""
    <.link
      id={"query-tile-#{@entry.query.id}"}
      navigate={lotus_path(["queries", @entry.query.id])}
      class="group relative block overflow-hidden rounded-xl border border-gray-200 bg-white transition hover:border-gray-300 hover:shadow-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-500 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-gray-500"
    >
      <div class="relative h-32 overflow-hidden border-b border-gray-100 bg-gray-50 px-3 pb-2 pt-9 dark:border-gray-700 dark:bg-gray-900/60">
        <span class="absolute left-2.5 top-2.5"><.source_badge source={@entry.source} dialect={@entry.dialect} /></span>
        <%= if @entry.chart do %>
          <Sketch.chart_sketch type={@entry.chart} />
        <% else %>
          <pre class="h-full overflow-hidden font-mono text-[11.5px] leading-relaxed text-gray-700 dark:text-gray-300"><.sql tokens={QueryList.tokens(@entry.query.statement, 5)} /></pre>
          <div class="pointer-events-none absolute inset-x-0 bottom-0 h-8 bg-gradient-to-t from-gray-50 dark:from-gray-900"></div>
        <% end %>
      </div>
      <div class="px-4 pb-4 pt-3">
        <h3 class="truncate text-[15px] font-semibold text-gray-900 dark:text-white"><%= @entry.query.name %></h3>
        <p class="mt-0.5 truncate text-sm text-gray-500 dark:text-gray-400"><%= @entry.query.description || " " %></p>
        <p class="mt-2.5 flex flex-wrap items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
          <span
            :for={variable <- @entry.query.variables || []}
            class="rounded bg-blue-50 px-1.5 py-0.5 font-mono text-[11px] text-blue-700 dark:bg-blue-900/30 dark:text-blue-300"
          ><%= "{{" <> variable.name <> "}}" %></span>
          <span
            :if={@entry.dashboards > 0}
            class="rounded-full bg-pink-50 px-2 py-0.5 text-[11px] font-medium text-pink-700 dark:bg-pink-900/30 dark:text-pink-300"
          >
            <%= ngettext("In 1 dashboard", "In %{count} dashboards", @entry.dashboards) %>
          </span>
          <span><%= gettext("Updated") %> <.updated id={"query-#{@entry.query.id}-updated"} at={to_datetime(@entry.query.updated_at)} /></span>
          <.pro_slot name={:query_badges} slot_assigns={%{query: @entry.query}} />
        </p>
      </div>
    </.link>
    """
  end

  # A query's SQL, its keywords and variables marked. Every token is
  # escaped; only the spans around it are markup.
  attr(:tokens, :list, required: true)

  defp sql(assigns) do
    ~H"<%= sql_html(@tokens) %>"
  end

  @keyword_class "font-semibold text-pink-700 dark:text-pink-400"
  @variable_class "rounded bg-blue-50 px-0.5 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300"

  defp sql_html(tokens) do
    {:safe,
     Enum.map(tokens, fn
       :newline -> "\n"
       {:keyword, text} -> [~s(<span class="#{@keyword_class}">), escape(text), "</span>"]
       {:variable, text} -> [~s(<span class="#{@variable_class}">), escape(text), "</span>"]
       {:text, text} -> escape(text)
     end)}
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  attr(:source, :string, required: true)
  attr(:dialect, :string, required: true)

  defp source_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1.5 rounded-full border border-gray-200 bg-white px-2 py-0.5 text-[11px] text-gray-600 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
      title={@dialect}
    >
      <span class={["h-2 w-2 rounded-full", dialect_color(@dialect)]}></span><%= @source %>
    </span>
    """
  end

  attr(:source, :string, required: true)
  attr(:dialect, :string, default: nil)
  attr(:label, :string, required: true)
  attr(:current, :string, required: true)
  attr(:search, :string, required: true)
  attr(:target, :any, required: true)

  defp source_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="search_queries"
      phx-value-source={@source}
      phx-value-search={@search}
      phx-target={@target}
      aria-pressed={to_string(@current == @source)}
      class={[
        "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm",
        @current == @source && "border-pink-500 bg-pink-50 text-pink-700 dark:bg-pink-900/30 dark:text-pink-300",
        @current != @source &&
          "border-gray-300 text-gray-600 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
      ]}
    >
      <span :if={@dialect} class={["h-2 w-2 rounded-full", dialect_color(@dialect)]}></span><%= @label %>
    </button>
    """
  end

  defp dialect_color("postgres"), do: "bg-[#336791]"
  defp dialect_color("mysql"), do: "bg-[#00758f]"
  defp dialect_color("sqlite"), do: "bg-[#0f80cc]"
  defp dialect_color("clickhouse"), do: "bg-[#f5c518]"
  defp dialect_color("elasticsearch"), do: "bg-[#00bfb3]"
  defp dialect_color(_dialect), do: "bg-gray-400"

  # The view a list shows: a gallery or a table (or list).
  attr(:list, :string, required: true)
  attr(:view, :atom, required: true)
  attr(:target, :any, required: true)

  defp view_toggle(assigns) do
    ~H"""
    <div class="inline-flex rounded-lg ring-1 ring-gray-300 dark:ring-gray-600" role="group" aria-label={gettext("View")}>
      <button
        :for={{view, label} <- [grid: gettext("Gallery"), list: gettext("Table")]}
        id={"#{@list}-view-#{view}"}
        type="button"
        phx-click="set_view"
        phx-value-view={view}
        phx-value-list={@list}
        phx-target={@target}
        data-view-choice={view}
        aria-pressed={to_string(@view == view)}
        title={label}
        aria-label={label}
        class={[
          "p-2 first:rounded-l-lg last:rounded-r-lg",
          @view == view && "bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-white",
          @view != view && "text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
        ]}
      >
        <Icons.squares_2x2 :if={view == :grid} class="h-4 w-4" />
        <Icons.list_bullet :if={view == :list} class="h-4 w-4" />
      </button>
    </div>
    """
  end

  defp shown_queries(entries, search, source) do
    words = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

    entries
    |> Enum.filter(fn %{query: query} = entry ->
      text = String.downcase("#{query.name} #{query.description} #{query.statement}")
      (source == "" or entry.source == source) and Enum.all?(words, &String.contains?(text, &1))
    end)
    |> Enum.sort_by(&to_datetime(&1.query.updated_at), {:desc, DateTime})
  end

  # The dashboards: a gallery of tiles, each with its layout sketched, or a
  # table with the sketch beside each name; the viewer's choice is kept in
  # their browser (the ListView hook).
  attr(:dashboards, :list, required: true)
  attr(:any?, :boolean, required: true)
  attr(:view, :atom, required: true)
  attr(:search, :string, required: true)
  attr(:sort, :string, required: true)
  attr(:can_create, :boolean, required: true)
  attr(:target, :any, required: true)

  defp dashboards_list(assigns) do
    ~H"""
    <%= if not @any? do %>
      <div class="py-12 text-center text-gray-500 dark:text-gray-400">
        <Icons.squares_2x2 class="mx-auto h-12 w-12 text-gray-300 dark:text-gray-600 mb-4" />
        <p><%= gettext("No dashboards yet.") %></p>
        <.link
          :if={@can_create}
          navigate={lotus_path(["dashboards", "new"])}
          class="mt-2 inline-block text-pink-600 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-300"
        >
          <%= gettext("Create your first dashboard") %>
        </.link>
      </div>
    <% else %>
      <div
        id="dashboards-list"
        phx-hook="ListView"
        data-store="dashboards_view"
        data-list="dashboards"
        data-view={@view}
        phx-target={@target}
        class="pb-8"
      >
        <div class="flex flex-wrap items-center gap-3 pt-6 pb-5">
          <form id="dashboards-search" phx-change="search_dashboards" phx-submit="search_dashboards" phx-target={@target} class="flex flex-1 flex-wrap items-center gap-3">
            <div class="relative w-full max-w-xs">
              <Icons.magnifying_glass class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input
                type="search"
                name="search"
                value={@search}
                placeholder={gettext("Search dashboards…")}
                phx-debounce="200"
                aria-label={gettext("Search dashboards")}
                class="w-full rounded-lg border border-gray-300 bg-white py-2 pl-9 pr-3 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              />
            </div>
            <select
              name="sort"
              aria-label={gettext("Sort")}
              class="rounded-lg border border-gray-300 bg-white py-2 pl-3 pr-8 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            >
              <option value="updated" selected={@sort == "updated"}><%= gettext("Recently updated") %></option>
              <option value="name" selected={@sort == "name"}><%= gettext("Name") %></option>
              <option value="created" selected={@sort == "created"}><%= gettext("Recently created") %></option>
            </select>
          </form>
          <.view_toggle list="dashboards" view={@view} target={@target} />
          <.link
            :if={@can_create}
            navigate={lotus_path(["dashboards", "new"])}
            class="inline-flex items-center gap-1.5 rounded-lg bg-pink-600 px-3 py-2 text-sm font-medium text-white hover:bg-pink-500"
          >
            <Icons.plus class="h-4 w-4" /> <%= gettext("New dashboard") %>
          </.link>
        </div>

        <p :if={@dashboards == []} class="py-12 text-center text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("No dashboard has these words.") %>
        </p>

        <div
          :if={@view == :grid and @dashboards != []}
          id="dashboards-gallery"
          class="grid grid-cols-[repeat(auto-fill,minmax(260px,1fr))] gap-5"
        >
          <.dashboard_tile :for={dashboard <- @dashboards} dashboard={dashboard} can_create={@can_create} target={@target} />
          <.link
            :if={@can_create}
            navigate={lotus_path(["dashboards", "new"])}
            class="flex min-h-[15rem] flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-gray-300 text-sm text-gray-500 hover:border-pink-400 hover:bg-pink-50/40 hover:text-pink-600 dark:border-gray-600 dark:text-gray-400 dark:hover:bg-pink-900/10"
          >
            <Icons.plus class="h-7 w-7" /> <%= gettext("New dashboard") %>
          </.link>
        </div>

        <.table :if={@view == :list and @dashboards != []} id="dashboards-table" rows={@dashboards}>
          <:col :let={dashboard} label={gettext("Name")}>
            <.link navigate={lotus_path(["dashboards", dashboard.id])} class="flex items-center gap-4">
              <span class="h-14 w-[5.5rem] shrink-0 rounded-md border border-gray-200 bg-gray-50 p-1 dark:border-gray-600 dark:bg-gray-900">
                <Sketch.sketch dashboard={dashboard} size={:mini} />
              </span>
              <span class="font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400 dark:hover:text-indigo-300">
                <%= dashboard.name %>
              </span>
              <.pro_slot name={:dashboard_badges} slot_assigns={%{dashboard: dashboard}} />
            </.link>
          </:col>
          <:col :let={dashboard} label={gettext("Description")}>
            <%= RichText.plain_text(dashboard.description) || "-" %>
          </:col>
          <:col :let={dashboard} label={gettext("Cards")}>
            <%= card_count(dashboard) %>
          </:col>
          <:col :let={dashboard} label={gettext("Updated")}>
            <.updated id={"dashboard-#{dashboard.id}-updated-row"} at={last_updated(dashboard)} />
          </:col>
        </.table>
      </div>
    <% end %>
    """
  end

  attr(:dashboard, :map, required: true)
  attr(:can_create, :boolean, required: true)
  attr(:target, :any, required: true)

  defp dashboard_tile(assigns) do
    assigns =
      assign(assigns,
        cards: card_count(assigns.dashboard),
        tabs: length(Tabs.list(assigns.dashboard))
      )

    ~H"""
    <div id={"dashboard-tile-#{@dashboard.id}"} class="group relative overflow-hidden rounded-xl border border-gray-200 bg-white transition hover:border-gray-300 hover:shadow-lg dark:border-gray-700 dark:bg-gray-800 dark:hover:border-gray-500">
      <.link navigate={lotus_path(["dashboards", @dashboard.id])} class="block focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-500">
        <div class="h-40 border-b border-gray-100 bg-gray-50 p-3 dark:border-gray-700 dark:bg-gray-900/60">
          <Sketch.sketch dashboard={@dashboard} />
        </div>
        <div class="px-4 pb-4 pt-3">
          <div class="flex items-center gap-2">
            <h3 class="truncate text-[15px] font-semibold text-gray-900 dark:text-white"><%= @dashboard.name %></h3>
            <span
              :if={@dashboard.public_token}
              class="shrink-0 rounded-full bg-pink-50 px-2 py-0.5 text-[11px] font-medium text-pink-700 dark:bg-pink-900/30 dark:text-pink-300"
            >
              <%= gettext("Public") %>
            </span>
            <.pro_slot name={:dashboard_badges} slot_assigns={%{dashboard: @dashboard}} />
          </div>
          <p class="mt-0.5 truncate text-sm text-gray-500 dark:text-gray-400">
            <%= RichText.plain_text(@dashboard.description) || " " %>
          </p>
          <p class="mt-2.5 flex flex-wrap gap-x-1.5 text-xs text-gray-500 dark:text-gray-400">
            <span><%= ngettext("1 card", "%{count} cards", @cards) %></span>
            <span :if={@tabs > 1}>· <%= ngettext("1 tab", "%{count} tabs", @tabs) %></span>
            <span>· <%= gettext("Updated") %> <.updated id={"dashboard-#{@dashboard.id}-updated"} at={last_updated(@dashboard)} /></span>
          </p>
        </div>
      </.link>
      <div :if={@can_create} class="absolute right-2.5 top-2.5 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
        <button
          id={"dashboard-tile-#{@dashboard.id}-duplicate"}
          type="button"
          phx-click="duplicate_dashboard"
          phx-value-id={@dashboard.id}
          phx-target={@target}
          class="inline-flex items-center gap-1 rounded-md bg-white px-2 py-1 text-xs font-medium text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600"
        >
          <Icons.clipboard_copy class="h-3.5 w-3.5" /> <%= gettext("Duplicate") %>
        </button>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:at, :any, required: true)

  defp updated(assigns) do
    ~H"""
    <time id={@id} phx-hook="RelativeTime" datetime={DateTime.to_iso8601(@at)}><%= Calendar.strftime(@at, "%b %d, %Y") %></time>
    """
  end

  # Its cards, without the headings over them.
  defp card_count(dashboard), do: Enum.count(dashboard.cards, &(not TextCard.heading?(&1)))

  # When a dashboard last changed: itself, or one of its cards.
  defp last_updated(dashboard) do
    [dashboard | dashboard.cards]
    |> Enum.map(&to_datetime(&1.updated_at || &1.inserted_at))
    |> Enum.max(DateTime)
  end

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp shown_dashboards(dashboards, search, sort) do
    words = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

    dashboards
    |> Enum.filter(fn dashboard ->
      text = String.downcase("#{dashboard.name} #{RichText.plain_text(dashboard.description)}")
      Enum.all?(words, &String.contains?(text, &1))
    end)
    |> sort_dashboards(sort)
  end

  defp sort_dashboards(dashboards, "name"),
    do: Enum.sort_by(dashboards, &String.downcase(&1.name || ""))

  defp sort_dashboards(dashboards, "created"),
    do: Enum.sort_by(dashboards, &to_datetime(&1.inserted_at), {:desc, DateTime})

  defp sort_dashboards(dashboards, _updated),
    do: Enum.sort_by(dashboards, &last_updated/1, {:desc, DateTime})

  @impl Page
  def handle_mount(socket) do
    socket
    |> assign(queries: [], query_entries: [], dashboards: [])
    |> assign(
      query_view: :grid,
      query_search: "",
      query_source: "",
      active_tab: :queries,
      dashboard_view: :grid,
      dashboard_search: "",
      dashboard_sort: "updated"
    )
  end

  # The page renders with the LiveView's assigns at each of its renders:
  # the list's view, search and sort are the page's own once set (the
  # viewer's), so a render of the LiveView does not put them back.
  @owned [
    :dashboard_view,
    :dashboard_search,
    :dashboard_sort,
    :query_view,
    :query_search,
    :query_source
  ]

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    assigns =
      if Map.has_key?(socket.assigns, :dashboard_view),
        do: Map.drop(assigns, @owned),
        else: assigns

    {:ok, assign(socket, assigns)}
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    socket = socket |> assign(params: params) |> load_lists()

    case params do
      %{"tab" => "dashboards"} -> {:noreply, assign(socket, active_tab: :dashboards)}
      _params -> {:noreply, socket}
    end
  end

  # Every query and dashboard, or those Lotus Pro lists for the request
  # (`Lotus.Web.Pro.list_options/2`, which may read the URL's params).
  defp load_lists(socket) do
    info = Pro.request_info(socket.assigns)
    queries = Pro.list_queries(info)

    assign(socket,
      queries: queries,
      query_entries: QueryList.entries(queries),
      dashboards: Pro.list_dashboards(info, preload: [:cards])
    )
  end

  @impl Phoenix.LiveComponent
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    active_tab =
      case tab do
        "queries" -> :queries
        "dashboards" -> :dashboards
        _ -> :queries
      end

    {:noreply, assign(socket, active_tab: active_tab)}
  end

  def handle_event("set_view", %{"view" => view} = params, socket) do
    key = if params["list"] == "queries", do: :query_view, else: :dashboard_view
    {:noreply, assign(socket, key, if(view == "list", do: :list, else: :grid))}
  end

  def handle_event("search_queries", params, socket) do
    sources = Enum.map(socket.assigns.query_entries, & &1.source)
    source = params["source"] || socket.assigns.query_source

    {:noreply,
     assign(socket,
       query_search: params["search"] || "",
       query_source: if(source in sources, do: source, else: "")
     )}
  end

  def handle_event("search_dashboards", params, socket) do
    {:noreply,
     assign(socket,
       dashboard_search: params["search"] || "",
       dashboard_sort:
         if(params["sort"] in ~w(updated name created), do: params["sort"], else: "updated")
     )}
  end

  def handle_event("duplicate_dashboard", %{"id" => id}, socket) do
    with true <- Authorization.allowed?(socket.assigns, :manage_dashboard),
         {id, ""} <- Integer.parse(id),
         {:ok, copy} <- Duplicate.copy(id, Actor.opts(socket.assigns)) do
      {:noreply, push_navigate(socket, to: lotus_path(["dashboards", copy.id]))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The dashboard could not be copied."))}
    end
  end

  @impl Page
  def handle_info(_msg, socket), do: {:noreply, socket}
end
