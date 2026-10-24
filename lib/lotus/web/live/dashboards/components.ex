defmodule Lotus.Web.Dashboards.Components do
  @moduledoc """
  The parts of a dashboard's page that the editor and the public view share:
  its head (name, description, when its data was read) and, in the editor,
  the bar of edit mode.
  """

  use Lotus.Web, :html

  alias Lotus.Web.Markdown

  @doc """
  The head of a dashboard: its name, its description, when its cards were
  last read and how often they are read again, and its actions.
  """
  attr(:dashboard, :map, required: true)
  attr(:title, :string, default: nil, doc: "the name to show, over the dashboard's")
  attr(:back, :string, default: nil, doc: "where the back arrow goes; none without it")
  attr(:refreshed_at, :any, default: nil, doc: "when the cards were last read")
  attr(:running, :boolean, default: false)
  slot(:actions)

  def dashboard_head(assigns) do
    ~H"""
    <div class="lotus-dashboard-head flex flex-wrap items-start gap-x-4 gap-y-3 px-4 sm:px-6 pt-5">
      <div class="min-w-0 basis-full sm:basis-0 flex-1">
        <div class="flex items-center gap-2">
          <.link
            :if={@back}
            navigate={@back}
            class="lotus-dashboard-back -ml-1 p-1 rounded-md text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:text-gray-300 dark:hover:bg-gray-700"
            aria-label={gettext("All dashboards")}
          >
            <Icons.chevron_left class="h-5 w-5" />
          </.link>
          <h1 class="lotus-title truncate text-xl font-semibold tracking-tight text-text-light dark:text-text-dark">
            <%= @title || @dashboard.name || gettext("Untitled") %>
          </h1>
        </div>
        <div
          :if={present?(@dashboard.description)}
          class="mt-1 prose prose-sm dark:prose-invert max-w-3xl text-gray-600 dark:text-gray-400"
        >
          <%= Markdown.to_safe_html(@dashboard.description) %>
        </div>
        <p
          :if={@running or @refreshed_at}
          class="mt-1.5 flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400"
        >
          <%= if @running do %>
            <.spinner size="12" />
            <span><%= gettext("Reading the data…") %></span>
          <% else %>
            <span class="h-1.5 w-1.5 rounded-full bg-green-500" aria-hidden="true"></span>
            <span>
              <%= gettext("Updated") %>
              <time
                id="dashboard-refreshed-at"
                phx-hook="RelativeTime"
                datetime={DateTime.to_iso8601(@refreshed_at)}
              ><%= gettext("just now") %></time><%= refresh_every(@dashboard.auto_refresh_seconds) %>
            </span>
          <% end %>
        </p>
      </div>
      <div :if={@actions != []} class="lotus-dashboard-actions flex shrink-0 items-center gap-2">
        <%= render_slot(@actions) %>
      </div>
    </div>
    """
  end

  @doc """
  A button of the head of a dashboard: an icon and a word.
  """
  attr(:rest, :global, include: ~w(id title))
  slot(:inner_block, required: true)

  def head_button(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-white px-3 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50 hover:text-gray-900 dark:bg-gray-800 dark:text-gray-200 dark:ring-gray-700 dark:hover:bg-gray-700"
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Full screen: the dashboard over the whole screen, for a wall or a TV,
  with no buttons (Escape leaves it).
  """
  def fullscreen_button(assigns) do
    ~H"""
    <.head_button
      id="dashboard-fullscreen"
      phx-click={JS.dispatch("lotus:fullscreen")}
      title={gettext("Full screen, for a wall or a TV (Escape leaves it)")}
    >
      <Icons.maximize class="h-4 w-4" /> <%= gettext("Full screen") %>
    </.head_button>
    """
  end

  @doc """
  A dashboard's tabs, over its cards: a tab shows its cards. In edit mode,
  the tab shown takes a new name in place, and is removed by its ×; Tab
  adds one. Out of edit mode it shows only for two tabs or more.
  """
  attr(:tabs, :list, required: true)
  attr(:current, :string, default: nil)
  attr(:editing, :boolean, default: false)
  attr(:target, :any, required: true)

  def tab_bar(assigns) do
    ~H"""
    <div
      :if={@editing or length(@tabs) > 1}
      id="dashboard-tabs"
      class="lotus-dashboard-tabs flex items-end gap-1 overflow-x-auto border-b border-gray-200 px-4 sm:px-6 pt-3 dark:border-gray-700"
      role="tablist"
      aria-label={gettext("Tabs")}
    >
      <div :for={tab <- @tabs} class="flex shrink-0 items-center">
        <%= if @editing and tab["id"] == @current do %>
          <form
            id={"dashboard-tab-#{tab["id"]}-name"}
            phx-change="rename_tab"
            phx-submit="rename_tab"
            phx-target={@target}
            class="flex items-center border-b-2 border-pink-600 pb-1.5"
          >
            <input type="hidden" name="tab" value={tab["id"]} />
            <input
              type="text"
              name="name"
              value={tab["name"]}
              phx-debounce="300"
              aria-label={gettext("Name of the tab")}
              class="w-32 rounded border-0 bg-transparent px-1 py-0.5 text-sm font-medium text-gray-900 focus:ring-1 focus:ring-pink-500 dark:text-white"
            />
            <button
              type="button"
              phx-click="delete_tab"
              phx-value-tab={tab["id"]}
              phx-target={@target}
              data-confirm={gettext("Remove this tab? Its cards go to the first tab.")}
              class="ml-0.5 rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-red-600 dark:hover:bg-gray-700"
              title={gettext("Remove the tab")}
              aria-label={gettext("Remove the tab")}
            >
              <Icons.x_mark class="h-3.5 w-3.5" />
            </button>
          </form>
        <% else %>
          <button
            id={"dashboard-tab-#{tab["id"]}"}
            type="button"
            role="tab"
            aria-selected={to_string(tab["id"] == @current)}
            phx-click="select_tab"
            phx-value-tab={tab["id"]}
            phx-target={@target}
            class={[
              "border-b-2 px-3 pb-2 pt-1 text-sm font-medium whitespace-nowrap",
              tab["id"] == @current && "border-pink-600 text-gray-900 dark:text-white",
              tab["id"] != @current &&
                "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            ]}
          >
            <%= tab["name"] %>
          </button>
        <% end %>
      </div>
      <button
        :if={@editing}
        id="dashboard-add-tab"
        type="button"
        phx-click="add_tab"
        phx-target={@target}
        class="mb-1 ml-1 inline-flex shrink-0 items-center gap-1 rounded-md px-2 py-1 text-sm text-pink-600 hover:bg-pink-50 dark:text-pink-400 dark:hover:bg-pink-900/20"
      >
        <Icons.plus class="h-4 w-4" /> <%= gettext("Tab") %>
      </button>
    </div>
    """
  end

  @doc """
  The bar of edit mode: what can be added, the dashboard's settings, and
  Cancel and Save.
  """
  attr(:name, :string, default: nil)
  attr(:target, :any, required: true)

  def edit_bar(assigns) do
    ~H"""
    <div
      id="dashboard-edit-bar"
      class="lotus-edit-bar sticky top-0 z-20 flex flex-wrap items-center gap-2 bg-gray-900 px-4 sm:px-6 py-2.5 text-sm text-white dark:bg-black"
    >
      <span class="mr-2 font-medium truncate">
        <%= if @name, do: gettext("Editing %{name}", name: @name), else: gettext("New dashboard") %>
      </span>
      <.bar_button phx-click="show_add_card_modal" phx-value-type="query" phx-target={@target} icon="chart">
        <%= gettext("Chart") %>
      </.bar_button>
      <.bar_button phx-click="show_add_card_modal" phx-value-type="text" phx-target={@target} icon="text">
        <%= gettext("Text") %>
      </.bar_button>
      <.bar_button phx-click="add_filter" phx-target={@target} icon="filter">
        <%= gettext("Filter") %>
      </.bar_button>
      <.bar_button
        id="dashboard-tidy"
        phx-click={JS.dispatch("lotus:tidy", to: "#dashboard-grid")}
        icon="tidy"
        title={gettext("Put the cards in full rows, with no gaps")}
      >
        <%= gettext("Tidy up") %>
      </.bar_button>
      <div class="flex-1"></div>
      <.bar_button phx-click="show_save_modal" phx-target={@target} icon="details">
        <%= gettext("Details") %>
      </.bar_button>
      <.bar_button phx-click="toggle_settings" phx-target={@target} icon="settings">
        <%= gettext("Settings") %>
      </.bar_button>
      <.bar_button id="dashboard-cancel-edit" phx-click="cancel_edit" phx-target={@target}>
        <%= gettext("Cancel") %>
      </.bar_button>
      <button
        id="dashboard-save"
        type="button"
        phx-click="save"
        phx-target={@target}
        class="inline-flex h-8 items-center rounded-md bg-pink-600 px-3 font-medium text-white hover:bg-pink-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-pink-400"
      >
        <%= gettext("Save") %>
      </button>
    </div>
    """
  end

  attr(:icon, :string, default: nil)
  attr(:rest, :global, include: ~w(id title))
  slot(:inner_block, required: true)

  defp bar_button(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex h-8 items-center gap-1.5 rounded-md border border-white/15 bg-white/5 px-3 font-medium text-white hover:bg-white/15 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-pink-400"
      {@rest}
    >
      <.bar_icon :if={@icon} name={@icon} />
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  attr(:name, :string, required: true)

  defp bar_icon(%{name: "chart"} = assigns), do: ~H|<Icons.chart_bar class="h-4 w-4" />|
  defp bar_icon(%{name: "text"} = assigns), do: ~H|<Icons.document_text class="h-4 w-4" />|
  defp bar_icon(%{name: "filter"} = assigns), do: ~H|<Icons.funnel class="h-4 w-4" />|
  defp bar_icon(%{name: "tidy"} = assigns), do: ~H|<Icons.blocks class="h-4 w-4" />|
  defp bar_icon(%{name: "details"} = assigns), do: ~H|<Icons.pencil class="h-4 w-4" />|
  defp bar_icon(%{name: "settings"} = assigns), do: ~H|<Icons.cog_6_tooth class="h-4 w-4" />|

  defp present?(nil), do: false
  defp present?(text) when is_binary(text), do: String.trim(text) != ""
  defp present?(_), do: true

  defp refresh_every(nil), do: nil

  defp refresh_every(seconds) when seconds < 3600,
    do: " · " <> gettext("refreshes every %{count} min", count: div(seconds, 60))

  defp refresh_every(seconds),
    do:
      " · " <>
        ngettext("refreshes every hour", "refreshes every %{count} hours", div(seconds, 3600))
end
