defmodule Lotus.Web.QueryEditorPage do
  @moduledoc false

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  @default_page_size 1000

  alias Lotus.Storage.Query
  alias Lotus.Web.ExportController
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter
  alias Lotus.Web.Page
  alias Lotus.Web.Queries.AiAssistantComponent
  alias Lotus.Web.Queries.DropdownOptionsModal
  alias Lotus.Web.Queries.SchemaExplorerComponent
  alias Lotus.Web.Queries.VariableSettingsComponent
  alias Lotus.Web.Queries.VisualizationSettingsComponent
  alias Lotus.Web.QueryEditor.Variables
  alias Lotus.Web.SchemaBuilder
  alias Lotus.Web.SourcesMap
  alias Lotus.Web.VegaSpecBuilder

  import Lotus.Web.Queries.EditorComponent
  import Lotus.Web.Queries.ResultsComponent
  import Lotus.Web.Queries.ResultsPillComponent

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="query-editor-page" class="flex flex-col h-full overflow-y-auto">
      <div id="toast-listener" phx-hook="Toast" class="hidden"></div>
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 min-h-full sm:h-full flex flex-col">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg min-h-full sm:h-full flex flex-col">
          <.header statement_empty={@statement_empty} query={@query} mode={@page.mode} />

          <div class="relative flex-1 sm:overflow-hidden">
            <%= if @left_drawer != nil or @right_drawer != nil do %>
              <div class="fixed inset-0 bg-black/50 z-10 sm:hidden"
                   phx-click={if @left_drawer, do: "close_left_drawer", else: "close_right_drawer"}
                   phx-target={@myself}>
              </div>
            <% end %>

            <.live_component
              module={VisualizationSettingsComponent}
              id="visualization-settings"
              visible={@left_drawer == :visualization}
              parent={@myself}
              drawer_tab={@visualization_drawer_tab}
              config={@visualization_config}
              columns={if @result, do: @result.columns, else: []}
            />

            <.live_component
              module={SchemaExplorerComponent}
              id="schema-explorer"
              visible={@right_drawer == :schema_explorer}
              parent={@myself}
              initial_db={@query_form[:data_source].value}
            />

            <.live_component
              module={VariableSettingsComponent}
              id="variable-settings"
              visible={@right_drawer == :variable_settings}
              form={@query_form}
              parent={@myself}
              active_tab={@variable_settings_active_tab}
              optional_variable_names={@optional_variable_names}
            />

            <.live_component
              module={AiAssistantComponent}
              id="ai-assistant"
              visible={@left_drawer == :ai_assistant}
              parent={@myself}
              data_source={@query_form[:data_source].value}
              generating={@ai_generating}
              conversation={@ai_conversation}
              current_sql={@query_form[:statement].value}
            />

            <div class={[
              "transition-all duration-300 ease-in-out flex flex-col h-full sm:overflow-y-auto",
              if(@left_drawer == :visualization, do: "sm:ml-80", else: ""),
              if(@left_drawer == :ai_assistant, do: "sm:ml-96", else: ""),
              if(@right_drawer == :schema_explorer, do: "sm:mr-80", else: ""),
              if(@right_drawer == :variable_settings, do: "sm:mr-80", else: "")
            ]}>

              <div id={"results-visibility-tracker-#{Map.get(@page, :id, "new")}"} phx-hook="ResultsVisibility">
                <.editor
                  form={@query_form}
                  target={@myself}
                  minimized={@editor_minimized}
                  data_source_names={@data_source_names}
                  schema={@editor_schema}
                  dialect={@editor_dialect}
                  running={@running}
                  statement_empty={@statement_empty}
                  right_drawer={@right_drawer}
                  left_drawer={@left_drawer}
                  ai_generating={@ai_generating}
                  variables={@query.variables}
                  variable_values={Map.get(assigns, :variable_values, %{})}
                  resolved_variable_options={@resolved_variable_options}
                  optional_variable_names={@optional_variable_names}
                  query_timeout={@query_timeout}
                  timeout_options_enabled={:timeout_options in (@features || [])}
                  source_type={@source_type}
                  data_source={@default_source}
                />

                <.results_pill
                  error={@error}
                  result={@result}
                  target={@myself}
                  results_visible={Map.get(assigns, :results_visible, true)}
                />
              </div>

              <div class="flex-1">
                <.render_result
                  query_id={Map.get(@page, :id, "new")}
                  result={@result}
                  error={@error}
                  running={@running}
                  os={Map.get(assigns, :os, :unknown)}
                  target={@myself}
                  is_saved_query={@page.mode == :edit}
                  filters={@filters}
                  sorts={@sorts}
                  visualization_config={@visualization_config}
                  visualization_view_mode={@visualization_view_mode}
                  visualization_visible={@left_drawer == :visualization}
                />
              </div>

            </div>
          </div>
        </div>
      </div>

      <.save_modal query_form={@query_form} target={@myself} />
      <.delete_modal :if={@page.mode == :edit} target={@myself} />

      <%= if @modal == :dropdown_options do %>
        <.live_component
          module={DropdownOptionsModal}
          id="dropdown_options_modal"
          variable_name={@dropdown_options_variable_name}
          variable_data={Variables.get_data(@query_form, @dropdown_options_variable_name)}
          parent={@myself}
        />
      <% end %>
    </div>
    """
  end

  defp header(assigns) do
    ~H"""
    <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
      <div class="flex items-center gap-3">
        <.link navigate={lotus_path("")} class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
          <Icons.chevron_left class="h-5 w-5" />
        </.link>
        <h2 class="text-xl font-semibold text-text-light dark:text-text-dark">
        <%= if @mode == :new do %>
          <%= gettext("New Query") %>
        <% else %>
          <%= @query.name || gettext("Untitled") %>
        <% end %>
      </h2>
      </div>
      <div class="flex gap-3">
        <%= if @mode == :edit do %>
          <.button
            type="button"
            variant="light"
            phx-click={show_modal("delete-query-modal")}
            class="text-red-600 hover:text-red-700 border-transparent hover:bg-red-50 dark:text-red-400 dark:hover:text-red-300 dark:border-transparent dark:hover:bg-white/10"
          >
            <%= gettext("Delete") %>
          </.button>
        <% end %>
        <.button
          type="button"
          disabled={@statement_empty}
          phx-click={show_modal("save-query-modal")}
          class={@statement_empty && "opacity-50 cursor-not-allowed"}
        >
          <%= gettext("Save") %>
        </.button>
      </div>
    </div>
    """
  end

  defp save_modal(assigns) do
    ~H"""
    <.modal id="save-query-modal">
      <h3 class="text-lg font-semibold mb-4"><%= gettext("Save Query") %></h3>

      <.form for={@query_form}
             phx-submit="save_query"
             phx-change="validate_save"
             phx-target={@target}>
        <div class="space-y-4">
          <.input
            field={@query_form[:name]}
            type="text"
            label={gettext("Name")}
            placeholder={gettext("Enter query name")}
            required
          />
          <.input
            field={@query_form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter query description (optional)")}
            rows="3"
          />
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <.button
            type="button"
            variant="light"
            phx-click={hide_modal("save-query-modal")}
          >
            <%= gettext("Cancel") %>
          </.button>
          <.button
            type="submit"
            phx-click={hide_modal("save-query-modal")}
            disabled={String.trim(Phoenix.HTML.Form.input_value(@query_form, :name) || "") == ""}
          >
            <%= gettext("Save Query") %>
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp delete_modal(assigns) do
    ~H"""
    <.modal id="delete-query-modal">
      <h3 class="text-lg font-semibold mb-4"><%= gettext("Delete query") %></h3>
      <p class="text-sm text-gray-500 dark:text-gray-400 mb-6">
        <%= gettext("Are you sure you want to delete this query? This action cannot be undone.") %>
      </p>
      <div class="flex justify-end gap-3">
        <.button
          type="button"
          variant="light"
          phx-click={hide_modal("delete-query-modal")}
        >
          <%= gettext("Cancel") %>
        </.button>
        <.button
          type="button"
          phx-click="delete_query"
          phx-target={@target}
          class="bg-red-600 hover:bg-red-700 focus-visible:outline-red-600"
        >
          <%= gettext("Delete") %>
        </.button>
      </div>
    </.modal>
    """
  end

  @impl Lotus.Web.Page
  def handle_mount(socket) do
    socket
    |> assign_data_sources()
    |> assign_ui_state()
  end

  @impl Lotus.Web.Page
  def handle_params(_params, _uri, socket) do
    case socket.assigns.page do
      %{mode: :edit, id: id} ->
        case Lotus.get_query(id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Query not found"))
             |> push_navigate(to: lotus_path(:queries))}

          %Query{} = query ->
            {:noreply,
             socket
             |> ensure_query_repo_default(query)
             |> assign_query_changeset(query)
             |> load_visualization(query)
             |> maybe_auto_run_query()}
        end

      %{mode: :new} ->
        query = %Query{
          name: "",
          description: "",
          statement: "",
          data_source: socket.assigns.default_source,
          variables: []
        }

        {:noreply, assign_query_changeset(socket, query)}
    end
  end

  # ── UI State Machine ──────────────────────────────────────────────────

  @impl Phoenix.LiveComponent
  def handle_event("close_left_drawer", _params, socket) do
    {:noreply, assign(socket, left_drawer: nil)}
  end

  def handle_event("close_right_drawer", _params, socket) do
    {:noreply, assign(socket, right_drawer: nil, variable_settings_active_tab: nil)}
  end

  def handle_event("close_variable_settings", _params, socket) do
    {:noreply, assign(socket, right_drawer: nil, variable_settings_active_tab: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("switch_variable_tab", %{"tab" => tab}, socket) do
    active_tab =
      case tab do
        "settings" -> :settings
        "help" -> :help
        _ -> :settings
      end

    {:noreply, assign(socket, variable_settings_active_tab: active_tab)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("results-visibility-changed", %{"visible" => visible}, socket) do
    {:noreply, assign(socket, results_visible: visible)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("scroll_to_results", _params, socket) do
    {:noreply,
     push_event(socket, "scroll-to-element", %{
       id: "query-results-#{Map.get(socket.assigns.page, :id, "new")}"
     })}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", params, socket) do
    query_params = Map.get(params, "query", %{})

    existing_vars = socket.assigns.variable_values || %{}

    var_params =
      params
      |> Map.get("variables", %{})
      |> Map.reject(fn {name, v} -> v == "" and not Map.has_key?(existing_vars, name) end)

    changeset = build_query_changeset(socket.assigns.query, query_params)

    statement_empty =
      query_params["statement"]
      |> case do
        nil -> check_statement_empty(socket.assigns.query.statement)
        statement -> check_statement_empty(statement)
      end

    send_update(SchemaExplorerComponent,
      id: "schema-explorer",
      initial_db: query_params["data_source"]
    )

    query = Ecto.Changeset.apply_changes(changeset)

    normalized_vars =
      (socket.assigns.variable_values || %{})
      |> Map.merge(var_params)
      |> Variables.clear_values_on_widget_change(query.variables, socket.assigns.query.variables)
      |> Variables.clear_values_on_default_change(query.variables, socket.assigns.query.variables)
      |> Variables.normalize_values(query.variables)

    socket =
      socket
      |> maybe_update_timeout(params)
      |> update_query_state(changeset,
        statement_empty: statement_empty,
        variable_values: normalized_vars
      )
      |> maybe_update_editor_schema(query_params["data_source"])

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("editor_content_changed", %{"statement" => statement}, socket) do
    base_params = socket.assigns.query_form.params || %{}
    params = Map.put(base_params, "statement", statement)
    changeset = Query.update(socket.assigns.query, params)

    socket =
      update_query_state(socket, changeset, statement_empty: check_statement_empty(statement))

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate_save", %{"query" => save_params}, socket) do
    changeset = build_query_changeset(socket.assigns.query, save_params)
    form = build_query_form(changeset)

    statement_present = not check_statement_empty(socket.assigns.query_form)
    name_present = String.trim(Phoenix.HTML.Form.input_value(form, :name) || "") != ""

    {:noreply,
     assign(socket,
       query_changeset: changeset,
       query_form: form,
       save_form_valid: name_present && statement_present
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("save_query", %{"query" => save_params}, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to save queries")]}
      )

      {:noreply,
       socket
       |> push_event("close-modal", %{id: "save-query-modal"})}
    else
      query_attrs = build_query_attrs(save_params, socket.assigns.query)
      result = perform_save_operation(socket.assigns.page, query_attrs)

      case result do
        {:ok, query} ->
          # Save visualization config if present
          save_visualization(query, socket.assigns.visualization_config)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Query saved successfully!"))
           |> push_patch(to: lotus_path(["queries", query.id]), replace: true)
           |> assign(query: query)
           |> assign_query_changeset(query)}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply,
           socket
           |> show_toast(:error, gettext("Failed to save query"))
           |> assign(query_changeset: cs, query_form: to_form(cs, as: "query"))}
      end
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_query", _params, socket) do
    if socket.assigns[:access] == :read_only do
      send(
        self(),
        {:put_flash, [:error, gettext("You don't have permission to delete queries")]}
      )

      {:noreply,
       socket
       |> push_event("close-modal", %{id: "delete-query-modal"})}
    else
      delete_query(socket)
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_editor", _params, socket) do
    {:noreply, assign(socket, editor_minimized: not socket.assigns.editor_minimized)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("expand_editor", _params, socket) do
    {:noreply, assign(socket, editor_minimized: false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("minimize_editor", _params, socket) do
    {:noreply, assign(socket, editor_minimized: true)}
  end

  def handle_event("toggle_schema_explorer", _params, socket) do
    current = socket.assigns.right_drawer

    {:noreply,
     assign(socket,
       right_drawer: if(current == :schema_explorer, do: nil, else: :schema_explorer)
     )}
  end

  def handle_event("close_schema_explorer", _params, socket) do
    {:noreply, assign(socket, right_drawer: nil)}
  end

  def handle_event("toggle_variable_settings", _params, socket) do
    current = socket.assigns.right_drawer

    {:noreply,
     assign(socket,
       right_drawer: if(current == :variable_settings, do: nil, else: :variable_settings)
     )}
  end

  # AI Assistant event handlers

  def handle_event("toggle_ai_assistant", _params, socket) do
    if Lotus.AI.enabled?() do
      conversation =
        if socket.assigns.left_drawer == :ai_assistant do
          socket.assigns.ai_conversation
        else
          socket.assigns[:ai_conversation] || new_conversation()
        end

      new_drawer = if socket.assigns.left_drawer == :ai_assistant, do: nil, else: :ai_assistant

      {:noreply, assign(socket, left_drawer: new_drawer, ai_conversation: conversation)}
    else
      {:noreply,
       socket
       |> put_flash(
         :error,
         gettext("AI features are not configured. Please add AI configuration.")
       )}
    end
  end

  def handle_event("close_ai_assistant", _params, socket) do
    {:noreply, assign(socket, left_drawer: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_ai_conversation", _params, socket) do
    {:noreply, assign(socket, ai_conversation: new_conversation(), ai_pending_variables: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_ai_prompt", _params, socket) do
    {:noreply,
     socket
     |> assign(ai_prompt: "")
     |> assign(ai_error: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("send_ai_message", %{"message" => message}, socket) do
    data_source = resolve_data_source(socket)

    if is_nil(data_source) or data_source == "" do
      conversation =
        add_error_message(
          socket.assigns.ai_conversation,
          gettext("Please select a data source first")
        )

      {:noreply, assign(socket, ai_conversation: conversation)}
    else
      conversation = add_user_message(socket.assigns.ai_conversation, message)
      query_context = build_ai_query_context(socket.assigns)

      socket =
        socket
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_async(:ai_generation, fn ->
          Lotus.AI.generate_query_with_context(
            prompt: message,
            data_source: data_source,
            conversation: conversation,
            query_context: query_context
          )
        end)

      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("use_ai_query", %{"sql" => sql} = params, socket) do
    current_sql = socket.assigns.query_form[:statement].value
    sql_changed = sql != current_sql
    ai_variables = extract_ai_variables(params, socket)

    socket = apply_ai_query(socket, sql, ai_variables)

    flash_message =
      case {sql_changed, ai_variables != nil} do
        {true, true} -> gettext("Query and variable settings applied")
        {true, false} -> gettext("Query inserted into editor")
        {false, true} -> gettext("Variable settings updated")
        {false, false} -> gettext("Query inserted into editor")
      end

    {:noreply, show_toast(socket, :info, flash_message)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("retry_ai_with_error", _params, socket) do
    # Automatically send a message asking AI to fix the last error
    message = gettext("Please fix the error and generate a corrected query")
    handle_event("send_ai_message", %{"message" => message}, socket)
  end

  @impl Phoenix.LiveComponent
  def handle_event("optimize_query", _params, socket) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before optimizing"))}
    else
      data_source = resolve_data_source(socket)

      conversation =
        add_user_message(socket.assigns.ai_conversation, gettext("Optimize this query"))

      socket =
        socket
        |> assign(left_drawer: :ai_assistant)
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_async(:ai_optimization, fn ->
          Lotus.AI.suggest_optimizations(
            sql: sql,
            data_source: data_source
          )
        end)

      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("explain_query", _params, socket) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before explaining"))}
    else
      data_source = resolve_data_source(socket)

      conversation =
        add_user_message(socket.assigns.ai_conversation, gettext("Explain this query"))

      socket =
        socket
        |> assign(left_drawer: :ai_assistant)
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_async(:ai_explanation, fn ->
          Lotus.AI.explain_query(
            sql: sql,
            data_source: data_source
          )
        end)

      {:noreply, socket}
    end
  end

  def handle_event("explain_fragment", %{"fragment" => fragment}, socket) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before explaining"))}
    else
      data_source = resolve_data_source(socket)

      conversation =
        add_user_message(
          socket.assigns.ai_conversation,
          gettext("Explain this fragment: `%{fragment}`", fragment: fragment)
        )

      socket =
        socket
        |> assign(left_drawer: :ai_assistant)
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_async(:ai_explanation, fn ->
          Lotus.AI.explain_query(
            sql: sql,
            fragment: fragment,
            data_source: data_source
          )
        end)

      {:noreply, socket}
    end
  end

  # Visualization event handlers

  def handle_event("smart_toggle_visualization_drawer", _params, socket) do
    if socket.assigns.left_drawer == :visualization do
      {:noreply, assign(socket, left_drawer: nil)}
    else
      tab =
        if has_valid_config?(socket.assigns.visualization_config),
          do: :config,
          else: :types

      {:noreply, assign(socket, left_drawer: :visualization, visualization_drawer_tab: tab)}
    end
  end

  def handle_event("close_visualization_settings", _params, socket) do
    {:noreply, assign(socket, left_drawer: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_chart_type", %{"type" => chart_type}, socket) do
    # Merge with existing config so compatible fields (x_field, y_field, etc.)
    # persist across chart type switches. build_config filters to only the
    # fields relevant for the new chart type.
    existing = socket.assigns[:visualization_config] || %{}
    config = VegaSpecBuilder.build_config(Map.put(existing, "chart_type", chart_type))

    socket =
      socket
      |> assign(visualization_config: config)
      |> assign(visualization_drawer_tab: :config)
      |> maybe_push_chart_update(config)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_visualization_config", params, socket) do
    config = socket.assigns.visualization_config || %{}

    updated =
      config
      |> maybe_put_config("x_field", params["x_field"])
      |> maybe_put_config("y_field", params["y_field"])
      |> put_or_remove_config("series_field", params["series_field"])
      |> maybe_put_config("value_field", params["value_field"])
      |> put_or_remove_config("kpi_label", params["kpi_label"])
      |> maybe_put_config("bin_count", params["bin_count"])
      |> put_or_remove_config("size_field", params["size_field"])
      |> put_or_remove_config("min_value", params["min_value"])
      |> put_or_remove_config("max_value", params["max_value"])
      |> put_or_remove_config("goal_value", params["goal_value"])
      |> put_or_remove_config("comparison_field", params["comparison_field"])
      |> put_or_remove_config("y2_field", params["y2_field"])
      |> put_or_remove_config("y2_axis_title", params["y2_axis_title"])
      |> maybe_put_axis_config(params)

    socket =
      socket
      |> assign(visualization_config: updated)
      |> maybe_push_chart_update(updated)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    view_mode =
      case mode do
        "table" -> :table
        "chart" -> :chart
        _ -> :table
      end

    {:noreply, assign(socket, visualization_view_mode: view_mode)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("switch_visualization_tab", %{"tab" => tab}, socket) do
    drawer_tab =
      case tab do
        "types" -> :types
        "config" -> :config
        _ -> :types
      end

    {:noreply, assign(socket, visualization_drawer_tab: drawer_tab)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("variables_changed", %{"variables" => incoming}, socket) do
    existing_vars = socket.assigns.variable_values || %{}

    filtered =
      Map.reject(incoming, fn {name, v} -> v == "" and not Map.has_key?(existing_vars, name) end)

    merged = Map.merge(existing_vars, filtered)
    normalized = Variables.normalize_values(merged, socket.assigns.query.variables)
    {:noreply, assign(socket, variable_values: normalized)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("open_dropdown_options_modal", %{"variable" => variable_name}, socket) do
    {:noreply,
     assign(socket,
       modal: :dropdown_options,
       dropdown_options_variable_name: variable_name
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("request_editor_schema", _params, socket) do
    data_source = socket.assigns.query.data_source
    socket = maybe_update_editor_schema(socket, data_source)
    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("fetch_dialect_config", %{"dialect" => dialect_name}, socket) do
    config =
      case find_source_for_dialect(dialect_name, socket.assigns) do
        nil -> %{language: "sql", keywords: [], types: [], functions: [], context_boundaries: []}
        source_name -> Lotus.Source.editor_config(source_name)
      end

    {:reply, %{config: config}, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("variables_detected", %{"variables" => names}, socket) do
    names = List.wrap(names)
    existing_variables = socket.assigns.query.variables
    ai_variables = socket.assigns.ai_pending_variables

    ordered_vars = Variables.build_ordered(names, existing_variables, ai_variables)

    socket =
      socket
      |> update_variable_state(ordered_vars, names, %{})
      |> assign(ai_pending_variables: nil)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("copy-to-clipboard-success", _params, socket) do
    {:noreply, show_toast(socket, :info, gettext("Query copied to clipboard!"))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("copy-to-clipboard-error", %{"error" => _error}, socket) do
    {:noreply, show_toast(socket, :error, gettext("Failed to copy to clipboard!"))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("copy_query", _params, socket) do
    {:noreply, push_event(socket, "copy-editor-content", %{})}
  end

  @impl Phoenix.LiveComponent
  def handle_event("export_csv", _params, socket) do
    case socket.assigns.result do
      nil ->
        {:noreply, show_toast(socket, :error, gettext("No query results to export"))}

      %{rows: [], meta: _} ->
        {:noreply, show_toast(socket, :error, gettext("No query results to export"))}

      _result ->
        {:noreply, generate_export_url(socket)}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("run_query", %{"query" => query_params}, socket) do
    changeset = build_query_changeset(socket.assigns.query, query_params)
    form = build_query_form(changeset)

    if check_statement_empty(form) do
      {:noreply,
       assign(socket,
         error: gettext("Please enter a statement"),
         result: nil,
         running: false
       )}
    else
      query = Ecto.Changeset.apply_changes(changeset)

      socket =
        socket
        |> update_query_state(changeset, [])
        |> assign(page_index: 0, filters: [], sorts: [])

      {:noreply, execute_query(socket, query)}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_filter", params, socket) do
    op = parse_filter_op(params["op"])
    value = if op in [:is_null, :is_not_null], do: nil, else: params["value"]
    filter = Lotus.Query.Filter.new(params["column"], op, value)

    if filter in socket.assigns.filters do
      {:noreply, socket}
    else
      filters = socket.assigns.filters ++ [filter]

      socket =
        socket
        |> assign(filters: filters, page_index: 0)
        |> execute_query(socket.assigns.query)

      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("remove_filter", %{"index" => index}, socket) do
    index = String.to_integer(index)
    filters = List.delete_at(socket.assigns.filters, index)

    socket =
      socket
      |> assign(filters: filters, page_index: 0)
      |> execute_query(socket.assigns.query)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(filters: [], page_index: 0)
      |> execute_query(socket.assigns.query)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_sort", %{"column" => col, "direction" => dir}, socket) do
    direction =
      case dir do
        "asc" -> :asc
        "desc" -> :desc
        _ -> :asc
      end

    new_sort = Lotus.Query.Sort.new(col, direction)

    sorts =
      if new_sort in socket.assigns.sorts do
        []
      else
        [new_sort]
      end

    socket =
      socket
      |> assign(sorts: sorts, page_index: 0)
      |> execute_query(socket.assigns.query)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("remove_sort", %{"index" => index}, socket) do
    index = String.to_integer(index)
    sorts = List.delete_at(socket.assigns.sorts, index)

    socket =
      socket
      |> assign(sorts: sorts, page_index: 0)
      |> execute_query(socket.assigns.query)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_sorts", _params, socket) do
    socket =
      socket
      |> assign(sorts: [], page_index: 0)
      |> execute_query(socket.assigns.query)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("next_page", _params, socket) do
    case socket.assigns[:result] do
      %{} = result ->
        meta = Map.get(result, :meta, %{})
        total = Map.get(meta, :total_count)
        page_size = socket.assigns.page_size || @default_page_size
        page_index = socket.assigns.page_index || 0

        can_next =
          if is_integer(total) do
            (page_index + 1) * page_size < total
          else
            length(result.rows || []) == page_size
          end

        if can_next do
          {:noreply,
           socket
           |> assign(page_index: page_index + 1)
           |> execute_query(socket.assigns.query)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("prev_page", _params, socket) do
    current = socket.assigns.page_index || 0
    new_index = max(current - 1, 0)

    if new_index != current do
      {:noreply,
       socket
       |> assign(page_index: new_index)
       |> execute_query(socket.assigns.query)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("goto_page", %{"index" => idx}, socket) do
    case Integer.parse(to_string(idx)) do
      {n, ""} when n >= 0 ->
        {:noreply, socket |> assign(page_index: n) |> execute_query(socket.assigns.query)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl Page
  def handle_info({:source_changed, new_source, _field}, socket) do
    current_query = socket.assigns.query
    updated_query = %{current_query | data_source: new_source}

    socket =
      socket
      |> assign(query: updated_query)
      |> assign_query_changeset(updated_query)
      |> maybe_update_editor_schema(new_source)

    {:noreply, socket}
  end

  def handle_info({:schema_changed, new_search_path, _field}, socket) do
    current_query = socket.assigns.query
    updated_query = %{current_query | search_path: new_search_path}

    socket =
      socket
      |> assign(query: updated_query)
      |> assign_query_changeset(updated_query)
      |> maybe_update_editor_schema(current_query.data_source)

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveComponent
  def handle_async(:ai_generation, {:ok, result}, socket) do
    conversation = socket.assigns.ai_conversation

    case result do
      {:ok, %{sql: sql, variables: variables}} ->
        conversation =
          add_assistant_response(
            conversation,
            gettext("Here's your query:"),
            sql,
            variables || []
          )

        socket =
          socket
          |> assign(ai_generating: false)
          |> assign(ai_conversation: conversation)

        {:noreply, socket}

      {:error, :not_configured} ->
        conversation =
          add_error_message(
            conversation,
            gettext("AI features are not configured")
          )

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, :api_key_not_configured} ->
        conversation =
          add_error_message(
            conversation,
            gettext("API key is missing or invalid")
          )

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, {:unable_to_generate, reason}} when is_binary(reason) ->
        conversation = add_error_message(conversation, reason)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} when is_binary(error) ->
        conversation = add_error_message(conversation, error)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} when is_exception(error) ->
        conversation = add_service_error_message(conversation, Exception.message(error))

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} ->
        conversation =
          add_error_message(
            conversation,
            gettext("Failed to generate query: %{error}", error: inspect(error))
          )

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}
    end
  end

  def handle_async(:ai_generation, {:exit, _reason}, socket) do
    conversation =
      add_error_message(
        socket.assigns.ai_conversation,
        gettext("Query generation timed out or crashed")
      )

    {:noreply,
     socket
     |> assign(ai_generating: false)
     |> assign(ai_conversation: conversation)}
  end

  def handle_async(:ai_optimization, {:ok, result}, socket) do
    conversation = socket.assigns.ai_conversation

    case result do
      {:ok, %{suggestions: suggestions}} ->
        conversation = add_optimization_result(conversation, suggestions)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} when is_exception(error) ->
        conversation = add_service_error_message(conversation, Exception.message(error))

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} ->
        error_msg =
          case error do
            :not_configured -> gettext("AI features are not configured")
            :api_key_not_configured -> gettext("API key is missing or invalid")
            msg when is_binary(msg) -> msg
            other -> gettext("Optimization failed: %{error}", error: inspect(other))
          end

        conversation = add_error_message(conversation, error_msg)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}
    end
  end

  def handle_async(:ai_optimization, {:exit, _reason}, socket) do
    conversation =
      add_error_message(
        socket.assigns.ai_conversation,
        gettext("Query optimization timed out or crashed")
      )

    {:noreply,
     socket
     |> assign(ai_generating: false)
     |> assign(ai_conversation: conversation)}
  end

  def handle_async(:ai_explanation, {:ok, result}, socket) do
    conversation = socket.assigns.ai_conversation

    case result do
      {:ok, %{explanation: explanation}} ->
        conversation = add_explanation_result(conversation, explanation)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} when is_exception(error) ->
        conversation = add_service_error_message(conversation, Exception.message(error))

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}

      {:error, error} ->
        error_msg =
          case error do
            :not_configured -> gettext("AI features are not configured")
            :api_key_not_configured -> gettext("API key is missing or invalid")
            msg when is_binary(msg) -> msg
            other -> gettext("Explanation failed: %{error}", error: inspect(other))
          end

        conversation = add_error_message(conversation, error_msg)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}
    end
  end

  def handle_async(:ai_explanation, {:exit, _reason}, socket) do
    conversation =
      add_error_message(
        socket.assigns.ai_conversation,
        gettext("Query explanation timed out or crashed")
      )

    {:noreply,
     socket
     |> assign(ai_generating: false)
     |> assign(ai_conversation: conversation)}
  end

  def handle_async(:query_execution, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, result: result, error: nil, running: false)}
  end

  def handle_async(:query_execution, {:ok, {:error, error_msg}}, socket) do
    conversation = maybe_add_query_error(socket, error_msg)

    {:noreply,
     socket
     |> assign(error: to_string(error_msg), result: nil, running: false)
     |> assign(ai_conversation: conversation)}
  end

  def handle_async(:query_execution, {:exit, _reason}, socket) do
    conversation = maybe_add_query_error(socket, gettext("Query execution failed"))

    {:noreply,
     socket
     |> assign(error: gettext("Query execution failed"), result: nil, running: false)
     |> assign(ai_conversation: conversation)}
  end

  @impl Phoenix.LiveComponent
  def update(%{action: :close_dropdown_options_modal}, socket) do
    {:ok, assign(socket, modal: nil, dropdown_options_variable_name: nil)}
  end

  def update(%{action: :save_dropdown_options} = assigns, socket) do
    socket =
      socket
      |> update_variable_options(assigns.variable_name, assigns.options_data)
      |> assign(modal: nil, dropdown_options_variable_name: nil)

    {:ok, socket}
  end

  def update(%{action: :test_dropdown_query} = assigns, socket) do
    repo = socket.assigns.query.data_source || socket.assigns.default_source
    search_path = socket.assigns.query.search_path

    case fetch_dropdown_options(assigns.sql_query, repo, search_path, limit: 3, cache: false) do
      {:ok, results} ->
        send_update(DropdownOptionsModal,
          id: "dropdown_options_modal",
          query_test_result: {:ok, results}
        )

      {:error, error} ->
        send_update(DropdownOptionsModal,
          id: "dropdown_options_modal",
          query_test_result: {:error, error}
        )
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp assign_data_sources(socket) do
    data_source_names = Lotus.list_data_source_names()
    {default_source, _module} = Lotus.default_data_source()
    sources_map = SourcesMap.build()

    source_type = Lotus.Source.source_type(default_source)

    socket
    |> assign(data_source_names: data_source_names, default_source: default_source)
    |> assign(sources_map: sources_map)
    |> assign(source_type: source_type)
  end

  defp show_toast(socket, kind, message) do
    push_event(socket, "toast", %{kind: kind, message: message})
  end

  defp resolve_data_source(socket) do
    case socket.assigns.query_form[:data_source].value do
      nil -> socket.assigns.default_source
      "" -> socket.assigns.default_source
      data_source -> data_source
    end
  end

  defp assign_ui_state(socket) do
    assign(socket,
      result: nil,
      error: nil,
      running: false,
      page_size: @default_page_size,
      page_index: 0,
      editor_minimized: false,
      left_drawer: nil,
      right_drawer: nil,
      modal: nil,
      variable_settings_active_tab: nil,
      dropdown_options_variable_name: nil,
      editor_schema: nil,
      editor_dialect: nil,
      optional_variable_names: MapSet.new(),
      detected_variables: [],
      variable_form: to_form(%{}, as: "variables"),
      resolved_variable_options: %{},
      # Quick filters state
      filters: [],
      # Sort state
      sorts: [],
      # Visualization state
      query_timeout: 5_000,
      visualization_config: nil,
      visualization_view_mode: :table,
      visualization_drawer_tab: :types,
      # AI Assistant state
      ai_generating: false,
      ai_conversation: new_conversation(),
      ai_pending_variables: nil
    )
  end

  defp assign_query_changeset(socket, %Query{} = query) do
    changeset = Query.update(query, %{})
    resolved_options = resolve_variable_options(query)

    variable_values =
      case Map.get(socket.assigns, :variable_values) do
        nil ->
          query.variables
          |> Enum.filter(& &1.default)
          |> Map.new(fn v -> {v.name, v.default} end)

        existing ->
          existing
      end

    optional_names = Query.extract_optional_variable_names(query.statement)

    assign(socket,
      query: query,
      query_changeset: changeset,
      query_form: to_form(changeset, as: "query"),
      statement_empty: String.trim(query.statement) == "",
      variable_values: variable_values,
      resolved_variable_options: resolved_options,
      optional_variable_names: optional_names
    )
  end

  defp ensure_query_repo_default(socket, %Query{} = q) do
    if q.data_source in socket.assigns.data_source_names do
      assign(socket, query: q)
    else
      assign(socket, query: %{q | data_source: socket.assigns.default_source})
    end
  end

  defp maybe_auto_run_query(socket) do
    query = socket.assigns[:query]
    variable_values = Map.get(socket.assigns, :variable_values, %{})

    if Lotus.can_run?(query, vars: variable_values) do
      execute_query(socket, query)
    else
      socket
    end
  end

  defp maybe_update_editor_schema(socket, data_source) do
    if data_source && data_source != "" do
      dialect = dialect_for_repo(data_source)
      source_type = Lotus.Source.source_type(data_source)
      search_path = socket.assigns.query && socket.assigns.query.search_path

      case SchemaBuilder.build(socket.assigns.sources_map, data_source, search_path) do
        {:ok, schema} ->
          assign(socket,
            editor_schema: schema,
            editor_dialect: dialect,
            source_type: source_type
          )

        {:error, _reason} ->
          assign(socket,
            editor_schema: nil,
            editor_dialect: dialect,
            source_type: source_type
          )
      end
    else
      assign(socket, editor_schema: nil, editor_dialect: nil)
    end
  end

  defp dialect_for_repo(repo_name) do
    case Lotus.Source.query_language(repo_name) do
      "sql:" <> dialect -> dialect
      "json:" <> _ = full -> full
      _ -> "sql"
    end
  end

  defp find_source_for_dialect(dialect_name, assigns) do
    data_source_names = assigns[:data_source_names] || []

    Enum.find(data_source_names, fn name ->
      case Lotus.Source.query_language(name) do
        "sql:" <> ^dialect_name -> true
        ^dialect_name -> true
        _ -> false
      end
    end)
  end

  defp build_query_changeset(query, params, action \\ :validate) do
    query
    |> Query.update(Variables.normalize_query_params(params))
    |> Map.put(:action, action)
  end

  defp build_query_form(changeset) do
    to_form(changeset, as: "query")
  end

  defp update_query_state(socket, changeset, additional_assigns) do
    form = build_query_form(changeset)
    query = Ecto.Changeset.apply_changes(changeset)

    base_assigns = [
      query: query,
      query_changeset: changeset,
      query_form: form
    ]

    assign(socket, base_assigns ++ additional_assigns)
  end

  defp check_statement_empty(statement) when is_binary(statement) do
    statement |> String.trim() |> Kernel.==("")
  end

  defp check_statement_empty(%Phoenix.HTML.Form{} = form) do
    form[:statement].value
    |> to_string()
    |> check_statement_empty()
  end

  defp check_statement_empty(nil), do: true

  defp maybe_update_timeout(socket, %{"query_timeout" => timeout_str})
       when is_binary(timeout_str) do
    case Integer.parse(timeout_str) do
      {timeout, ""} -> assign(socket, query_timeout: timeout)
      _ -> socket
    end
  end

  defp maybe_update_timeout(socket, _params), do: socket

  defp execute_query(socket, query) do
    vars = Map.get(socket.assigns, :variable_values, %{})
    repo = query.data_source || socket.assigns.default_source
    page_size = socket.assigns.page_size || @default_page_size
    page_index = socket.assigns.page_index || 0
    query_timeout = socket.assigns[:query_timeout]

    filters = Map.get(socket.assigns, :filters, [])
    sorts = Map.get(socket.assigns, :sorts, [])

    opts = [
      repo: repo,
      vars: vars,
      filters: filters,
      sorts: sorts,
      window: [limit: page_size, offset: page_index * page_size, count: :exact]
    ]

    opts =
      if query.search_path && String.trim(query.search_path) != "" do
        Keyword.put(opts, :search_path, query.search_path)
      else
        opts
      end

    opts =
      if is_integer(query_timeout) and query_timeout > 0 do
        opts
        |> Keyword.put(:timeout, query_timeout)
        |> Keyword.put(:statement_timeout_ms, query_timeout)
      else
        opts
      end

    socket
    |> assign(running: true, error: nil, result: nil)
    |> start_async(:query_execution, fn ->
      Lotus.run_query(query, opts)
    end)
  end

  defp update_variable_state(socket, ordered_vars, names, extra_params) do
    params =
      Map.merge(%{"variables" => Enum.map(ordered_vars, &Variables.to_params/1)}, extra_params)

    changeset = build_query_changeset(socket.assigns.query, params)

    current_vals = socket.assigns.variable_values || %{}
    keep = Map.take(current_vals, names)
    old_variables = socket.assigns.query.variables

    with_defaults =
      keep
      |> Variables.merge_defaults(ordered_vars)
      |> Variables.clear_values_on_widget_change(ordered_vars, old_variables)
      |> Variables.normalize_values(ordered_vars)

    prev_names = Enum.map(old_variables, & &1.name)
    new_names = names -- prev_names
    show_settings = new_names != [] and socket.assigns.right_drawer != :variable_settings

    query = Ecto.Changeset.apply_changes(changeset)
    resolved_options = resolve_variable_options(query)
    optional_names = Query.extract_optional_variable_names(query.statement)

    update_query_state(socket, changeset,
      variable_values: with_defaults,
      resolved_variable_options: resolved_options,
      optional_variable_names: optional_names,
      right_drawer: if(show_settings, do: :variable_settings, else: socket.assigns.right_drawer),
      variable_settings_active_tab:
        if(show_settings, do: :settings, else: socket.assigns.variable_settings_active_tab)
    )
  end

  defp build_query_attrs(save_params, current_query) do
    %{
      "name" => save_params["name"],
      "description" => save_params["description"],
      "statement" => current_query.statement,
      "data_source" => current_query.data_source,
      "search_path" => current_query.search_path,
      "variables" => Enum.map(current_query.variables, &Variables.to_params/1)
    }
  end

  defp perform_save_operation(page, query_attrs) do
    case page do
      %{mode: :edit, id: id} ->
        case Lotus.get_query(id) do
          nil -> {:error, "Query not found"}
          %Query{} = query -> Lotus.update_query(query, query_attrs)
        end

      %{mode: :new} ->
        Lotus.create_query(query_attrs)
    end
  end

  defp update_variable_options(socket, variable_name, options_data) do
    current_query = socket.assigns.query

    updated_variables =
      Enum.map(current_query.variables, fn var ->
        if var.name == variable_name do
          %{
            var
            | static_options: options_data.static_options,
              options_query: options_data.options_query
          }
        else
          var
        end
      end)

    updated_query = %{current_query | variables: updated_variables}
    params = %{"variables" => Enum.map(updated_variables, &Variables.to_params/1)}
    changeset = build_query_changeset(updated_query, params)

    resolved_options = resolve_variable_options(updated_query)

    socket
    |> update_query_state(changeset, [])
    |> assign(:resolved_variable_options, resolved_options)
  end

  defp fetch_dropdown_options(sql_query, repo, search_path, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    use_cache = Keyword.get(opts, :cache, true)

    try do
      limited_query =
        if limit do
          Lotus.Source.limit_query(repo, sql_query, limit)
        else
          sql_query
        end

      run_opts = [repo: repo]

      run_opts =
        if search_path && String.trim(search_path) != "" do
          Keyword.put(run_opts, :search_path, search_path)
        else
          run_opts
        end

      run_opts =
        if use_cache do
          Keyword.put(run_opts, :cache, profile: :options)
        else
          run_opts
        end

      case Lotus.run_statement(limited_query, [], run_opts) do
        {:ok, result} ->
          formatted_results = OptionsFormatter.from_lotus_result(result)
          {:ok, formatted_results}

        {:error, error} ->
          {:error, to_string(error)}
      end
    rescue
      error ->
        {:error, gettext("Query execution failed: %{reason}", reason: Exception.message(error))}
    end
  end

  defp resolve_variable_options(%{data_source: nil}), do: %{}
  defp resolve_variable_options(%{data_source: ""}), do: %{}

  defp resolve_variable_options(%{
         data_source: repo,
         search_path: search_path,
         variables: variables
       }) do
    variables
    |> Enum.reduce(%{}, fn var, acc ->
      process_variable_options(var, acc, repo, search_path)
    end)
  end

  defp process_variable_options(var, acc, repo, search_path) do
    case var.options_query do
      nil ->
        acc

      "" ->
        acc

      sql_query when is_binary(sql_query) ->
        case fetch_dropdown_options(sql_query, repo, search_path) do
          {:ok, results} ->
            options = OptionsFormatter.to_select_options(results)
            Map.put(acc, var.name, options)

          {:error, _error} ->
            Map.put(acc, var.name, [])
        end
    end
  end

  defp generate_export_url(socket) do
    query = socket.assigns.query
    vars = Map.get(socket.assigns, :variable_values, %{})
    repo = query.data_source || socket.assigns.default_source

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_naive()
      |> Calendar.strftime("%Y%m%d%H%M%S")

    base_name =
      case query.name do
        name when is_binary(name) and name != "" ->
          name
          |> String.trim()
          |> String.replace(~r/[^\w\s-]/, "")
          |> String.replace(~r/\s+/, "_")
          |> String.downcase()

        _ ->
          "query_results"
      end

    filename = "#{timestamp}_#{base_name}.csv"

    search_path =
      if Lotus.Source.supports_feature?(repo, :search_path),
        do: query.search_path,
        else: nil

    export_params =
      case socket.assigns.page do
        %{mode: :edit, id: id} ->
          %{
            "query_id" => id,
            "repo" => repo,
            "vars" => vars,
            "search_path" => search_path,
            "filename" => filename
          }

        %{mode: :new} ->
          %{
            "query_attrs" => %{
              "statement" => query.statement,
              "variables" => Enum.map(query.variables || [], &Variables.to_params/1)
            },
            "repo" => repo,
            "vars" => vars,
            "search_path" => search_path,
            "filename" => filename
          }
      end

    endpoint = socket.endpoint
    token = ExportController.generate_token(endpoint, export_params)

    export_path = lotus_path([:export, :csv], %{token: URI.encode_www_form(token)})
    push_event(socket, "open-blank", %{location: export_path})
  end

  defp delete_query(socket) do
    query_id = socket.assigns.page.id

    case Lotus.get_query(query_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Query not found"))
         |> push_navigate(to: lotus_path(:queries), replace: true)}

      query ->
        case Lotus.delete_query(query) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Query deleted successfully"))
             |> push_navigate(to: lotus_path(:queries), replace: true)}

          {:error, _} ->
            {:noreply,
             socket
             |> show_toast(:error, gettext("Failed to delete query"))
             |> push_event("close-modal", %{id: "delete-query-modal"})}
        end
    end
  end

  # Visualization persistence

  defp save_visualization(_query, nil), do: :ok
  defp save_visualization(_query, config) when config == %{}, do: :ok

  defp save_visualization(query, config) when is_map(config) do
    case Lotus.list_visualizations(query.id) do
      [] ->
        # Create new visualization
        Lotus.create_visualization(query.id, %{
          name: "Default",
          position: 0,
          config: config
        })

      [existing | _] ->
        # Update existing visualization
        Lotus.update_visualization(existing, %{config: config})
    end
  end

  defp load_visualization(socket, query) do
    case Lotus.list_visualizations(query.id) do
      [viz | _] ->
        assign(socket,
          visualization_config: viz.config,
          visualization_view_mode: :table
        )

      [] ->
        socket
    end
  end

  defp maybe_push_chart_update(socket, config) do
    # Only push update if in chart view mode and config is valid
    if socket.assigns.visualization_view_mode == :chart &&
         socket.assigns.result != nil &&
         has_valid_config?(config) do
      spec = VegaSpecBuilder.build(socket.assigns.result, config)
      push_event(socket, "update-chart", %{spec: spec})
    else
      socket
    end
  end

  defp has_valid_config?(config), do: VegaSpecBuilder.valid_config?(config)

  defp maybe_put_config(map, _key, nil), do: map
  defp maybe_put_config(map, _key, ""), do: map
  defp maybe_put_config(map, key, value), do: Map.put(map, key, value)

  # For optional fields: remove key when empty, put when present
  defp put_or_remove_config(map, key, nil), do: Map.delete(map, key)
  defp put_or_remove_config(map, key, ""), do: Map.delete(map, key)
  defp put_or_remove_config(map, key, value), do: Map.put(map, key, value)

  # Handle axis display config (only for cartesian charts)
  # Check if axis title params exist to know if axis section was rendered
  defp maybe_put_axis_config(config, params) do
    # Only update axis config if the axis section is rendered (not pie chart)
    # We detect this by checking if the title inputs are present in params
    if Map.has_key?(params, "x_axis_title") or Map.has_key?(params, "y_axis_title") do
      config
      |> put_or_remove_config("x_axis_title", params["x_axis_title"])
      |> put_or_remove_config("y_axis_title", params["y_axis_title"])
      |> Map.put("x_axis_show_label", Map.has_key?(params, "x_axis_show_label"))
      |> Map.put("y_axis_show_label", Map.has_key?(params, "y_axis_show_label"))
    else
      config
    end
  end

  # AI Conversation helpers
  defp new_conversation do
    %{
      messages: [],
      schema_context: %{tables_analyzed: []},
      generation_count: 0,
      started_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }
  end

  defp extract_ai_variables(%{"message-index" => index_str}, socket) do
    with {index, ""} <- Integer.parse(index_str),
         %{variables: vars} when is_list(vars) and vars != [] <-
           Enum.at(socket.assigns.ai_conversation.messages, index) do
      vars
    else
      _ -> nil
    end
  end

  defp extract_ai_variables(_params, _socket), do: nil

  defp apply_ai_query(socket, sql, ai_variables) when is_list(ai_variables) do
    names = Query.extract_variables_from_statement(sql)
    existing_variables = socket.assigns.query.variables
    ordered = Variables.build_ordered(names, existing_variables, ai_variables)

    socket
    |> assign(ai_pending_variables: ai_variables)
    |> update_variable_state(ordered, names, %{"statement" => sql})
    |> assign(ai_pending_variables: nil)
  end

  defp apply_ai_query(socket, sql, _ai_variables) do
    changeset = build_query_changeset(socket.assigns.query, %{"statement" => sql})
    update_query_state(socket, changeset, statement_empty: check_statement_empty(sql))
  end

  defp build_ai_query_context(assigns) do
    sql = assigns.query_form[:statement].value

    if is_binary(sql) and sql != "" do
      %{sql: sql, variables: Enum.map(assigns.query.variables, &variable_to_ai_context/1)}
    else
      nil
    end
  end

  defp variable_to_ai_context(v) do
    base = %{
      "name" => v.name,
      "type" => to_string(v.type),
      "widget" => to_string(v.widget),
      "label" => v.label,
      "default" => v.default,
      "list" => v.list
    }

    case v.widget do
      :select ->
        base
        |> Map.put("static_options", Enum.map(v.static_options, &Map.from_struct/1))
        |> Map.put("options_query", v.options_query)

      _ ->
        base
    end
  end

  defp maybe_add_query_error(socket, error_msg) do
    if socket.assigns.left_drawer == :ai_assistant do
      # Get the current SQL from the editor (what the user just ran)
      current_sql = socket.assigns.query.statement
      add_error_message(socket.assigns.ai_conversation, to_string(error_msg), current_sql)
    else
      socket.assigns.ai_conversation
    end
  end

  defp add_user_message(conversation, content) do
    message = %{
      role: :user,
      content: content,
      sql: nil,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_assistant_response(conversation, content, sql, variables) do
    message = %{
      role: :assistant,
      content: content,
      sql: sql,
      variables: variables,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        generation_count: conversation.generation_count + 1,
        last_activity: DateTime.utc_now()
    }
  end

  defp add_optimization_result(conversation, suggestions) do
    message = %{
      role: :optimization,
      content: nil,
      sql: nil,
      suggestions: suggestions,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_explanation_result(conversation, explanation) do
    message = %{
      role: :explanation,
      content: explanation,
      sql: nil,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_error_message(conversation, error_content, sql \\ nil) do
    message = %{
      role: :error,
      content: error_content,
      sql: sql,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_service_error_message(conversation, error_content) do
    message = %{
      role: :service_error,
      content: error_content,
      sql: nil,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp parse_filter_op("eq"), do: :eq
  defp parse_filter_op("neq"), do: :neq
  defp parse_filter_op("gt"), do: :gt
  defp parse_filter_op("lt"), do: :lt
  defp parse_filter_op("gte"), do: :gte
  defp parse_filter_op("lte"), do: :lte
  defp parse_filter_op("like"), do: :like
  defp parse_filter_op("is_null"), do: :is_null
  defp parse_filter_op("is_not_null"), do: :is_not_null
  defp parse_filter_op(_), do: :eq
end
