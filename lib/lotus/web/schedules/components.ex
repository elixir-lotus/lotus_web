defmodule Lotus.Web.Schedules.Components do
  # The schedules on the home page's Schedules tab: a gallery of tiles, each
  # with its cadence drawn, or a table; and the pieces the schedule editor
  # shares with them (the status, the runs, the cadence's drawing).

  use Lotus.Web, :html

  alias Lotus.Schedules
  alias Lotus.Schedules.Cron
  alias Lotus.Storage.Schedule
  alias Lotus.Web.Schedules.{Cadence, TimeZones}

  @recent_runs 12

  ## Entries

  @doc """
  The schedules with what the list shows of each: its cadence, what it runs,
  its zone and its latest runs.
  """
  def entries(schedules, queries, dashboards) do
    queries = Map.new(queries, &{&1.id, &1})
    dashboards = Map.new(dashboards, &{&1.id, &1})
    now = DateTime.utc_now()

    Enum.map(schedules, fn schedule -> entry(schedule, queries, dashboards, now) end)
  end

  defp entry(%Schedule{} = schedule, queries, dashboards, now) do
    cadence = Cadence.from_cron(schedule.cron)

    %{
      schedule: schedule,
      cadence: cadence,
      sentence: Cadence.sentence(cadence),
      target: target(schedule, queries, dashboards),
      zone: TimeZones.entry(schedule.time_zone, now) || TimeZones.entry("Etc/UTC", now),
      runs: schedule |> Schedules.list_runs(limit: @recent_runs) |> Enum.reverse(),
      status: status(schedule)
    }
  end

  @doc "What a schedule runs: its kind, id and name."
  def target(%Schedule{query_id: id}, queries, _dashboards) when not is_nil(id) do
    query = Map.get(queries, id)

    %{
      kind: :query,
      id: id,
      name: (query && query.name) || gettext("A query"),
      description: query && query.description
    }
  end

  def target(%Schedule{dashboard_id: id}, _queries, dashboards) do
    dashboard = Map.get(dashboards, id)

    %{
      kind: :dashboard,
      id: id,
      name: (dashboard && dashboard.name) || gettext("A dashboard"),
      description: nil
    }
  end

  @doc """
  A schedule's status: `:paused`, `:firing` (an alert whose rule holds),
  `:watching` (an alert whose rule does not) or `:active`.
  """
  def status(%Schedule{enabled: false}), do: :paused

  def status(%Schedule{rule: rule, state: state}) when not is_nil(rule) do
    if Map.get(state || %{}, "status") == "firing", do: :firing, else: :watching
  end

  def status(_schedule), do: :active

  ## The list

  attr(:entries, :list, required: true)
  attr(:any?, :boolean, required: true)
  attr(:view, :atom, required: true)
  attr(:search, :string, required: true)
  attr(:filter, :string, required: true)
  attr(:counts, :map, required: true)
  attr(:can_manage, :boolean, required: true)
  attr(:target, :any, required: true)

  def schedules_list(assigns) do
    ~H"""
    <%= if not @any? do %>
      <.empty can_manage={@can_manage} />
    <% else %>
      <div
        id="schedules-list"
        phx-hook="ListView"
        data-store="schedules_view"
        data-list="schedules"
        data-view={@view}
        phx-target={@target}
        class="pb-8"
      >
        <div class="flex flex-wrap items-center gap-3 pt-6 pb-5">
          <form id="schedules-search" phx-change="search_schedules" phx-submit="search_schedules" phx-target={@target} class="w-full max-w-xs">
            <input type="hidden" name="filter" value={@filter} />
            <div class="relative">
              <Icons.magnifying_glass class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input
                type="search"
                name="search"
                value={@search}
                placeholder={gettext("Search reports and alerts…")}
                phx-debounce="200"
                aria-label={gettext("Search reports and alerts")}
                class="w-full rounded-lg border border-gray-300 bg-white py-2 pl-9 pr-3 text-sm placeholder:text-gray-400 focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
              />
            </div>
          </form>
          <div class="flex flex-wrap items-center gap-2" role="group" aria-label={gettext("Show")}>
            <.filter_chip
              :for={{filter, label} <- filters()}
              :if={filter == "all" or @counts[filter] > 0}
              filter={filter}
              label={label}
              count={@counts[filter]}
              current={@filter}
              search={@search}
              target={@target}
            />
          </div>
          <div class="flex-1"></div>
          <.view_toggle view={@view} target={@target} />
          <.link
            :if={@can_manage}
            id="new-alert"
            navigate={lotus_path(["schedules", "new"], %{"alert" => "true", "cron" => "*/15 * * * *"})}
            class="inline-flex items-center gap-1.5 rounded-lg bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-700"
          >
            <Icons.exclamation_triangle class="h-4 w-4" /> <%= gettext("New alert") %>
          </.link>
          <.link
            :if={@can_manage}
            id="new-schedule"
            navigate={lotus_path(["schedules", "new"])}
            class="inline-flex items-center gap-1.5 rounded-lg bg-pink-600 px-3 py-2 text-sm font-medium text-white hover:bg-pink-500"
          >
            <Icons.plus class="h-4 w-4" /> <%= gettext("New report") %>
          </.link>
        </div>

        <p :if={@entries == []} class="py-12 text-center text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("No report or alert matches.") %>
        </p>

        <div
          :if={@view == :grid and @entries != []}
          id="schedules-gallery"
          class="grid grid-cols-[repeat(auto-fill,minmax(290px,1fr))] gap-5"
        >
          <.schedule_tile :for={entry <- @entries} entry={entry} can_manage={@can_manage} target={@target} />
          <.link
            :if={@can_manage}
            navigate={lotus_path(["schedules", "new"])}
            class="flex min-h-[15rem] flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-gray-300 text-sm text-gray-500 hover:border-pink-400 hover:bg-pink-50/40 hover:text-pink-600 dark:border-gray-600 dark:text-gray-400 dark:hover:bg-pink-900/10"
          >
            <Icons.plus class="h-7 w-7" /> <%= gettext("New report") %>
          </.link>
        </div>

        <div :if={@view == :list and @entries != []} id="schedules-table" class="divide-y divide-gray-100 dark:divide-gray-700">
          <div
            :for={entry <- @entries}
            id={"schedule-row-#{entry.schedule.id}"}
            class="group relative grid grid-cols-[2.75rem_minmax(0,1.3fr)_minmax(0,1.2fr)_9rem_8rem_3rem] items-center gap-4 px-2 py-3 hover:bg-gray-50 dark:hover:bg-gray-700/40"
          >
            <.link navigate={lotus_path(["schedules", entry.schedule.id])} class="absolute inset-0" aria-label={entry.schedule.name}></.link>
            <span class="flex h-11 w-11 flex-col items-center justify-center rounded-lg border border-gray-200 bg-gray-50 leading-none dark:border-gray-600 dark:bg-gray-900">
              <Icons.clock class="h-4 w-4 text-pink-500" />
              <span class="mt-1 font-mono text-[10px] text-gray-600 dark:text-gray-300"><%= headline(entry).time %></span>
            </span>
            <span class="min-w-0">
              <span class="flex items-center gap-2">
                <span class="truncate font-medium text-gray-900 dark:text-white"><%= entry.schedule.name %></span>
                <.status_pill status={entry.status} id={"schedule-#{entry.schedule.id}-status-row"} />
              </span>
              <span class="block truncate text-xs text-gray-500 dark:text-gray-400">
                <%= entry.sentence %> · <%= entry.zone.city %>
              </span>
            </span>
            <span class="flex min-w-0 items-center gap-2 text-sm text-gray-600 dark:text-gray-300">
              <.target_icon kind={entry.target.kind} class="h-4 w-4 shrink-0 text-gray-400" />
              <span class="truncate"><%= entry.target.name %></span>
            </span>
            <span class="text-sm text-gray-500 dark:text-gray-400">
              <.next_run id={"schedule-#{entry.schedule.id}-next-row"} at={entry.schedule.next_run_at} />
            </span>
            <span><.run_dots runs={entry.runs} /></span>
            <span class="relative z-10 flex justify-end">
              <.switch
                :if={@can_manage}
                id={"schedule-#{entry.schedule.id}-toggle-row"}
                on={entry.schedule.enabled}
                phx-click="toggle_schedule"
                phx-value-id={entry.schedule.id}
                phx-target={@target}
                label={gettext("Active")}
              />
            </span>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp filters do
    [
      {"all", gettext("All")},
      {"reports", gettext("Reports")},
      {"alerts", gettext("Alerts")},
      {"firing", gettext("Firing")},
      {"paused", gettext("Paused")}
    ]
  end

  @doc "Whether an entry is in a filter of the list."
  def in_filter?(_entry, "all"), do: true
  def in_filter?(entry, "reports"), do: is_nil(entry.schedule.rule)
  def in_filter?(entry, "alerts"), do: not is_nil(entry.schedule.rule)
  def in_filter?(entry, "firing"), do: entry.status == :firing
  def in_filter?(entry, "paused"), do: not entry.schedule.enabled
  def in_filter?(_entry, _filter), do: true

  @doc "How many entries each filter has."
  def counts(entries),
    do:
      Map.new(filters(), fn {filter, _label} ->
        {filter, Enum.count(entries, &in_filter?(&1, filter))}
      end)

  attr(:filter, :string, required: true)
  attr(:label, :string, required: true)
  attr(:count, :integer, default: nil)
  attr(:current, :string, required: true)
  attr(:search, :string, required: true)
  attr(:target, :any, required: true)

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      id={"schedules-filter-#{@filter}"}
      phx-click="search_schedules"
      phx-value-filter={@filter}
      phx-value-search={@search}
      phx-target={@target}
      aria-pressed={to_string(@current == @filter)}
      class={[
        "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm",
        @current == @filter && "border-pink-500 bg-pink-50 text-pink-700 dark:bg-pink-900/30 dark:text-pink-300",
        @current != @filter &&
          "border-gray-300 text-gray-600 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
      ]}
    >
      <span :if={@filter == "firing"} class="h-1.5 w-1.5 rounded-full bg-red-500"></span>
      <%= @label %>
      <span :if={@filter != "all"} class="text-xs opacity-70"><%= @count %></span>
    </button>
    """
  end

  attr(:view, :atom, required: true)
  attr(:target, :any, required: true)

  defp view_toggle(assigns) do
    ~H"""
    <div class="inline-flex rounded-lg ring-1 ring-gray-300 dark:ring-gray-600" role="group" aria-label={gettext("View")}>
      <button
        :for={{view, label} <- [grid: gettext("Gallery"), list: gettext("Table")]}
        id={"schedules-view-#{view}"}
        type="button"
        phx-click="set_view"
        phx-value-view={view}
        phx-value-list="schedules"
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

  attr(:can_manage, :boolean, required: true)

  defp empty(assigns) do
    ~H"""
    <div id="schedules-empty" class="mx-auto flex max-w-2xl flex-col items-center py-16 text-center">
      <div class="relative mb-6">
        <div class="flex h-16 w-16 items-center justify-center rounded-2xl bg-pink-50 text-pink-600 ring-8 ring-pink-50/50 dark:bg-pink-900/30 dark:text-pink-300 dark:ring-pink-900/10">
          <Icons.clock class="h-8 w-8" />
        </div>
      </div>
      <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
        <%= gettext("Reports and alerts, delivered") %>
      </h3>
      <p class="mt-2 max-w-md text-sm text-gray-500 dark:text-gray-400">
        <%= gettext("A report sends a query's results or a whole dashboard on the days and at the times you choose. An alert checks a query and sends only when a number crosses a line.") %>
      </p>
      <div :if={@can_manage} class="mt-8 grid w-full gap-3 sm:grid-cols-3">
        <.link
          :for={{icon, title, text, params} <- templates()}
          navigate={lotus_path(["schedules", "new"], params)}
          class="group rounded-xl border border-gray-200 bg-white p-4 text-left transition hover:border-pink-300 hover:shadow-md dark:border-gray-700 dark:bg-gray-800 dark:hover:border-pink-700"
        >
          <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-gray-50 text-gray-500 group-hover:bg-pink-50 group-hover:text-pink-600 dark:bg-gray-700 dark:text-gray-300 dark:group-hover:bg-pink-900/30">
            <%= case icon do %>
              <% :calendar -> %><Icons.calendar class="h-4 w-4" />
              <% :clock -> %><Icons.clock class="h-4 w-4" />
              <% :alert -> %><Icons.exclamation_triangle class="h-4 w-4" />
            <% end %>
          </span>
          <span class="mt-3 block text-sm font-semibold text-gray-900 dark:text-white"><%= title %></span>
          <span class="mt-0.5 block text-xs text-gray-500 dark:text-gray-400"><%= text %></span>
        </.link>
      </div>
      <.link
        :if={@can_manage}
        id="new-schedule"
        navigate={lotus_path(["schedules", "new"])}
        class="mt-6 inline-flex items-center gap-1.5 rounded-lg bg-pink-600 px-4 py-2 text-sm font-medium text-white hover:bg-pink-500"
      >
        <Icons.plus class="h-4 w-4" /> <%= gettext("New report") %>
      </.link>
    </div>
    """
  end

  defp templates do
    [
      {:calendar, gettext("Weekly report"), gettext("Every Monday at 08:00"),
       %{"cron" => "0 8 * * 1"}},
      {:clock, gettext("Daily digest"), gettext("Every weekday at 09:00"),
       %{"cron" => "0 9 * * 1-5"}},
      {:alert, gettext("Threshold alert"),
       gettext("Checks every 15 minutes, sends when it crosses"),
       %{"cron" => "*/15 * * * *", "alert" => "true"}}
    ]
  end

  ## A tile

  attr(:entry, :map, required: true)
  attr(:can_manage, :boolean, required: true)
  attr(:target, :any, required: true)

  def schedule_tile(assigns) do
    assigns = assign(assigns, headline: headline(assigns.entry))

    ~H"""
    <div
      id={"schedule-#{@entry.schedule.id}"}
      class={[
        "group relative overflow-hidden rounded-xl border bg-white transition hover:shadow-lg dark:bg-gray-800",
        @entry.status == :firing && "border-red-200 hover:border-red-300 dark:border-red-900/60",
        @entry.status != :firing && "border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-500"
      ]}
    >
      <.link navigate={lotus_path(["schedules", @entry.schedule.id])} class="block focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-500">
        <div class={[
          "relative h-36 border-b px-4 pt-10 pb-3 dark:border-gray-700",
          @entry.schedule.enabled && "border-gray-100 bg-gradient-to-br from-gray-50 to-pink-50/40 dark:from-gray-900/60 dark:to-pink-950/20",
          not @entry.schedule.enabled && "border-gray-100 bg-gray-50 dark:bg-gray-900/60"
        ]}>
          <span class="absolute left-3 top-3"><.kind_badge alert={not is_nil(@entry.schedule.rule)} /></span>
          <span class="absolute right-3 top-3"><.status_pill status={@entry.status} id={"schedule-#{@entry.schedule.id}-status"} /></span>
          <div class={["flex h-full items-end justify-between gap-3", not @entry.schedule.enabled && "opacity-50"]}>
            <div class="min-w-0">
              <p class="font-mono text-[28px] font-light leading-none tracking-tight text-gray-900 tabular-nums dark:text-white">
                <%= @headline.time %>
              </p>
              <p class="mt-1.5 truncate text-xs text-gray-500 dark:text-gray-400">
                <%= @headline.caption %>
              </p>
            </div>
            <.cadence_sketch entry={@entry} />
          </div>
        </div>
        <div class="px-4 pb-4 pt-3">
          <h3 class="truncate text-[15px] font-semibold text-gray-900 dark:text-white"><%= @entry.schedule.name %></h3>
          <p class="mt-0.5 truncate text-sm text-gray-500 dark:text-gray-400"><%= @entry.sentence %></p>
          <p class="mt-1.5 flex min-w-0 items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
            <.target_icon kind={@entry.target.kind} class="h-3.5 w-3.5 shrink-0 text-gray-400" />
            <span class="truncate"><%= @entry.target.name %></span>
            <span :if={@entry.schedule.deliveries != []} class="shrink-0">
              · <%= ngettext("1 destination", "%{count} destinations", length(@entry.schedule.deliveries)) %>
            </span>
          </p>
          <div class="mt-3 flex items-center justify-between gap-3 border-t border-gray-100 pt-3 text-xs text-gray-500 dark:border-gray-700 dark:text-gray-400">
            <span class="min-w-0 truncate">
              <%= if @entry.schedule.enabled do %>
                <%= gettext("Next") %> <.next_run id={"schedule-#{@entry.schedule.id}-next"} at={@entry.schedule.next_run_at} />
              <% else %>
                <%= gettext("Paused") %>
              <% end %>
            </span>
            <span class="mr-12"><.run_dots runs={@entry.runs} id={"schedule-#{@entry.schedule.id}-runs"} /></span>
          </div>
        </div>
      </.link>
      <div :if={@can_manage} class="absolute bottom-3.5 right-4">
        <.switch
          id={"schedule-#{@entry.schedule.id}-toggle"}
          on={@entry.schedule.enabled}
          phx-click="toggle_schedule"
          phx-value-id={@entry.schedule.id}
          phx-target={@target}
          label={if @entry.schedule.enabled, do: gettext("Pause"), else: gettext("Resume")}
        />
      </div>
    </div>
    """
  end

  @doc """
  What the tile writes large: the time of its runs, or how often, with the
  zone under it.
  """
  def headline(%{cadence: cadence, zone: zone} = entry) do
    caption =
      if zone.name == "Etc/UTC", do: "UTC", else: "#{zone.city} · #{short_offset(zone.offset)}"

    case cadence["frequency"] do
      "minutes" ->
        %{
          time: "#{cadence["every"]} min",
          caption: gettext("every %{count} minutes", count: cadence["every"])
        }

      "hourly" ->
        minute = String.pad_leading(cadence["minute"], 2, "0")

        %{
          time: ":" <> minute,
          caption:
            ngettext("every hour", "every %{count} hours", String.to_integer(cadence["every"]))
        }

      "custom" ->
        %{time: custom_time(entry), caption: caption}

      _clock ->
        {hour, minute} = Cadence.time(cadence["time"])

        %{
          time:
            String.pad_leading("#{hour}", 2, "0") <>
              ":" <> String.pad_leading("#{minute}", 2, "0"),
          caption: caption
        }
    end
  end

  # "UTC+1", "UTC−3:30".
  defp short_offset(0), do: "UTC"

  defp short_offset(seconds) do
    sign = if seconds < 0, do: "−", else: "+"
    hours = div(abs(seconds), 3600)

    case div(rem(abs(seconds), 3600), 60) do
      0 -> "UTC#{sign}#{hours}"
      minutes -> "UTC#{sign}#{hours}:#{String.pad_leading("#{minutes}", 2, "0")}"
    end
  end

  # A custom cadence shows the wall clock time of its next run.
  defp custom_time(%{schedule: %{next_run_at: %DateTime{} = at, time_zone: zone}}) do
    case DateTime.shift_zone(at, zone, Cron.database()) do
      {:ok, local} -> Calendar.strftime(local, "%H:%M")
      _error -> "cron"
    end
  end

  defp custom_time(_entry), do: "cron"

  ## The cadence drawn

  attr(:entry, :map, required: true)

  @doc """
  The cadence drawn: the weekdays it runs on, the days of its month, or the
  hours of its day.
  """
  def cadence_sketch(assigns) do
    assigns = assign(assigns, :shape, shape(assigns.entry))

    ~H"""
    <%= case @shape do %>
      <% {:week, days} -> %>
        <div class="flex shrink-0 gap-1" aria-hidden="true">
          <span
            :for={day <- 1..7}
            class={[
              "flex h-6 w-5 items-center justify-center rounded text-[10px] font-semibold",
              day in days && "bg-pink-500 text-white shadow-sm shadow-pink-500/30",
              day not in days && "bg-gray-200/70 text-gray-400 dark:bg-gray-700 dark:text-gray-500"
            ]}
          ><%= String.first(Cadence.day_initial(day)) %></span>
        </div>
      <% {:month, first_weekday, length, days} -> %>
        <div class="grid shrink-0 grid-cols-7 gap-[3px]" aria-hidden="true">
          <span :for={_blank <- 1..(first_weekday - 1)//1} class="h-[7px] w-[7px]"></span>
          <span
            :for={day <- 1..length}
            class={[
              "h-[7px] w-[7px] rounded-[2px]",
              day in days && "bg-pink-500",
              day not in days && "bg-gray-200 dark:bg-gray-700"
            ]}
          ></span>
        </div>
      <% {:day, hours} -> %>
        <div class="flex h-9 shrink-0 items-end gap-[2px]" aria-hidden="true">
          <span
            :for={hour <- 0..23}
            class={[
              "w-[4px] rounded-sm",
              hour in hours && "h-full bg-pink-500",
              hour not in hours && "h-2 bg-gray-200 dark:bg-gray-700"
            ]}
          ></span>
        </div>
    <% end %>
    """
  end

  defp shape(%{cadence: %{"frequency" => "minutes"}}), do: {:day, Enum.to_list(0..23)}

  defp shape(%{cadence: %{"frequency" => "hourly", "every" => every}}) do
    {:day, Enum.take_every(0..23, String.to_integer(every))}
  end

  defp shape(%{cadence: %{"frequency" => "daily", "weekdays" => "true"}}),
    do: {:week, [1, 2, 3, 4, 5]}

  defp shape(%{cadence: %{"frequency" => "daily"}}), do: {:week, Enum.to_list(1..7)}

  defp shape(%{cadence: %{"frequency" => "weekly", "days" => days}}),
    do: {:week, Enum.map(days, &String.to_integer/1)}

  # A monthly or custom cadence: the days of the coming month it runs on.
  defp shape(%{schedule: schedule}) do
    db = Cron.database()
    runs = Cadence.next_runs(schedule.cron, schedule.time_zone, 40)

    local =
      Enum.flat_map(runs, fn at ->
        case DateTime.shift_zone(at, schedule.time_zone, db) do
          {:ok, local} -> [local]
          _error -> []
        end
      end)

    case local do
      [] -> {:week, []}
      [first | _rest] -> local_shape(local, first)
    end
  end

  # Several runs on its first day: their hours. Else the days of its month.
  defp local_shape(local, first) do
    day = DateTime.to_date(first)
    hours = for at <- local, Date.compare(DateTime.to_date(at), day) == :eq, do: at.hour

    if length(hours) > 1 do
      {:day, Enum.uniq(hours)}
    else
      month = Date.beginning_of_month(day)
      days = for at <- local, at.year == month.year and at.month == month.month, do: at.day
      {:month, Date.day_of_week(month), Date.days_in_month(month), days}
    end
  end

  ## Small pieces

  attr(:alert, :boolean, required: true)

  @doc "A report (it sends on its schedule) or an alert (it sends when its rule changes)."
  def kind_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full border bg-white px-2 py-0.5 text-[11px] font-medium dark:bg-gray-800",
      @alert && "border-amber-200 text-amber-700 dark:border-amber-900/60 dark:text-amber-300",
      not @alert && "border-gray-200 text-gray-600 dark:border-gray-600 dark:text-gray-300"
    ]}>
      <Icons.exclamation_triangle :if={@alert} class="h-3 w-3" />
      <Icons.send :if={not @alert} class="h-3 w-3" />
      <%= if @alert, do: gettext("Alert"), else: gettext("Report") %>
    </span>
    """
  end

  attr(:kind, :atom, required: true)
  attr(:class, :string, default: "h-4 w-4")

  def target_icon(assigns) do
    ~H"""
    <Icons.terminal :if={@kind == :query} class={@class} />
    <Icons.squares_2x2 :if={@kind != :query} class={@class} />
    """
  end

  attr(:status, :atom, required: true)
  attr(:id, :string, default: nil)

  def status_pill(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium",
        @status == :firing && "bg-red-50 text-red-700 ring-1 ring-red-200 dark:bg-red-900/30 dark:text-red-300 dark:ring-red-900",
        @status == :watching && "bg-amber-50 text-amber-700 ring-1 ring-amber-200 dark:bg-amber-900/20 dark:text-amber-300 dark:ring-amber-900/50",
        @status == :active && "bg-green-50 text-green-700 ring-1 ring-green-200 dark:bg-green-900/20 dark:text-green-300 dark:ring-green-900/50",
        @status == :paused && "bg-gray-100 text-gray-600 ring-1 ring-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600"
      ]}
    >
      <span class="relative flex h-1.5 w-1.5">
        <span :if={@status == :firing} class="absolute inline-flex h-full w-full animate-ping rounded-full bg-red-400 opacity-75"></span>
        <span class={[
          "relative inline-flex h-1.5 w-1.5 rounded-full",
          @status == :firing && "bg-red-500",
          @status == :watching && "bg-amber-500",
          @status == :active && "bg-green-500",
          @status == :paused && "bg-gray-400"
        ]}></span>
      </span>
      <%= status_label(@status) %>
    </span>
    """
  end

  def status_label(:firing), do: gettext("Firing")
  def status_label(:watching), do: gettext("Watching")
  def status_label(:active), do: gettext("Active")
  def status_label(:paused), do: gettext("Paused")

  attr(:runs, :list, required: true)
  attr(:id, :string, default: nil)

  @doc "The latest runs, oldest first, a square each."
  def run_dots(assigns) do
    ~H"""
    <span id={@id} class="flex items-center gap-[3px]" aria-label={gettext("Latest runs")}>
      <span :if={@runs == []} class="text-xs text-gray-400"><%= gettext("No runs yet") %></span>
      <span
        :for={run <- @runs}
        title={"#{run.status} · #{Calendar.strftime(run.scheduled_for, "%Y-%m-%d %H:%M UTC")}"}
        class={["h-3 w-1.5 rounded-sm", run_color(run.status)]}
      ></span>
    </span>
    """
  end

  def run_color("succeeded"), do: "bg-green-500"
  def run_color("failed"), do: "bg-red-500"
  def run_color("running"), do: "bg-blue-400 animate-pulse"
  def run_color(_pending), do: "bg-gray-300 dark:bg-gray-600"

  attr(:id, :string, required: true)
  attr(:at, :any, required: true)

  def next_run(assigns) do
    ~H"""
    <%= if @at do %>
      <time id={@id} phx-hook="RelativeTime" datetime={DateTime.to_iso8601(@at)}><%= Calendar.strftime(@at, "%b %d, %H:%M") %></time>
    <% else %>
      <span>-</span>
    <% end %>
    """
  end

  attr(:id, :string, required: true)
  attr(:on, :boolean, required: true)
  attr(:label, :string, required: true)
  attr(:rest, :global)

  @doc "An on and off switch."
  def switch(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      role="switch"
      aria-checked={to_string(@on)}
      aria-label={@label}
      title={@label}
      class={[
        "relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-500 focus-visible:ring-offset-2",
        @on && "bg-pink-600",
        not @on && "bg-gray-200 dark:bg-gray-600"
      ]}
      {@rest}
    >
      <span class={[
        "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200",
        @on && "translate-x-4",
        not @on && "translate-x-0"
      ]}></span>
    </button>
    """
  end
end
