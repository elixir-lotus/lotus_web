defmodule Lotus.Web.Queries.ResultsComponent do
  @moduledoc false

  use Lotus.Web, :html

  alias Lotus.Result.Statistics
  alias Lotus.Web.Charts
  alias Lotus.Web.Queries.MasuResults
  alias Lotus.Web.Queries.Pin

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
  # The result's foreign key columns (`Lotus.Web.Queries.References`).
  attr(:references, :map, default: %{})
  # The run changed data (an UPDATE, INSERT or DELETE the person confirmed).
  attr(:changed, :boolean, default: false)
  # A result kept to compare the next runs with (`Lotus.Web.Queries.Pin`),
  # beside the result (`:split`) or above it (`:stacked`, open or not).
  attr(:pinned, :any, default: nil)
  attr(:pin_layout, :atom, default: :split)
  attr(:pin_open, :boolean, default: false)
  # Side by side, the tables scroll together; and every row of both queries
  # compared (`Lotus.diff/3`): `%{status: :running | :ok | :error, …}`.
  attr(:pin_sync, :boolean, default: true)
  attr(:pin_diff, :map, default: nil)
  attr(:pin_diff_tab, :atom, default: :removed)

  def render_result(assigns) do
    ~H"""
    <div id={"query-results-#{assigns[:query_id] || "default"}"} class="px-4 sm:px-6 lg:px-8 h-full flex flex-col">
      <%= cond do %>
        <%!-- While a query runs, the grid keeps its rows and shows it loads --%>
        <% @running == true and @result == nil -> %>
          <.loading_spinner />

        <% @result != nil and @changed and @result.columns in [nil, []] -> %>
          <div class="pt-3 pb-2 px-0 flex items-center gap-3 flex-shrink-0">
            <h2 class="text-base font-semibold text-text-light dark:text-text-dark"><%= gettext("Results") %></h2>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400 rounded">
              <Icons.check class="w-3 h-3" />
              <%= gettext("Success") %>
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              <%= gettext("%{duration}ms", duration: @result.duration_ms) %>
            </span>
          </div>
          <div id="results-changed" class="flex flex-1 flex-col items-center justify-center gap-1 pb-8 text-center">
            <p class="text-lg font-semibold text-text-light dark:text-text-dark">
              <%= ngettext("%{count} row changed", "%{count} rows changed", @result.num_rows || 0, count: @result.num_rows || 0) %>
            </p>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              <%= gettext("Running the statement again changes the data again.") %>
            </p>
          </div>

        <% @result != nil -> %>
          <%!-- Compact header row, with the grid's filters at its end --%>
          <div
            id={"query-results-header-#{@query_id}"}
            class="pt-3 pb-2 px-0 flex flex-wrap items-center gap-x-3 gap-y-2 flex-shrink-0"
          >
            <h2 class="text-base font-semibold text-text-light dark:text-text-dark"><%= gettext("Results") %></h2>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400 rounded">
              <Icons.check class="w-3 h-3" />
              <%= gettext("Success") %>
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              <%= info_text(@result) %>
            </span>
            <%!-- The grid's filter bar (its chips and Add filter), which
            Masu draws in the grid and the hook moves here. A new element
            for each grid; hidden with the grid under a chart --%>
            <div class={[
              "lotus-results-filters",
              @visualization_view_mode == :chart && has_valid_config?(@visualization_config) &&
                "hidden"
            ]}>
              <div
                id={"results-filters-#{@query_id}-#{@results_run}"}
                class="masu lotus-results"
                phx-hook="ResultsFilters"
                phx-update="ignore"
                data-grid={grid_id(@query_id, @results_run)}
              >
              </div>
            </div>
            <.pin_button pinned={@pinned} target={@target} />
          </div>

          <.compare_bar
            :if={@pinned}
            comparison={Pin.compare(@pinned, @result)}
            keys={Pin.key_columns(@pinned, @result)}
            diff={@pin_diff}
            layout={@pin_layout}
            sync={@pin_sync}
            target={@target}
          />

          <.diff_panel :if={@pinned && @pin_diff} diff={@pin_diff} tab={@pin_diff_tab} target={@target} />

          <.pinned_strip
            :if={@pinned && @pin_layout == :stacked}
            pinned={@pinned}
            open={@pin_open}
            comparison={Pin.compare(@pinned, @result)}
            removed_keys={removed_keys(@pin_diff)}
            target={@target}
          />

          <%!-- Content area: Table or Chart, beside the pinned result --%>
          <div class={[
            "flex-1 overflow-hidden",
            @pinned && @pin_layout == :split && "grid grid-cols-1 md:grid-cols-2 gap-3"
          ]}>
            <.pinned_panel
              :if={@pinned && @pin_layout == :split}
              pinned={@pinned}
              comparison={Pin.compare(@pinned, @result)}
              removed_keys={removed_keys(@pin_diff)}
              grid={grid_id(@query_id, @results_run)}
              sync={@pin_sync}
              target={@target}
              class="h-full"
            />
            <div class="h-full min-w-0 overflow-hidden">
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
                id={grid_id(@query_id, @results_run)}
                result={@result}
                running={@running}
                target={@target}
                operators={@filter_operators}
                stats={Statistics.compute_all(@result)}
                references={@references}
              />
            </div>
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
          <.pinned_panel
            :if={@pinned}
            pinned={@pinned}
            comparison={%{removed: []}}
            target={@target}
            class="mb-4 max-h-[60%]"
          />

        <% true -> %>
          <.empty_state os={@os} />
      <% end %>
    </div>
    """
  end

  attr(:pinned, :any, required: true)
  attr(:target, :any, required: true)

  defp pin_button(assigns) do
    ~H"""
    <button
      id="pin-result-btn"
      type="button"
      phx-click="pin_result"
      phx-target={@target}
      title={
        if @pinned,
          do: gettext("Pin this result in place of the pinned one"),
          else: gettext("Keep this result on screen to compare the next runs with it")
      }
      class="inline-flex items-center gap-1.5 px-2.5 py-1 text-sm font-medium text-gray-600 dark:text-gray-300 border border-gray-200 dark:border-gray-600 rounded-md hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
    >
      <Icons.pin class="h-4 w-4" />
      <%= if @pinned, do: gettext("Pin this instead"), else: gettext("Pin to compare") %>
    </button>
    """
  end

  attr(:comparison, :map, required: true)
  attr(:keys, :list, default: [])
  attr(:diff, :map, default: nil)
  attr(:layout, :atom, required: true)
  attr(:sync, :boolean, default: true)
  attr(:target, :any, required: true)

  defp compare_bar(assigns) do
    ~H"""
    <div
      id="pin-compare-bar"
      class="pb-2 flex flex-wrap items-center gap-2 flex-shrink-0 text-xs text-gray-700 dark:text-gray-300"
    >
      <span class="font-semibold text-gray-900 dark:text-gray-100"><%= gettext("Compared with the pinned result") %></span>
      <span id="pin-compare-rows" class="inline-flex items-center gap-1.5 rounded-md bg-gray-100 dark:bg-gray-700/60 px-2 py-1">
        <%= gettext("Rows") %>
        <strong class="font-semibold"><%= @comparison.rows %> → <%= @comparison.now %></strong>
        <span :if={@comparison.delta != 0} class={["font-semibold", delta_class(@comparison.delta)]}>
          <%= delta_text(@comparison) %>
        </span>
      </span>
      <span id="pin-compare-columns" class="inline-flex flex-wrap items-center gap-1.5 rounded-md bg-gray-100 dark:bg-gray-700/60 px-2 py-1">
        <%= if @comparison.added == [] and @comparison.removed == [] do %>
          <%= gettext("Columns unchanged") %>
        <% else %>
          <%= gettext("Columns") %>
          <span :for={c <- @comparison.added} class="font-semibold text-blue-800 dark:text-blue-300">+<%= c %></span>
          <span :for={c <- @comparison.removed} class="font-semibold text-orange-800 dark:text-orange-300">−<%= c %></span>
        <% end %>
      </span>
      <span
        :if={is_integer(@comparison.duration) and is_integer(@comparison.now_duration)}
        class="rounded-md bg-gray-100 dark:bg-gray-700/60 px-2 py-1"
      >
        <%= gettext("%{before}ms → %{after}ms", before: @comparison.duration, after: @comparison.now_duration) %>
      </span>
      <form
        :if={@keys != []}
        id="pin-diff-form"
        phx-submit="diff_rows"
        phx-target={@target}
        class="inline-flex items-center gap-1.5"
      >
        <label for="pin-diff-key" class="text-gray-600 dark:text-gray-400"><%= gettext("Match rows on") %></label>
        <select
          id="pin-diff-key"
          name="key"
          class="h-7 rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 py-0 pl-2 pr-7 text-xs"
        >
          <option :for={key <- @keys} value={key} selected={@diff && @diff[:key] == key}><%= key %></option>
        </select>
        <button
          id="pin-diff-btn"
          type="submit"
          disabled={@diff && @diff.status == :running}
          title={gettext("Run both queries and compare every row, matched on this column")}
          class="px-2 py-1 font-medium rounded-md border border-gray-300 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-50"
        >
          <%= gettext("Compare rows") %>
        </button>
      </form>
      <button
        :if={@layout == :split}
        id="pin-sync-btn"
        type="button"
        phx-click="toggle_pin_sync"
        phx-target={@target}
        aria-pressed={to_string(@sync)}
        class={[
          "ml-auto hidden md:inline-flex px-2 py-1 font-medium rounded-md border transition-colors",
          if(@sync,
            do: "border-pink-200 bg-pink-50 text-pink-700 dark:border-pink-800 dark:bg-pink-900/30 dark:text-pink-300",
            else: "border-gray-200 text-gray-600 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-400 dark:hover:bg-gray-700"
          )
        ]}
      >
        <%= gettext("Scroll together") %>
      </button>
      <div
        role="group"
        aria-label={gettext("Where the pinned result shows")}
        class={[
          "hidden md:inline-flex rounded-md border border-gray-200 dark:border-gray-600 overflow-hidden",
          @layout != :split && "ml-auto"
        ]}
      >
        <button
          :for={{layout, label} <- [split: gettext("Side by side"), stacked: gettext("Stacked")]}
          id={"pin-layout-#{layout}"}
          type="button"
          phx-click="set_pin_layout"
          phx-value-layout={layout}
          phx-target={@target}
          aria-pressed={to_string(@layout == layout)}
          class={[
            "px-2.5 py-1 text-xs font-medium transition-colors [&+&]:border-l [&+&]:border-gray-200 dark:[&+&]:border-gray-600",
            if(@layout == layout,
              do: "bg-pink-50 text-pink-700 dark:bg-pink-900/30 dark:text-pink-300",
              else: "text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-700"
            )
          ]}
        >
          <%= label %>
        </button>
      </div>
    </div>
    """
  end

  attr(:pinned, :any, required: true)
  attr(:comparison, :map, required: true)
  attr(:removed_keys, :any, default: nil)
  attr(:grid, :string, default: nil)
  attr(:sync, :boolean, default: true)
  attr(:target, :any, required: true)
  attr(:class, :string, default: nil)

  # The pinned result beside the current one: its rows as they were, read only.
  defp pinned_panel(assigns) do
    ~H"""
    <section
      id="pinned-result"
      aria-label={gettext("Pinned result")}
      class={[
        "flex flex-col min-w-0 rounded-md border border-indigo-200 bg-indigo-50/60 dark:border-indigo-800 dark:bg-indigo-950/30 overflow-hidden",
        @class
      ]}
    >
      <.pinned_header pinned={@pinned} target={@target} />
      <div
        id="pinned-result-scroll"
        class="flex-1 overflow-auto"
        phx-hook="PinScroll"
        data-grid={@grid}
        data-sync={to_string(@sync)}
      >
        <.pinned_table pinned={@pinned} removed={@comparison.removed} removed_keys={@removed_keys} />
      </div>
    </section>
    """
  end

  attr(:pinned, :any, required: true)
  attr(:open, :boolean, required: true)
  attr(:comparison, :map, required: true)
  attr(:removed_keys, :any, default: nil)
  attr(:target, :any, required: true)

  # The pinned result above the current one: a line, its rows when opened.
  defp pinned_strip(assigns) do
    ~H"""
    <section
      id="pinned-result"
      aria-label={gettext("Pinned result")}
      class="mb-2 flex-shrink-0 flex flex-col max-h-[45%] min-h-0 rounded-md border border-indigo-200 bg-indigo-50/60 dark:border-indigo-800 dark:bg-indigo-950/30 overflow-hidden"
    >
      <.pinned_header pinned={@pinned} target={@target} toggle={true} open={@open} />
      <div :if={@open} id="pinned-result-rows" class="min-h-0 overflow-auto border-t border-indigo-200 dark:border-indigo-800">
        <.pinned_table pinned={@pinned} removed={@comparison.removed} removed_keys={@removed_keys} />
      </div>
    </section>
    """
  end

  attr(:pinned, :any, required: true)
  attr(:target, :any, required: true)
  attr(:toggle, :boolean, default: false)
  attr(:open, :boolean, default: false)

  defp pinned_header(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 py-2 text-indigo-900 dark:text-indigo-200">
      <button
        :if={@toggle}
        id="pinned-result-toggle"
        type="button"
        phx-click="toggle_pin_open"
        phx-target={@target}
        aria-expanded={to_string(@open)}
        aria-controls="pinned-result-rows"
        aria-label={if @open, do: gettext("Hide the pinned rows"), else: gettext("Show the pinned rows")}
        class="p-1 -ml-1 rounded hover:bg-indigo-100 dark:hover:bg-indigo-900/40"
      >
        <Icons.chevron_right class={["h-4 w-4 transition-transform", @open && "rotate-90"]} />
      </button>
      <Icons.pin class="h-4 w-4 flex-shrink-0" />
      <div class="flex flex-col min-w-0 flex-1">
        <span class="text-sm font-semibold">
          <%= ngettext(
            "Pinned · %{count} row · %{time}",
            "Pinned · %{count} rows · %{time}",
            Pin.row_count(@pinned.result),
            count: Pin.row_count(@pinned.result),
            time: Calendar.strftime(@pinned.pinned_at, "%H:%M")
          ) %>
        </span>
        <code
          :if={@pinned.statement}
          title={@pinned.statement}
          class="text-xs text-indigo-800 dark:text-indigo-300 truncate"
        ><%= one_line(@pinned.statement) %></code>
      </div>
      <button
        :if={@pinned.text}
        id="restore-pinned-sql-btn"
        type="button"
        phx-click="restore_pinned_sql"
        phx-target={@target}
        title={gettext("Put the pinned result's query back in the editor")}
        class="px-2 py-1 text-xs font-medium rounded-md border border-indigo-300 dark:border-indigo-700 hover:bg-indigo-100 dark:hover:bg-indigo-900/40"
      >
        <%= gettext("Restore SQL") %>
      </button>
      <button
        id="unpin-result-btn"
        type="button"
        phx-click="unpin_result"
        phx-target={@target}
        aria-label={gettext("Unpin")}
        title={gettext("Unpin")}
        class="p-1 rounded-md border border-indigo-300 dark:border-indigo-700 hover:bg-indigo-100 dark:hover:bg-indigo-900/40"
      >
        <Icons.x_mark class="h-4 w-4" />
      </button>
    </div>
    """
  end

  attr(:pinned, :any, required: true)
  attr(:removed, :list, default: [])
  # `{key column, the values of the rows the last run does not have}`,
  # once the rows were compared.
  attr(:removed_keys, :any, default: nil)

  defp pinned_table(assigns) do
    assigns = assign(assigns, :key_index, key_index(assigns.pinned, assigns.removed_keys))

    ~H"""
    <table class="w-full border-collapse text-sm">
      <thead class="sticky top-0 bg-indigo-50 dark:bg-indigo-950">
        <tr>
          <th
            :for={column <- @pinned.result.columns || []}
            class={[
              "px-3 h-9 text-left text-xs font-semibold text-gray-700 dark:text-gray-300 border-b border-indigo-200 dark:border-indigo-800 whitespace-nowrap",
              column in @removed && "bg-orange-100 dark:bg-orange-900/30"
            ]}
          >
            <%= column %>
            <span
              :if={column in @removed}
              class="ml-1 rounded px-1 py-px text-[11px] font-semibold text-orange-800 bg-orange-200/70 dark:text-orange-200 dark:bg-orange-800/50"
            >
              <%= gettext("removed") %>
            </span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          :for={row <- @pinned.result.rows || []}
          class={
            if gone?(row, @key_index, @removed_keys),
              do: "lotus-pin-gone bg-orange-100/80 dark:bg-orange-900/30",
              else: "odd:bg-transparent even:bg-indigo-100/40 dark:even:bg-indigo-900/20"
          }
        >
          <td
            :for={value <- row}
            class="px-3 h-10 text-gray-900 dark:text-gray-100 whitespace-nowrap max-w-xs truncate"
          >
            <%= Lotus.Web.CellFormatter.format(value) %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr(:diff, :map, required: true)
  attr(:tab, :atom, required: true)
  attr(:target, :any, required: true)

  # Every row of both queries compared, on the pin's key: the rows gone,
  # new and changed, a tab each.
  defp diff_panel(assigns) do
    ~H"""
    <section
      id="pin-diff"
      aria-label={gettext("Rows compared")}
      class="mb-2 flex-shrink-0 flex flex-col max-h-[40%] min-h-0 rounded-md border border-gray-200 dark:border-gray-700 overflow-hidden text-xs"
    >
      <div class="flex flex-wrap items-center gap-2 px-3 py-2 bg-gray-50 dark:bg-gray-800/60">
        <%= case @diff.status do %>
          <% :running -> %>
            <span class="inline-flex items-center gap-1.5 text-gray-600 dark:text-gray-300">
              <.spinner class="w-3 h-3" />
              <%= gettext("Comparing every row on %{key}…", key: @diff.key) %>
            </span>
          <% :error -> %>
            <span id="pin-diff-error" class="text-red-700 dark:text-red-400"><%= @diff.message %></span>
          <% :ok -> %>
            <span class="font-semibold text-gray-900 dark:text-gray-100">
              <%= gettext("Every row, on %{key}", key: @diff.key) %>
            </span>
            <div role="tablist" class="inline-flex flex-wrap gap-1">
              <button
                :for={{tab, label, count, class} <- diff_tabs(@diff.diff)}
                id={"pin-diff-tab-#{tab}"}
                type="button"
                role="tab"
                aria-selected={to_string(@tab == tab)}
                phx-click="set_pin_diff_tab"
                phx-value-tab={tab}
                phx-target={@target}
                class={[
                  "px-2 py-0.5 rounded-md border font-medium",
                  if(@tab == tab,
                    do: "border-gray-400 bg-white dark:bg-gray-700 dark:border-gray-500",
                    else: "border-transparent hover:bg-white dark:hover:bg-gray-700"
                  ),
                  class
                ]}
              >
                <%= label %> <span class="tabular-nums"><%= count %></span>
              </button>
            </div>
            <span class="text-gray-600 dark:text-gray-400">
              <%= ngettext("%{count} row the same", "%{count} rows the same", @diff.diff.unchanged, count: @diff.diff.unchanged) %>
            </span>
        <% end %>
        <button
          type="button"
          phx-click="clear_pin_diff"
          phx-target={@target}
          aria-label={gettext("Close the comparison")}
          class="ml-auto p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
        >
          <Icons.x_mark class="h-3.5 w-3.5" />
        </button>
      </div>
      <div :if={@diff.status == :ok} id="pin-diff-rows" class="min-h-0 overflow-auto">
        <.diff_rows diff={@diff.diff} tab={@tab} />
      </div>
    </section>
    """
  end

  attr(:diff, :map, required: true)
  attr(:tab, :atom, required: true)

  @diff_rows_shown 200

  defp diff_rows(assigns) do
    rows = Map.fetch!(assigns.diff, assigns.tab)

    assigns =
      assign(assigns,
        rows: Enum.take(rows, @diff_rows_shown),
        more: max(length(rows) - @diff_rows_shown, 0)
      )

    ~H"""
    <p :if={@rows == []} class="px-3 py-3 text-gray-600 dark:text-gray-400">
      <%= gettext("None.") %>
    </p>
    <table :if={@rows != []} class="w-full border-collapse">
      <thead class="sticky top-0 bg-white dark:bg-gray-800">
        <tr>
          <th
            :for={column <- @diff.columns}
            class="px-3 h-8 text-left font-semibold text-gray-700 dark:text-gray-300 border-b border-gray-200 dark:border-gray-700 whitespace-nowrap"
          >
            <%= column %>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows} class="border-b border-gray-100 dark:border-gray-700/60">
          <td
            :for={column <- @diff.columns}
            class={[
              "px-3 h-8 whitespace-nowrap max-w-xs truncate text-gray-900 dark:text-gray-100",
              @tab == :changed && column in row.columns && "bg-blue-50 dark:bg-blue-900/30"
            ]}
          >
            <%= if @tab == :changed and column in row.columns do %>
              <span class="text-orange-800 dark:text-orange-300 line-through"><%= cell(row.before[column]) %></span>
              → <span class="font-semibold text-blue-800 dark:text-blue-300"><%= cell(row.after[column]) %></span>
            <% else %>
              <%= cell(if(@tab == :changed, do: row.after[column], else: row[column])) %>
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    <p :if={@more > 0} class="px-3 py-2 text-gray-600 dark:text-gray-400">
      <%= ngettext("And %{count} more row.", "And %{count} more rows.", @more, count: @more) %>
    </p>
    """
  end

  defp diff_tabs(diff) do
    [
      {:removed, gettext("Rows gone"), length(diff.removed),
       "text-orange-800 dark:text-orange-300"},
      {:added, gettext("New rows"), length(diff.added), "text-blue-800 dark:text-blue-300"},
      {:changed, gettext("Changed rows"), length(diff.changed),
       "text-gray-800 dark:text-gray-200"}
    ]
  end

  defp cell(nil), do: ""
  defp cell(value), do: Lotus.Web.CellFormatter.format(value)

  # The key and the values (as shown) of the pinned rows the last run does
  # not have, once every row was compared.
  defp removed_keys(%{status: :ok, key: key, diff: diff}),
    do: {key, MapSet.new(diff.removed, &cell(&1[key]))}

  defp removed_keys(_diff), do: nil

  defp key_index(_pinned, nil), do: nil

  defp key_index(pinned, {key, _values}),
    do: Enum.find_index(pinned.result.columns || [], &(&1 == key))

  defp gone?(_row, nil, _removed), do: false
  defp gone?(row, index, {_key, values}), do: MapSet.member?(values, cell(Enum.at(row, index)))

  defp delta_class(delta) when delta < 0, do: "text-orange-800 dark:text-orange-300"
  defp delta_class(_delta), do: "text-blue-800 dark:text-blue-300"

  defp delta_text(%{delta: delta, percent: percent}) do
    sign = if delta > 0, do: "+", else: "−"
    count = "#{sign}#{abs(delta)}"
    if percent, do: "#{count} (#{sign}#{abs(percent)}%)", else: count
  end

  defp one_line(statement), do: statement |> String.split() |> Enum.join(" ")

  defp grid_id(query_id, results_run), do: "results-grid-#{query_id}-#{results_run}"

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
