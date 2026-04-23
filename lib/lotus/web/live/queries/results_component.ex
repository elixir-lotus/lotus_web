defmodule Lotus.Web.Queries.ResultsComponent do
  @moduledoc false

  use Lotus.Web, :html

  alias Lotus.Query.Filter
  alias Lotus.Query.Sort
  alias Lotus.Result.Statistics
  alias Lotus.Web.CellFormatter
  alias Lotus.Web.VegaSpecBuilder

  attr(:query_id, :string, default: "default")
  attr(:result, :any, default: nil)
  attr(:error, :string, default: nil)
  attr(:running, :boolean, default: false)
  attr(:os, :atom, default: :unknown)
  attr(:target, Phoenix.LiveComponent.CID, default: nil)
  attr(:is_saved_query, :boolean, default: true)
  # Quick filter attrs
  attr(:filters, :list, default: [])
  # Sort attrs
  attr(:sorts, :list, default: [])
  # Visualization attrs
  attr(:visualization_config, :map, default: nil)
  attr(:visualization_view_mode, :atom, default: :table)
  attr(:visualization_visible, :boolean, default: false)

  def render_result(assigns) do
    ~H"""
    <div id={"query-results-#{assigns[:query_id] || "default"}"} class="px-4 sm:px-6 lg:px-8 h-full flex flex-col">
      <%= cond do %>
        <% @running == true -> %>
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

          <%!-- Quick filter chips --%>
          <.filter_chips :if={@filters != []} filters={@filters} target={@target} />

          <%!-- Sort chips --%>
          <.sort_chips :if={@sorts != []} sorts={@sorts} target={@target} />

          <%!-- Content area: Table or Chart --%>
          <div class="flex-1 overflow-hidden">
            <%= if @visualization_view_mode == :chart && has_valid_config?(@visualization_config) do %>
              <.render_chart result={@result} config={@visualization_config} />
            <% else %>
              <.render_table result={@result} target={@target} sorts={@sorts} />
            <% end %>
          </div>

          <%!-- Bottom bar with controls --%>
          <.bottom_bar
            result={@result}
            target={@target}
            visualization_config={@visualization_config}
            visualization_view_mode={@visualization_view_mode}
            visualization_visible={@visualization_visible}
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

  defp render_table(assigns) do
    stats = Statistics.compute_all(assigns.result)
    assigns = assign(assigns, :column_stats, stats)

    ~H"""
    <div class="flow-root h-full" id="results-table-context" phx-hook="CellContextMenu">
      <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8 overflow-y-auto h-full">
        <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
          <table class="relative min-w-full">
            <thead class="sticky top-0 z-10 bg-white dark:bg-gray-800 shadow-[0_1px_0_0] shadow-gray-300 dark:shadow-gray-600">
              <tr>
                <th
                  :for={{col, _index} <- Enum.with_index(@result.columns)}
                  scope="col"
                  data-column={col}
                  data-stats={safe_json_encode_or_empty(encode_stats(@column_stats[col]))}
                  class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-text-light dark:text-text-dark sm:pl-3 bg-white dark:bg-gray-800 select-none cursor-context-menu hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
                >
                  <span class="inline-flex items-center gap-1">
                    {col}
                    <%= if sort = find_sort(@sorts, col) do %>
                      <%= if sort.direction == :asc do %>
                        <Icons.chevron_up class="w-3.5 h-3.5 text-blue-500 dark:text-blue-400" />
                      <% else %>
                        <Icons.chevron_down class="w-3.5 h-3.5 text-blue-500 dark:text-blue-400" />
                      <% end %>
                    <% end %>
                  </span>
                </th>
              </tr>
            </thead>
            <tbody id="query-results" class="bg-white dark:bg-gray-800">
              <tr :for={row <- @result.rows} class="even:bg-gray-50 dark:even:bg-gray-700">
                <td
                  :for={{col, index} <- Enum.with_index(@result.columns)}
                  class="whitespace-nowrap py-4 pl-4 pr-3 text-sm text-text-light dark:text-text-dark sm:pl-3 cursor-context-menu hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
                  data-column={col}
                  data-value={CellFormatter.format(Enum.at(row, index))}
                  data-is-null={to_string(is_nil(Enum.at(row, index)))}
                >
                  {CellFormatter.format(Enum.at(row, index))}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    <%= if Enum.empty?(@result.rows) do %>
      <div class="text-center py-12 text-gray-500 dark:text-gray-400">
        <p class="text-base"><%= gettext("No results found") %></p>
        <p class="text-sm mt-1"><%= gettext("Your query returned no rows") %></p>
      </div>
    <% end %>
    """
  end

  defp filter_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 pb-2 flex-shrink-0">
      <span class="text-xs font-medium text-gray-500 dark:text-gray-400"><%= gettext("Filters:") %></span>
      <span
        :for={{filter, index} <- Enum.with_index(@filters)}
        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-blue-50 text-blue-700 dark:bg-blue-900/20 dark:text-blue-400 rounded-full"
      >
        <span class="font-semibold">{filter.column}</span>
        <span>{Filter.operator_label(filter.op)}</span>
        <span :if={filter.op not in [:is_null, :is_not_null]}>{format_filter_value(filter.value)}</span>
        <button
          type="button"
          phx-click="remove_filter"
          phx-target={@target}
          phx-value-index={index}
          class="ml-0.5 hover:text-blue-900 dark:hover:text-blue-200"
        >
          <Icons.x_mark class="w-3 h-3" />
        </button>
      </span>
      <button
        type="button"
        phx-click="clear_filters"
        phx-target={@target}
        class="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
        title={gettext("Clear all filters")}
      >
        <Icons.funnel_x class="w-3.5 h-3.5" />
        <%= gettext("Clear all") %>
      </button>
    </div>
    """
  end

  defp sort_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 pb-2 flex-shrink-0">
      <span class="text-xs font-medium text-gray-500 dark:text-gray-400"><%= gettext("Sort:") %></span>
      <span
        :for={{sort, index} <- Enum.with_index(@sorts)}
        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-purple-50 text-purple-700 dark:bg-purple-900/20 dark:text-purple-400 rounded-full"
      >
        <span class="font-semibold">{sort.column}</span>
        <span>{Sort.direction_label(sort.direction)}</span>
        <button
          type="button"
          phx-click="remove_sort"
          phx-target={@target}
          phx-value-index={index}
          class="ml-0.5 hover:text-purple-900 dark:hover:text-purple-200"
        >
          <Icons.x_mark class="w-3 h-3" />
        </button>
      </span>
      <button
        type="button"
        phx-click="clear_sorts"
        phx-target={@target}
        class="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
        title={gettext("Clear all sorts")}
      >
        <Icons.x_mark class="w-3.5 h-3.5" />
        <%= gettext("Clear all") %>
      </button>
    </div>
    """
  end

  defp find_sort(sorts, column) do
    Enum.find(sorts, &(&1.column == column))
  end

  defp format_filter_value(nil), do: "NULL"

  defp format_filter_value(value) when is_binary(value) and byte_size(value) > 30 do
    String.slice(value, 0, 30) <> "…"
  end

  defp format_filter_value(value) when is_binary(value), do: value
  defp format_filter_value(value), do: to_string(value)

  defp encode_stats(nil), do: %{}

  defp encode_stats(stats) do
    Map.new(stats, fn {k, v} -> {k, Lotus.Normalizer.normalize(v)} end)
  end

  defp render_chart(assigns) do
    spec = VegaSpecBuilder.build(assigns.result, assigns.config)

    case safe_json_encode(spec) do
      {:ok, json} ->
        assigns = assign(assigns, :spec_json, json)

        ~H"""
        <div
          id="vega-chart-container"
          phx-hook="VegaChart"
          phx-update="ignore"
          data-spec={@spec_json}
          class="w-full h-full min-h-[250px] max-h-[500px] flex items-center justify-center"
        >
          <div class="text-gray-400">
            <.spinner />
          </div>
        </div>
        """

      {:error, _reason} ->
        ~H"""
        <div class="flex items-center justify-center h-64 text-red-500 dark:text-red-400 text-sm">
          <Icons.exclamation_circle class="h-5 w-5 mr-2 flex-shrink-0" />
          <span><%= gettext("Chart could not be rendered: result contains values that cannot be displayed") %></span>
        </div>
        """
    end
  end

  attr(:result, :any, required: true)
  attr(:target, Phoenix.LiveComponent.CID, required: true)
  attr(:visualization_config, :map, default: nil)
  attr(:visualization_view_mode, :atom, default: :table)
  attr(:visualization_visible, :boolean, default: false)

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

  defp has_valid_config?(config), do: VegaSpecBuilder.valid_config?(config)

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
