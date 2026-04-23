defmodule Lotus.Web.Queries.AiAssistantComponent do
  @moduledoc """
  Conversational AI Assistant for generating and refining SQL queries.
  Displays conversation history with message bubbles and supports multi-turn interactions.
  """
  use Lotus.Web, :live_component

  alias Lotus.Web.Components.Icons

  # Assigns:
  # - visible: boolean
  # - parent: Phoenix.LiveComponent.CID
  # - data_source: string (from query_form)
  # - generating: boolean (loading state)
  # - conversation: map (conversation history)
  # - current_sql: string (current SQL in the editor)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "fixed sm:absolute top-0 left-0 h-full w-full sm:w-96",
        "bg-white dark:bg-gray-800",
        "border-r-0 sm:border-r border-gray-200 dark:border-gray-700",
        "z-20 transition-transform duration-300 ease-in-out overflow-hidden",
        "flex flex-col",
        if(@visible, do: "translate-x-0", else: "-translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= if @visible do %>
        <.header parent={@parent} conversation={@conversation} />
        <.conversation_history conversation={@conversation} parent={@parent} current_sql={@current_sql} />
        <.input_area generating={@generating} parent={@parent} current_sql={@current_sql} />
      <% end %>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:conversation, :map, required: true)

  defp header(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900/50 flex-shrink-0">
      <div class="flex items-center justify-between">
        <div class="flex-1">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-gray-100">
            <%= gettext("AI Assistant") %>
          </h3>
          <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            <%= if length(@conversation.messages) == 0 do %>
              <%= gettext("Describe your query in plain English") %>
            <% else %>
              <%= gettext("%{count} messages • %{generations} queries generated",
                count: length(@conversation.messages),
                generations: @conversation.generation_count) %>
            <% end %>
          </p>
        </div>
        <div class="flex items-center gap-1">
          <%= if length(@conversation.messages) > 0 do %>
            <button
              type="button"
              phx-click="clear_ai_conversation"
              phx-target={@parent}
              class="p-1.5 text-gray-400 dark:text-gray-500 hover:text-pink-600 dark:hover:text-pink-400 transition-colors"
              aria-label={gettext("Clear conversation")}
              title={gettext("Clear conversation")}
            >
              <Icons.trash class="h-4 w-4" />
            </button>
          <% end %>
          <button
            type="button"
            phx-click="close_ai_assistant"
            phx-target={@parent}
            class="p-1.5 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
            aria-label={gettext("Close")}
          >
            <Icons.x_mark class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr(:conversation, :map, required: true)
  attr(:parent, :any, required: true)
  attr(:current_sql, :string, default: nil)

  defp conversation_history(assigns) do
    ~H"""
    <div
      id="ai-conversation-history"
      phx-hook="AutoScrollAI"
      class="flex-1 overflow-y-auto p-4 space-y-3"
    >
      <%= if length(@conversation.messages) == 0 do %>
        <.empty_state parent={@parent} current_sql={@current_sql} />
      <% else %>
        <%= for {message, index} <- Enum.with_index(@conversation.messages) do %>
          <.message_bubble message={message} index={index} parent={@parent} current_sql={@current_sql} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:current_sql, :string, default: nil)

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full text-center py-12">
      <div class="p-3 bg-pink-50 dark:bg-pink-900/20 rounded-full mb-4">
        <Icons.sparkles class="h-8 w-8 text-pink-600 dark:text-pink-400" />
      </div>
      <h4 class="text-sm font-medium text-gray-900 dark:text-gray-100 mb-1">
        <%= gettext("Start a conversation") %>
      </h4>
      <p class="text-xs text-gray-500 dark:text-gray-400 max-w-xs">
        <%= gettext("Ask me to generate a SQL query, and I can help you refine it through conversation") %>
      </p>
      <div class="mt-6 text-xs text-gray-400 dark:text-gray-500 space-y-2">
        <p class="font-medium"><%= gettext("Example prompts:") %></p>
        <ul class="space-y-1 text-left">
          <li>• <%= gettext("Show all active users") %></li>
          <li>• <%= gettext("Count orders by month") %></li>
          <li>• <%= gettext("Find top 10 products by revenue") %></li>
        </ul>
      </div>
      <div class="mt-6">
        <p class="text-xs text-gray-400 dark:text-gray-500 mb-2">
          <%= gettext("or use AI on your current query") %>
        </p>
        <.ai_action_buttons
          parent={@parent}
          current_sql={@current_sql}
          generating={false}
          size={:lg}
        />
      </div>
    </div>
    """
  end

  attr(:parent, :any, required: true)
  attr(:current_sql, :string, default: nil)
  attr(:generating, :boolean, default: false)
  attr(:size, :atom, values: [:sm, :lg], default: :sm)

  defp ai_action_buttons(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        type="button"
        phx-click="explain_query"
        phx-target={@parent}
        disabled={ai_action_disabled?(@generating, @current_sql)}
        title={gettext("Get a plain-language explanation of your SQL query")}
        class={[
          ai_action_base_classes(@size),
          if(ai_action_disabled?(@generating, @current_sql),
            do: ai_action_disabled_classes(@size),
            else: "text-cyan-700 dark:text-cyan-300 border-cyan-300 dark:border-cyan-600 hover:bg-cyan-50 dark:hover:bg-cyan-900/20"
          )
        ]}
      >
        <Icons.brain class="h-3.5 w-3.5" />
        <%= gettext("Explain query") %>
      </button>
      <button
        type="button"
        phx-click="optimize_query"
        phx-target={@parent}
        disabled={ai_action_disabled?(@generating, @current_sql)}
        title={gettext("Analyze your SQL and suggest performance improvements")}
        class={[
          ai_action_base_classes(@size),
          if(ai_action_disabled?(@generating, @current_sql),
            do: ai_action_disabled_classes(@size),
            else: "text-amber-700 dark:text-amber-300 border-amber-300 dark:border-amber-600 hover:bg-amber-50 dark:hover:bg-amber-900/20"
          )
        ]}
      >
        <Icons.wrench class="h-3.5 w-3.5" />
        <%= gettext("Optimize query") %>
      </button>
    </div>
    """
  end

  defp ai_action_disabled?(generating, current_sql),
    do: generating or is_nil(current_sql) or current_sql == ""

  defp ai_action_base_classes(:lg),
    do:
      "inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors"

  defp ai_action_base_classes(:sm),
    do:
      "inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md border transition-colors"

  defp ai_action_disabled_classes(_size),
    do: "text-gray-400 dark:text-gray-600 border-gray-200 dark:border-gray-700 cursor-not-allowed"

  attr(:message, :map, required: true)
  attr(:index, :integer, required: true)
  attr(:parent, :any, required: true)
  attr(:current_sql, :string, default: nil)

  defp message_bubble(assigns) do
    ~H"""
    <div class={[
      "flex",
      if(@message.role == :user, do: "justify-end", else: "justify-start")
    ]}>
      <div class={[
        "max-w-[85%] rounded-lg px-3 py-2",
        case @message.role do
          :user -> "bg-pink-100 dark:bg-pink-900/20 text-gray-800 dark:text-pink-100"
          :assistant -> "bg-transparent text-gray-900 dark:text-gray-100"
          :error -> "bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-900 dark:text-red-100"
          :service_error -> "bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 text-amber-900 dark:text-amber-100"
          :optimization -> "bg-transparent text-gray-900 dark:text-gray-100"
          :explanation -> "bg-transparent text-gray-900 dark:text-gray-100"
        end
      ]}>
        <%= case @message.role do %>
          <% :user -> %>
            <p class="text-sm whitespace-pre-wrap"><%= @message.content %></p>

          <% :assistant -> %>
            <div class="space-y-2">
              <%= if @message.content && @message.content != "" do %>
                <p class="text-xs text-gray-600 dark:text-gray-400"><%= @message.content %></p>
              <% end %>

              <%= if @message.sql do %>
                <div class="mt-2 relative group">
                  <pre class="text-xs bg-slate-100 dark:bg-gray-950 text-gray-900 dark:text-gray-100 p-2 rounded overflow-x-auto"><code><%= @message.sql %></code></pre>
                  <%= if Map.get(@message, :variables, []) != [] do %>
                    <div class="mt-1.5 flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
                      <Icons.variable class="h-3.5 w-3.5 text-pink-500 dark:text-pink-400" />
                      <span>
                        <%= variable_summary(Map.get(@message, :variables, [])) %>
                      </span>
                    </div>
                  <% end %>
                  <button
                    type="button"
                    phx-click="use_ai_query"
                    phx-value-sql={@message.sql}
                    phx-value-message-index={@index}
                    phx-target={@parent}
                    class="mt-2 w-full inline-flex items-center justify-center px-3 py-1.5 text-xs font-medium rounded bg-pink-600 hover:bg-pink-700 text-white transition-colors"
                  >
                    <Icons.corner_down_right class="h-3.5 w-3.5 mr-1" />
                    <%= if variables_only_change?(@message, @current_sql) do %>
                      <%= gettext("Apply variable changes") %>
                    <% else %>
                      <%= gettext("Use this query") %>
                    <% end %>
                  </button>
                </div>
              <% end %>
            </div>

          <% :optimization -> %>
            <.optimization_message message={@message} />

          <% :explanation -> %>
            <.explanation_message message={@message} />

          <% :error -> %>
            <div class="space-y-2">
              <div class="flex items-start">
                <Icons.exclamation_triangle class="h-4 w-4 text-red-600 dark:text-red-400 mr-2 flex-shrink-0 mt-0.5" />
                <div class="text-sm">
                  <p class="font-medium"><%= gettext("Query Failed") %></p>
                  <p class="mt-1 text-xs opacity-90"><%= @message.content %></p>
                </div>
              </div>

              <%= if @message.sql do %>
                <details class="mt-2">
                  <summary class="text-xs cursor-pointer text-red-800 dark:text-red-300 hover:underline">
                    <%= gettext("Show failed query") %>
                  </summary>
                  <pre class="mt-1 text-xs bg-red-100 dark:bg-red-950/30 p-2 rounded overflow-x-auto"><code><%= @message.sql %></code></pre>
                </details>
              <% end %>

              <button
                type="button"
                phx-click="retry_ai_with_error"
                phx-target={@parent}
                class="mt-2 w-full inline-flex items-center justify-center px-3 py-1.5 text-xs font-medium rounded bg-red-600 hover:bg-red-700 text-white transition-colors"
              >
                <Icons.rotate_ccw class="h-3.5 w-3.5 mr-1" />
                <%= gettext("Ask AI to fix this") %>
              </button>
            </div>

          <% :service_error -> %>
            <div class="space-y-2">
              <div class="flex items-start">
                <Icons.exclamation_triangle class="h-4 w-4 text-amber-600 dark:text-amber-400 mr-2 flex-shrink-0 mt-0.5" />
                <div class="text-sm">
                  <p class="font-medium"><%= gettext("Service Unavailable") %></p>
                  <p class="mt-1 text-xs opacity-90"><%= @message.content %></p>
                </div>
              </div>
            </div>
        <% end %>

        <p class="text-[10px] mt-1.5 opacity-60">
          <%= Calendar.strftime(@message.timestamp, "%I:%M %p") %>
        </p>
      </div>
    </div>
    """
  end

  attr(:message, :map, required: true)

  defp optimization_message(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if Map.get(@message, :suggestions, []) == [] do %>
        <div class="flex items-center gap-2 text-sm text-green-700 dark:text-green-400">
          <Icons.check class="h-4 w-4 flex-shrink-0" />
          <span><%= gettext("Your query is already well-optimized!") %></span>
        </div>
      <% else %>
        <p class="text-xs text-gray-600 dark:text-gray-400 mb-2">
          <%= ngettext(
            "%{count} optimization suggestion:",
            "%{count} optimization suggestions:",
            length(@message.suggestions),
            count: length(@message.suggestions)
          ) %>
        </p>
        <%= for suggestion <- @message.suggestions do %>
          <div class="rounded-md border border-gray-200 dark:border-gray-700 p-2.5 space-y-1.5">
            <div class="flex items-center gap-1.5 flex-wrap">
              <.suggestion_type_pill type={suggestion["type"] || "rewrite"} />
              <.suggestion_impact_pill impact={suggestion["impact"] || "medium"} />
            </div>
            <p class="text-xs font-semibold text-gray-900 dark:text-gray-100">
              <%= suggestion["title"] %>
            </p>
            <div class="text-xs text-gray-700 dark:text-gray-300 whitespace-pre-wrap"><%= suggestion["suggestion"] %></div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr(:message, :map, required: true)

  defp explanation_message(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-center gap-1.5 mb-1">
        <Icons.brain class="h-3.5 w-3.5 text-cyan-600 dark:text-cyan-400" />
        <span class="text-xs font-medium text-cyan-700 dark:text-cyan-300">
          <%= gettext("Query Explanation") %>
        </span>
      </div>
      <div class="text-sm text-gray-700 dark:text-gray-300 prose prose-sm dark:prose-invert max-w-none prose-p:my-1 prose-ul:my-1 prose-li:my-0.5 prose-code:before:content-none prose-code:after:content-none prose-code:bg-gray-100 prose-code:dark:bg-gray-700 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-xs"><%= render_markdown(@message.content) %></div>
    </div>
    """
  end

  attr(:type, :string, required: true)

  defp suggestion_type_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
      case @type do
        "index" -> "bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300"
        "rewrite" -> "bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-300"
        "structure" -> "bg-teal-100 dark:bg-teal-900/30 text-teal-700 dark:text-teal-300"
        "configuration" -> "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300"
        _ -> "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300"
      end
    ]}>
      <%= @type %>
    </span>
    """
  end

  attr(:impact, :string, required: true)

  defp suggestion_impact_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
      case @impact do
        "high" -> "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300"
        "medium" -> "bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300"
        "low" -> "bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300"
        _ -> "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300"
      end
    ]}>
      <%= @impact %>
    </span>
    """
  end

  attr(:generating, :boolean, required: true)
  attr(:parent, :any, required: true)
  attr(:current_sql, :string, default: nil)

  defp input_area(assigns) do
    ~H"""
    <div class="flex-shrink-0 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900/50 p-4">
      <div class="mb-2">
        <.ai_action_buttons
          parent={@parent}
          current_sql={@current_sql}
          generating={@generating}
          size={:sm}
        />
      </div>
      <form id="ai-message-form" phx-submit="send_ai_message" phx-target={@parent}>
        <div class="flex gap-2">
          <textarea
            id="ai-message-input"
            name="message"
            rows="1"
            class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-transparent bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100 resize-none"
            placeholder={gettext("Type your message...")}
            required
            disabled={@generating}
            phx-hook="AIMessageInput"
          ></textarea>
          <button
            type="submit"
            disabled={@generating}
            class={[
              "flex-shrink-0 p-2.5 rounded-lg transition-colors",
              if(@generating,
                do: "bg-gray-400 cursor-not-allowed",
                else: "bg-pink-600 hover:bg-pink-700"
              )
            ]}
            aria-label={gettext("Send message")}
          >
            <%= if @generating do %>
              <svg class="animate-spin h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            <% else %>
              <Icons.send class="h-5 w-5 text-white" />
            <% end %>
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp variables_only_change?(message, current_sql) do
    message.sql != nil and
      Map.get(message, :variables, []) != [] and
      normalize_sql(message.sql) == normalize_sql(current_sql)
  end

  defp normalize_sql(nil), do: nil

  defp normalize_sql(sql) when is_binary(sql),
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
     |> assign(current_sql: nil)}
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
