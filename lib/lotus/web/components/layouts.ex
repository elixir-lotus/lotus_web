defmodule Lotus.Web.Layouts do
  @moduledoc false

  use Lotus.Web, :html

  alias Lotus.Web.Assets
  alias Lotus.Web.Branding

  embed_templates("layouts/*")

  # The mount prefix comes from the same process-dictionary entry every other
  # dashboard link uses (set in `DashboardLive.mount/3`), so the asset URLs
  # follow whatever path the host mounted Lotus under.
  defp asset_path(asset) when asset in [:css, :js] do
    lotus_path("#{asset}-#{Assets.current_hash(asset)}")
  end

  defp asset_path(:svg), do: lotus_path("icon-#{Assets.current_hash(:svg)}")
  defp asset_path(:ico), do: lotus_path("ico-#{Assets.current_hash(:ico)}")
  defp asset_path(:world), do: lotus_path("world-#{Assets.current_hash(:world)}")
  defp asset_path(:us_states), do: lotus_path("us-states-#{Assets.current_hash(:us_states)}")

  defp product_name(assigns), do: (assigns[:branding] || Branding.default()).product_name

  attr(:branding, Branding, required: true)

  # The branding's logo, or its name; the Lotus mark and wordmark for Lotus.
  # It goes home within the LiveView, as the nav's links do, so the page
  # comes as the viewer left it rather than rendered afresh first.
  def logo(%{branding: %Branding{logo: url}} = assigns) when is_binary(url) do
    ~H"""
    <.link navigate={lotus_path("")} title={@branding.product_name} class="flex items-center gap-3">
      <img src={@branding.logo} alt={@branding.product_name} class="h-10 w-auto" />
    </.link>
    """
  end

  def logo(%{branding: %Branding{product_name: name}} = assigns) when name != "Lotus" do
    ~H"""
    <.link navigate={lotus_path("")} title={@branding.product_name} class="flex items-center gap-3">
      <span class="text-lg font-semibold text-gray-950 dark:text-gray-50">
        {@branding.product_name}
      </span>
    </.link>
    """
  end

  def logo(assigns) do
    ~H"""
    <.link navigate={lotus_path("")} title="Lotus Web" class="flex items-center gap-3">
      <svg
        class="h-10 w-auto text-[rgb(var(--lotus-logo-ink))] dark:text-[rgb(var(--lotus-logo-ink-dark))]"
        viewBox="0 0 112 112"
        aria-hidden="true"
      >
        <defs>
          <mask id="lotus-bloom" maskUnits="userSpaceOnUse" x="0" y="0" width="112" height="112">
            <rect width="112" height="112" fill="white" />
            <path
              d="M56 14Q82 38 80 62Q78 86 56 96Q34 86 32 62Q30 38 56 14Z"
              fill="none"
              stroke="black"
              stroke-width="3.5"
            />
          </mask>
        </defs>
        <g mask="url(#lotus-bloom)">
          <path fill="currentColor" d="M56 96Q16 98 12 38Q46 46 56 96Z" />
          <path class="fill-[rgb(var(--lotus-logo-petal))]" d="M56 96Q96 98 100 38Q66 46 56 96Z" />
          <path fill="currentColor" d="M56 14Q82 38 80 62Q78 86 56 96Q34 86 32 62Q30 38 56 14Z" />
        </g>
      </svg>
      <span class="lotus-wordmark text-gray-950 dark:text-gray-50">LO<span>TUS</span></span>
    </.link>
    """
  end

  attr(:name, :string, required: true)

  # The icons of the command palette's actions, by the names that
  # Lotus.Web.Commands gives them.
  defp palette_icon(assigns) do
    ~H"""
    <Icons.terminal :if={@name == "terminal"} class="h-4 w-4" />
    <Icons.blocks :if={@name == "blocks"} class="h-4 w-4" />
    <Icons.plus :if={@name == "plus"} class="h-4 w-4" />
    <Icons.play :if={@name == "play"} class="h-4 w-4" />
    <Icons.database :if={@name == "database"} class="h-4 w-4" />
    <Icons.variable :if={@name == "variable"} class="h-4 w-4" />
    <Icons.chart_bar :if={@name == "chart_bar"} class="h-4 w-4" />
    <Icons.clipboard_copy :if={@name == "clipboard_copy"} class="h-4 w-4" />
    <Icons.sparkles :if={@name == "sparkles"} class="h-4 w-4" />
    <Icons.sun :if={@name == "sun"} class="h-4 w-4" />
    <Icons.moon :if={@name == "moon"} class="h-4 w-4" />
    <Icons.monitor :if={@name == "monitor"} class="h-4 w-4" />
    <Icons.layers :if={@name == "layers"} class="h-4 w-4" />
    """
  end

  attr(:rest, :global)

  def footer(assigns) do
    assigns =
      assign(assigns,
        oss_version: Application.spec(:lotus, :vsn),
        web_version: Application.spec(:lotus_web, :vsn)
      )

    ~H"""
    <footer class={["flex flex-col px-3 pb-3 text-sm justify-center items-center md:flex-row", @rest[:class] || ""]}>
      <.version name="Lotus" version={@oss_version} />
      <.version name="Lotus.Web" version={@web_version} />
      <a
        href="https://hattori.ai"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-2 font-medium text-gray-700 hover:text-gray-950 dark:text-gray-300 dark:hover:text-white transition-colors"
      >
        <span class="h-px w-3 bg-[rgb(var(--lotus-logo-petal))]" aria-hidden="true"></span>
        {gettext("Made by Hattori AI")}
      </a>
    </footer>
    """
  end

  attr(:name, :string)
  attr(:version, :string)

  defp version(assigns) do
    ~H"""
    <span class="text-gray-600 dark:text-gray-400 tabular mr-0 mb-1 md:mr-3 md:mb-0">
      {@name} {if @version, do: "v#{@version}", else: "–"}
    </span>
    """
  end

  def shortcuts_modal(assigns) do
    ~H"""
    <.modal id="shortcuts-modal">
      <div class="max-w-2xl">
        <h3 class="text-lg font-semibold mb-6"><%= gettext("Keyboard Shortcuts") %></h3>

        <div class="space-y-6">
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3 uppercase tracking-wider"><%= gettext("General") %></h4>
            <div class="space-y-2">
              <.shortcut_item
                description={gettext("Show keyboard shortcuts")}
                keys={["⌘", "/"]}
                alt_keys={["Ctrl", "/"]}
              />
              <.shortcut_item
                description={gettext("Search queries and dashboards, or run a command")}
                keys={["⌘", "K"]}
                alt_keys={["Ctrl", "K"]}
              />
            </div>
          </div>

          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3 uppercase tracking-wider"><%= gettext("Query Editor") %></h4>
            <div class="space-y-2">
              <.shortcut_item
                description={gettext("Run query")}
                keys={["⌘", "Enter"]}
                alt_keys={["Ctrl", "Enter"]}
              />
              <.shortcut_item
                description={gettext("Copy query to clipboard")}
                keys={["⌘", "Shift", "C"]}
                alt_keys={["Ctrl", "Shift", "C"]}
              />
              <.shortcut_item
                description={gettext("Pretty-print the query (JSON sources)")}
                keys={["⌘", "Shift", "F"]}
                alt_keys={["Ctrl", "Shift", "F"]}
              />
              <.shortcut_item
                description={gettext("Toggle Schema Explorer")}
                keys={["⌘", "E"]}
                alt_keys={["Ctrl", "E"]}
              />
              <.shortcut_item
                description={gettext("Toggle Variable Settings")}
                keys={["⌘", "X"]}
                alt_keys={["Ctrl", "X"]}
              />
              <.shortcut_item
                description={gettext("Toggle Visualization Settings")}
                keys={["⌘", "Shift", "V"]}
                alt_keys={["Ctrl", "Shift", "V"]}
              />
              <%= if Lotus.Web.AI.assistant?() do %>
                <.shortcut_item
                  description={gettext("Toggle AI Assistant")}
                  keys={["⌘", "J"]}
                  alt_keys={["Ctrl", "J"]}
                />
              <% end %>
              <.shortcut_item
                description={gettext("Expand editor")}
                keys={["⌘", "↓"]}
                alt_keys={["Ctrl", "↓"]}
              />
              <.shortcut_item
                description={gettext("Minimize editor")}
                keys={["⌘", "↑"]}
                alt_keys={["Ctrl", "↑"]}
              />
            </div>
          </div>

          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3 uppercase tracking-wider"><%= gettext("Query Results") %></h4>
            <div class="space-y-2">
              <.shortcut_item
                description={gettext("Switch to table view")}
                keys={["⌘", "1"]}
                alt_keys={["Ctrl", "1"]}
              />
              <.shortcut_item
                description={gettext("Switch to chart view")}
                keys={["⌘", "2"]}
                alt_keys={["Ctrl", "2"]}
              />
            </div>
          </div>
        </div>

        <div class="mt-6 text-xs text-gray-500 dark:text-gray-400">
          <span class="font-medium"><%= gettext("Note:") %></span> <%= gettext("⌘ is the Command key on Mac") %>
        </div>

        <div class="mt-6 flex justify-end">
          <.button
            type="button"
            variant="light"
            phx-click={hide_modal("shortcuts-modal")}
          >
            <%= gettext("Close") %>
          </.button>
        </div>
      </div>
    </.modal>
    """
  end

  attr(:description, :string, required: true)
  attr(:keys, :list, required: true)
  attr(:alt_keys, :list, default: [])

  defp shortcut_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2 px-3 rounded-md hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors">
      <span class="text-sm text-gray-700 dark:text-gray-300"><%= @description %></span>
      <div class="flex items-center gap-4">
        <div class="flex items-center gap-1">
          <%= for key <- @keys do %>
            <kbd class="px-2 py-1 bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded text-xs font-sans text-gray-700 dark:text-gray-300 min-w-[28px] text-center">
              <%= key %>
            </kbd>
            <%= if key != List.last(@keys) do %>
              <span class="text-xs text-gray-500 dark:text-gray-400">+</span>
            <% end %>
          <% end %>
        </div>
        <%= if @alt_keys != [] do %>
          <span class="text-xs text-gray-400 dark:text-gray-500">or</span>
          <div class="flex items-center gap-1">
            <%= for key <- @alt_keys do %>
              <kbd class="px-2 py-1 bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded text-xs font-sans text-gray-700 dark:text-gray-300 min-w-[28px] text-center">
                <%= key %>
              </kbd>
              <%= if key != List.last(@alt_keys) do %>
                <span class="text-xs text-gray-500 dark:text-gray-400">+</span>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
