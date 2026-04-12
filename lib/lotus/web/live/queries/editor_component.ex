defmodule Lotus.Web.Queries.EditorComponent do
  @moduledoc false

  use Lotus.Web, :html

  alias Lotus.Web.Queries.SegmentedDataSelectorComponent
  import Lotus.Web.Queries.WidgetComponent

  @left_drawer_values [nil, :visualization, :ai_assistant]
  @right_drawer_values [nil, :schema_explorer, :variable_settings]

  defp ai_enabled? do
    Lotus.AI.enabled?()
  end

  attr(:minimized, :boolean, default: false)
  attr(:running, :boolean, default: false)
  attr(:statement_empty, :boolean, default: false)
  attr(:right_drawer, :atom, default: nil, values: @right_drawer_values)
  attr(:left_drawer, :atom, default: nil, values: @left_drawer_values)
  attr(:ai_generating, :boolean, default: false)
  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:target, Phoenix.LiveComponent.CID, required: true)
  attr(:data_source_names, :list, default: [])
  attr(:schema, :map, default: %{})
  attr(:dialect, :string, default: "postgres")
  attr(:variables, :list, default: [])
  attr(:variable_values, :map, default: %{})
  attr(:resolved_variable_options, :map, default: %{})
  attr(:optional_variable_names, :any, default: MapSet.new())
  attr(:query_timeout, :integer, default: 5_000)
  attr(:timeout_options_enabled, :boolean, default: false)
  attr(:source_type, :atom, default: :postgres)
  attr(:data_source, :string, default: nil)

  def editor(assigns) do
    search_path_field = assigns.form[:search_path]

    search_path_value =
      case search_path_field.value do
        nil -> ""
        [] -> ""
        list when is_list(list) -> Enum.join(list, ",")
        value when is_binary(value) -> value
      end

    show_search_path =
      (search_path_value != "" &&
         assigns.data_source != nil) and
        Lotus.Source.supports_feature?(assigns.data_source, :search_path)

    assigns =
      assigns
      |> assign(:search_path_value, search_path_value)
      |> assign(:show_search_path, show_search_path)

    ~H"""
    <.form for={@form} phx-submit="run_query" phx-target={@target} phx-change="validate">
      <div class="bg-editor-light dark:bg-editor-dark">
        <.render_toolbar
          form={@form}
          data_source_names={@data_source_names}
          right_drawer={@right_drawer}
          left_drawer={@left_drawer}
          target={@target}
          minimized={@minimized}
          running={@running}
          statement_empty={@statement_empty}
          variables={@variables}
          variable_values={@variable_values}
          resolved_variable_options={@resolved_variable_options}
          optional_variable_names={@optional_variable_names}
          query_timeout={@query_timeout}
          timeout_options_enabled={@timeout_options_enabled}
        />

        <div id="editor-context-menu-wrapper" phx-hook="EditorContextMenu" data-ai-enabled={to_string(ai_enabled?())} class={["relative pb-8", if(@minimized, do: "hidden", else: "")]}>
          <%!-- AI Generation Loading Overlay --%>
          <%= if assigns[:ai_generating] do %>
            <div class="absolute inset-0 bg-white/70 dark:bg-gray-900/70 z-30 flex items-center justify-center backdrop-blur-sm">
              <div class="flex flex-col items-center space-y-3">
                <svg class="animate-spin h-8 w-8 text-pink-600" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                  <%= gettext("AI is thinking...") %>
                </p>
              </div>
            </div>
          <% end %>

          <div id="editor" phx-update="ignore" class="w-full bg-editor-light dark:bg-editor-dark" style="min-height: 300px;"></div>
          <.input type="textarea" field={@form[:statement]} phx-hook="EditorForm" phx-target={@target} style="display: none;" />
          <div
            data-editor-schema={Lotus.JSON.encode!(@schema || %{})}
            data-editor-dialect={@dialect || "postgres"}
            style="display: none;">
          </div>

          <%= if @show_search_path do %>
            <div class="absolute bottom-2 left-4 flex items-center gap-2 text-sm">
              <span class="font-medium text-gray-600 dark:text-gray-400"><%= gettext("search_path:") %></span>
              <code class="px-2 py-0.5 bg-gray-100/80 dark:bg-gray-700/80 backdrop-blur-sm rounded text-xs font-mono text-gray-700 dark:text-gray-300">
                <%= @search_path_value %>
              </code>
            </div>
          <% end %>

          <button
            id="run-query-btn"
            type="submit"
            disabled={@running or @statement_empty}
            class={[
              "absolute bottom-4 right-4 w-12 h-12 rounded-full shadow-lg transition-all duration-200 flex items-center justify-center bg-pink-600",
              if(@running or @statement_empty,
                do: "cursor-not-allowed opacity-50",
                else: "hover:bg-pink-500 hover:shadow-xl transform hover:scale-105"
              )
            ]}
           title={
             if @statement_empty,
               do: gettext("Enter a query to run"),
               else: gettext("Run Query")
           }
          >
            <%= if @running do %>
              <svg class="animate-spin h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            <% else %>
              <Icons.play class="h-5 w-5 text-white ml-0.5" />
            <% end %>
          </button>
        </div>
      </div>
    </.form>
    """
  end

  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:data_source_names, :list, default: [])
  attr(:right_drawer, :atom, default: nil, values: @right_drawer_values)
  attr(:left_drawer, :atom, default: nil, values: @left_drawer_values)
  attr(:target, Phoenix.LiveComponent.CID, required: true)
  attr(:minimized, :boolean, default: false)
  attr(:running, :boolean, default: false)
  attr(:statement_empty, :boolean, default: false)
  attr(:variables, :list, default: [])
  attr(:variable_values, :map, default: %{})
  attr(:resolved_variable_options, :map, default: %{})
  attr(:optional_variable_names, :any, default: MapSet.new())
  attr(:query_timeout, :integer, default: 5_000)
  attr(:timeout_options_enabled, :boolean, default: false)

  def render_toolbar(assigns) do
    ~H"""
    <div class="sticky top-0 z-10 bg-editor-light dark:bg-editor-dark w-full border-b border-gray-200 dark:border-gray-700">
      <span class="sr-only"><%= gettext("Toolbar") %></span>
      <div class="flex flex-col sm:flex-row sm:items-center w-full px-3 sm:px-6 py-3 gap-3 sm:gap-4">
        <div class="flex items-center gap-2 sm:gap-4">
          <.live_component
            module={SegmentedDataSelectorComponent}
            id="data-selector"
            source_field={@form[:data_source]}
            schema_field={@form[:search_path]}
            source_options={Enum.map(@data_source_names, &{&1, &1})}
            source_id="source-selector"
            schema_id="schema-selector"
            target_field="data_source"
            parent={@target}
            disabled={false}
          />
        </div>

        <div class="hidden sm:block w-px self-stretch bg-gray-300 dark:bg-gray-600"></div>

        <div class="flex-1 flex flex-wrap gap-2 sm:gap-3 items-center">
          <%= for v <- @variables do %>
            <.widget
              var={v}
              value={Map.get(@variable_values, v.name, v.default)}
              resolved_options={get_variable_options(@resolved_variable_options, v.name)}
              optional={MapSet.member?(@optional_variable_names, v.name)}
            />
          <% end %>
        </div>

        <div class="flex items-center gap-2 justify-end sm:justify-start">
          <.timeout_selector :if={@timeout_options_enabled} query_timeout={@query_timeout} />
          <.render_actions
            target={@target}
            right_drawer={@right_drawer}
            left_drawer={@left_drawer}
            minimized={@minimized}
            running={@running}
            statement_empty={@statement_empty}
          />
        </div>
      </div>
    </div>
    """
  end

  attr(:query_timeout, :integer, default: 5_000)

  defp timeout_selector(assigns) do
    timeout_options = [
      {"5s", "5000"},
      {"15s", "15000"},
      {"30s", "30000"},
      {"60s", "60000"},
      {"2m", "120000"},
      {"5m", "300000"},
      {gettext("None"), "0"}
    ]

    assigns = assign(assigns, :timeout_options, timeout_options)

    ~H"""
    <div
      id="timeout-selector-tippy"
      class="flex items-center"
      data-title={gettext("Query timeout")}
      phx-hook="Tippy"
    >
      <div class="flex items-center gap-1 text-gray-400 dark:text-gray-500">
        <Icons.clock class="h-4 w-4" />
        <select
          name="query_timeout"
          class="appearance-none bg-transparent border-none text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 focus:ring-0 focus:outline-none cursor-pointer py-0 pl-0 pr-5"
        >
          <%= for {label, value} <- @timeout_options do %>
            <option value={value} selected={to_string(@query_timeout) == value}><%= label %></option>
          <% end %>
        </select>
      </div>
    </div>
    """
  end

  attr(:target, Phoenix.LiveComponent.CID, required: true)
  attr(:right_drawer, :atom, default: nil, values: @right_drawer_values)
  attr(:left_drawer, :atom, default: nil, values: @left_drawer_values)
  attr(:minimized, :boolean, default: false)
  attr(:running, :boolean, default: false)
  attr(:statement_empty, :boolean, default: false)

  def render_actions(assigns) do
    ~H"""
    <div class="flex items-center space-x-1">
      <span
        id="toolbar-run-query-tippy"
        data-title={
          cond do
            @statement_empty -> gettext("Enter a query to run")
            @running -> gettext("Query running...")
            true -> gettext("Run query")
          end
        }
        phx-hook="Tippy"
      >
        <button
          id="toolbar-run-query-btn"
          type="submit"
          disabled={@running or @statement_empty}
          class={[
            "p-2 transition-colors",
            if(@running or @statement_empty,
              do: "text-gray-300 dark:text-gray-600 cursor-not-allowed",
              else: "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
            )
          ]}
        >
          <Icons.play_outline class="h-5 w-5" />
        </button>
      </span>

      <button
        id="copy-query-btn"
        type="button"
        phx-click="copy_query"
        phx-target={@target}
        class="p-2 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400 transition-colors"
        data-title={gettext("Copy query to clipboard")}
        phx-hook="Tippy"
      >
        <Icons.clipboard_copy class="h-5 w-5" />
      </button>

      <button
        id="visualization-btn"
        type="button"
        phx-click="smart_toggle_visualization_drawer"
        phx-target={@target}
        class={[
          "p-2 transition-colors",
          if(@left_drawer == :visualization,
            do: "text-pink-600 hover:text-pink-700",
            else: "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
          )
        ]}
        data-title={gettext("Visualization settings")}
        phx-hook="Tippy"
      >
        <Icons.chart_bar class="h-5 w-5" />
      </button>

      <%!-- AI Assistant button --%>
      <%= if ai_enabled?() do %>
        <button
          id="ai-assistant-btn"
          type="button"
          phx-click="toggle_ai_assistant"
          phx-target={@target}
          class={[
            "p-2 transition-colors",
            if(Map.get(assigns, :left_drawer) == :ai_assistant,
              do: "text-pink-600 hover:text-pink-700",
              else: "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
            )
          ]}
          data-title={gettext("Generate query with AI")}
          phx-hook="Tippy"
        >
          <Icons.robot class="h-5 w-5" />
        </button>
      <% end %>

      <button
        id="variable-settings-btn"
        type="button"
        phx-click="toggle_variable_settings"
        phx-target={@target}
        class={[
          "p-2 transition-colors",
          if(@right_drawer == :variable_settings,
            do: "text-pink-600 hover:text-pink-700",
            else: "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
          )
        ]}
        data-title={gettext("Variable settings")}
        phx-hook="Tippy"
      >
        <Icons.variable class="h-5 w-5" />
      </button>
      <button
        id="schema-explorer-btn"
        type="button"
        phx-click="toggle_schema_explorer"
        phx-target={@target}
        class={[
          "p-2 transition-colors",
          if(@right_drawer == :schema_explorer,
            do: "text-pink-600 hover:text-pink-700",
            else: "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
          )
        ]}
        data-title={gettext("Browse tables")}
        phx-hook="Tippy"
      >
        <Icons.tables class="h-5 w-5" />
      </button>

      <button
        id="toggle-editor-btn"
        type="button"
        phx-click="toggle_editor"
        phx-target={@target}
        class="p-2 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400 transition-colors"
        data-title={
          if @minimized,
            do: gettext("Expand editor"),
            else: gettext("Minimize editor")
        }
        phx-hook="Tippy"
      >
        <%= if @minimized do %>
          <Icons.maximize class="h-5 w-5" />
        <% else %>
          <Icons.minimize class="h-5 w-5" />
        <% end %>
      </button>
    </div>
    """
  end

  defp get_variable_options(options, variable_name) do
    Map.get(options, variable_name)
  end
end
