defmodule Lotus.Web.Queries.ResultsComponent do
  @moduledoc false

  use Lotus.Web, :html

  alias Lotus.Result.Statistics
  alias Lotus.Web.Charts
  alias Lotus.Web.Queries.MasuResults

  attr(:query_id, :string, default: "default")
  attr(:result, :any, default: nil)
  attr(:error, :string, default: nil)
  attr(:running, :boolean, default: false)
  attr(:os, :atom, default: :unknown)
  attr(:target, Phoenix.LiveComponent.CID, default: nil)
  attr(:is_saved_query, :boolean, default: true)
  # Visualization attrs
  attr(:visualization_config, :map, default: nil)
  attr(:visualization_view_mode, :atom, default: :table)
  attr(:visualization_visible, :boolean, default: false)
  attr(:can_export, :boolean, default: true)
  # Each run of the editor's query: a new results grid, with no sort or
  # filter of the one before.
  attr(:results_run, :integer, default: 0)
  # The `Lotus.Query.Filter` operators the query's source runs.
  attr(:filter_operators, :list, default: [])

  def render_result(assigns) do
    ~H"""
    <div id={"query-results-#{assigns[:query_id] || "default"}"} class="px-4 sm:px-6 lg:px-8 h-full flex flex-col">
      <%= cond do %>
        <%!-- While a query runs, the grid keeps its rows and shows it loads --%>
        <% @running == true and @result == nil -> %>
          <.loading_spinner />

        <% @result != nil -> %>
          <%!-- Compact header row --%>
          <div class="pt-3 pb-2 px-0 flex items-center gap-3 flex-shrink-0">
            <h2 class="text-base font-semibold text-text-light dark:text-text-dark"><%= gettext("Results") %></h2>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400 rounded">
              <Icons.check class="w-3 h-3" />
              <%= gettext("Success") %>
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              <%= info_text(@result) %>
            </span>
          </div>

          <%!-- Content area: Table or Chart --%>
          <div class="flex-1 overflow-hidden">
            <.render_chart
              :if={@visualization_view_mode == :chart && has_valid_config?(@visualization_config)}
              result={@result}
              config={@visualization_config}
            />
            <%!-- Hidden, not gone, under a chart: the grid keeps the sort and
            filters Lotus runs, and shows them again with the table --%>
            <div class={[
              "h-full",
              @visualization_view_mode == :chart && has_valid_config?(@visualization_config) &&
                "hidden"
            ]}>
              <MasuResults.grid
                id={"results-grid-#{@query_id}-#{@results_run}"}
                result={@result}
                running={@running}
                target={@target}
                operators={@filter_operators}
                stats={Statistics.compute_all(@result)}
              />
            </div>
          </div>

          <%!-- Bottom bar with controls --%>
          <.bottom_bar
            result={@result}
            target={@target}
            visualization_config={@visualization_config}
            visualization_view_mode={@visualization_view_mode}
            visualization_visible={@visualization_visible}
            can_export={@can_export}
          />

        <% is_binary(@error) and @error != "" -> %>
          <%!-- Compact error header row --%>
          <div class="pt-3 pb-2 px-0 flex items-center gap-3 flex-shrink-0">
            <h2 class="text-base font-semibold text-text-light dark:text-text-dark"><%= gettext("Results") %></h2>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-red-50 text-red-700 dark:bg-red-900/20 dark:text-red-400 rounded">
              <Icons.x_mark class="w-3 h-3" />
              <%= gettext("Error") %>
            </span>
          </div>
          <.render_error error={@error} />

        <% true -> %>
          <.empty_state os={@os} />
      <% end %>
    </div>
    """
  end

  defp render_chart(assigns) do
    ~H"""
    <div class="w-full h-full overflow-auto py-2">
      <Charts.draw id="query-chart" result={@result} config={@config} height={360} export />
    </div>
    """
  end

  attr(:result, :any, required: true)
  attr(:target, Phoenix.LiveComponent.CID, required: true)
  attr(:visualization_config, :map, default: nil)
  attr(:visualization_view_mode, :atom, default: :table)
  attr(:visualization_visible, :boolean, default: false)
  attr(:can_export, :boolean, default: true)

  defp bottom_bar(assigns) do
    ~H"""
    <div class="mt-auto pb-4 flex items-center border-t border-gray-200 dark:border-gray-700 pt-4 relative z-10 bg-white dark:bg-gray-800">
      <%!-- Left: Pagination and Export --%>
      <div class="flex items-center gap-2 flex-1">
        <%= if @visualization_view_mode == :table do %>
          <button
            phx-click="prev_page"
            phx-target={@target}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md transition-colors disabled:opacity-50"
            disabled={not can_prev(@result)}
          >
            <Icons.chevron_left class="h-5 w-5" />
            <%= gettext("Prev") %>
          </button>
          <button
            phx-click="next_page"
            phx-target={@target}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md transition-colors disabled:opacity-50"
            disabled={not can_next(@result)}
          >
            <%= gettext("Next") %>
            <Icons.chevron_right class="h-5 w-5" />
          </button>
          <button
            :if={@can_export}
            id="export-csv-btn"
            phx-click="export_csv"
            phx-target={@target}
            title={gettext("Export query results to CSV")}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md transition-colors disabled:opacity-50"
          >
            <Icons.download class="h-5 w-5" />
            <%= gettext("Export (.csv)") %>
          </button>
        <% end %>
      </div>

      <%!-- Center: View toggle (only when config exists) --%>
      <%= if has_valid_config?(@visualization_config) do %>
        <div class="hidden sm:flex items-center justify-center">
          <div class="flex rounded-md border border-gray-200 dark:border-gray-600 overflow-hidden">
            <button
              id="view-mode-table-btn"
              phx-click="set_view_mode"
              phx-value-mode="table"
              phx-target={@target}
              data-title={gettext("Table view")}
              phx-hook="Tippy"
              class={[
                "p-2 transition-colors",
                if(@visualization_view_mode == :table,
                  do: "bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100",
                  else: "text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800"
                )
              ]}
            >
              <Icons.table_view class="h-5 w-5" />
            </button>
            <button
              id="view-mode-chart-btn"
              phx-click="set_view_mode"
              phx-value-mode="chart"
              phx-target={@target}
              data-title={gettext("Chart view")}
              phx-hook="Tippy"
              class={[
                "p-2 transition-colors border-l border-gray-200 dark:border-gray-600",
                if(@visualization_view_mode == :chart,
                  do: "bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100",
                  else: "text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800"
                )
              ]}
            >
              <Icons.chart_combined class="h-5 w-5" />
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Right: Visualization controls --%>
      <div class="flex items-center gap-2 flex-1 justify-end">
        <%!-- Visualization button with cog icon --%>
        <.button
          type="button"
          variant="light"
          phx-click="smart_toggle_visualization_drawer"
          phx-target={@target}
          class={
            "!py-1.5 !px-3 inline-flex items-center gap-1.5 " <>
            if(@visualization_visible,
              do: "!bg-pink-100 !text-pink-700 !ring-pink-300 dark:!bg-pink-900/30 dark:!text-pink-400 dark:!ring-pink-700",
              else: ""
            )
          }
        >
          <%= gettext("Visualization") %>
          <Icons.cog_6_tooth class="h-4 w-4" />
        </.button>

        <%= if has_valid_config?(@visualization_config) do %>
          <%!-- Mobile view toggle --%>
          <div class="flex sm:hidden rounded-md border border-gray-200 dark:border-gray-600 overflow-hidden">
            <button
              id="view-mode-table-btn-mobile"
              phx-click="set_view_mode"
              phx-value-mode="table"
              phx-target={@target}
              data-title={gettext("Table view")}
              phx-hook="Tippy"
              class={[
                "p-2 transition-colors",
                if(@visualization_view_mode == :table,
                  do: "bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100",
                  else: "text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800"
                )
              ]}
            >
              <Icons.table_view class="h-5 w-5" />
            </button>
            <button
              id="view-mode-chart-btn-mobile"
              phx-click="set_view_mode"
              phx-value-mode="chart"
              phx-target={@target}
              data-title={gettext("Chart view")}
              phx-hook="Tippy"
              class={[
                "p-2 transition-colors border-l border-gray-200 dark:border-gray-600",
                if(@visualization_view_mode == :chart,
                  do: "bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100",
                  else: "text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800"
                )
              ]}
            >
              <Icons.chart_combined class="h-5 w-5" />
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp has_valid_config?(config), do: Charts.valid_config?(config)

  defp info_text(%{num_rows: n, duration_ms: ms, meta: meta}) do
    {range_text, total_text} =
      case meta do
        %{} ->
          win = Map.get(meta, :window)
          total = Map.get(meta, :total_count)

          if is_map(win) do
            format_window_text(n, win, total)
          else
            default_range_text(n)
          end

        _ ->
          default_range_text(n)
      end

    stats_text = String.trim(range_text <> total_text)

    gettext("%{stats} • %{duration}ms",
      stats: stats_text,
      duration: to_string(ms)
    )
  end

  defp format_window_text(n, win, total) do
    offset = Map.get(win, :offset, 0)
    from = if n > 0, do: offset + 1, else: 0
    to_ = offset + n

    range =
      if n > 0 do
        gettext("Showing %{from}–%{to}", from: from, to: to_)
      else
        gettext("Showing 0")
      end

    total_part =
      if is_integer(total) do
        ngettext(" of %{count} row", " of %{count} rows", total, count: total)
      else
        gettext(" rows")
      end

    {range, total_part}
  end

  defp default_range_text(n) when is_integer(n) do
    {ngettext("%{count} row", "%{count} rows", n, count: n), ""}
  end

  defp can_prev(%{meta: %{} = meta}) do
    case Map.get(meta, :window) do
      %{} = win -> Map.get(win, :offset, 0) > 0
      _ -> false
    end
  end

  defp can_prev(_), do: false

  defp can_next(%{num_rows: n, meta: %{} = meta}) when is_integer(n) do
    win = Map.get(meta, :window, %{})
    page = Map.get(win, :limit)
    offset = Map.get(win, :offset, 0)
    total = Map.get(meta, :total_count)

    cond do
      is_integer(total) -> offset + n < total
      is_integer(page) -> n == page
      true -> false
    end
  end

  defp can_next(_), do: false

  attr(:error, :string, required: true)

  defp render_error(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-16 text-gray-500">
      <div class="text-red-600 text-center">
        <p class="text-sm mt-1"><%= @error %></p>
      </div>
    </div>
    """
  end

  attr(:os, :atom, default: :unknown)

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-16 text-gray-500">
      <div class="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mb-6">
        <Icons.terminal class="h-8 w-8 text-gray-400" />
      </div>

      <p class="text-base text-gray-600 mb-2 flex items-center justify-center gap-2">
        <span><%= gettext("To run your query, click on the Run button or press") %></span>
        <span class="inline-flex items-center gap-1">
          <%= if @os == :mac do %>
            <kbd class="px-2 py-1 bg-gray-100 border border-gray-300 rounded text-sm font-sans text-gray-700">⌘</kbd>
            <span class="text-sm text-gray-500">+</span>
            <kbd class="px-2 py-1 bg-gray-100 border border-gray-300 rounded text-sm font-sans text-gray-700">Enter</kbd>
          <% else %>
            <kbd class="px-2 py-1 bg-gray-100 border border-gray-300 rounded text-sm font-sans text-gray-700">Ctrl</kbd>
            <span class="text-sm text-gray-500">+</span>
            <kbd class="px-2 py-1 bg-gray-100 border border-gray-300 rounded text-sm font-sans text-gray-700">Enter</kbd>
          <% end %>
        </span>
      </p>
      <p class="text-sm text-gray-500">
        <%= gettext("Here's where your results will appear") %>
      </p>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <div class="pt-3 pb-2 px-0 flex items-center gap-3 flex-shrink-0">
      <h2 class="text-base font-semibold text-text-light dark:text-text-dark"><%= gettext("Results") %></h2>
      <span class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium text-gray-500 dark:text-gray-400">
        <.spinner class="w-3 h-3" />
        <%= gettext("Running...") %>
      </span>
    </div>
    """
  end
end
