defmodule Lotus.Web.SchedulesPage do
  @moduledoc """
  The editor of a schedule or an alert of `Lotus.Schedules`: what it runs,
  when, where its results go, and when an alert sends. Beside it, the
  schedule in a sentence and its next runs; for a saved one, its latest
  runs. The list of schedules is the home page's Schedules tab. Shown with
  `lotus_dashboard "/lotus", features: [:schedules]`.

  Anyone who reaches the page sees the schedule and its runs; saving,
  pausing and deleting asks for `:manage_schedule`
  (`Lotus.Web.Authorization`).
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Schedules
  alias Lotus.Schedules.{Alert, Cron}
  alias Lotus.Storage.Schedule
  alias Lotus.Web.{Actor, Authorization, Page, Pro}
  alias Lotus.Web.Schedules.{Cadence, TimeZones}
  alias Lotus.Web.Schedules.Components, as: Parts

  @runs 20
  @next_runs 5

  @impl Phoenix.LiveComponent
  def render(assigns) do
    cron = Cadence.to_cron(assigns.draft["cadence"])

    assigns =
      assign(assigns,
        can_manage: Authorization.allowed?(assigns, :manage_schedule),
        cron: cron,
        cron_error: cron_error(cron),
        zone: TimeZones.entry(assigns.draft["time_zone"]) || TimeZones.entry("Etc/UTC"),
        next_runs: Cadence.next_runs(cron, assigns.draft["time_zone"], @next_runs),
        target_entry: target_entry(assigns.draft["target"], assigns.queries, assigns.dashboards)
      )

    ~H"""
    <div id="schedules-page" class="flex h-full flex-col overflow-hidden">
      <div class="mx-auto h-full w-full px-0 py-0 sm:px-0 sm:py-6 lg:px-6">
        <form
          id="schedule-form"
          phx-change="change_draft"
          phx-submit="save_schedule"
          phx-target={@myself}
          class="flex h-full flex-col overflow-hidden rounded-lg bg-gray-50 shadow-sm ring-1 ring-black/5 dark:bg-gray-900 dark:ring-white/10"
        >
          <.head draft={@draft} schedule={@schedule} can_manage={@can_manage} target={@myself} />

          <div class="flex-1 overflow-y-auto">
            <div class="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-6 lg:grid-cols-[minmax(0,1fr)_21rem]">
              <fieldset disabled={not @can_manage} class="min-w-0 space-y-5">
                <div
                  :if={@errors != []}
                  id="schedule-errors"
                  class="flex gap-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/60 dark:bg-red-950/30 dark:text-red-300"
                >
                  <Icons.exclamation_circle class="mt-0.5 h-5 w-5 shrink-0" />
                  <div>
                    <p class="font-medium"><%= gettext("It could not be saved") %></p>
                    <ul class="mt-1 list-disc space-y-0.5 pl-4">
                      <li :for={error <- @errors}><%= error %></li>
                    </ul>
                  </div>
                </div>

                <.what_section
                  draft={@draft}
                  target_entry={@target_entry}
                  picking={@picking}
                  search={@target_search}
                  queries={@queries}
                  dashboards={@dashboards}
                  target={@myself}
                />
                <.when_section
                  cadence={@draft["cadence"]}
                  cron_error={@cron_error}
                  zone={@zone}
                  zone_open={@zone_open}
                  zone_search={@zone_search}
                  viewer_zone={@viewer_zone}
                  target={@myself}
                />
                <.deliver_section deliveries={@draft["deliveries"]} channels={@channels} formats={@formats} target={@myself} />
                <.alert_section draft={@draft} conditions={@conditions} target_entry={@target_entry} />
              </fieldset>

              <aside class="space-y-5 lg:sticky lg:top-0 lg:self-start">
                <.summary
                  draft={@draft}
                  cron={@cron}
                  cron_error={@cron_error}
                  zone={@zone}
                  next_runs={@next_runs}
                  viewer_zone={@viewer_zone}
                  target_entry={@target_entry}
                />
                <.runs :if={@schedule} schedule={@schedule} runs={@runs} />
              </aside>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  ## The head: back, the name, active, delete and save

  attr(:draft, :map, required: true)
  attr(:schedule, :any, required: true)
  attr(:can_manage, :boolean, required: true)
  attr(:target, :any, required: true)

  defp head(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-3 border-b border-gray-200 bg-white px-4 py-3 dark:border-gray-700 dark:bg-gray-800 sm:px-6">
      <div class="flex min-w-0 flex-1 items-center gap-2">
        <.link
          navigate={lotus_path("schedules")}
          class="-ml-1 rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-300"
          aria-label={gettext("All reports and alerts")}
          title={gettext("All reports and alerts")}
        >
          <Icons.chevron_left class="h-5 w-5" />
        </.link>
        <div class="min-w-0 flex-1">
          <input
            type="text"
            id="schedule-name"
            name="draft[name]"
            value={@draft["name"]}
            placeholder={if @draft["alert"] == "true", do: gettext("Name this alert"), else: gettext("Name this report")}
            aria-label={gettext("Name")}
            autocomplete="off"
            disabled={not @can_manage}
            class="lotus-title -ml-2 w-full max-w-xl truncate rounded-md border-0 bg-transparent px-2 py-1 text-xl font-semibold tracking-tight text-gray-900 placeholder:font-normal placeholder:text-gray-400 hover:bg-gray-50 focus:bg-white focus:ring-2 focus:ring-pink-500 dark:text-white dark:placeholder:text-gray-500 dark:hover:bg-gray-700/50 dark:focus:bg-gray-900"
          />
          <p class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
            <%= if @schedule do %>
              <Parts.status_pill status={Parts.status(@schedule)} id="schedule-status" />
              <span><%= gettext("Created") %> <time id="schedule-created" phx-hook="RelativeTime" datetime={DateTime.to_iso8601(to_datetime(@schedule.inserted_at))}></time></span>
            <% else %>
              <span><%= if @draft["alert"] == "true", do: gettext("New alert"), else: gettext("New report") %></span>
            <% end %>
          </p>
        </div>
      </div>

      <div :if={@can_manage} class="flex shrink-0 items-center gap-2">
        <label class="mr-2 flex cursor-pointer items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
          <input type="hidden" name="draft[enabled]" value="false" />
          <input type="checkbox" id="schedule-enabled" name="draft[enabled]" value="true" checked={@draft["enabled"] == "true"} class="peer sr-only" />
          <span class="relative inline-flex h-5 w-9 shrink-0 rounded-full bg-gray-200 transition-colors peer-checked:bg-pink-600 peer-focus-visible:ring-2 peer-focus-visible:ring-pink-500 peer-focus-visible:ring-offset-2 dark:bg-gray-600 [&>span]:peer-checked:translate-x-4">
            <span class="pointer-events-none absolute left-0.5 top-0.5 inline-block h-4 w-4 rounded-full bg-white shadow transition"></span>
          </span>
          <%= if @draft["enabled"] == "true", do: gettext("Active"), else: gettext("Paused") %>
        </label>
        <button
          :if={@schedule}
          type="button"
          id="delete-schedule"
          phx-click="delete_schedule"
          phx-target={@target}
          data-confirm={gettext("Delete it and the history of its runs?")}
          class="inline-flex h-9 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/40"
        >
          <Icons.trash class="h-4 w-4" /> <%= gettext("Delete") %>
        </button>
        <.link
          navigate={lotus_path("schedules")}
          class="inline-flex h-9 items-center rounded-lg bg-white px-3 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-200 dark:ring-gray-700 dark:hover:bg-gray-700"
        >
          <%= gettext("Cancel") %>
        </.link>
        <button
          type="submit"
          id="save-schedule"
          phx-disable-with={gettext("Saving…")}
          class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-pink-600 px-4 text-sm font-medium text-white shadow-sm hover:bg-pink-500"
        >
          <Icons.check class="h-4 w-4" />
          <%= cond do %>
            <% @schedule -> %><%= gettext("Save") %>
            <% @draft["alert"] == "true" -> %><%= gettext("Create alert") %>
            <% true -> %><%= gettext("Create report") %>
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  ## A section

  attr(:id, :string, required: true)
  attr(:step, :integer, required: true)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  slot(:aside)
  slot(:inner_block, required: true)

  defp section(assigns) do
    ~H"""
    <section id={@id} class="rounded-xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <header class="flex items-start gap-3 px-5 pt-4">
        <span class="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-pink-50 text-xs font-semibold text-pink-600 ring-1 ring-pink-100 dark:bg-pink-900/30 dark:text-pink-300 dark:ring-pink-900/50">
          <%= @step %>
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-semibold text-gray-900 dark:text-white"><%= @title %></h2>
          <p :if={@subtitle} class="text-xs text-gray-500 dark:text-gray-400"><%= @subtitle %></p>
        </div>
        <%= render_slot(@aside) %>
      </header>
      <div class="px-5 pb-5 pt-4"><%= render_slot(@inner_block) %></div>
    </section>
    """
  end

  ## 1. What to send

  attr(:draft, :map, required: true)
  attr(:target_entry, :any, required: true)
  attr(:picking, :boolean, required: true)
  attr(:search, :string, required: true)
  attr(:queries, :list, required: true)
  attr(:dashboards, :list, required: true)
  attr(:target, :any, required: true)

  defp what_section(assigns) do
    assigns =
      assign(assigns,
        found_queries: found(assigns.queries, assigns.search),
        found_dashboards: found(assigns.dashboards, assigns.search)
      )

    ~H"""
    <.section id="schedule-what" step={1} title={gettext("What to send")} subtitle={gettext("A query's results, or every card of a dashboard.")}>
      <input type="hidden" name="draft[target]" value={@draft["target"]} />

      <div
        :if={@target_entry && not @picking}
        id="schedule-target"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-gray-50/60 p-3 dark:border-gray-700 dark:bg-gray-900/40"
      >
        <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-white text-pink-600 shadow-sm ring-1 ring-gray-200 dark:bg-gray-800 dark:text-pink-400 dark:ring-gray-700">
          <Parts.target_icon kind={@target_entry.kind} class="h-5 w-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-medium text-gray-900 dark:text-white"><%= @target_entry.name %></p>
          <p class="truncate text-xs text-gray-500 dark:text-gray-400">
            <%= if @target_entry.kind == :query, do: gettext("Query"), else: gettext("Dashboard") %><span :if={@target_entry.description}> · <%= @target_entry.description %></span>
          </p>
        </div>
        <button
          type="button"
          id="change-target"
          phx-click="pick_target"
          phx-target={@target}
          class="rounded-md px-2.5 py-1.5 text-sm font-medium text-pink-600 hover:bg-pink-50 dark:text-pink-400 dark:hover:bg-pink-950/40"
        >
          <%= gettext("Change") %>
        </button>
      </div>

      <div :if={is_nil(@target_entry) or @picking} id="target-picker" class="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700">
        <div class="relative border-b border-gray-200 dark:border-gray-700">
          <Icons.magnifying_glass class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="search"
            id="target-search"
            name="target_search"
            value={@search}
            placeholder={gettext("Search your queries and dashboards…")}
            aria-label={gettext("Search your queries and dashboards")}
            autocomplete="off"
            phx-debounce="150"
            class="w-full border-0 bg-white py-2.5 pl-9 pr-3 text-sm placeholder:text-gray-400 focus:ring-0 dark:bg-gray-800 dark:text-white dark:placeholder:text-gray-500"
          />
        </div>
        <div class="max-h-72 overflow-y-auto py-1">
          <.target_group
            :if={@found_queries != []}
            label={gettext("Queries")}
            kind={:query}
            items={@found_queries}
            current={@draft["target"]}
            target={@target}
          />
          <.target_group
            :if={@found_dashboards != []}
            label={gettext("Dashboards")}
            kind={:dashboard}
            items={@found_dashboards}
            current={@draft["target"]}
            target={@target}
          />
          <p :if={@found_queries == [] and @found_dashboards == []} class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
            <%= gettext("Nothing has these words. Save a query or a dashboard first, then schedule it.") %>
          </p>
        </div>
      </div>
    </.section>
    """
  end

  attr(:label, :string, required: true)
  attr(:kind, :atom, required: true)
  attr(:items, :list, required: true)
  attr(:current, :string, required: true)
  attr(:target, :any, required: true)

  defp target_group(assigns) do
    ~H"""
    <p class="px-4 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-gray-400"><%= @label %></p>
    <button
      :for={item <- @items}
      type="button"
      id={"target-#{@kind}-#{item.id}"}
      phx-click="set_target"
      phx-value-target={"#{@kind}:#{item.id}"}
      phx-target={@target}
      class={[
        "flex w-full items-center gap-3 px-4 py-2 text-left hover:bg-pink-50/60 dark:hover:bg-pink-950/20",
        @current == "#{@kind}:#{item.id}" && "bg-pink-50 dark:bg-pink-950/30"
      ]}
    >
      <Parts.target_icon kind={@kind} class="h-4 w-4 shrink-0 text-gray-400" />
      <span class="min-w-0 flex-1">
        <span class="block truncate text-sm text-gray-900 dark:text-white"><%= item.name %></span>
        <span :if={description(item)} class="block truncate text-xs text-gray-500 dark:text-gray-400"><%= description(item) %></span>
      </span>
      <Icons.check :if={@current == "#{@kind}:#{item.id}"} class="h-4 w-4 text-pink-600" />
    </button>
    """
  end

  defp description(%{description: description}) when is_binary(description) and description != "",
    do: Lotus.Web.RichText.plain_text(description)

  defp description(_item), do: nil

  defp found(items, search) do
    words = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

    Enum.filter(items, fn item ->
      text = String.downcase("#{item.name} #{description(item)}")
      Enum.all?(words, &String.contains?(text, &1))
    end)
  end

  ## 2. When

  attr(:cadence, :map, required: true)
  attr(:cron_error, :any, required: true)
  attr(:zone, :map, required: true)
  attr(:zone_open, :boolean, required: true)
  attr(:zone_search, :string, required: true)
  attr(:viewer_zone, :any, required: true)
  attr(:target, :any, required: true)

  defp when_section(assigns) do
    ~H"""
    <.section id="schedule-when" step={2} title={gettext("When")} subtitle={gettext("How often it runs, at what time, and in which time zone.")}>
      <div class="space-y-5">
        <div class="flex flex-wrap gap-1 rounded-lg bg-gray-100 p-1 dark:bg-gray-900" role="radiogroup" aria-label={gettext("How often")}>
          <label
            :for={{value, label} <- frequencies()}
            class={[
              "flex-1 cursor-pointer whitespace-nowrap rounded-md px-3 py-1.5 text-center text-sm font-medium transition",
              @cadence["frequency"] == value && "bg-white text-gray-900 shadow-sm ring-1 ring-black/5 dark:bg-gray-700 dark:text-white",
              @cadence["frequency"] != value && "text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
            ]}
          >
            <input
              type="radio"
              id={"frequency-#{value}"}
              name="draft[cadence][frequency]"
              value={value}
              checked={@cadence["frequency"] == value}
              class="sr-only"
            />
            <%= label %>
          </label>
        </div>

        <.cadence_fields cadence={@cadence} cron_error={@cron_error} target={@target} />

        <div class="grid gap-4 sm:grid-cols-[11rem_minmax(0,1fr)]">
          <div :if={@cadence["frequency"] in ~w(daily weekly monthly)}>
            <span id="schedule-time-label" class="mb-1.5 block text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("At") %></span>
            <div class="lotus-time-field">
              <Koyomi.Components.time_picker
                id="schedule-time"
                name="draft[cadence][time]"
                value={time_value(@cadence["time"])}
                label_id="schedule-time-label"
                hour_cycle="h23"
                rules={Koyomi.Rules.new(step: 15)}
                locale={Gettext.get_locale(Lotus.Web.Gettext)}
              />
            </div>
          </div>
          <div class={[@cadence["frequency"] not in ~w(daily weekly monthly) && "sm:col-span-2"]}>
            <span class="mb-1.5 block text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("Time zone") %></span>
            <.zone_picker zone={@zone} open={@zone_open} search={@zone_search} viewer_zone={@viewer_zone} target={@target} />
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp frequencies do
    [
      {"minutes", gettext("Minutes")},
      {"hourly", gettext("Hourly")},
      {"daily", gettext("Daily")},
      {"weekly", gettext("Weekly")},
      {"monthly", gettext("Monthly")},
      {"custom", gettext("Custom")}
    ]
  end

  attr(:cadence, :map, required: true)
  attr(:cron_error, :any, required: true)
  attr(:target, :any, required: true)

  defp cadence_fields(%{cadence: %{"frequency" => "minutes"}} = assigns) do
    ~H"""
    <.field_row label={gettext("Every")}>
      <.choice_pills name="draft[cadence][every]" current={@cadence["every"]} options={for n <- Cadence.minute_steps(), do: {n, gettext("%{count} min", count: n)}} />
    </.field_row>
    """
  end

  defp cadence_fields(%{cadence: %{"frequency" => "hourly"}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.field_row label={gettext("Every")}>
        <.choice_pills
          name="draft[cadence][every]"
          current={@cadence["every"]}
          options={for n <- Cadence.hour_steps(), do: {n, ngettext("hour", "%{count} hours", String.to_integer(n))}}
        />
      </.field_row>
      <.field_row label={gettext("At minute")}>
        <.choice_pills
          name="draft[cadence][minute]"
          current={@cadence["minute"]}
          options={for m <- ~w(0 15 30 45), do: {m, ":" <> String.pad_leading(m, 2, "0")}}
        />
      </.field_row>
    </div>
    """
  end

  defp cadence_fields(%{cadence: %{"frequency" => "daily"}} = assigns) do
    ~H"""
    <.field_row label={gettext("On")}>
      <.choice_pills
        name="draft[cadence][weekdays]"
        current={@cadence["weekdays"]}
        options={[{"false", gettext("Every day")}, {"true", gettext("Weekdays only")}]}
      />
    </.field_row>
    """
  end

  defp cadence_fields(%{cadence: %{"frequency" => "weekly"}} = assigns) do
    ~H"""
    <.field_row label={gettext("On")}>
      <div class="flex flex-wrap gap-1.5" role="group" aria-label={gettext("Days of the week")}>
        <input type="hidden" name="draft[cadence][days][]" value="" />
        <label
          :for={day <- 1..7}
          title={Cadence.day_name(day)}
          class={[
            "flex h-9 w-11 cursor-pointer items-center justify-center rounded-lg text-sm font-medium ring-1 transition",
            to_string(day) in @cadence["days"] && "bg-pink-600 text-white ring-pink-600 shadow-sm shadow-pink-600/20",
            to_string(day) not in @cadence["days"] && "bg-white text-gray-600 ring-gray-300 hover:ring-gray-400 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600"
          ]}
        >
          <input
            type="checkbox"
            id={"day-#{day}"}
            name="draft[cadence][days][]"
            value={day}
            checked={to_string(day) in @cadence["days"]}
            class="sr-only"
          />
          <%= Cadence.day_initial(day) %>
        </label>
      </div>
    </.field_row>
    """
  end

  defp cadence_fields(%{cadence: %{"frequency" => "monthly"}} = assigns) do
    ~H"""
    <.field_row label={gettext("On")}>
      <div class="space-y-2">
        <label class={month_option_class(@cadence["month_mode"] == "day")}>
          <input type="radio" id="month-mode-day" name="draft[cadence][month_mode]" value="day" checked={@cadence["month_mode"] == "day"} class="text-pink-600 focus:ring-pink-500" />
          <span><%= gettext("Day") %></span>
          <select name="draft[cadence][month_day]" aria-label={gettext("Day of the month")} class={small_select_class()}>
            <option :for={day <- 1..31} value={day} selected={@cadence["month_day"] == to_string(day)}><%= day %></option>
          </select>
          <span class="text-xs text-gray-500 dark:text-gray-400" :if={@cadence["month_day"] in ~w(29 30 31)}><%= gettext("skips the months without it") %></span>
        </label>
        <label class={month_option_class(@cadence["month_mode"] == "last")}>
          <input type="radio" id="month-mode-last" name="draft[cadence][month_mode]" value="last" checked={@cadence["month_mode"] == "last"} class="text-pink-600 focus:ring-pink-500" />
          <span><%= gettext("The last day of the month") %></span>
        </label>
        <label class={month_option_class(@cadence["month_mode"] == "weekday")}>
          <input type="radio" id="month-mode-weekday" name="draft[cadence][month_mode]" value="weekday" checked={@cadence["month_mode"] == "weekday"} class="text-pink-600 focus:ring-pink-500" />
          <span><%= gettext("The") %></span>
          <select name="draft[cadence][ordinal]" aria-label={gettext("Which one")} class={small_select_class()}>
            <option :for={ordinal <- ~w(1 2 3 4 last)} value={ordinal} selected={@cadence["ordinal"] == ordinal}><%= Cadence.ordinal_name(ordinal) %></option>
          </select>
          <select name="draft[cadence][weekday]" aria-label={gettext("Day of the week")} class={small_select_class()}>
            <option :for={day <- 1..7} value={day} selected={@cadence["weekday"] == to_string(day)}><%= Cadence.day_name(day) %></option>
          </select>
        </label>
      </div>
    </.field_row>
    """
  end

  defp cadence_fields(assigns) do
    ~H"""
    <div class="space-y-3">
      <div>
        <label for="schedule-cron" class="mb-1.5 block text-xs font-medium text-gray-700 dark:text-gray-300">
          <%= gettext("Cron expression") %>
        </label>
        <input
          type="text"
          id="schedule-cron"
          name="draft[cadence][cron]"
          value={@cadence["cron"]}
          placeholder="0 9 * * 1-5"
          spellcheck="false"
          autocomplete="off"
          phx-debounce="250"
          class={[
            "w-full rounded-lg border bg-white px-3 py-2.5 font-mono text-base tracking-wider placeholder:text-gray-300 focus:ring-1 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500",
            @cron_error && "border-red-300 focus:border-red-500 focus:ring-red-500",
            is_nil(@cron_error) && "border-gray-300 focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600"
          ]}
        />
        <p class="mt-1.5 font-mono text-[11px] text-gray-400">
          <%= gettext("minute · hour · day of the month · month · day of the week") %>
        </p>
        <p :if={@cron_error} id="cron-error" class="mt-1.5 flex items-center gap-1.5 text-xs text-red-600 dark:text-red-400">
          <Icons.exclamation_circle class="h-3.5 w-3.5" /> <%= @cron_error %>
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-1.5">
        <span class="text-xs text-gray-500 dark:text-gray-400"><%= gettext("Examples:") %></span>
        <button
          :for={{cron, label} <- cron_examples()}
          type="button"
          phx-click="use_cron"
          phx-value-cron={cron}
          phx-target={@target}
          class="lotus-cron-example rounded-full border border-gray-200 bg-white px-2.5 py-0.5 text-xs text-gray-600 hover:border-pink-300 hover:text-pink-700 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
          title={cron}
        >
          <%= label %>
        </button>
      </div>
    </div>
    """
  end

  defp cron_examples do
    [
      {"0 9,17 * * 1-5", gettext("09:00 and 17:00 on weekdays")},
      {"0 8-18 * * 1-5", gettext("Every hour of the working day")},
      {"0 7 1,15 * *", gettext("The 1st and 15th at 07:00")},
      {"0 6 1 1,4,7,10 *", gettext("Each quarter")}
    ]
  end

  defp month_option_class(checked),
    do: [
      "flex flex-wrap cursor-pointer items-center gap-2.5 rounded-lg border px-3 py-2 text-sm text-gray-700 dark:text-gray-200",
      checked && "border-pink-300 bg-pink-50/50 dark:border-pink-800 dark:bg-pink-950/20",
      not checked && "border-gray-200 hover:border-gray-300 dark:border-gray-700"
    ]

  defp small_select_class,
    do:
      "rounded-md border-gray-300 bg-white py-1 pl-2 pr-7 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  defp field_row(assigns) do
    ~H"""
    <div class="grid items-start gap-2 sm:grid-cols-[5.5rem_minmax(0,1fr)] sm:gap-4">
      <span class="pt-2 text-xs font-medium text-gray-700 dark:text-gray-300"><%= @label %></span>
      <div><%= render_slot(@inner_block) %></div>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:current, :string, required: true)
  attr(:options, :list, required: true)

  defp choice_pills(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5" role="radiogroup">
      <label
        :for={{value, label} <- @options}
        class={[
          "cursor-pointer rounded-lg px-3 py-1.5 text-sm font-medium ring-1 transition",
          @current == value && "bg-pink-600 text-white ring-pink-600 shadow-sm shadow-pink-600/20",
          @current != value && "bg-white text-gray-600 ring-gray-300 hover:ring-gray-400 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600"
        ]}
      >
        <input type="radio" name={@name} value={value} checked={@current == value} class="sr-only" />
        <%= label %>
      </label>
    </div>
    """
  end

  attr(:zone, :map, required: true)
  attr(:open, :boolean, required: true)
  attr(:search, :string, required: true)
  attr(:viewer_zone, :any, required: true)
  attr(:target, :any, required: true)

  defp zone_picker(assigns) do
    assigns =
      assign(assigns,
        found: if(assigns.open, do: TimeZones.search(assigns.search), else: []),
        viewer:
          assigns.viewer_zone && assigns.viewer_zone != assigns.zone.name &&
            TimeZones.entry(assigns.viewer_zone)
      )

    ~H"""
    <div id="zone-picker" class="relative" phx-click-away={@open && "close_zones"} phx-target={@target}>
      <input type="hidden" name="draft[time_zone]" value={@zone.name} />
      <button
        type="button"
        id="zone-button"
        phx-click="toggle_zones"
        phx-target={@target}
        aria-haspopup="listbox"
        aria-expanded={to_string(@open)}
        class="flex h-10 w-full items-center gap-3 rounded-lg border border-gray-300 bg-white px-3 text-left hover:border-gray-400 focus:border-pink-500 focus:outline-none focus:ring-1 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700"
      >
        <Icons.globe class="h-4 w-4 shrink-0 text-gray-400" />
        <span class="min-w-0 flex-1 truncate text-sm">
          <span class="font-medium text-gray-900 dark:text-white"><%= @zone.city %></span>
          <span class="text-gray-500 dark:text-gray-400"> · <%= @zone.region %></span>
        </span>
        <span class="shrink-0 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[11px] text-gray-600 dark:bg-gray-800 dark:text-gray-300"><%= @zone.offset_label %></span>
        <span class="hidden shrink-0 text-xs text-gray-400 sm:inline"><%= gettext("%{time} now", time: @zone.now) %></span>
        <Icons.chevron_down class="h-4 w-4 shrink-0 text-gray-400" />
      </button>
      <button
        :if={@viewer && not @open}
        type="button"
        id="use-my-zone"
        phx-click="set_zone"
        phx-value-zone={@viewer.name}
        phx-target={@target}
        class="mt-1.5 text-xs text-pink-600 hover:text-pink-700 dark:text-pink-400"
      >
        <%= gettext("Use my time zone (%{city}, %{offset})", city: @viewer.city, offset: @viewer.offset_label) %>
      </button>

      <div
        :if={@open}
        id="zone-list"
        class="absolute z-30 mt-1 w-full overflow-hidden rounded-lg bg-white shadow-xl ring-1 ring-black/10 dark:bg-gray-800 dark:ring-white/10"
      >
        <div class="relative border-b border-gray-100 dark:border-gray-700">
          <Icons.magnifying_glass class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="search"
            id="zone-search"
            name="zone_search"
            value={@search}
            placeholder={gettext("Search a city, a region or UTC+2…")}
            aria-label={gettext("Search time zones")}
            autocomplete="off"
            phx-debounce="100"
            phx-mounted={JS.focus()}
            class="w-full border-0 bg-transparent py-2.5 pl-9 pr-3 text-sm placeholder:text-gray-400 focus:ring-0 dark:text-white dark:placeholder:text-gray-500"
          />
        </div>
        <ul class="max-h-72 overflow-y-auto py-1" role="listbox">
          <li :if={@viewer && @search == ""}>
            <.zone_option zone={@viewer} current={@zone.name} hint={gettext("Your time zone")} target={@target} />
          </li>
          <li :for={zone <- @found}>
            <.zone_option zone={zone} current={@zone.name} target={@target} />
          </li>
          <li :if={@found == []} class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
            <%= gettext("No time zone matches. Type an IANA name, such as America/Halifax.") %>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr(:zone, :map, required: true)
  attr(:current, :string, required: true)
  attr(:hint, :string, default: nil)
  attr(:target, :any, required: true)

  defp zone_option(assigns) do
    ~H"""
    <button
      type="button"
      id={"zone-#{String.replace(@zone.name, ~r/[^A-Za-z0-9]/, "-")}#{@hint && "-mine"}"}
      phx-click="set_zone"
      phx-value-zone={@zone.name}
      phx-target={@target}
      role="option"
      aria-selected={to_string(@zone.name == @current)}
      class={[
        "flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-pink-50/70 dark:hover:bg-pink-950/20",
        @zone.name == @current && "bg-pink-50 dark:bg-pink-950/30"
      ]}
    >
      <span class="w-[4.75rem] shrink-0 font-mono text-[11px] text-gray-500 dark:text-gray-400"><%= @zone.offset_label %></span>
      <span class="min-w-0 flex-1">
        <span class="block truncate text-sm text-gray-900 dark:text-white"><%= @zone.city %></span>
        <span class="block truncate text-xs text-gray-500 dark:text-gray-400"><%= @hint || @zone.region %></span>
      </span>
      <span class="shrink-0 text-xs tabular-nums text-gray-400"><%= @zone.now %></span>
      <Icons.check :if={@zone.name == @current} class="h-4 w-4 shrink-0 text-pink-600" />
    </button>
    """
  end

  ## 3. Deliver to

  attr(:deliveries, :list, required: true)
  attr(:channels, :list, required: true)
  attr(:formats, :list, required: true)
  attr(:target, :any, required: true)

  defp deliver_section(assigns) do
    ~H"""
    <.section id="schedule-deliver" step={3} title={gettext("Deliver to")} subtitle={gettext("Where each run's results go. Without a destination, runs are only recorded.")}>
      <div class="space-y-3">
        <div
          :for={{delivery, index} <- Enum.with_index(@deliveries)}
          id={"delivery-#{index}"}
          class="rounded-lg border border-gray-200 dark:border-gray-700"
        >
          <div class="flex flex-wrap items-center gap-3 border-b border-gray-100 px-3 py-2 dark:border-gray-700">
            <span class="flex h-7 w-7 items-center justify-center rounded-md bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300">
              <Icons.link_icon :if={delivery["channel"] == "webhook"} class="h-4 w-4" />
              <Icons.send :if={delivery["channel"] != "webhook"} class="h-4 w-4" />
            </span>
            <select
              :if={length(@channels) > 1}
              name={"draft[deliveries][#{index}][channel]"}
              aria-label={gettext("Channel")}
              class="rounded-md border-0 bg-transparent py-1 pl-1 pr-7 text-sm font-medium text-gray-900 focus:ring-2 focus:ring-pink-500 dark:text-white"
            >
              <option :for={channel <- @channels} value={channel} selected={delivery["channel"] == channel}><%= channel_label(channel) %></option>
            </select>
            <span :if={length(@channels) <= 1} class="text-sm font-medium text-gray-900 dark:text-white">
              <input type="hidden" name={"draft[deliveries][#{index}][channel]"} value={delivery["channel"]} />
              <%= channel_label(delivery["channel"]) %>
            </span>
            <div class="flex-1"></div>
            <div class="inline-flex rounded-md bg-gray-100 p-0.5 dark:bg-gray-900" role="radiogroup" aria-label={gettext("Format")}>
              <label
                :for={format <- @formats}
                class={[
                  "cursor-pointer rounded px-2.5 py-1 font-mono text-xs uppercase",
                  delivery["format"] == format && "bg-white text-gray-900 shadow-sm dark:bg-gray-700 dark:text-white",
                  delivery["format"] != format && "text-gray-500 hover:text-gray-800 dark:text-gray-400"
                ]}
              >
                <input type="radio" name={"draft[deliveries][#{index}][format]"} value={format} checked={delivery["format"] == format} class="sr-only" />
                <%= format %>
              </label>
            </div>
            <button
              type="button"
              id={"remove-delivery-#{index}"}
              phx-click="remove_delivery"
              phx-value-index={index}
              phx-target={@target}
              aria-label={gettext("Remove this destination")}
              title={gettext("Remove this destination")}
              class="rounded-md p-1.5 text-gray-400 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950/40"
            >
              <Icons.trash class="h-4 w-4" />
            </button>
          </div>
          <div class="space-y-3 p-3">
            <%= if delivery["channel"] == "webhook" do %>
              <label class="block">
                <span class="mb-1 block text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("URL") %></span>
                <input
                  type="url"
                  name={"draft[deliveries][#{index}][url]"}
                  value={delivery["url"]}
                  placeholder="https://"
                  autocomplete="off"
                  class={input_class()}
                />
                <span class="mt-1 block text-xs text-gray-500 dark:text-gray-400">
                  <%= gettext("Lotus POSTs JSON with the results attached as a %{format} file. Any 2xx answer counts as delivered.", format: String.upcase(delivery["format"] || "")) %>
                </span>
              </label>
              <label class="block">
                <span class="mb-1 block text-xs font-medium text-gray-700 dark:text-gray-300">
                  <%= gettext("Authorization header") %> <span class="font-normal text-gray-400"><%= gettext("optional") %></span>
                </span>
                <input
                  type="text"
                  name={"draft[deliveries][#{index}][authorization]"}
                  value={delivery["authorization"]}
                  placeholder="Bearer …"
                  autocomplete="off"
                  class={[input_class(), "font-mono"]}
                />
              </label>
            <% else %>
              <label class="block">
                <span class="mb-1 block text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("Settings, as JSON") %></span>
                <textarea
                  name={"draft[deliveries][#{index}][config]"}
                  rows="3"
                  placeholder={~s({"to": ["team@example.com"]})}
                  class={[input_class(), "font-mono text-xs"]}
                ><%= delivery["config"] %></textarea>
                <span class="mt-1 block text-xs text-gray-500 dark:text-gray-400">
                  <%= gettext("What the %{channel} channel needs; its documentation lists them.", channel: channel_label(delivery["channel"])) %>
                </span>
              </label>
            <% end %>
          </div>
        </div>

        <button
          type="button"
          id="add-delivery"
          phx-click="add_delivery"
          phx-target={@target}
          class="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-300 px-4 py-3 text-sm font-medium text-gray-600 hover:border-pink-400 hover:bg-pink-50/40 hover:text-pink-600 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-pink-950/20"
        >
          <Icons.plus class="h-4 w-4" />
          <%= if @deliveries == [], do: gettext("Add a destination"), else: gettext("Add another destination") %>
        </button>
      </div>
    </.section>
    """
  end

  defp channel_label("webhook"), do: gettext("Webhook")

  defp channel_label(channel),
    do: channel |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp input_class,
    do:
      "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:border-pink-500 focus:ring-1 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"

  ## 4. Alert

  attr(:draft, :map, required: true)
  attr(:conditions, :list, required: true)
  attr(:target_entry, :any, required: true)

  defp alert_section(assigns) do
    assigns =
      assign(assigns,
        query?: match?(%{kind: :query}, assigns.target_entry),
        on?: assigns.draft["alert"] == "true",
        compared?: assigns.draft["condition"] in ~w(above below equals)
      )

    ~H"""
    <.section id="schedule-alert" step={4} title={gettext("Make it an alert")} subtitle={gettext("Send only when the result crosses a line, instead of on every run.")}>
      <:aside>
        <label :if={@query?} class="flex cursor-pointer items-center">
          <input type="hidden" name="draft[alert]" value="false" />
          <input type="checkbox" id="schedule-alert-toggle" name="draft[alert]" value="true" checked={@on?} class="peer sr-only" aria-label={gettext("Alert")} />
          <span class="relative inline-flex h-5 w-9 shrink-0 rounded-full bg-gray-200 transition-colors peer-checked:bg-pink-600 peer-focus-visible:ring-2 peer-focus-visible:ring-pink-500 peer-focus-visible:ring-offset-2 dark:bg-gray-600 [&>span]:peer-checked:translate-x-4">
            <span class="pointer-events-none absolute left-0.5 top-0.5 inline-block h-4 w-4 rounded-full bg-white shadow transition"></span>
          </span>
        </label>
      </:aside>

      <p :if={not @query?} class="text-sm text-gray-500 dark:text-gray-400">
        <%= gettext("An alert reads a query's result. Choose a query above to add one.") %>
      </p>

      <p :if={@query? and not @on?} class="text-sm text-gray-500 dark:text-gray-400">
        <%= gettext("Off: every run sends its results.") %>
      </p>

      <div :if={@query? and @on?} class="space-y-4">
        <div class="flex flex-wrap items-center gap-2 rounded-lg bg-gray-50 p-3 text-sm text-gray-700 dark:bg-gray-900/50 dark:text-gray-200">
          <span><%= gettext("Send when") %></span>
          <input
            :if={@compared?}
            type="text"
            id="alert-column"
            name="draft[column]"
            value={@draft["column"]}
            placeholder={gettext("the row count")}
            aria-label={gettext("Column")}
            autocomplete="off"
            class="w-40 rounded-md border-gray-300 bg-white px-2 py-1 font-mono text-sm placeholder:font-sans placeholder:text-gray-400 focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          />
          <span :if={not @compared?}><%= gettext("the result") %></span>
          <select name="draft[condition]" id="alert-condition" aria-label={gettext("Condition")} class={small_select_class()}>
            <option :for={condition <- @conditions} value={condition} selected={@draft["condition"] == condition}><%= condition_label(condition) %></option>
          </select>
          <input
            :if={@compared?}
            type="text"
            inputmode="decimal"
            id="alert-threshold"
            name="draft[threshold]"
            value={@draft["threshold"]}
            placeholder="1000"
            aria-label={gettext("Threshold")}
            autocomplete="off"
            class="w-28 rounded-md border-gray-300 bg-white px-2 py-1 font-mono text-sm placeholder:text-gray-300 focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          />
        </div>
        <p :if={@compared?} class="text-xs text-gray-500 dark:text-gray-400">
          <%= gettext("A column's value in the first row, or the number of rows when no column is named.") %>
        </p>
        <label class="flex items-start gap-2.5 text-sm text-gray-700 dark:text-gray-300">
          <input type="hidden" name="draft[notify_recovery]" value="false" />
          <input type="checkbox" id="alert-recovery" name="draft[notify_recovery]" value="true" checked={@draft["notify_recovery"] != "false"} class="mt-0.5 rounded text-pink-600 focus:ring-pink-500" />
          <span>
            <%= gettext("Also send when it's back to normal") %>
            <span class="block text-xs text-gray-500 dark:text-gray-400"><%= gettext("Lotus sends once when the alert starts firing, and once when it recovers; not on every run.") %></span>
          </span>
        </label>
      </div>
    </.section>
    """
  end

  defp condition_label("above"), do: gettext("is above")
  defp condition_label("below"), do: gettext("is below")
  defp condition_label("equals"), do: gettext("equals")
  defp condition_label("any_rows"), do: gettext("has any rows")
  defp condition_label("no_rows"), do: gettext("has no rows")
  defp condition_label(name), do: name |> String.replace("_", " ")

  ## The summary

  attr(:draft, :map, required: true)
  attr(:cron, :string, required: true)
  attr(:cron_error, :any, required: true)
  attr(:zone, :map, required: true)
  attr(:next_runs, :list, required: true)
  attr(:viewer_zone, :any, required: true)
  attr(:target_entry, :any, required: true)

  defp summary(assigns) do
    assigns =
      assign(assigns,
        sentence: Cadence.sentence(assigns.draft["cadence"]),
        show_viewer?: assigns.viewer_zone && assigns.viewer_zone != assigns.zone.name
      )

    ~H"""
    <section id="schedule-summary" class="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <div class="bg-gradient-to-br from-pink-50 via-white to-white px-5 pb-4 pt-5 dark:from-pink-950/30 dark:via-gray-800 dark:to-gray-800">
        <p class="text-[11px] font-semibold uppercase tracking-wide text-pink-600 dark:text-pink-400">
          <%= if @draft["alert"] == "true", do: gettext("Checks"), else: gettext("Sends") %>
        </p>
        <p id="schedule-sentence" class="mt-1 text-lg font-semibold leading-snug text-gray-900 dark:text-white">
          <%= if @cron_error, do: gettext("Not a valid schedule yet"), else: @sentence %>
        </p>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("%{city} time (%{offset})", city: @zone.city, offset: @zone.offset_label) %>
        </p>
        <p class="mt-2 inline-block rounded bg-white/80 px-1.5 py-0.5 font-mono text-[11px] text-gray-500 ring-1 ring-gray-200 dark:bg-gray-900/60 dark:text-gray-400 dark:ring-gray-700" title={gettext("The cron expression Lotus stores")}>
          <%= @cron %>
        </p>
      </div>

      <div class="border-t border-gray-100 px-5 py-4 dark:border-gray-700">
        <p class="mb-2 text-xs font-medium text-gray-500 dark:text-gray-400"><%= gettext("Next runs") %></p>
        <ol :if={@next_runs != []} id="next-runs" class="space-y-1.5">
          <li :for={{at, index} <- Enum.with_index(@next_runs)} class="flex items-baseline justify-between gap-3 text-sm">
            <span class="text-gray-900 dark:text-white">
              <%= local(at, @zone.name, "%a, %b %-d") %>
              <span class="font-mono tabular-nums text-gray-600 dark:text-gray-300"><%= local(at, @zone.name, "%H:%M") %></span>
              <span :if={@show_viewer?} class="block text-xs text-gray-400">
                <%= gettext("%{time} your time", time: local(at, @viewer_zone, "%a %H:%M")) %>
              </span>
            </span>
            <time
              :if={index == 0}
              id="next-run-relative"
              phx-hook="RelativeTime"
              datetime={DateTime.to_iso8601(at)}
              class="shrink-0 rounded-full bg-pink-50 px-2 py-0.5 text-[11px] font-medium text-pink-700 dark:bg-pink-900/30 dark:text-pink-300"
            ></time>
          </li>
        </ol>
        <p :if={@next_runs == []} class="text-sm text-gray-400"><%= gettext("Choose when it runs to see the next runs.") %></p>
      </div>

      <dl class="space-y-3 border-t border-gray-100 px-5 py-4 text-sm dark:border-gray-700">
        <div class="flex items-start gap-3">
          <dt class="sr-only"><%= gettext("What") %></dt>
          <Parts.target_icon kind={(@target_entry && @target_entry.kind) || :query} class="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />
          <dd class={["min-w-0 truncate", @target_entry && "text-gray-900 dark:text-white", !@target_entry && "text-gray-400"]}>
            <%= (@target_entry && @target_entry.name) || gettext("Nothing chosen yet") %>
          </dd>
        </div>
        <div class="flex items-start gap-3">
          <dt class="sr-only"><%= gettext("Where") %></dt>
          <Icons.send class="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />
          <dd class="min-w-0 text-gray-700 dark:text-gray-300">
            <%= case @draft["deliveries"] do %>
              <% [] -> %><span class="text-gray-400"><%= gettext("Recorded only, sent nowhere") %></span>
              <% deliveries -> %><%= deliveries |> Enum.map(&delivery_label/1) |> Enum.join(", ") %>
            <% end %>
          </dd>
        </div>
        <div :if={@draft["alert"] == "true" and match?(%{kind: :query}, @target_entry)} class="flex items-start gap-3">
          <dt class="sr-only"><%= gettext("Alert") %></dt>
          <Icons.exclamation_triangle class="mt-0.5 h-4 w-4 shrink-0 text-amber-500" />
          <dd class="min-w-0 text-gray-700 dark:text-gray-300"><%= alert_sentence(@draft) %></dd>
        </div>
      </dl>
    </section>
    """
  end

  defp delivery_label(%{"channel" => "webhook", "url" => url, "format" => format}) do
    host =
      case URI.parse(url || "") do
        %URI{host: host} when is_binary(host) and host != "" -> host
        _ -> gettext("a webhook")
      end

    "#{host} (#{String.upcase(format || "")})"
  end

  defp delivery_label(%{"channel" => channel, "format" => format}),
    do: "#{channel_label(channel)} (#{String.upcase(format || "")})"

  defp alert_sentence(%{"condition" => condition} = draft)
       when condition in ~w(above below equals) do
    subject = blank(draft["column"]) || gettext("the row count")

    gettext("Only when %{subject} %{condition} %{threshold}",
      subject: subject,
      condition: condition_label(condition),
      threshold: blank(draft["threshold"]) || "…"
    )
  end

  defp alert_sentence(draft),
    do:
      gettext("Only when the result %{condition}", condition: condition_label(draft["condition"]))

  ## The runs

  attr(:schedule, :map, required: true)
  attr(:runs, :list, required: true)

  defp runs(assigns) do
    ~H"""
    <section id="schedule-runs" class="rounded-xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <header class="flex items-center justify-between px-5 pt-4">
        <h2 class="text-sm font-semibold text-gray-900 dark:text-white"><%= gettext("Latest runs") %></h2>
        <Parts.run_dots runs={Enum.reverse(@runs)} />
      </header>
      <p :if={@runs == []} class="px-5 pb-5 pt-3 text-sm text-gray-500 dark:text-gray-400"><%= gettext("It has not run yet.") %></p>
      <ol :if={@runs != []} class="relative mt-3 px-5 pb-4">
        <li :for={run <- @runs} id={"run-#{run.id}"} class="relative flex gap-3 pb-3 last:pb-0">
          <span class={["relative z-10 mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ring-4 ring-white dark:ring-gray-800", Parts.run_color(run.status)]}></span>
          <div class="min-w-0 flex-1">
            <p class="flex flex-wrap items-baseline gap-x-2 text-sm">
              <span class="text-gray-900 dark:text-white"><%= Calendar.strftime(run.scheduled_for, "%Y-%m-%d %H:%M UTC") %></span>
              <span class={["text-xs font-medium", run_text(run.status)]}><%= run_status(run.status) %></span>
            </p>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              <span :if={run.row_count}><%= ngettext("1 row", "%{count} rows", run.row_count) %></span>
              <span :if={duration(run)}> · <%= duration(run) %></span>
            </p>
            <p :if={run.error} class="mt-1 break-words rounded-md bg-red-50 px-2 py-1 font-mono text-xs text-red-700 dark:bg-red-950/40 dark:text-red-300"><%= run.error %></p>
          </div>
        </li>
      </ol>
    </section>
    """
  end

  defp run_status("succeeded"), do: gettext("Succeeded")
  defp run_status("failed"), do: gettext("Failed")
  defp run_status("running"), do: gettext("Running")
  defp run_status(_pending), do: gettext("Pending")

  defp run_text("succeeded"), do: "text-green-700 dark:text-green-400"
  defp run_text("failed"), do: "text-red-600 dark:text-red-400"
  defp run_text(_status), do: "text-gray-500"

  defp duration(%{started_at: %DateTime{} = started, finished_at: %DateTime{} = finished}) do
    ms = DateTime.diff(finished, started, :millisecond)
    if ms < 1000, do: "#{ms} ms", else: "#{Float.round(ms / 1000, 1)} s"
  end

  defp duration(_run), do: nil

  defp local(at, zone, format) do
    case DateTime.shift_zone(at, zone, Cron.database()) do
      {:ok, local} -> Calendar.strftime(local, format)
      _error -> Calendar.strftime(at, format)
    end
  end

  defp time_value(text) do
    {hour, minute} = Cadence.time(text)

    String.pad_leading("#{hour}", 2, "0") <>
      ":" <> String.pad_leading("#{minute}", 2, "0") <> ":00"
  end

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp cron_error(cron) do
    case Cadence.validate(cron) do
      :ok -> nil
      {:error, message} -> gettext("Not a cron expression: %{message}", message: message)
    end
  end

  defp target_entry("query:" <> id, queries, _dashboards), do: find_target(:query, id, queries)

  defp target_entry("dashboard:" <> id, _queries, dashboards),
    do: find_target(:dashboard, id, dashboards)

  defp target_entry(_target, _queries, _dashboards), do: nil

  defp find_target(kind, id, items) do
    case Enum.find(items, &(to_string(&1.id) == id)) do
      nil -> nil
      item -> %{kind: kind, id: item.id, name: item.name, description: description(item)}
    end
  end

  ## Mount and params

  @impl Page
  def handle_mount(socket) do
    info = Pro.request_info(socket.assigns)

    viewer_zone =
      if Phoenix.LiveView.connected?(socket) do
        zone = Phoenix.LiveView.get_connect_params(socket)["time_zone"]
        if Cron.valid_time_zone?(zone), do: zone
      end

    assign(socket,
      schedule: nil,
      draft: new_draft(%{}, viewer_zone),
      errors: [],
      runs: [],
      picking: false,
      target_search: "",
      zone_open: false,
      zone_search: "",
      viewer_zone: viewer_zone,
      queries: Pro.list_queries(info),
      dashboards: Pro.list_dashboards(info),
      channels: Lotus.Delivery.channels() |> Map.keys() |> Enum.sort(),
      formats: Lotus.Delivery.formats() |> Map.keys() |> Enum.sort(),
      conditions: Alert.conditions()
    )
  end

  # A new schedule takes `?query_id=` or `?dashboard_id=` (the query editor
  # and a dashboard link here) and `?cron=` and `?alert=` (the templates of
  # the empty list).
  @impl Page
  def handle_params(params, _uri, socket) do
    case socket.assigns.page do
      %{mode: :edit, id: id} ->
        case Schedules.get_schedule(id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("This report or alert does not exist."))
             |> push_navigate(to: lotus_path("schedules"))}

          schedule ->
            {:noreply,
             assign(socket,
               schedule: schedule,
               draft: draft(schedule),
               runs: Schedules.list_runs(schedule, limit: @runs),
               errors: []
             )}
        end

      _new ->
        {:noreply,
         assign(socket,
           schedule: nil,
           draft: new_draft(params, socket.assigns.viewer_zone),
           runs: [],
           errors: []
         )}
    end
  end

  @impl Page
  def handle_info(_message, socket), do: {:noreply, socket}

  # The draft is the page's own once mounted: a render of the LiveView does
  # not put it back.
  @owned [:draft, :errors, :picking, :target_search, :zone_open, :zone_search, :schedule, :runs]

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    assigns =
      if Map.has_key?(socket.assigns, :draft) and socket.assigns[:page] == assigns[:page],
        do: Map.drop(assigns, @owned),
        else: assigns

    {:ok, assign(socket, assigns)}
  end

  ## Events

  @impl Phoenix.LiveComponent
  def handle_event("change_draft", params, socket) do
    socket =
      socket
      |> assign(draft: merge_draft(socket.assigns.draft, params["draft"] || %{}))
      |> assign_searches(params)

    {:noreply, socket}
  end

  def handle_event("pick_target", _params, socket),
    do: {:noreply, assign(socket, picking: true, target_search: "")}

  def handle_event("set_target", %{"target" => target}, socket) do
    draft = %{socket.assigns.draft | "target" => target}

    # A dashboard has no alert: an alert reads a query's result.
    draft =
      if String.starts_with?(target, "dashboard:"), do: %{draft | "alert" => "false"}, else: draft

    draft =
      if blank(draft["name"]),
        do: draft,
        else: %{draft | "name" => suggested_name(target, socket.assigns)}

    {:noreply, assign(socket, draft: draft, picking: false, target_search: "")}
  end

  def handle_event("toggle_zones", _params, socket),
    do: {:noreply, assign(socket, zone_open: not socket.assigns.zone_open, zone_search: "")}

  def handle_event("close_zones", _params, socket),
    do: {:noreply, assign(socket, zone_open: false, zone_search: "")}

  def handle_event("set_zone", %{"zone" => zone}, socket) do
    if Cron.valid_time_zone?(zone),
      do:
        {:noreply,
         assign(socket,
           draft: %{socket.assigns.draft | "time_zone" => zone},
           zone_open: false,
           zone_search: ""
         )},
      else: {:noreply, socket}
  end

  def handle_event("use_cron", %{"cron" => cron}, socket) do
    cadence = %{socket.assigns.draft["cadence"] | "cron" => cron, "frequency" => "custom"}
    {:noreply, assign(socket, draft: %{socket.assigns.draft | "cadence" => cadence})}
  end

  def handle_event("add_delivery", _params, socket) do
    draft = socket.assigns.draft

    format =
      if "csv" in socket.assigns.formats, do: "csv", else: List.first(socket.assigns.formats)

    channel =
      if "webhook" in socket.assigns.channels,
        do: "webhook",
        else: List.first(socket.assigns.channels)

    delivery = %{
      "channel" => channel,
      "format" => format,
      "url" => "",
      "authorization" => "",
      "config" => "",
      "extra" => %{}
    }

    {:noreply,
     assign(socket, draft: %{draft | "deliveries" => draft["deliveries"] ++ [delivery]})}
  end

  def handle_event("remove_delivery", %{"index" => index}, socket) do
    draft = socket.assigns.draft
    deliveries = List.delete_at(draft["deliveries"], String.to_integer(index))
    {:noreply, assign(socket, draft: %{draft | "deliveries" => deliveries})}
  end

  def handle_event("save_schedule", params, socket) do
    manage(socket, fn ->
      draft = merge_draft(socket.assigns.draft, params["draft"] || %{})

      case save(draft, socket.assigns) do
        {:ok, _schedule} ->
          socket
          |> put_flash(:info, saved_message(draft))
          |> push_navigate(to: lotus_path("schedules"))

        {:error, errors} ->
          assign(socket, draft: draft, errors: errors)
      end
    end)
  end

  def handle_event("delete_schedule", _params, socket) do
    manage(socket, fn ->
      case socket.assigns.schedule do
        %Schedule{} = schedule ->
          Schedules.delete_schedule(schedule, actor(socket))

          socket
          |> put_flash(:info, gettext("Deleted."))
          |> push_navigate(to: lotus_path("schedules"))

        nil ->
          socket
      end
    end)
  end

  defp saved_message(%{"alert" => "true"}), do: gettext("Alert saved.")
  defp saved_message(_draft), do: gettext("Report saved.")

  defp assign_searches(socket, params) do
    socket
    |> then(
      &if(Map.has_key?(params, "target_search"),
        do: assign(&1, target_search: params["target_search"]),
        else: &1
      )
    )
    |> then(
      &if(Map.has_key?(params, "zone_search"),
        do: assign(&1, zone_search: params["zone_search"]),
        else: &1
      )
    )
  end

  defp suggested_name(target, assigns) do
    case target_entry(target, assigns.queries, assigns.dashboards) do
      nil -> ""
      entry -> entry.name
    end
  end

  # Saving and deleting asks for :manage_schedule, in the handler too, so a
  # crafted event is refused.
  defp manage(socket, fun) do
    case Authorization.authorize(socket.assigns, :manage_schedule, nil) do
      :allow -> {:noreply, fun.()}
      {:deny, reason} -> {:noreply, put_flash(socket, :error, reason)}
    end
  end

  defp actor(socket), do: Actor.opts(socket.assigns)

  ## The draft: the form's fields as strings, as the form sends them

  defp new_draft(params, viewer_zone) do
    target =
      case params do
        %{"query_id" => id} -> "query:#{id}"
        %{"dashboard_id" => id} -> "dashboard:#{id}"
        _ -> ""
      end

    cadence =
      case params do
        %{"cron" => cron} when is_binary(cron) -> Cadence.from_cron(cron)
        _ -> Cadence.default()
      end

    %{
      "name" => "",
      "target" => target,
      "cadence" => cadence,
      "time_zone" => viewer_zone || "Etc/UTC",
      "enabled" => "true",
      "deliveries" => [],
      "alert" =>
        if(params["alert"] == "true" and not String.starts_with?(target, "dashboard:"),
          do: "true",
          else: "false"
        ),
      "condition" => "above",
      "column" => "",
      "threshold" => "",
      "notify_recovery" => "true"
    }
  end

  defp draft(%Schedule{} = schedule) do
    Map.merge(
      %{
        "name" => schedule.name,
        "target" => draft_target(schedule),
        "cadence" => Cadence.from_cron(schedule.cron),
        "time_zone" => schedule.time_zone,
        "enabled" => to_string(schedule.enabled),
        "deliveries" => Enum.map(schedule.deliveries, &draft_delivery/1)
      },
      draft_rule(schedule.rule)
    )
  end

  defp draft_target(%Schedule{query_id: nil, dashboard_id: id}), do: "dashboard:#{id}"
  defp draft_target(%Schedule{query_id: id}), do: "query:#{id}"

  defp draft_delivery(delivery) do
    config = delivery.config || %{}
    headers = config["headers"] || %{}

    %{
      "channel" => delivery.channel,
      "format" => delivery.format,
      "url" => config["url"] || "",
      "authorization" => headers["authorization"] || headers["Authorization"] || "",
      "config" => if(config == %{}, do: "", else: Lotus.JSON.encode!(config)),
      # A webhook's settings that the form does not show are kept.
      "extra" => Map.drop(config, ["url"])
    }
  end

  defp draft_rule(nil),
    do: %{
      "alert" => "false",
      "condition" => "above",
      "column" => "",
      "threshold" => "",
      "notify_recovery" => "true"
    }

  defp draft_rule(rule) do
    %{
      "alert" => "true",
      "condition" => rule.condition,
      "column" => rule.column || "",
      "threshold" => if(rule.threshold, do: Decimal.to_string(rule.threshold, :normal), else: ""),
      "notify_recovery" => to_string(rule.notify_recovery)
    }
  end

  defp merge_draft(draft, params) do
    deliveries =
      case params["deliveries"] do
        %{} = by_index ->
          by_index
          |> Enum.sort_by(fn {index, _delivery} -> String.to_integer(index) end)
          |> Enum.map(fn {index, delivery} ->
            previous = Enum.at(draft["deliveries"], String.to_integer(index)) || %{}

            Map.merge(
              %{"url" => "", "authorization" => "", "config" => "", "extra" => %{}},
              Map.merge(previous, delivery)
            )
          end)

        _none ->
          draft["deliveries"]
      end

    cadence =
      case params["cadence"] do
        %{} = cadence -> Cadence.merge(draft["cadence"], cadence)
        _none -> draft["cadence"]
      end

    draft
    |> Map.merge(
      Map.take(
        params,
        ~w(name target time_zone enabled alert condition column threshold notify_recovery)
      )
    )
    |> Map.put("deliveries", deliveries)
    |> Map.put("cadence", cadence)
  end

  defp save(draft, assigns) do
    with {:ok, attrs} <- attrs(draft) do
      result =
        case assigns.schedule do
          nil -> Schedules.create_schedule(attrs, Actor.opts(assigns))
          schedule -> Schedules.update_schedule(schedule, attrs, Actor.opts(assigns))
        end

      case result do
        {:ok, schedule} -> {:ok, schedule}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, errors(changeset)}
        {:error, reason} -> {:error, [inspect(reason)]}
      end
    end
  end

  defp attrs(draft) do
    with {:ok, deliveries} <- deliveries(draft["deliveries"]) do
      {query_id, dashboard_id} = target(draft["target"])

      {:ok,
       %{
         name: draft["name"],
         query_id: query_id,
         dashboard_id: dashboard_id,
         cron: Cadence.to_cron(draft["cadence"]),
         time_zone: blank(draft["time_zone"]) || "Etc/UTC",
         enabled: draft["enabled"] == "true",
         deliveries: deliveries,
         rule: rule(draft, query_id)
       }}
    end
  end

  defp target("query:" <> id), do: {id, nil}
  defp target("dashboard:" <> id), do: {nil, id}
  defp target(_none), do: {nil, nil}

  defp deliveries(deliveries) do
    Enum.reduce_while(deliveries, {:ok, []}, fn delivery, {:ok, acc} ->
      case config(delivery) do
        {:ok, config} ->
          {:cont,
           {:ok,
            acc ++ [%{channel: delivery["channel"], format: delivery["format"], config: config}]}}

        {:error, message} ->
          {:halt, {:error, [message]}}
      end
    end)
  end

  defp config(%{"channel" => "webhook"} = delivery) do
    extra = delivery["extra"] || %{}
    headers = Map.drop(extra["headers"] || %{}, ["authorization", "Authorization"])

    headers =
      case blank(delivery["authorization"]) do
        nil -> headers
        value -> Map.put(headers, "authorization", value)
      end

    config =
      extra
      |> Map.put("url", String.trim(delivery["url"] || ""))
      |> then(
        &if(headers == %{}, do: Map.delete(&1, "headers"), else: Map.put(&1, "headers", headers))
      )

    {:ok, config}
  end

  defp config(%{"config" => json}) do
    case blank(json) do
      nil ->
        {:ok, %{}}

      json ->
        case Lotus.JSON.decode(json) do
          {:ok, %{} = config} -> {:ok, config}
          _other -> {:error, gettext("A destination's settings must be a JSON object")}
        end
    end
  end

  defp config(_delivery), do: {:ok, %{}}

  defp rule(%{"alert" => "true"} = draft, query_id) when not is_nil(query_id) do
    %{
      condition: draft["condition"],
      column: blank(draft["column"]),
      threshold: blank(draft["threshold"]),
      notify_recovery: draft["notify_recovery"] != "false"
    }
  end

  defp rule(_draft, _query_id), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank(_value), do: nil

  # The changeset's errors as sentences: "Name can't be blank".
  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> flatten([])
  end

  defp flatten(errors, path) when is_map(errors),
    do: Enum.flat_map(errors, fn {field, value} -> flatten(value, path ++ [field]) end)

  defp flatten([%{} | _] = list, path),
    do:
      list
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {errors, n} -> flatten(errors, path ++ [n]) end)

  defp flatten(messages, path) when is_list(messages),
    do: Enum.map(messages, &"#{field_label(path)} #{&1}")

  defp field_label([:query_id | _]), do: gettext("What to send:")
  defp field_label([:dashboard_id | _]), do: gettext("What to send:")
  defp field_label([:cron | _]), do: gettext("When:")
  defp field_label([:time_zone | _]), do: gettext("Time zone:")
  defp field_label([:deliveries, n | _]), do: gettext("Destination %{n}:", n: n)
  defp field_label([:rule | _]), do: gettext("Alert:")
  defp field_label([:name | _]), do: gettext("Name:")
  defp field_label(path), do: (path |> Enum.join(" ") |> String.capitalize()) <> ":"
end
