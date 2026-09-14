defmodule Lotus.Web.Dashboards.SettingsDrawer do
  @moduledoc """
  Dashboard settings drawer component for configuring auto-refresh, public sharing, and deletion.
  Slides in from the right side.
  """

  use Lotus.Web, :live_component

  @impl Phoenix.LiveComponent
  def mount(socket) do
    # The parent passes what the user may do. Until it does, show nothing that
    # writes.
    {:ok, assign(socket, visible: false, dashboard: nil, can_share: false, can_manage: false)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "fixed sm:absolute top-0 right-0 h-full w-full sm:w-80 bg-white dark:bg-gray-800 border-l border-gray-200 dark:border-gray-700 z-20 transition-transform duration-300 ease-in-out",
        if(@visible, do: "translate-x-0", else: "translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= if @visible do %>
        <div class="h-full flex flex-col">
          <%!-- Header --%>
          <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
            <h3 class="font-medium text-gray-900 dark:text-white">
              <%= gettext("Dashboard Settings") %>
            </h3>
            <button
              phx-click="close_settings"
              phx-target={@parent}
              class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
            >
              <Icons.x_mark class="h-5 w-5" />
            </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-4 space-y-6">
            <%!-- Auto-refresh --%>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                <%= gettext("Auto-refresh") %>
              </label>
              <select
                name="auto_refresh_seconds"
                phx-change="update_auto_refresh"
                phx-target={@parent}
                class="w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2.5 bg-white dark:bg-gray-700 dark:text-white focus:ring-pink-500 focus:border-pink-500"
              >
                <option value="" selected={!@dashboard.auto_refresh_seconds}>
                  <%= gettext("Disabled") %>
                </option>
                <option value="60" selected={@dashboard.auto_refresh_seconds == 60}>
                  1 <%= gettext("minute") %>
                </option>
                <option value="300" selected={@dashboard.auto_refresh_seconds == 300}>
                  5 <%= gettext("minutes") %>
                </option>
                <option value="600" selected={@dashboard.auto_refresh_seconds == 600}>
                  10 <%= gettext("minutes") %>
                </option>
                <option value="1800" selected={@dashboard.auto_refresh_seconds == 1800}>
                  30 <%= gettext("minutes") %>
                </option>
                <option value="3600" selected={@dashboard.auto_refresh_seconds == 3600}>
                  1 <%= gettext("hour") %>
                </option>
              </select>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                <%= gettext("Automatically refresh all cards at this interval.") %>
              </p>
            </div>

            <%!-- Public Sharing --%>
            <div :if={@can_share or @dashboard.public_token}>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                <%= gettext("Public Sharing") %>
              </label>
              <%= if @dashboard.public_token do %>
                <div class="space-y-3">
                  <div class="flex items-center gap-2 p-2 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
                    <Icons.globe class="h-4 w-4 text-green-600 dark:text-green-400" />
                    <span class="text-sm text-green-700 dark:text-green-400">
                      <%= gettext("Public link enabled") %>
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <input
                      id="public-url"
                      type="text"
                      readonly
                      value={public_url(@dashboard.public_token, @uri)}
                      class="flex-1 text-xs p-2 bg-gray-100 dark:bg-gray-600 rounded border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300"
                    />
                    <button
                      type="button"
                      phx-hook="Clipboard"
                      data-copy-from="#public-url"
                      id="copy-url-btn"
                      class="p-2 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 border border-gray-300 dark:border-gray-600 rounded"
                      title={gettext("Copy URL")}
                    >
                      <Icons.clipboard_copy class="h-4 w-4" />
                    </button>
                  </div>
                  <button
                    :if={@can_share}
                    type="button"
                    phx-click="disable_sharing"
                    phx-target={@parent}
                    class="w-full text-sm text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300 py-2 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  >
                    <%= gettext("Disable Sharing") %>
                  </button>
                </div>
              <% else %>
                <div class="space-y-3">
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    <%= gettext("Create a public link to share this dashboard with anyone. They won't need to log in.") %>
                  </p>
                  <%= if persisted?(@dashboard) do %>
                    <button
                      type="button"
                      phx-click="enable_sharing"
                      phx-target={@parent}
                      class="w-full flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium text-pink-600 dark:text-pink-400 bg-pink-50 dark:bg-pink-900/20 border border-pink-200 dark:border-pink-800 rounded-lg hover:bg-pink-100 dark:hover:bg-pink-900/30 transition-colors"
                    >
                      <Icons.globe class="h-4 w-4" />
                      <%= gettext("Enable Public Link") %>
                    </button>
                  <% else %>
                    <div class="text-sm text-gray-500 dark:text-gray-400 p-3 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg">
                      <%= gettext("Save the dashboard first to enable public sharing.") %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Danger Zone --%>
            <div :if={@can_manage} class="pt-4 border-t border-gray-200 dark:border-gray-700">
              <h4 class="text-sm font-medium text-red-600 dark:text-red-400 mb-3">
                <%= gettext("Danger Zone") %>
              </h4>
              <button
                type="button"
                phx-click="show_delete_modal"
                phx-target={@parent}
                class="w-full flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
              >
                <Icons.trash class="h-4 w-4" />
                <%= gettext("Delete Dashboard") %>
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp public_url(token, uri) do
    if uri do
      uri = URI.parse(uri)

      "#{uri.scheme}://#{uri.host}#{if uri.port && uri.port not in [80, 443], do: ":#{uri.port}", else: ""}#{lotus_path(["public", token])}"
    else
      lotus_path(["public", token])
    end
  end

  defp persisted?(dashboard) do
    dashboard.id && is_integer(dashboard.id)
  end

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    {:ok, assign(socket, params)}
  end
end
