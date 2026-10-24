defmodule Lotus.Web.Queries.AiAssistantComponent do
  @moduledoc """
  Conversational AI Assistant for generating and refining queries.

  The work shows as it happens: each tool the model calls is a step in the
  panel while it answers, folded under the answer once it has. An answer
  with a query shows what changed from the editor's, and what it returns:
  its first rows and the chart they suggest.
  """
  use Lotus.Web, :live_component

  alias Lotus.Web.Components.Icons
  alias Lotus.Web.Queries.AiPreview
  alias Lotus.Web.Queries.AiSteps

  # Assigns:
  # - visible: boolean
  # - parent: Phoenix.LiveComponent.CID
  # - data_source: string (from query_form)
  # - generating: boolean (loading state)
  # - conversation: map (conversation history)
  # - current_statement: string (current query in the editor)
  # - steps: the tool calls of the answer being written (`AiSteps`)
  # - action: what the assistant is doing (:generate, :explain, ...)
  # - schema: the editor's schema, table => columns, for the suggestions
  # - lotus_mark: whether to draw the Lotus mark (not under another brand)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "lotus-ai-panel fixed sm:absolute top-0 left-0 h-full w-full sm:w-[26rem]",
        "bg-white dark:bg-gray-800",
        "border-r-0 sm:border-r border-gray-200 dark:border-gray-700",
        "z-20 transition-transform duration-300 ease-in-out overflow-hidden",
        "flex flex-col",
        if(@visible, do: "translate-x-0", else: "-translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= cond do %>
        <% not @visible -> %>
        <% Lotus.Web.AI.missing_dependency?() -> %>
          <.header parent={@parent} conversation={@conversation} assistant_name={assigns[:assistant_name]} data_source={@data_source} lotus_mark={assigns[:lotus_mark]} />
          <.missing_dependency />
        <% true -> %>
          <.header parent={@parent} conversation={@conversation} assistant_name={assigns[:assistant_name]} data_source={@data_source} lotus_mark={assigns[:lotus_mark]} />
          <.conversation_history
            conversation={@conversation}
            parent={@parent}
            current_statement={@current_statement}
            data_source={@data_source}
            generating={@generating}
            steps={assigns[:steps] || []}
            action={assigns[:action]}
            schema={assigns[:schema]}
            lotus_mark={assigns[:lotus_mark]}
          />
          <.input_area
            generating={@generating}
            parent={@parent}
            current_statement={@current_statement}
            data_source={@data_source}
            conversation={@conversation}
          />
      <% end %>
    </div>
    """
  end

  # AI is switched on, but req_llm, which it needs, is not installed: the
  # panel says so, where the conversation would be.
  defp missing_dependency(assigns) do
    ~H"""
    <div id="ai-missing-dependency" class="flex-1 p-6 text-sm text-gray-600 dark:text-gray-300">
      <p class="font-medium text-gray-900 dark:text-gray-100">
        <%= gettext("The AI assistant is not installed") %>
      </p>
      <p class="mt-2">
        <%= gettext("AI is enabled, but it needs the req_llm package. Add it to your app's dependencies and restart it:") %>
      </p>
      <pre class="mt-3 rounded bg-gray-100 dark:bg-gray-900 px-3 py-2 font-mono text-xs"><code><%= ~s({:req_llm, "~> 1.29"}) %></code></pre>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:conversation, :map, required: true)
  attr(:assistant_name, :string, default: nil)
  attr(:data_source, :string, default: nil)
  attr(:lotus_mark, :boolean, default: true)

  defp header(assigns) do
    ~H"""
    <div class="relative px-4 py-3 flex-shrink-0 flex items-center gap-3 border-b border-gray-200/70 dark:border-gray-700/70">
      <.mark lotus_mark={@lotus_mark} class="h-8 w-8" />
      <div class="flex-1 min-w-0">
        <h3 class="text-sm font-semibold text-gray-900 dark:text-gray-100 leading-tight">
          <%= @assistant_name || gettext("AI Assistant") %>
        </h3>
        <p :if={@data_source not in [nil, ""]} class="mt-0.5 flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400 truncate">
          <Icons.database class="h-3 w-3 flex-shrink-0" />
          <span class="truncate"><%= @data_source %></span>
        </p>
      </div>
      <div class="flex items-center gap-0.5">
        <button
          :if={@conversation.messages != []}
          type="button"
          phx-click="clear_ai_conversation"
          phx-target={@parent}
          class="lotus-ai-icon-button"
          aria-label={gettext("New conversation")}
          title={gettext("New conversation")}
        >
          <Icons.plus class="h-4 w-4" />
        </button>
        <button
          type="button"
          phx-click="close_ai_assistant"
          phx-target={@parent}
          class="lotus-ai-icon-button"
          aria-label={gettext("Close")}
        >
          <Icons.x_mark class="h-4 w-4" />
        </button>
      </div>
    </div>
    """
  end

  attr(:lotus_mark, :boolean, default: true)
  attr(:class, :any, default: nil)
  attr(:busy, :boolean, default: false)

  # The assistant's mark: the Lotus bloom, whose petals open while it works;
  # sparkles under another brand.
  defp mark(assigns) do
    ~H"""
    <span class={["lotus-ai-mark", @busy && "lotus-ai-mark-busy", @class]} aria-hidden="true">
      <%= if @lotus_mark do %>
        <svg viewBox="0 0 112 112" class="h-[62%] w-[62%]">
          <path class="lotus-ai-petal lotus-ai-petal-left" fill="currentColor" d="M56 96Q16 98 12 38Q46 46 56 96Z" />
          <path class="lotus-ai-petal lotus-ai-petal-right fill-[rgb(var(--lotus-logo-petal))]" d="M56 96Q96 98 100 38Q66 46 56 96Z" />
          <path fill="currentColor" d="M56 14Q82 38 80 62Q78 86 56 96Q34 86 32 62Q30 38 56 14Z" />
        </svg>
      <% else %>
        <Icons.sparkles class="h-[55%] w-[55%]" />
      <% end %>
    </span>
    """
  end

  attr(:conversation, :map, required: true)
  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)
  attr(:data_source, :string, default: nil)
  attr(:generating, :boolean, default: false)
  attr(:steps, :list, default: [])
  attr(:action, :atom, default: nil)
  attr(:schema, :map, default: nil)
  attr(:lotus_mark, :boolean, default: true)

  defp conversation_history(assigns) do
    ~H"""
    <div
      id="ai-conversation-history"
      phx-hook="AutoScrollAI"
      class="relative flex-1 overflow-y-auto px-4 py-4 space-y-5"
    >
      <%= if @conversation.messages == [] and not @generating do %>
        <.empty_state
          parent={@parent}
          current_statement={@current_statement}
          data_source={@data_source}
          schema={@schema}
          lotus_mark={@lotus_mark}
        />
      <% else %>
        <%= for {message, index} <- Enum.with_index(@conversation.messages) do %>
          <.message message={message} index={index} parent={@parent} current_statement={@current_statement} />
        <% end %>
        <.working :if={@generating} steps={@steps} action={@action} lotus_mark={@lotus_mark} />
      <% end %>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)
  attr(:data_source, :string, default: nil)
  attr(:schema, :map, default: nil)
  attr(:lotus_mark, :boolean, default: true)

  defp empty_state(assigns) do
    assigns = assign(assigns, :prompts, suggested_prompts(assigns.schema))

    ~H"""
    <div class="flex flex-col h-full pt-8 pb-2 lotus-ai-in">
      <div class="flex flex-col items-center text-center">
        <.mark lotus_mark={@lotus_mark} class="lotus-ai-mark-hero h-16 w-16" />
        <h4 class="mt-5 text-lg font-semibold tracking-tight text-gray-900 dark:text-gray-50 lotus-title">
          <%= gettext("What would you like to know?") %>
        </h4>
        <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400 max-w-[18rem]">
          <%= gettext("Ask in your own words. I read the schema, write the query and show you what it returns.") %>
        </p>
      </div>

      <div class="mt-8 space-y-2" id="ai-suggested-prompts">
        <p class="px-1 text-[11px] font-medium uppercase tracking-wider text-gray-400 dark:text-gray-500">
          <%= gettext("Try") %>
        </p>
        <button
          :for={{prompt, index} <- Enum.with_index(@prompts)}
          type="button"
          phx-click="send_ai_message"
          phx-value-message={prompt}
          phx-target={@parent}
          class="lotus-ai-prompt group lotus-ai-in"
          style={"animation-delay: #{80 + index * 60}ms"}
        >
          <Icons.sparkles class="h-3.5 w-3.5 flex-shrink-0 text-pink-500 dark:text-pink-400 opacity-70 group-hover:opacity-100" />
          <span class="flex-1 text-left"><%= prompt %></span>
          <Icons.corner_down_right class="h-3.5 w-3.5 flex-shrink-0 text-gray-300 dark:text-gray-600 group-hover:text-pink-500 transition-colors" />
        </button>
      </div>

      <div :if={@current_statement not in [nil, ""]} class="mt-auto pt-8">
        <p class="px-1 mb-2 text-[11px] font-medium uppercase tracking-wider text-gray-400 dark:text-gray-500">
          <%= gettext("On the query in the editor") %>
        </p>
        <.ai_action_buttons
          parent={@parent}
          current_statement={@current_statement}
          data_source={@data_source}
          generating={false}
        />
      </div>
    </div>
    """
  end

  attr(:steps, :list, required: true)
  attr(:action, :atom, default: nil)
  attr(:lotus_mark, :boolean, default: true)

  # The answer being written: what the assistant is doing, step by step.
  defp working(assigns) do
    ~H"""
    <div id="ai-working" data-ai-working class="flex gap-3 lotus-ai-in" aria-live="polite">
      <.mark lotus_mark={@lotus_mark} busy class="h-7 w-7 flex-shrink-0" />
      <div class="flex-1 min-w-0 pt-1">
        <p class="text-sm font-medium lotus-ai-shimmer-text"><%= working_label(@action) %></p>
        <ol :if={@steps != []} class="mt-2.5 space-y-1.5">
          <.step :for={step <- @steps} step={step} />
        </ol>
        <div :if={@steps == []} class="mt-3 space-y-2">
          <div class="lotus-ai-skeleton h-2.5 w-4/5"></div>
          <div class="lotus-ai-skeleton h-2.5 w-3/5"></div>
        </div>
      </div>
    </div>
    """
  end

  attr(:step, :map, required: true)

  defp step(assigns) do
    ~H"""
    <li class="flex items-center gap-2 text-xs lotus-ai-in" data-step-status={@step.status}>
      <span class={["lotus-ai-step-dot", "lotus-ai-step-#{@step.status}"]}>
        <%= case @step.status do %>
          <% :done -> %><Icons.check class="h-2.5 w-2.5" />
          <% :failed -> %><Icons.x_mark class="h-2.5 w-2.5" />
          <% :running -> %>
        <% end %>
      </span>
      <span class="flex items-center gap-1.5 min-w-0 text-gray-700 dark:text-gray-200">
        <.step_icon kind={AiSteps.kind(@step)} />
        <span class="truncate"><%= AiSteps.label(@step) %></span>
      </span>
      <span :if={@step.summary} class="truncate text-gray-400 dark:text-gray-500">
        · <%= @step.summary %>
      </span>
      <span :if={@step.ms} class="ml-auto pl-2 tabular-nums text-[10px] text-gray-400 dark:text-gray-500">
        <%= AiSteps.seconds(@step.ms) %>
      </span>
    </li>
    """
  end

  attr(:kind, :atom, required: true)

  defp step_icon(%{kind: :list} = assigns),
    do: ~H"<Icons.tables class='h-3 w-3 flex-shrink-0 text-gray-400' />"

  defp step_icon(%{kind: :table} = assigns),
    do: ~H"<Icons.table_view class='h-3 w-3 flex-shrink-0 text-gray-400' />"

  defp step_icon(%{kind: :values} = assigns),
    do: ~H"<Icons.list_bullet class='h-3 w-3 flex-shrink-0 text-gray-400' />"

  defp step_icon(%{kind: :check} = assigns),
    do: ~H"<Icons.check class='h-3 w-3 flex-shrink-0 text-gray-400' />"

  defp step_icon(assigns),
    do: ~H"<Icons.play_outline class='h-3 w-3 flex-shrink-0 text-gray-400' />"

  defp working_label(:optimize), do: gettext("Looking for improvements")

  defp working_label(action) when action in [:explain, :explain_fragment],
    do: gettext("Reading the query")

  defp working_label(_action), do: gettext("Writing the query")

  attr(:steps, :list, required: true)
  attr(:elapsed_ms, :integer, default: nil)
  attr(:id, :string, required: true)

  # The steps behind an answer, folded to a line.
  defp work(assigns) do
    assigns = assign(assigns, :tables, AiSteps.tables(assigns.steps))

    ~H"""
    <details :if={@steps != []} id={@id} class="group/work mb-2">
      <summary class="inline-flex items-center gap-1.5 cursor-pointer select-none list-none text-xs text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200">
        <span class="lotus-ai-step-dot lotus-ai-step-done"><Icons.check class="h-2.5 w-2.5" /></span>
        <span><%= AiSteps.headline(@steps, @elapsed_ms) %></span>
        <span :for={table <- Enum.take(@tables, 3)} class="lotus-ai-chip"><%= table %></span>
        <Icons.chevron_down class="h-3 w-3 transition-transform group-open/work:rotate-180" />
      </summary>
      <ol class="mt-2 ml-1 pl-3 border-l border-gray-200 dark:border-gray-700 space-y-1.5">
        <.step :for={step <- @steps} step={step} />
      </ol>
    </details>
    """
  end

  attr(:message, :map, required: true)
  attr(:index, :integer, required: true)
  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)

  defp message(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div id={"ai-message-#{@index}"} class="flex justify-end lotus-ai-in" title={time(@message)}>
      <p class="lotus-ai-user max-w-[85%] text-sm whitespace-pre-wrap"><%= @message.content %></p>
    </div>
    """
  end

  defp message(assigns) do
    assigns =
      assigns
      |> assign(:work, Map.get(assigns.message, :work))
      |> assign(:time, time(assigns.message))

    ~H"""
    <div id={"ai-message-#{@index}"} class="lotus-ai-in" title={@time} data-ai-answer={@message.role == :assistant}>
      <.work :if={@work} id={"ai-work-#{@index}"} steps={@work.steps} elapsed_ms={@work.elapsed_ms} />
      <.message_body message={@message} index={@index} parent={@parent} current_statement={@current_statement} />
    </div>
    """
  end

  attr(:message, :map, required: true)
  attr(:index, :integer, required: true)
  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)

  defp message_body(%{message: %{role: :assistant}} = assigns) do
    message = assigns.message
    diff = diff(Map.get(message, :base), message.statement)

    assigns =
      assigns
      |> assign(:diff, diff)
      |> assign(:preview, Map.get(message, :preview))
      |> assign(:variables, Map.get(message, :variables, []))

    ~H"""
    <div class="space-y-3">
      <p :if={@message.content not in [nil, ""]} class="text-sm text-gray-700 dark:text-gray-300">
        <%= if @diff, do: gettext("Here's the change:"), else: @message.content %>
      </p>

      <.sql_card :if={@message.statement} id={"ai-sql-#{@index}"} statement={@message.statement} diff={@diff} />

      <div :if={@variables != []} class="flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
        <Icons.variable class="h-3.5 w-3.5 text-pink-500 dark:text-pink-400" />
        <span><%= variable_summary(@variables) %></span>
      </div>

      <.preview :if={@preview} preview={@preview} index={@index} />

      <div :if={@message.statement} class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          phx-click="use_ai_query"
          phx-value-statement={@message.statement}
          phx-value-message-index={@index}
          phx-target={@parent}
          class="lotus-ai-primary"
        >
          <Icons.corner_down_right class="h-3.5 w-3.5" />
          <%= cond do %>
            <% variables_only_change?(@message, @current_statement) -> %><%= gettext("Apply variable changes") %>
            <% @diff -> %><%= gettext("Apply change") %>
            <% true -> %><%= gettext("Use this query") %>
          <% end %>
        </button>
        <button
          :if={match?(%{status: :ok, chart: %{}}, @preview)}
          type="button"
          phx-click="use_ai_chart"
          phx-value-message-index={@index}
          phx-target={@parent}
          class="lotus-ai-secondary"
        >
          <.chart_icon type={@preview.chart.type} />
          <%= chart_action(@preview.chart.type) %>
        </button>
      </div>
    </div>
    """
  end

  defp message_body(%{message: %{role: :optimization}} = assigns) do
    ~H"""
    <.optimization_message message={@message} index={@index} />
    """
  end

  defp message_body(%{message: %{role: :explanation}} = assigns) do
    ~H"""
    <.explanation_message message={@message} />
    """
  end

  defp message_body(%{message: %{role: :error}} = assigns) do
    ~H"""
    <div class="lotus-ai-alert lotus-ai-alert-error space-y-2.5">
      <div class="flex items-start gap-2">
        <Icons.exclamation_triangle class="h-4 w-4 flex-shrink-0 mt-0.5" />
        <div class="text-sm min-w-0">
          <p class="font-medium"><%= gettext("The query failed") %></p>
          <p class="mt-0.5 text-xs opacity-90 break-words"><%= @message.content %></p>
        </div>
      </div>
      <details :if={@message.statement} class="text-xs">
        <summary class="cursor-pointer hover:underline"><%= gettext("Show the query") %></summary>
        <.sql_card id={"ai-sql-#{@index}"} statement={@message.statement} diff={nil} class="mt-2" />
      </details>
      <button
        type="button"
        phx-click="retry_ai_with_error"
        phx-target={@parent}
        class="lotus-ai-secondary"
      >
        <Icons.rotate_ccw class="h-3.5 w-3.5" />
        <%= gettext("Ask AI to fix this") %>
      </button>
    </div>
    """
  end

  defp message_body(%{message: %{role: :service_error}} = assigns) do
    ~H"""
    <div class="lotus-ai-alert lotus-ai-alert-muted flex items-start gap-2">
      <Icons.exclamation_triangle class="h-4 w-4 flex-shrink-0 mt-0.5" />
      <div class="text-sm min-w-0">
        <p class="font-medium"><%= gettext("Service Unavailable") %></p>
        <p class="mt-0.5 text-xs opacity-90 break-words"><%= @message.content %></p>
      </div>
    </div>
    """
  end

  defp message_body(assigns), do: ~H""

  attr(:id, :string, required: true)
  attr(:statement, :string, required: true)
  attr(:diff, :any, default: nil)
  attr(:class, :any, default: nil)

  # A query, highlighted as the editor highlights it (the AiSql hook); with
  # a diff, the lines it adds and removes from the editor's.
  defp sql_card(assigns) do
    lines = assigns.diff || Enum.map(String.split(assigns.statement, "\n"), &{:eq, &1})
    assigns = assign(assigns, :lines, lines)

    ~H"""
    <div class={["lotus-ai-code group/code", @class]}>
      <div class="flex items-center gap-2 px-3 pt-2 pb-1">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">
          <%= if @diff, do: gettext("Changes"), else: gettext("Query") %>
        </span>
        <span :if={@diff} class="flex items-center gap-1 text-[10px] font-medium tabular-nums">
          <span class="lotus-ai-diff-count-added">+<%= count(@diff, :ins) %></span>
          <span class="lotus-ai-diff-count-removed">−<%= count(@diff, :del) %></span>
        </span>
        <button
          type="button"
          id={"#{@id}-copy"}
          phx-hook="AiCopy"
          data-clipboard-text={@statement}
          class="ml-auto lotus-ai-icon-button -mr-1 opacity-0 group-hover/code:opacity-100 focus:opacity-100"
          aria-label={gettext("Copy")}
          title={gettext("Copy")}
        >
          <Icons.clipboard_copy class="h-3.5 w-3.5" />
        </button>
      </div>
      <pre id={@id} phx-hook="AiSql" phx-update="ignore" class="lotus-ai-sql"><code><span
          :for={{op, line} <- @lines}
          class={["lotus-ai-line", op == :ins && "lotus-ai-line-added", op == :del && "lotus-ai-line-removed"]}
          data-line
        ><%= line %></span></code></pre>
    </div>
    """
  end

  attr(:preview, :map, required: true)
  attr(:index, :integer, required: true)

  # What the query returns: a chart its columns suggest, and its first rows.
  defp preview(%{preview: %{status: :loading}} = assigns) do
    ~H"""
    <div class="lotus-ai-preview" data-preview="loading" aria-busy="true">
      <div class="flex items-end gap-1.5 h-16 px-1">
        <div :for={h <- [38, 55, 42, 70, 60, 84, 66]} class="lotus-ai-skeleton flex-1 rounded-t-sm rounded-b-none" style={"height: #{h}%"}></div>
      </div>
      <div class="mt-3 space-y-1.5">
        <div class="lotus-ai-skeleton h-2 w-full"></div>
        <div class="lotus-ai-skeleton h-2 w-11/12"></div>
        <div class="lotus-ai-skeleton h-2 w-4/5"></div>
      </div>
    </div>
    """
  end

  defp preview(%{preview: %{status: :error}} = assigns) do
    ~H"""
    <p class="flex items-start gap-1.5 text-xs text-gray-500 dark:text-gray-400" data-preview="error">
      <Icons.information_circle class="h-3.5 w-3.5 flex-shrink-0 mt-px" />
      <span class="break-words"><%= gettext("No preview: %{reason}", reason: @preview.error) %></span>
    </p>
    """
  end

  defp preview(assigns) do
    assigns =
      assigns
      |> assign(:shown, Enum.take(assigns.preview.rows, 5))
      |> assign(:more, max(length(assigns.preview.rows) - 5, 0))

    ~H"""
    <div class="lotus-ai-preview lotus-ai-in" data-preview="ok">
      <.mini_chart :if={@preview.chart} chart={@preview.chart} />
      <div :if={@preview.columns != []} class={["overflow-x-auto -mx-3 px-3", @preview.chart && "mt-3"]}>
        <table class="w-full text-[11px] tabular-nums">
          <thead>
            <tr>
              <th :for={column <- @preview.columns} class="pb-1.5 pr-3 text-left font-medium text-gray-400 dark:text-gray-500 whitespace-nowrap"><%= column %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @shown} class="border-t border-gray-100 dark:border-gray-700/60">
              <td :for={value <- row} class="py-1 pr-3 text-gray-700 dark:text-gray-300 whitespace-nowrap max-w-[10rem] truncate"><%= AiPreview.cell(value) %></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-2 text-[11px] text-gray-400 dark:text-gray-500">
        <%= cond do %>
          <% @preview.rows == [] -> %><%= gettext("No rows") %>
          <% @more > 0 and length(@preview.rows) >= 50 -> %><%= gettext("First 5 of 50+ rows") %>
          <% @more > 0 -> %><%= gettext("First 5 of %{count} rows", count: length(@preview.rows)) %>
          <% true -> %><%= ngettext("%{count} row", "%{count} rows", length(@preview.rows), count: length(@preview.rows)) %>
        <% end %>
      </p>
    </div>
    """
  end

  attr(:chart, :map, required: true)

  defp mini_chart(%{chart: %{type: "kpi"}} = assigns) do
    assigns = assign(assigns, :value, assigns.chart.points |> hd() |> elem(1))

    ~H"""
    <div class="py-2" data-chart="kpi">
      <p class="text-[11px] font-medium text-gray-400 dark:text-gray-500"><%= @chart.y %></p>
      <p class="mt-0.5 text-3xl font-semibold tracking-tight text-gray-900 dark:text-gray-50 tabular-nums"><%= AiPreview.cell(@value) %></p>
    </div>
    """
  end

  defp mini_chart(assigns) do
    {points, last} = chart_geometry(assigns.chart)
    {first_label, _} = hd(assigns.chart.points)
    {last_label, last_value} = List.last(assigns.chart.points)

    assigns =
      assign(assigns,
        geometry: points,
        last: last,
        first_label: first_label,
        last_label: last_label,
        last_value: last_value
      )

    ~H"""
    <div data-chart={@chart.type}>
      <div class="flex items-baseline justify-between gap-2">
        <p class="text-[11px] font-medium text-gray-400 dark:text-gray-500 truncate">
          <%= gettext("%{y} by %{x}", y: @chart.y, x: @chart.x) %>
        </p>
        <p :if={@chart.type == "line"} class="text-sm font-semibold text-gray-900 dark:text-gray-50 tabular-nums">
          <%= AiPreview.cell(round_value(@last_value)) %>
        </p>
      </div>
      <svg viewBox="0 0 300 80" preserveAspectRatio="none" class="mt-1.5 w-full h-20 text-pink-500 dark:text-pink-400 overflow-visible">
        <%= if @chart.type == "line" do %>
          <path d={area_path(@geometry)} class="lotus-ai-chart-area" fill="currentColor" fill-opacity="0.12" />
          <polyline points={polyline(@geometry)} fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke" class="lotus-ai-chart-line" />
          <circle cx={elem(@last, 0)} cy={elem(@last, 1)} r="3" fill="currentColor" class="lotus-ai-chart-dot" />
        <% else %>
          <rect
            :for={{{x, y, w}, index} <- Enum.with_index(@geometry)}
            x={x}
            y={y}
            width={w}
            height={80 - y}
            rx="2"
            fill="currentColor"
            fill-opacity={if index == length(@geometry) - 1, do: "1", else: "0.55"}
            class="lotus-ai-chart-bar"
            style={"animation-delay: #{index * 35}ms"}
          />
        <% end %>
      </svg>
      <div class="mt-1 flex justify-between text-[10px] text-gray-400 dark:text-gray-500">
        <span class="truncate"><%= @first_label %></span>
        <span class="truncate"><%= @last_label %></span>
      </div>
    </div>
    """
  end

  attr(:type, :string, required: true)

  defp chart_icon(%{type: "line"} = assigns), do: ~H"<Icons.chart_line class='h-3.5 w-3.5' />"
  defp chart_icon(%{type: "kpi"} = assigns), do: ~H"<Icons.chart_kpi class='h-3.5 w-3.5' />"
  defp chart_icon(assigns), do: ~H"<Icons.chart_bar class='h-3.5 w-3.5' />"

  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)
  attr(:data_source, :string, default: nil)
  attr(:generating, :boolean, default: false)

  defp ai_action_buttons(assigns) do
    assigns =
      assigns
      |> assign(:explain_reason, ai_unsupported_reason(assigns.data_source, :explanation))
      |> assign(:optimize_reason, ai_unsupported_reason(assigns.data_source, :optimization))

    ~H"""
    <div class="flex items-center gap-1.5">
      <button
        type="button"
        phx-click="explain_query"
        phx-target={@parent}
        disabled={ai_action_disabled?(@generating, @current_statement, @explain_reason)}
        title={@explain_reason || gettext("Get a plain-language explanation of your query")}
        class="lotus-ai-chip-button"
      >
        <Icons.brain class="h-3.5 w-3.5" />
        <%= gettext("Explain query") %>
      </button>
      <button
        type="button"
        phx-click="optimize_query"
        phx-target={@parent}
        disabled={ai_action_disabled?(@generating, @current_statement, @optimize_reason)}
        title={@optimize_reason || gettext("Analyze your query and suggest performance improvements")}
        class="lotus-ai-chip-button"
      >
        <Icons.wrench class="h-3.5 w-3.5" />
        <%= gettext("Optimize query") %>
      </button>
    </div>
    """
  end

  defp ai_action_disabled?(generating, current_statement, unsupported_reason),
    do:
      generating or is_nil(current_statement) or current_statement == "" or
        not is_nil(unsupported_reason)

  # An adapter declares per-feature AI capabilities, so a source that cannot
  # explain or optimize says so with a reason. Surface it on a disabled button
  # rather than letting the user click into an error.
  #
  # Anything unexpected here leaves the button enabled: a UI gate that fails
  # closed on an unresolvable source would hide a feature that works.
  defp ai_unsupported_reason(source, feature) when is_binary(source) and source != "" do
    Lotus.AI.unsupported_reason(source, feature)
  rescue
    _ -> nil
  end

  defp ai_unsupported_reason(_source, _feature), do: nil

  attr(:message, :map, required: true)
  attr(:index, :integer, required: true)

  defp optimization_message(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if Map.get(@message, :suggestions, []) == [] do %>
        <p class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
          <span class="lotus-ai-step-dot lotus-ai-step-done"><Icons.check class="h-2.5 w-2.5" /></span>
          <%= gettext("Your query is already well-optimized!") %>
        </p>
      <% else %>
        <p class="text-sm text-gray-700 dark:text-gray-300">
          <%= ngettext(
            "%{count} optimization suggestion:",
            "%{count} optimization suggestions:",
            length(@message.suggestions),
            count: length(@message.suggestions)
          ) %>
        </p>
        <details
          :for={{suggestion, n} <- Enum.with_index(@message.suggestions)}
          id={"ai-suggestion-#{@index}-#{n}"}
          class="lotus-ai-suggestion group/suggestion"
          open={n == 0}
        >
          <summary class="flex items-start gap-3 cursor-pointer list-none">
            <.impact_meter impact={suggestion["impact"] || "medium"} />
            <span class="flex-1 min-w-0">
              <span class="block text-sm font-medium text-gray-900 dark:text-gray-100"><%= suggestion["title"] %></span>
              <span class="mt-0.5 block text-[11px] text-gray-400 dark:text-gray-500">
                <%= suggestion_type(suggestion["type"]) %> · <%= impact_label(suggestion["impact"]) %>
              </span>
            </span>
            <Icons.chevron_down class="h-3.5 w-3.5 mt-1 text-gray-400 transition-transform group-open/suggestion:rotate-180" />
          </summary>
          <div class="mt-2.5 space-y-2 pl-7">
            <%= for {kind, text} <- suggestion_parts(suggestion["suggestion"]) do %>
              <p :if={kind == :text} class="text-xs leading-relaxed text-gray-600 dark:text-gray-300 whitespace-pre-wrap"><%= text %></p>
              <.sql_card :if={kind == :sql} id={"ai-suggestion-sql-#{@index}-#{n}-#{:erlang.phash2(text)}"} statement={text} diff={nil} />
            <% end %>
          </div>
        </details>
      <% end %>
    </div>
    """
  end

  attr(:impact, :string, required: true)

  defp impact_meter(assigns) do
    assigns = assign(assigns, :level, impact_level(assigns.impact))

    ~H"""
    <span class="mt-1 flex items-end gap-0.5 h-3.5 flex-shrink-0" aria-hidden="true">
      <span :for={n <- 1..3} class={["w-1 rounded-sm", n <= @level && "bg-pink-500 dark:bg-pink-400", n > @level && "bg-gray-200 dark:bg-gray-700"]} style={"height: #{n * 33}%"}></span>
    </span>
    """
  end

  attr(:message, :map, required: true)

  defp explanation_message(assigns) do
    ~H"""
    <div class="lotus-ai-explanation">
      <div class="text-sm text-gray-700 dark:text-gray-300 prose prose-sm dark:prose-invert max-w-none prose-p:my-1.5 prose-ul:my-1.5 prose-li:my-0.5 prose-strong:text-gray-900 dark:prose-strong:text-gray-50 prose-code:before:content-none prose-code:after:content-none prose-code:bg-gray-100 prose-code:dark:bg-gray-700/70 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-[11px] prose-code:font-normal"><%= render_markdown(@message.content) %></div>
    </div>
    """
  end

  attr(:generating, :boolean, required: true)
  attr(:parent, :any, required: true)
  attr(:current_statement, :string, default: nil)
  attr(:data_source, :string, default: nil)
  attr(:conversation, :map, required: true)

  defp input_area(assigns) do
    ~H"""
    <div class="flex-shrink-0 px-4 pb-4 pt-2">
      <div :if={@conversation.messages != []} class="mb-2">
        <.ai_action_buttons
          parent={@parent}
          current_statement={@current_statement}
          data_source={@data_source}
          generating={@generating}
        />
      </div>
      <form id="ai-message-form" phx-submit="send_ai_message" phx-target={@parent} class="lotus-ai-composer">
        <textarea
          id="ai-message-input"
          name="message"
          rows="1"
          class="block w-full resize-none border-0 bg-transparent px-3.5 pt-3 pb-1 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:ring-0 focus:outline-none"
          placeholder={if @conversation.messages == [], do: gettext("Ask about your data…"), else: gettext("Ask a follow-up…")}
          required
          disabled={@generating}
          phx-hook="AIMessageInput"
        ></textarea>
        <div class="flex items-center justify-between px-2.5 pb-2">
          <span class="text-[10px] text-gray-400 dark:text-gray-500 pl-1">
            <%= gettext("Enter to send · Shift+Enter for a new line") %>
          </span>
          <button
            type="submit"
            disabled={@generating}
            class="lotus-ai-send"
            aria-label={gettext("Send message")}
          >
            <%= if @generating do %>
              <span class="lotus-ai-send-busy"></span>
            <% else %>
              <Icons.send class="h-4 w-4" />
            <% end %>
          </button>
        </div>
      </form>
    </div>
    """
  end

  # --- Helpers ---

  @doc false
  # The lines of a query against the editor's: `{:eq | :ins | :del, line}`.
  # `nil` when there is nothing to compare: no query in the editor, the same
  # query, or a new one that keeps none of its lines.
  @spec diff(String.t() | nil, String.t() | nil) :: [{:eq | :ins | :del, String.t()}] | nil
  def diff(base, statement) when is_binary(base) and is_binary(statement) do
    old = base |> String.trim() |> String.split("\n")
    new = statement |> String.trim() |> String.split("\n")

    if String.trim(base) == "" or old == new do
      nil
    else
      ops = List.myers_difference(old, new)

      if Keyword.has_key?(ops, :eq) do
        Enum.flat_map(ops, fn {op, lines} -> Enum.map(lines, &{op, &1}) end)
      end
    end
  end

  def diff(_base, _statement), do: nil

  defp count(diff, op), do: Enum.count(diff, &(elem(&1, 0) == op))

  @doc false
  # Prompts to start from, made of the source's own tables: a total by month
  # where a table has a date and an amount, a count by status, the latest rows.
  @spec suggested_prompts(map() | nil) :: [String.t()]
  def suggested_prompts(schema) when is_map(schema) and map_size(schema) > 0 do
    tables = Enum.sort_by(schema, fn {table, columns} -> {-length(columns), table} end)

    by_month =
      Enum.find_value(tables, fn {table, columns} ->
        with date when is_binary(date) <- Enum.find(columns, &date_column?/1),
             amount when is_binary(amount) <- Enum.find(columns, &amount_column?/1) do
          amount = amount |> humanize() |> String.replace_prefix("total ", "")

          gettext("Total %{amount} by month in %{table}", amount: amount, table: short(table))
        else
          _ -> nil
        end
      end)

    by_status =
      Enum.find_value(tables, fn {table, columns} ->
        case Enum.find(columns, &category_column?/1) do
          nil ->
            nil

          column ->
            gettext("How many %{table} are there by %{column}?",
              table: short(table),
              column: humanize(column)
            )
        end
      end)

    latest =
      Enum.find_value(tables, fn {table, columns} ->
        if Enum.any?(columns, &date_column?/1),
          do: gettext("The 10 most recent %{table}", table: short(table))
      end)

    fallback = gettext("Which tables have the most rows?")

    [by_month, by_status, latest, fallback]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(3)
  end

  def suggested_prompts(_schema) do
    [
      gettext("Show all active users"),
      gettext("Count orders by month"),
      gettext("Find top 10 products by revenue")
    ]
  end

  defp date_column?(column),
    do: column =~ ~r/(_at|_on|_date|^date|_time)$/ and column not in ~w(updated_at deleted_at)

  defp amount_column?(column),
    do: column =~ ~r/(amount|total|price|revenue|cost|value|quantity)/

  defp category_column?(column),
    do: column =~ ~r/^(status|state|category|type|kind|role|plan|tier|country)$/

  defp short(table), do: table |> String.split(".") |> List.last() |> humanize()
  defp humanize(name), do: String.replace(name, "_", " ")

  @doc false
  # A suggestion's text, its statements apart: an index to create, a rewrite.
  @spec suggestion_parts(String.t() | nil) :: [{:text | :sql, String.t()}]
  def suggestion_parts(text) when is_binary(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map(fn part ->
      part = String.trim(part)

      if part =~ ~r/^(CREATE|ALTER|SELECT|WITH|DROP|SET|ANALYZE|VACUUM)\b/i,
        do: {:sql, part},
        else: {:text, part}
    end)
  end

  def suggestion_parts(_text), do: []

  defp suggestion_type("index"), do: gettext("Index")
  defp suggestion_type("rewrite"), do: gettext("Rewrite")
  defp suggestion_type("structure"), do: gettext("Structure")
  defp suggestion_type("configuration"), do: gettext("Configuration")
  defp suggestion_type(other), do: other || gettext("Rewrite")

  defp impact_level("high"), do: 3
  defp impact_level("low"), do: 1
  defp impact_level(_impact), do: 2

  defp impact_label("high"), do: gettext("high impact")
  defp impact_label("low"), do: gettext("low impact")
  defp impact_label(_impact), do: gettext("medium impact")

  defp chart_action("line"), do: gettext("Use as line chart")
  defp chart_action("bar"), do: gettext("Use as bar chart")
  defp chart_action("kpi"), do: gettext("Use as KPI card")
  defp chart_action(_type), do: gettext("Use as chart")

  # The points of a mini chart in its 300×80 box: `{x, y}` for a line,
  # `{x, y, width}` for bars; and the last point of a line.
  defp chart_geometry(%{type: type, points: points}) do
    values = Enum.map(points, &elem(&1, 1))
    {low, high} = Enum.min_max(values)
    low = if type == "bar", do: min(low, 0), else: low
    span = if high == low, do: 1, else: high - low
    y = fn value -> 76 - (value - low) / span * 70 end
    n = length(points)

    case type do
      "bar" ->
        slot = 300 / n
        width = slot * 0.68

        geometry =
          values
          |> Enum.with_index()
          |> Enum.map(fn {value, i} ->
            {r(i * slot + (slot - width) / 2), r(y.(value)), r(width)}
          end)

        {geometry, nil}

      _line ->
        step = 300 / max(n - 1, 1)

        geometry =
          values |> Enum.with_index() |> Enum.map(fn {v, i} -> {r(i * step), r(y.(v))} end)

        {geometry, List.last(geometry)}
    end
  end

  defp r(number), do: Float.round(number * 1.0, 2)

  defp polyline(points), do: Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)

  defp area_path([{x0, _} | _] = points) do
    {xn, _} = List.last(points)
    "M#{x0},80 L" <> Enum.map_join(points, " L", fn {x, y} -> "#{x},#{y}" end) <> " L#{xn},80 Z"
  end

  defp round_value(value) when is_float(value), do: Float.round(value, 2)
  defp round_value(value), do: value

  defp time(%{timestamp: %DateTime{} = timestamp}), do: Calendar.strftime(timestamp, "%H:%M")
  defp time(_message), do: nil

  defp variables_only_change?(message, current_statement) do
    message.statement != nil and
      Map.get(message, :variables, []) != [] and
      normalize_statement(message.statement) == normalize_statement(current_statement)
  end

  defp normalize_statement(nil), do: nil

  defp normalize_statement(sql) when is_binary(sql),
    do: sql |> String.trim() |> String.replace(~r/\s+/, " ")

  defp variable_summary(variables) when is_list(variables) and variables != [] do
    details =
      Enum.map_join(variables, ", ", fn v ->
        name = v["name"] || v["label"] || "?"
        widget = format_widget_type(v["widget"])
        "#{name} (#{widget})"
      end)

    ngettext(
      "%{count} variable: %{details}",
      "%{count} variables: %{details}",
      length(variables),
      count: length(variables),
      details: details
    )
  end

  defp variable_summary(_), do: ""

  defp render_markdown(text), do: Lotus.Web.Markdown.to_safe_html(text)

  defp format_widget_type("select"), do: gettext("dropdown")
  defp format_widget_type("input"), do: gettext("text input")
  defp format_widget_type(_), do: gettext("text input")

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(visible: false)
     |> assign(generating: false)
     |> assign(conversation: new_conversation())
     |> assign(current_statement: nil)
     |> assign(steps: [], action: nil, schema: nil, lotus_mark: true)}
  end

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    {:ok, assign(socket, params)}
  end

  defp new_conversation do
    %{
      messages: [],
      source_context: %{tables_analyzed: []},
      generation_count: 0,
      started_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }
  end
end
