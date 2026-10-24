defmodule Lotus.Web.SchedulesPage do
  @moduledoc """
  The schedules and alerts of `Lotus.Schedules`: their list, a form to create
  or edit one, and each one's recent runs. Shown with
  `lotus_dashboard "/lotus", features: [:schedules]`.

  Anyone who reaches the page sees the list and the runs; creating, editing,
  pausing and deleting asks for `:manage_schedule`
  (`Lotus.Web.Authorization`).
  """

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  alias Lotus.Schedules
  alias Lotus.Schedules.Alert

  alias Lotus.Storage.Schedule
  alias Lotus.Web.{Actor, Authorization, Page, Pro}

  @runs 20

  # A few time zones to pick from; any IANA name is accepted.
  @time_zones ~w(Etc/UTC Europe/London Europe/Lisbon Europe/Paris Europe/Berlin Europe/Madrid
                 America/New_York America/Chicago America/Denver America/Los_Angeles
                 America/Sao_Paulo Asia/Tokyo Asia/Singapore Asia/Kolkata Australia/Sydney)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, can_manage: Authorization.allowed?(assigns, :manage_schedule))

    ~H"""
    <div id="schedules-page" class="flex flex-col h-full overflow-hidden">
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 h-full">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg h-full flex flex-col overflow-hidden">
          <div class="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div>
              <h2 class="lotus-title text-xl font-semibold text-gray-900 dark:text-white">
                <%= gettext("Schedules") %>
              </h2>
              <p class="text-sm text-gray-500 dark:text-gray-400">
                <%= gettext("Queries and dashboards run on a schedule, and alerts on query results.") %>
              </p>
            </div>
            <.button :if={@can_manage} id="new-schedule" phx-click="new_schedule" phx-target={@myself}>
              <%= gettext("New schedule") %>
            </.button>
          </div>

          <div class="flex-1 overflow-y-auto px-6 py-4">
            <.schedule_form
              :if={@draft}
              draft={@draft}
              errors={@errors}
              queries={@queries}
              dashboards={@dashboards}
              time_zones={@time_zones}
              channels={@channels}
              formats={@formats}
              conditions={@conditions}
              target={@myself}
            />

            <p :if={@schedules == [] and is_nil(@draft)} id="schedules-empty" class="py-12 text-center text-sm text-gray-500 dark:text-gray-400">
              <%= gettext("No schedules yet.") %>
            </p>

            <table :if={@schedules != []} id="schedules-table" class="w-full text-left text-sm">
              <thead class="text-xs uppercase text-gray-500 dark:text-gray-400">
                <tr>
                  <th class="py-2 pr-4"><%= gettext("Name") %></th>
                  <th class="py-2 pr-4"><%= gettext("Runs") %></th>
                  <th class="py-2 pr-4"><%= gettext("When") %></th>
                  <th class="py-2 pr-4"><%= gettext("Next run") %></th>
                  <th class="py-2 pr-4"><%= gettext("Last run") %></th>
                  <th class="py-2"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 dark:divide-gray-700">
                <tr :for={entry <- @schedules} id={"schedule-#{entry.schedule.id}"} class="align-top">
                  <td class="py-3 pr-4">
                    <span class="font-medium text-gray-900 dark:text-white"><%= entry.schedule.name %></span>
                    <span
                      :if={entry.schedule.rule}
                      id={"schedule-#{entry.schedule.id}-alert"}
                      class={[
                        "ml-2 rounded-full px-2 py-0.5 text-[11px] font-medium",
                        alert_status(entry.schedule) == "firing" && "bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-300",
                        alert_status(entry.schedule) != "firing" && "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300"
                      ]}
                    >
                      <%= alert_label(entry.schedule) %>
                    </span>
                    <span :if={not entry.schedule.enabled} class="ml-2 text-xs text-gray-400"><%= gettext("Paused") %></span>
                  </td>
                  <td class="py-3 pr-4 text-gray-600 dark:text-gray-300"><%= entry.target %></td>
                  <td class="py-3 pr-4 font-mono text-xs text-gray-600 dark:text-gray-300">
                    <%= entry.schedule.cron %> · <%= entry.schedule.time_zone %>
                  </td>
                  <td class="py-3 pr-4 text-gray-600 dark:text-gray-300"><%= at(entry.schedule.next_run_at) %></td>
                  <td class="py-3 pr-4">
                    <span :if={entry.last_run} class={status_class(entry.last_run.status)}><%= entry.last_run.status %></span>
                    <span :if={is_nil(entry.last_run)} class="text-gray-400">-</span>
                  </td>
                  <td class="py-3 text-right whitespace-nowrap">
                    <button type="button" id={"schedule-#{entry.schedule.id}-runs"} phx-click="show_runs" phx-value-id={entry.schedule.id} phx-target={@myself} class="text-sm text-gray-600 hover:text-gray-900 dark:text-gray-300">
                      <%= gettext("Runs") %>
                    </button>
                    <%= if @can_manage do %>
                      <button type="button" id={"schedule-#{entry.schedule.id}-toggle"} phx-click="toggle_schedule" phx-value-id={entry.schedule.id} phx-target={@myself} class="ml-3 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-300">
                        <%= if entry.schedule.enabled, do: gettext("Pause"), else: gettext("Resume") %>
                      </button>
                      <button type="button" id={"schedule-#{entry.schedule.id}-edit"} phx-click="edit_schedule" phx-value-id={entry.schedule.id} phx-target={@myself} class="ml-3 text-sm text-pink-600 hover:text-pink-700">
                        <%= gettext("Edit") %>
                      </button>
                      <button type="button" id={"schedule-#{entry.schedule.id}-delete"} phx-click="delete_schedule" phx-value-id={entry.schedule.id} phx-target={@myself} data-confirm={gettext("Delete this schedule and its runs?")} class="ml-3 text-sm text-red-600 hover:text-red-700">
                        <%= gettext("Delete") %>
                      </button>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>

            <.runs :if={@runs_of} schedule={@runs_of} runs={@runs} target={@myself} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:draft, :map, required: true)
  attr(:errors, :list, required: true)
  attr(:queries, :list, required: true)
  attr(:dashboards, :list, required: true)
  attr(:time_zones, :list, required: true)
  attr(:channels, :list, required: true)
  attr(:formats, :list, required: true)
  attr(:conditions, :list, required: true)
  attr(:target, :any, required: true)

  defp schedule_form(assigns) do
    ~H"""
    <form
      id="schedule-form"
      phx-change="change_draft"
      phx-submit="save_schedule"
      phx-target={@target}
      class="mb-6 space-y-4 rounded-lg border border-gray-200 p-4 dark:border-gray-700"
    >
      <h3 class="font-medium text-gray-900 dark:text-white">
        <%= if @draft["id"], do: gettext("Edit schedule"), else: gettext("New schedule") %>
      </h3>

      <ul :if={@errors != []} id="schedule-errors" class="space-y-1 text-sm text-red-600">
        <li :for={error <- @errors}><%= error %></li>
      </ul>

      <div class="grid gap-4 sm:grid-cols-2">
        <label class="block text-sm">
          <span class="text-gray-700 dark:text-gray-300"><%= gettext("Name") %></span>
          <input type="text" name="draft[name]" value={@draft["name"]} required class={input_class()} />
        </label>

        <label class="block text-sm">
          <span class="text-gray-700 dark:text-gray-300"><%= gettext("Runs") %></span>
          <select name="draft[target]" class={input_class()}>
            <option value=""><%= gettext("Choose a query or a dashboard…") %></option>
            <optgroup label={gettext("Queries")}>
              <option :for={query <- @queries} value={"query:#{query.id}"} selected={@draft["target"] == "query:#{query.id}"}><%= query.name %></option>
            </optgroup>
            <optgroup label={gettext("Dashboards")}>
              <option :for={dashboard <- @dashboards} value={"dashboard:#{dashboard.id}"} selected={@draft["target"] == "dashboard:#{dashboard.id}"}><%= dashboard.name %></option>
            </optgroup>
          </select>
        </label>

        <label class="block text-sm">
          <span class="text-gray-700 dark:text-gray-300"><%= gettext("When (cron)") %></span>
          <input type="text" name="draft[cron]" value={@draft["cron"]} placeholder="0 8 * * MON" required class={[input_class(), "font-mono"]} />
          <span class="mt-1 block text-xs text-gray-500"><%= gettext("Minute, hour, day of the month, month, day of the week.") %></span>
        </label>

        <label class="block text-sm">
          <span class="text-gray-700 dark:text-gray-300"><%= gettext("Time zone") %></span>
          <input type="text" name="draft[time_zone]" value={@draft["time_zone"]} list="schedule-time-zones" class={input_class()} />
          <datalist id="schedule-time-zones">
            <option :for={zone <- @time_zones} value={zone} />
          </datalist>
        </label>
      </div>

      <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
        <input type="hidden" name="draft[enabled]" value="false" />
        <input type="checkbox" name="draft[enabled]" value="true" checked={@draft["enabled"] == "true"} />
        <%= gettext("Enabled") %>
      </label>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-gray-700 dark:text-gray-300"><%= gettext("Deliveries") %></legend>
        <div :for={{delivery, index} <- Enum.with_index(@draft["deliveries"])} id={"delivery-#{index}"} class="grid gap-2 sm:grid-cols-[10rem_8rem_1fr_auto] items-start">
          <select name={"draft[deliveries][#{index}][channel]"} class={input_class()}>
            <option :for={channel <- @channels} value={channel} selected={delivery["channel"] == channel}><%= channel %></option>
          </select>
          <select name={"draft[deliveries][#{index}][format]"} class={input_class()}>
            <option :for={format <- @formats} value={format} selected={delivery["format"] == format}><%= format %></option>
          </select>
          <%= if delivery["channel"] == "webhook" do %>
            <input type="url" name={"draft[deliveries][#{index}][url]"} value={delivery["url"]} placeholder="https://hooks.example.com/lotus" class={input_class()} />
          <% else %>
            <textarea name={"draft[deliveries][#{index}][config]"} rows="2" placeholder={~s({"to": "team@example.com"})} class={[input_class(), "font-mono text-xs"]}><%= delivery["config"] %></textarea>
          <% end %>
          <button type="button" phx-click="remove_delivery" phx-value-index={index} phx-target={@target} class="mt-2 text-sm text-red-600"><%= gettext("Remove") %></button>
        </div>
        <button type="button" id="add-delivery" phx-click="add_delivery" phx-target={@target} class="text-sm text-pink-600 hover:text-pink-700">
          <%= gettext("Add a delivery") %>
        </button>
      </fieldset>

      <fieldset class="space-y-2">
        <label class="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
          <input type="hidden" name="draft[alert]" value="false" />
          <input type="checkbox" id="schedule-alert" name="draft[alert]" value="true" checked={@draft["alert"] == "true"} />
          <%= gettext("Alert: send only when the result crosses a rule") %>
        </label>
        <div :if={@draft["alert"] == "true"} class="grid gap-2 sm:grid-cols-4">
          <select name="draft[condition]" class={input_class()}>
            <option :for={condition <- @conditions} value={condition} selected={@draft["condition"] == condition}><%= condition %></option>
          </select>
          <input type="text" name="draft[column]" value={@draft["column"]} placeholder={gettext("Column (row count without)")} class={input_class()} />
          <input type="text" name="draft[threshold]" value={@draft["threshold"]} placeholder={gettext("Threshold")} class={input_class()} />
          <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input type="hidden" name="draft[notify_recovery]" value="false" />
            <input type="checkbox" name="draft[notify_recovery]" value="true" checked={@draft["notify_recovery"] != "false"} />
            <%= gettext("Also when it recovers") %>
          </label>
        </div>
      </fieldset>

      <div class="flex justify-end gap-3">
        <.button type="button" variant="light" phx-click="cancel_draft" phx-target={@target}><%= gettext("Cancel") %></.button>
        <.button type="submit" id="save-schedule"><%= gettext("Save") %></.button>
      </div>
    </form>
    """
  end

  attr(:schedule, :map, required: true)
  attr(:runs, :list, required: true)
  attr(:target, :any, required: true)

  defp runs(assigns) do
    ~H"""
    <section id="schedule-runs" class="mt-8">
      <div class="flex items-center justify-between">
        <h3 class="font-medium text-gray-900 dark:text-white">
          <%= gettext("Runs of %{name}", name: @schedule.name) %>
        </h3>
        <button type="button" phx-click="hide_runs" phx-target={@target} class="text-sm text-gray-500"><%= gettext("Close") %></button>
      </div>
      <p :if={@runs == []} class="py-4 text-sm text-gray-500"><%= gettext("It has not run yet.") %></p>
      <table :if={@runs != []} class="mt-2 w-full text-left text-sm">
        <tbody class="divide-y divide-gray-100 dark:divide-gray-700">
          <tr :for={run <- @runs} id={"run-#{run.id}"}>
            <td class="py-2 pr-4 text-gray-600 dark:text-gray-300"><%= at(run.scheduled_for) %></td>
            <td class="py-2 pr-4"><span class={status_class(run.status)}><%= run.status %></span></td>
            <td class="py-2 pr-4 text-gray-600 dark:text-gray-300"><%= run.row_count && ngettext("1 row", "%{count} rows", run.row_count) %></td>
            <td class="py-2 text-red-600"><%= run.error %></td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp input_class,
    do:
      "mt-1 w-full rounded-lg border border-gray-300 bg-white p-2 text-sm focus:border-pink-500 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"

  defp status_class("succeeded"), do: "text-green-700 dark:text-green-400"
  defp status_class("failed"), do: "text-red-600"
  defp status_class(_status), do: "text-gray-500"

  defp alert_status(%Schedule{state: state}), do: (state || %{})["status"] || "ok"

  defp alert_label(schedule) do
    case alert_status(schedule) do
      "firing" -> gettext("Alert: firing")
      _ok -> gettext("Alert")
    end
  end

  defp at(nil), do: "-"
  defp at(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  @impl Page
  def handle_mount(socket) do
    info = Pro.request_info(socket.assigns)

    assign(socket,
      schedules: [],
      draft: nil,
      errors: [],
      runs_of: nil,
      runs: [],
      queries: Pro.list_queries(info),
      dashboards: Pro.list_dashboards(info),
      time_zones: @time_zones,
      channels: Lotus.Delivery.channels() |> Map.keys() |> Enum.sort(),
      formats: Lotus.Delivery.formats() |> Map.keys() |> Enum.sort(),
      conditions: Alert.conditions()
    )
  end

  # `?query_id=` or `?dashboard_id=` opens the form for it: the query editor
  # and the dashboard link here to schedule them.
  @impl Page
  def handle_params(params, _uri, socket) do
    socket = load(socket)

    target =
      case params do
        %{"query_id" => id} -> "query:#{id}"
        %{"dashboard_id" => id} -> "dashboard:#{id}"
        _ -> nil
      end

    if target && Authorization.allowed?(socket.assigns, :manage_schedule),
      do: {:noreply, assign(socket, draft: new_draft(target), errors: [])},
      else: {:noreply, socket}
  end

  @impl Page
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveComponent
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl Phoenix.LiveComponent
  def handle_event("new_schedule", _params, socket) do
    manage(socket, fn -> assign(socket, draft: new_draft(nil), errors: []) end)
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    manage(socket, fn ->
      case Schedules.get_schedule(id) do
        nil -> socket
        schedule -> assign(socket, draft: draft(schedule), errors: [])
      end
    end)
  end

  def handle_event("cancel_draft", _params, socket),
    do: {:noreply, assign(socket, draft: nil, errors: [])}

  def handle_event("change_draft", %{"draft" => params}, socket),
    do: {:noreply, assign(socket, draft: merge_draft(socket.assigns.draft, params))}

  def handle_event("add_delivery", _params, socket) do
    draft = socket.assigns.draft
    delivery = %{"channel" => "webhook", "format" => "csv", "url" => "", "config" => ""}

    {:noreply,
     assign(socket, draft: %{draft | "deliveries" => draft["deliveries"] ++ [delivery]})}
  end

  def handle_event("remove_delivery", %{"index" => index}, socket) do
    draft = socket.assigns.draft
    deliveries = List.delete_at(draft["deliveries"], String.to_integer(index))
    {:noreply, assign(socket, draft: %{draft | "deliveries" => deliveries})}
  end

  def handle_event("save_schedule", %{"draft" => params}, socket) do
    manage(socket, fn ->
      draft = merge_draft(socket.assigns.draft, params)

      case save(draft, socket.assigns) do
        {:ok, _schedule} -> socket |> assign(draft: nil, errors: []) |> load()
        {:error, errors} -> assign(socket, draft: draft, errors: errors)
      end
    end)
  end

  def handle_event("toggle_schedule", %{"id" => id}, socket) do
    manage(socket, fn ->
      with %Schedule{} = schedule <- Schedules.get_schedule(id) do
        Schedules.update_schedule(schedule, %{enabled: not schedule.enabled}, actor(socket))
      end

      load(socket)
    end)
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    manage(socket, fn ->
      Schedules.delete_schedule(id, actor(socket))
      socket |> assign(runs_of: nil, runs: []) |> load()
    end)
  end

  def handle_event("show_runs", %{"id" => id}, socket) do
    case Schedules.get_schedule(id) do
      nil ->
        {:noreply, socket}

      schedule ->
        {:noreply,
         assign(socket, runs_of: schedule, runs: Schedules.list_runs(schedule, limit: @runs))}
    end
  end

  def handle_event("hide_runs", _params, socket),
    do: {:noreply, assign(socket, runs_of: nil, runs: [])}

  # Creating, editing, pausing and deleting asks for :manage_schedule, in the
  # handler too, so a crafted event is refused.
  defp manage(socket, fun) do
    case Authorization.authorize(socket.assigns, :manage_schedule, nil) do
      :allow -> {:noreply, fun.()}
      {:deny, reason} -> {:noreply, put_flash(socket, :error, reason)}
    end
  end

  defp actor(socket), do: Actor.opts(socket.assigns)

  # The schedules, each with what it runs and its last run.
  defp load(socket) do
    queries = Map.new(socket.assigns.queries, &{&1.id, &1.name})
    dashboards = Map.new(socket.assigns.dashboards, &{&1.id, &1.name})

    entries =
      for schedule <- Schedules.list_schedules() do
        %{
          schedule: schedule,
          target: target_name(schedule, queries, dashboards),
          last_run: List.first(Schedules.list_runs(schedule, limit: 1))
        }
      end

    assign(socket, schedules: entries)
  end

  defp target_name(%Schedule{query_id: id}, queries, _dashboards) when not is_nil(id),
    do: Map.get(queries, id, gettext("A query"))

  defp target_name(%Schedule{dashboard_id: id}, _queries, dashboards),
    do: Map.get(dashboards, id, gettext("A dashboard"))

  ## The form's draft: its fields as strings, as the form sends them.

  defp new_draft(target) do
    %{
      "id" => nil,
      "name" => "",
      "target" => target || "",
      "cron" => "0 8 * * MON",
      "time_zone" => "Etc/UTC",
      "enabled" => "true",
      "deliveries" => [],
      "alert" => "false",
      "condition" => "above",
      "column" => "",
      "threshold" => "",
      "notify_recovery" => "true"
    }
  end

  defp draft(%Schedule{} = schedule) do
    Map.merge(
      %{
        "id" => schedule.id,
        "name" => schedule.name,
        "target" => draft_target(schedule),
        "cron" => schedule.cron,
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

    %{
      "channel" => delivery.channel,
      "format" => delivery.format,
      "url" => config["url"] || "",
      "config" => if(config == %{}, do: "", else: Lotus.JSON.encode!(config))
    }
  end

  defp draft_rule(nil),
    do: Map.take(new_draft(nil), ~w(alert condition column threshold notify_recovery))

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
          |> Enum.map(fn {_index, delivery} ->
            Map.merge(%{"url" => "", "config" => ""}, delivery)
          end)

        _none ->
          draft["deliveries"]
      end

    draft
    |> Map.merge(
      Map.take(
        params,
        ~w(name target cron time_zone enabled alert condition column threshold notify_recovery)
      )
    )
    |> Map.put("deliveries", deliveries)
  end

  defp save(draft, assigns) do
    with {:ok, attrs} <- attrs(draft) do
      result =
        case draft["id"] do
          nil -> Schedules.create_schedule(attrs, Actor.opts(assigns))
          id -> Schedules.update_schedule(Schedules.get_schedule!(id), attrs, Actor.opts(assigns))
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
         cron: draft["cron"],
         time_zone: blank(draft["time_zone"]) || "Etc/UTC",
         enabled: draft["enabled"] == "true",
         deliveries: deliveries,
         rule: rule(draft)
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

  defp config(%{"channel" => "webhook", "url" => url}), do: {:ok, %{"url" => url}}

  defp config(%{"config" => json}) do
    case blank(json) do
      nil ->
        {:ok, %{}}

      json ->
        case Lotus.JSON.decode(json) do
          {:ok, %{} = config} -> {:ok, config}
          _other -> {:error, gettext("A delivery's settings must be a JSON object")}
        end
    end
  end

  defp rule(%{"alert" => "true"} = draft) do
    %{
      condition: draft["condition"],
      column: blank(draft["column"]),
      threshold: blank(draft["threshold"]),
      notify_recovery: draft["notify_recovery"] != "false"
    }
  end

  defp rule(_draft), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank(_value), do: nil

  # The changeset's errors as lines: "cron is not a cron expression: …".
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
    do: Enum.map(messages, &"#{Enum.join(path, " ")}: #{&1}")
end
