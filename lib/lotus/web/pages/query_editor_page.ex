defmodule Lotus.Web.QueryEditorPage do
  @moduledoc false

  @behaviour Lotus.Web.Page

  use Lotus.Web, :live_component

  @default_page_size 1000

  alias Lotus.Query.Statement
  alias Lotus.Storage.Query
  alias Lotus.Web.Actor
  alias Lotus.Web.Authorization
  alias Lotus.Web.Charts
  alias Lotus.Web.ExportController
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter
  alias Lotus.Web.Page
  alias Lotus.Web.Queries.AiAssistantComponent
  alias Lotus.Web.Queries.AiPreview
  alias Lotus.Web.Queries.AiSteps
  alias Lotus.Web.Queries.DropdownOptionsModal
  alias Lotus.Web.Queries.MasuResults
  alias Lotus.Web.Queries.References
  alias Lotus.Web.Queries.SchemaDiagramComponent
  alias Lotus.Web.Queries.SchemaExplorerComponent
  alias Lotus.Web.Queries.VariableSettingsComponent
  alias Lotus.Web.Queries.VisualizationSettingsComponent
  alias Lotus.Web.QueryEditor.Variables
  alias Lotus.Web.SchemaBuilder
  alias Lotus.Web.SourcesMap
  alias Lotus.Web.Telemetry
  alias Phoenix.LiveView.JS

  import Lotus.Web.Queries.EditorComponent
  import Lotus.Web.Queries.ResultsComponent
  import Lotus.Web.Queries.ResultsPillComponent

  @impl Phoenix.LiveComponent
  def render(assigns) do
    source = current_source(assigns)
    {save_action, save_resource} = save_permission(assigns)

    assigns =
      assign(assigns,
        can_save: Authorization.allowed?(assigns, save_action, save_resource),
        can_delete:
          assigns.page.mode == :edit and
            Authorization.allowed?(assigns, :delete_query, assigns.query),
        can_query: Authorization.allowed?(assigns, :query, source),
        can_export: Authorization.allowed?(assigns, :export, source),
        can_ai: Authorization.allowed?(assigns, :ai_generate, source)
      )

    ~H"""
    <div id="query-editor-page" class="flex flex-col h-full overflow-y-auto">
      <div id="toast-listener" phx-hook="Toast" class="hidden"></div>
      <div class="mx-auto w-full px-0 sm:px-0 lg:px-6 py-0 sm:py-6 min-h-full sm:h-full flex flex-col">
        <div class="bg-white dark:bg-gray-800 shadow rounded-lg min-h-full sm:h-full flex flex-col">
          <.header
            statement_empty={@statement_empty}
            query={@query}
            mode={@page.mode}
            can_save={@can_save}
            can_delete={@can_delete}
            can_schedule={:schedules in (@features || []) and Authorization.allowed?(assigns, :manage_schedule)}
            info={Lotus.Web.Pro.request_info(assigns)}
          />

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
              actor={@actor}
              source_names={@data_source_names}
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
              :if={@can_ai}
              module={AiAssistantComponent}
              id="ai-assistant"
              visible={@left_drawer == :ai_assistant}
              parent={@myself}
              data_source={@query_form[:data_source].value}
              generating={@ai_generating}
              conversation={@ai_conversation}
              current_statement={@query_form[:statement].value}
              assistant_name={@branding.assistant_name}
              steps={@ai_steps}
              draft={@ai_draft}
              action={@ai_action}
              schema={@editor_schema}
              lotus_mark={@branding.product_name == "Lotus" and is_nil(@branding.logo)}
            />

            <div class={[
              "transition-all duration-300 ease-in-out flex flex-col h-full sm:overflow-y-auto",
              if(@left_drawer == :visualization, do: "sm:ml-80", else: ""),
              if(@left_drawer == :ai_assistant, do: "sm:ml-[26rem]", else: ""),
              if(@right_drawer == :schema_explorer, do: "sm:mr-80", else: ""),
              if(@right_drawer == :variable_settings, do: "sm:mr-80", else: "")
            ]}>

              <div id={"results-visibility-tracker-#{Map.get(@page, :id, "new")}"} phx-hook="ResultsVisibility">
                <.editor
                  form={@query_form}
                  target={@myself}
                  actor={@actor}
                  minimized={@editor_minimized}
                  data_source_names={@data_source_names}
                  schema={@editor_schema}
                  dialect={@editor_dialect}
                  language={@editor_language}
                  schemas={@editor_schemas}
                  source={@query.data_source}
                  running={@running}
                  can_stop={not is_nil(@cancel_token)}
                  statement_empty={@statement_empty}
                  right_drawer={@right_drawer}
                  left_drawer={@left_drawer}
                  variables={@query.variables}
                  variable_values={Map.get(assigns, :variable_values, %{})}
                  resolved_variable_options={@resolved_variable_options}
                  optional_variable_names={@optional_variable_names}
                  query_timeout={@query_timeout}
                  timeout_options_enabled={:timeout_options in (@features || [])}
                  source_type={@source_type}
                  data_source={@default_source}
                  can_query={@can_query}
                  can_ai={@can_ai}
                  run_scope={@run_scope}
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
                  results_run={Map.get(assigns, :results_run, 0)}
                  filter_operators={Map.get(assigns, :filter_operators, [])}
                  references={@result_references}
                  visualization_config={@visualization_config}
                  visualization_view_mode={@visualization_view_mode}
                  visualization_visible={@left_drawer == :visualization}
                  can_export={@can_export and not @ran_write}
                  changed={@ran_write}
                />
              </div>

            </div>
          </div>
        </div>
      </div>

      <.save_modal :if={@can_save} query_form={@query_form} target={@myself} />
      <.delete_modal :if={@page.mode == :edit and @can_delete} target={@myself} />
      <.write_modal :if={@pending_write} source={@pending_write.source} target={@myself} />

      <%!-- On the body, over everything of the page and its layout. --%>
      <.portal :if={@schema_diagram} id="schema-diagram-portal" target="body">
        <.live_component
          module={SchemaDiagramComponent}
          id="schema-diagram"
          database={@schema_diagram}
          search_path={if @schema_diagram == current_source(assigns), do: @query.search_path}
          source_names={@data_source_names}
          actor={@actor}
          parent={@myself}
        />
      </.portal>

      <%= if @modal == :dropdown_options do %>
        <.live_component
          module={DropdownOptionsModal}
          id="dropdown_options_modal"
          variable_name={@dropdown_options_variable_name}
          variable_data={Variables.get_data(@query_form, @dropdown_options_variable_name)}
          dynamic_options={@dynamic_options}
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
        <h2 class="lotus-title text-xl font-semibold text-text-light dark:text-text-dark">
        <%= if @mode == :new do %>
          <%= gettext("New Query") %>
        <% else %>
          <%= @query.name || gettext("Untitled") %>
        <% end %>
      </h2>
        <.pro_slot
          :if={@mode == :edit}
          name={:query_editor_header}
          slot_assigns={%{query: @query, info: @info}}
        />
      </div>
      <div class="flex gap-3">
        <.link
          :if={@mode == :edit and @can_schedule}
          id="schedule-query"
          navigate={lotus_path(["schedules", "new"], %{"query_id" => @query.id})}
          class="inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-white/10"
        >
          <Icons.clock class="h-4 w-4" /> <%= gettext("Report or alert") %>
        </.link>
        <%= if @mode == :edit and @can_delete do %>
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
          :if={@can_save}
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
             id="save-query-form"
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

  # Asks before a statement that changes data runs.
  defp write_modal(assigns) do
    ~H"""
    <.modal id="write-query-modal" show on_cancel={JS.push("cancel_write", target: @target)}>
      <div class="flex items-start gap-3">
        <Icons.exclamation_triangle class="mt-0.5 h-6 w-6 shrink-0 text-amber-500" />
        <div>
          <h3 id="write-query-modal-title" class="text-lg font-semibold mb-2">
            <%= gettext("Change data in %{source}?", source: @source) %>
          </h3>
          <p id="write-query-modal-description" class="text-sm text-gray-500 dark:text-gray-400 mb-6">
            <%= gettext("This statement changes data, and running it again changes it again. Run it?") %>
          </p>
        </div>
      </div>
      <div class="flex justify-end gap-3">
        <.button type="button" variant="light" phx-click="cancel_write" phx-target={@target}>
          <%= gettext("Cancel") %>
        </.button>
        <.button
          id="write-query-confirm"
          type="button"
          phx-click="confirm_write"
          phx-target={@target}
        >
          <%= gettext("Run it") %>
        </.button>
      </div>
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
  def handle_params(params, _uri, socket) do
    case socket.assigns.page do
      %{mode: :edit, id: id} ->
        case Lotus.get_query(id, Actor.opts(socket.assigns)) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Query not found"))
             |> push_navigate(to: lotus_path(:queries))}

          %Query{} = query ->
            {:noreply,
             socket
             |> report_view(query)
             |> ensure_query_repo_default(query)
             |> prefill_variables(query, params["vars"])
             |> assign_query_changeset(query)
             |> load_visualization(query)
             |> maybe_auto_run_query()}
        end

      %{mode: :new} ->
        case follow_query(socket, params) do
          {:ok, query, values} ->
            {:noreply,
             socket
             |> assign(variable_values: values)
             |> assign_query_changeset(query)
             |> maybe_update_editor_schema(query.data_source)
             |> maybe_auto_run_query()}

          :error ->
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
  end

  # A saved query's view is reported once per connected page load, not on
  # each patch (`Lotus.Web.Telemetry`).
  defp report_view(socket, %Query{id: id} = query) do
    if connected?(socket) and socket.assigns[:viewed_query_id] != id do
      Telemetry.query_view(query, socket.assigns[:context], socket.assigns[:client])
      assign(socket, viewed_query_id: id)
    else
      socket
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
    query_attrs = build_query_attrs(save_params, socket.assigns.query)

    case perform_save_operation(socket, query_attrs) do
      {:ok, query} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Query saved successfully!"))
         |> push_patch(to: lotus_path(["queries", query.id]), replace: true)
         |> assign(query: query)
         |> assign_query_changeset(query)}

      {:error, %Ecto.Changeset{data: %Query{}} = cs} ->
        {:noreply,
         socket
         |> show_toast(:error, gettext("Failed to save query"))
         |> assign(query_changeset: cs, query_form: to_form(cs, as: "query"))}

      {:deny, reason} ->
        {:noreply,
         socket
         |> deny(reason)
         |> push_event("close-modal", %{id: "save-query-modal"})}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Query not found"))
         |> push_navigate(to: lotus_path(:queries), replace: true)}

      {:error, {:halted, reason}} ->
        {:noreply,
         socket
         |> show_toast(:error, refused_message(reason))
         |> push_event("close-modal", %{id: "save-query-modal"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> show_toast(:error, gettext("Failed to save query"))
         |> push_event("close-modal", %{id: "save-query-modal"})}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("delete_query", _params, socket) do
    delete_query(socket)
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

  def handle_event("open_schema_diagram", %{"database" => database}, socket) do
    {:noreply, assign(socket, schema_diagram: database)}
  end

  def handle_event("close_schema_diagram", _params, socket) do
    {:noreply, assign(socket, schema_diagram: nil)}
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
    authorize_ai(socket, fn -> ai_toggle_assistant(socket) end)
  end

  def handle_event("close_ai_assistant", _params, socket) do
    {:noreply, assign(socket, left_drawer: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_ai_conversation", _params, socket) do
    {:noreply,
     assign(socket, ai_conversation: new_conversation(), ai_pending_variables: nil, ai_steps: [])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear_ai_prompt", _params, socket) do
    {:noreply,
     socket
     |> assign(ai_prompt: "")
     |> assign(ai_error: nil)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("send_ai_message", %{"message" => message} = params, socket) do
    context = ai_context(params["context"])
    authorize_ai(socket, fn -> ai_send_message(socket, message, context) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("use_ai_query", %{"statement" => statement} = params, socket) do
    current_statement = socket.assigns.query_form[:statement].value
    statement_changed = statement != current_statement
    ai_variables = extract_ai_variables(params, socket)

    socket = apply_ai_query(socket, statement, ai_variables)

    flash_message =
      case {statement_changed, ai_variables != nil} do
        {true, true} -> gettext("Query and variable settings applied")
        {true, false} -> gettext("Query inserted into editor")
        {false, true} -> gettext("Variable settings updated")
        {false, false} -> gettext("Query inserted into editor")
      end

    {:noreply, show_toast(socket, :info, flash_message)}
  end

  # The chart a preview suggests: the query goes into the editor, runs, and
  # shows as that chart.
  @impl Phoenix.LiveComponent
  def handle_event("use_ai_chart", %{"message-index" => index}, socket) do
    with {index, ""} <- Integer.parse(index),
         %{statement: statement, preview: %{chart: %{} = chart}} <-
           Enum.at(socket.assigns.ai_conversation.messages, index) do
      config =
        case chart do
          %{type: "kpi", y: y} -> %{"chart_type" => "kpi", "value_field" => y}
          %{type: type, x: x, y: y} -> %{"chart_type" => type, "x_field" => x, "y_field" => y}
        end

      socket =
        socket
        |> apply_ai_query(statement, nil)
        |> assign(
          visualization_config: Charts.build_config(config),
          visualization_view_mode: :chart,
          page_index: 0,
          filters: [],
          sorts: [],
          ran_statement: nil
        )
        |> assign(results_run: Map.get(socket.assigns, :results_run, 0) + 1)

      {:noreply, execute_query(socket, socket.assigns.query)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("retry_ai_with_error", _params, socket) do
    # Automatically send a message asking AI to fix the last error
    message = gettext("Please fix the error and generate a corrected query")
    handle_event("send_ai_message", %{"message" => message}, socket)
  end

  @impl Phoenix.LiveComponent
  def handle_event("optimize_query", _params, socket) do
    authorize_ai(socket, fn -> ai_optimize_query(socket) end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("explain_query", _params, socket) do
    authorize_ai(socket, fn -> ai_explain_query(socket) end)
  end

  def handle_event("explain_fragment", %{"fragment" => fragment}, socket) do
    authorize_ai(socket, fn -> ai_explain_fragment(socket, fragment) end)
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
    config = Charts.build_config(Map.put(existing, "chart_type", chart_type))

    socket =
      socket
      |> assign(visualization_config: config)
      |> assign(visualization_drawer_tab: :config)

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
      |> maybe_put_config("map", params["map"])
      |> maybe_put_axis_config(params)
      |> put_chart_options(params)

    {:noreply, assign(socket, visualization_config: updated)}
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

  # The columns of the tables a statement uses, which the editor's
  # autocomplete asks for as the person writes (SchemaBuilder.columns/5).
  @impl Phoenix.LiveComponent
  def handle_event("editor_columns", %{"tables" => tables}, socket) when is_list(tables) do
    {columns, socket} = describe_columns(socket, tables)
    {:reply, %{columns: columns}, socket}
  end

  def handle_event("editor_columns", _params, socket), do: {:reply, %{columns: %{}}, socket}

  @impl Phoenix.LiveComponent
  def handle_event("fetch_dialect_config", %{"dialect" => dialect_name}, socket) do
    config =
      case find_source_for_dialect(dialect_name, socket.assigns) do
        nil ->
          %{language: "sql", keywords: [], types: [], functions: [], context_boundaries: []}

        source_name ->
          source_name
          |> Lotus.Source.editor_config()
          |> Map.put(:tokenizer, tokenizer_profile(source_name))
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
  def handle_event("format_query", _params, socket) do
    {:noreply,
     push_event(socket, "format-editor-content", %{
       dialect: socket.assigns.editor_dialect
     })}
  end

  @impl Phoenix.LiveComponent
  def handle_event("format-editor-content-success", _params, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("format-editor-content-error", %{"error" => error}, socket) do
    {:noreply,
     show_toast(
       socket,
       :error,
       gettext("Could not format query: %{error}", error: error)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("export_csv", _params, socket) do
    case socket.assigns.result do
      nil ->
        {:noreply, show_toast(socket, :error, gettext("No query results to export"))}

      %{rows: [], meta: _} ->
        {:noreply, show_toast(socket, :error, gettext("No query results to export"))}

      _result ->
        case Authorization.authorize(socket.assigns, :export, query_source(socket)) do
          :allow -> {:noreply, generate_export_url(socket)}
          {:deny, reason} -> {:noreply, deny(socket, reason)}
        end
    end
  end

  # What the run buttons run, as the editor reports it: the selection, the
  # statement at the cursor, or the whole query.
  @impl Phoenix.LiveComponent
  def handle_event("editor_run_scope", %{"scope" => scope}, socket) do
    scope =
      case scope do
        "selection" -> :selection
        "statement" -> :statement
        _all -> :all
      end

    {:noreply, assign(socket, run_scope: scope)}
  end

  # The editor sends its whole text as the query's statement, and the part to
  # run (the selection, or the statement at the cursor) as `run_statement`.
  # The query keeps its text; the run, its pages and its export run the part.
  @impl Phoenix.LiveComponent
  def handle_event("run_query", %{"query" => query_params} = params, socket) do
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
      socket =
        socket
        |> update_query_state(changeset, [])
        |> assign(ran_statement: run_statement(params))
        |> assign(page_index: 0, filters: [], sorts: [])
        |> assign(results_run: Map.get(socket.assigns, :results_run, 0) + 1)

      {:noreply, execute_query(socket, query_to_run(socket.assigns))}
    end
  end

  # Stops the running statement. The database is asked from another
  # process: it may take a moment to answer.
  @impl Phoenix.LiveComponent
  def handle_event("cancel_query", _params, socket) do
    case socket.assigns do
      %{running: true, cancel_token: token} when not is_nil(token) ->
        {:noreply,
         socket
         |> assign(cancel_token: nil)
         |> start_async(:cancel_query, fn -> Lotus.cancel(token) end)}

      _not_running ->
        {:noreply, socket}
    end
  end

  # The person said to run the statement that changes data.
  @impl Phoenix.LiveComponent
  def handle_event("confirm_write", _params, socket) do
    case socket.assigns.pending_write do
      %{query: query, source: repo} ->
        socket = assign(socket, pending_write: nil)

        case Authorization.authorize(socket.assigns, :query, repo) do
          :allow -> {:noreply, start_query(socket, query, repo, :write)}
          {:deny, reason} -> {:noreply, assign(socket, error: reason, result: nil)}
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("cancel_write", _params, socket),
    do: {:noreply, assign(socket, pending_write: nil)}

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
           |> execute_query(query_to_run(socket.assigns))}
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
       |> execute_query(query_to_run(socket.assigns))}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def handle_event("goto_page", %{"index" => idx}, socket) do
    case Integer.parse(to_string(idx)) do
      {n, ""} when n >= 0 ->
        {:noreply, socket |> assign(page_index: n) |> execute_query(query_to_run(socket.assigns))}

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

  # The result of each AI action. `handle_async/3` keeps the work that led to
  # it with the message it added.
  defp ai_result(:ai_generation, {:ok, result}, socket) do
    conversation = socket.assigns.ai_conversation

    case result do
      {:ok, %{statement: statement, variables: variables}} ->
        conversation =
          add_assistant_response(
            conversation,
            gettext("Here's your query:"),
            statement,
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

      {:error, :dependency_missing} ->
        conversation = add_error_message(conversation, missing_dependency_message())

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

  defp ai_result(:ai_generation, {:exit, _reason}, socket) do
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

  defp ai_result(:ai_optimization, {:ok, result}, socket) do
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
            :dependency_missing -> missing_dependency_message()
            msg when is_binary(msg) -> msg
            {:ai_feature_unsupported, _feature, reason} -> reason
            other -> gettext("Optimization failed: %{error}", error: inspect(other))
          end

        conversation = add_error_message(conversation, error_msg)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}
    end
  end

  defp ai_result(:ai_optimization, {:exit, _reason}, socket) do
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

  defp ai_result(:ai_explanation, {:ok, result}, socket) do
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
            :dependency_missing -> missing_dependency_message()
            msg when is_binary(msg) -> msg
            {:ai_feature_unsupported, _feature, reason} -> reason
            other -> gettext("Explanation failed: %{error}", error: inspect(other))
          end

        conversation = add_error_message(conversation, error_msg)

        {:noreply,
         socket
         |> assign(ai_generating: false)
         |> assign(ai_conversation: conversation)}
    end
  end

  defp ai_result(:ai_explanation, {:exit, _reason}, socket) do
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

  @ai_tasks [:ai_generation, :ai_optimization, :ai_explanation]

  @impl Phoenix.LiveComponent
  def handle_async(name, result, socket) when name in @ai_tasks do
    steps = socket.assigns.ai_steps
    started_at = socket.assigns.ai_started_at
    elapsed = if started_at, do: now_ms() - started_at
    base = socket.assigns.query_form[:statement].value
    {:noreply, socket} = ai_result(name, result, socket)

    socket =
      socket
      |> assign(ai_steps: [], ai_draft: "", ai_action: nil, ai_started_at: nil)
      |> update(:ai_conversation, &keep_ai_work(&1, steps, elapsed, base))
      |> maybe_preview_ai_answer()

    {:noreply, socket}
  end

  def handle_async({:ai_preview, index}, result, socket) do
    preview =
      case result do
        {:ok, preview} ->
          preview

        {:exit, _reason} ->
          %{AiPreview.loading() | status: :error, error: gettext("The preview stopped")}
      end

    {:noreply, update(socket, :ai_conversation, &put_ai_message(&1, index, :preview, preview))}
  end

  def handle_async(:query_execution, {:ok, {:ok, result, {key, references}}}, socket) do
    {:noreply,
     assign(socket,
       result: result,
       error: nil,
       running: false,
       cancel_token: nil,
       result_references: references,
       references_key: key
     )}
  end

  def handle_async(:query_execution, {:ok, {:error, error_msg}}, socket) do
    conversation = maybe_add_query_error(socket, error_msg)

    {:noreply,
     socket
     |> assign(error: to_string(error_msg), result: nil, running: false, cancel_token: nil)
     |> assign(ai_conversation: conversation)}
  end

  def handle_async(:query_execution, {:exit, _reason}, socket) do
    conversation = maybe_add_query_error(socket, gettext("Query execution failed"))

    {:noreply,
     socket
     |> assign(
       error: gettext("Query execution failed"),
       result: nil,
       running: false,
       cancel_token: nil
     )
     |> assign(ai_conversation: conversation)}
  end

  # Asked the database to stop the statement: the run itself ends with the
  # cancelled error. A statement that ended first has nothing to stop.
  def handle_async(:cancel_query, {:ok, :ok}, socket), do: {:noreply, socket}

  def handle_async(:cancel_query, {:ok, {:error, _reason}}, socket) do
    if socket.assigns.running,
      do:
        {:noreply, assign(socket, cancel_token: nil, error: gettext("Could not stop the query."))},
      else: {:noreply, socket}
  end

  def handle_async(:cancel_query, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveComponent
  def update(%{action: :ai_tool_call, event: event}, socket) do
    # Text the model wrote before it called a tool is not the answer.
    socket = if event[:phase] == :start, do: assign(socket, ai_draft: ""), else: socket
    {:ok, update(socket, :ai_steps, &AiSteps.track(&1, event))}
  end

  # A question from the command palette: the assistant opens and answers it.
  def update(%{action: :ai_ask, question: question}, socket) do
    {:noreply, socket} =
      authorize_ai(socket, fn ->
        socket
        |> assign(left_drawer: :ai_assistant)
        |> ai_send_message(String.trim(question), [])
      end)

    {:ok, socket}
  end

  def update(%{action: :ai_text, text: text}, socket) do
    {:ok, update(socket, :ai_draft, &((&1 || "") <> text))}
  end

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
    repo = query_source(socket)
    search_path = socket.assigns.query.search_path

    dropdown_opts = [limit: 3, cache: false] ++ Actor.opts(socket.assigns)

    result =
      case Authorization.authorize(socket.assigns, :query, repo) do
        :allow -> fetch_dropdown_options(assigns.sql_query, repo, search_path, dropdown_opts)
        {:deny, reason} -> {:error, reason}
      end

    case result do
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

  # The person's sort or filters in the results grid: Lotus's own, and the
  # query again.
  def update(%{action: :masu_query, report: report}, socket) do
    {filters, sorts} = MasuResults.lotus_query(report.query)

    {:ok,
     socket
     |> assign(filters: filters, sorts: sorts, page_index: 0)
     |> execute_query(query_to_run(socket.assigns))}
  end

  # The token that stops the running statement, for the Stop button; a
  # token of an earlier run is spent.
  def update(%{action: :cancel_token, run: run, token: token}, socket) do
    if socket.assigns.running and socket.assigns[:run] == run,
      do: {:ok, assign(socket, cancel_token: token)},
      else: {:ok, socket}
  end

  # A foreign key's cell in the results: its row opens in a new tab.
  def update(%{action: :follow_reference, column: column, value: value}, socket) do
    {:ok, follow_reference(socket, column, value)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # The editor offers, browses and autocompletes only the sources the user may
  # browse, so a denied source's schemas, tables and columns are never listed.
  defp assign_data_sources(socket) do
    data_source_names =
      Enum.filter(
        Lotus.list_data_source_names(),
        &Authorization.discoverable?(socket.assigns, &1)
      )

    {default_source, _module} = Lotus.default_data_source()

    source_type = Lotus.Source.source_type(default_source)

    socket
    |> assign(data_source_names: data_source_names, default_source: default_source)
    |> assign(sources_map: build_sources_map(socket, data_source_names))
    |> assign(source_type: source_type)
  end

  # Building the sources map lists schemas and tables for every source it is
  # given. Skipping it on the disconnected mount keeps those queries off the
  # first render; the connected mount builds it before the editor needs a
  # schema.
  defp build_sources_map(socket, source_names) do
    if connected?(socket),
      do: SourcesMap.build(Actor.opts(socket.assigns), source_names),
      else: %SourcesMap{}
  end

  defp show_toast(socket, kind, message) do
    push_event(socket, "toast", %{kind: kind, message: message})
  end

  defp resolve_data_source(socket), do: current_source(socket.assigns)

  # The source the editor acts on. Render and every handler resolve it the same
  # way, so a hidden control and a handler decision never disagree.
  defp current_source(assigns),
    do: source_or_default(assigns.query_form[:data_source].value, assigns)

  defp source_or_default(source, assigns) when source in [nil, ""], do: assigns.default_source
  defp source_or_default(source, _assigns), do: source

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
      schema_diagram: nil,
      modal: nil,
      variable_settings_active_tab: nil,
      dropdown_options_variable_name: nil,
      editor_schema: nil,
      editor_dialect: nil,
      editor_language: nil,
      # The schemas of the editor's tables, and the columns described so far,
      # by {source, search path} (`editor_columns`).
      editor_schemas: [],
      column_cache: %{},
      dynamic_options: false,
      # What the run buttons run (`:all`, `:statement`, `:selection`), and
      # the part of the text the last run ran, when it was not all of it.
      run_scope: :all,
      ran_statement: nil,
      # The running statement's run, the token that stops it once the source
      # gives one, and a statement that changes data waiting for the person.
      run: nil,
      cancel_token: nil,
      pending_write: nil,
      ran_write: false,
      # The foreign keys of the result's columns, and the run they are of
      # ({source, statement, search path}).
      result_references: %{},
      references_key: nil,
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
      ai_pending_variables: nil,
      ai_steps: [],
      ai_draft: "",
      ai_action: nil,
      ai_started_at: nil
    )
  end

  defp assign_query_changeset(socket, %Query{} = query) do
    changeset = Query.update(query, %{})
    resolved_options = resolve_variable_options(query, socket.assigns)

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

  # A query opened with values for its variables (`?vars[region]=North`,
  # a dashboard card's "Open the query"): its defaults, and these over them.
  # Only on the first open; a name that is no variable of the query is left out.
  defp prefill_variables(socket, %Query{} = query, vars) when is_map(vars) do
    if Map.get(socket.assigns, :variable_values) do
      socket
    else
      names = Enum.map(query.variables, & &1.name)

      values =
        query.variables
        |> Enum.filter(& &1.default)
        |> Map.new(&{&1.name, &1.default})
        |> Map.merge(Map.take(vars, names))
        |> Variables.normalize_values(query.variables)

      assign(socket, variable_values: values)
    end
  end

  defp prefill_variables(socket, _query, _vars), do: socket

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

    # execute_query/2 asks for :query and shows the reason on a deny.
    if Lotus.can_run?(query, vars: variable_values) do
      execute_query(socket, query)
    else
      socket
    end
  end

  defp maybe_update_editor_schema(socket, data_source) do
    if data_source && data_source != "" &&
         Authorization.discoverable?(socket.assigns, data_source) do
      dialect = dialect_for_repo(data_source)
      language = Lotus.Source.query_language(data_source)
      source_type = Lotus.Source.source_type(data_source)
      search_path = socket.assigns.query && socket.assigns.query.search_path

      dynamic_options = dynamic_options?(data_source)

      case SchemaBuilder.build(
             socket.assigns.sources_map,
             data_source,
             search_path,
             Actor.opts(socket.assigns)
           ) do
        {:ok, schema} ->
          # The columns already described for the source, kept from before.
          known = Map.get(socket.assigns[:column_cache] || %{}, {data_source, search_path}, %{})

          assign(socket,
            editor_schema: Map.merge(schema, Map.take(known, Map.keys(schema))),
            editor_schemas:
              SchemaBuilder.schemas(socket.assigns.sources_map, data_source, search_path),
            editor_dialect: dialect,
            editor_language: language,
            source_type: source_type,
            dynamic_options: dynamic_options
          )

        {:error, _reason} ->
          assign(socket,
            editor_schema: nil,
            editor_dialect: dialect,
            editor_language: language,
            source_type: source_type,
            dynamic_options: dynamic_options
          )
      end
    else
      assign(socket,
        editor_schema: nil,
        editor_dialect: nil,
        editor_language: nil,
        dynamic_options: false
      )
    end
  end

  # Describes the editor's tables `keys` not described yet, for a source the
  # person may browse, and keeps their columns in the editor's schema. Gives
  # the columns of `keys` it knows.
  defp describe_columns(socket, keys) do
    data_source = socket.assigns.query.data_source
    search_path = socket.assigns.query.search_path
    schema = socket.assigns.editor_schema || %{}

    wanted =
      Enum.filter(keys, &(is_binary(&1) and Map.has_key?(schema, &1) and is_nil(schema[&1])))

    with [_ | _] <- wanted,
         true <- is_binary(data_source),
         true <- Authorization.discoverable?(socket.assigns, data_source),
         {:ok, columns} <-
           SchemaBuilder.columns(
             socket.assigns.sources_map,
             data_source,
             search_path,
             wanted,
             Actor.opts(socket.assigns)
           ) do
      schema = Map.merge(schema, columns)

      socket =
        socket
        |> assign(editor_schema: schema)
        |> update(:column_cache, fn cache ->
          Map.update(cache || %{}, {data_source, search_path}, columns, &Map.merge(&1, columns))
        end)

      {described(schema, keys), socket}
    else
      _ -> {described(schema, keys), socket}
    end
  end

  defp described(schema, keys) do
    schema |> Map.take(keys) |> Map.reject(fn {_key, columns} -> is_nil(columns) end)
  end

  defp dialect_for_repo(repo_name) do
    case Lotus.Source.query_language(repo_name) do
      "sql:" <> dialect -> dialect
      "json:" <> _ = full -> full
      _ -> "sql"
    end
  end

  defp cancellable?(repo) do
    Lotus.cancellable?(repo)
  rescue
    _error -> false
  end

  # The lexical rules Lotus tokenizes the source's statements with
  # (`Lotus.Query.Tokenizer.Profile`), for the editor's tokenizer to read the
  # text as the server does.
  defp tokenizer_profile(source_name) do
    source_name
    |> Lotus.Source.resolve!(nil)
    |> Lotus.Source.Adapter.lexical_profile()
    |> Map.from_struct()
  rescue
    _error -> nil
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

    socket
    |> assign(base_assigns ++ additional_assigns)
    |> close_denied_ai_drawer()
  end

  # The AI drawer belongs to the selected source. When the user picks a source
  # without :ai_generate, close it rather than leave an empty margin behind.
  defp close_denied_ai_drawer(%{assigns: %{left_drawer: :ai_assistant}} = socket) do
    if Authorization.allowed?(socket.assigns, :ai_generate, resolve_data_source(socket)),
      do: socket,
      else: assign(socket, left_drawer: nil)
  end

  defp close_denied_ai_drawer(socket), do: socket

  defp check_statement_empty(statement) when is_binary(statement) do
    statement |> String.trim() |> Kernel.==("")
  end

  defp check_statement_empty(%Phoenix.HTML.Form{} = form) do
    form[:statement].value
    |> to_string()
    |> check_statement_empty()
  end

  defp check_statement_empty(nil), do: true

  defp run_statement(%{"run_statement" => statement}) when is_binary(statement) do
    if check_statement_empty(statement), do: nil, else: statement
  end

  defp run_statement(_params), do: nil

  # The query as the last run ran it: its own statement, or the part of it
  # the person ran.
  defp query_to_run(%{query: query} = assigns) do
    case assigns[:ran_statement] do
      nil -> query
      statement -> %{query | statement: statement}
    end
  end

  defp maybe_update_timeout(socket, %{"query_timeout" => timeout_str})
       when is_binary(timeout_str) do
    case Integer.parse(timeout_str) do
      {timeout, ""} -> assign(socket, query_timeout: timeout)
      _ -> socket
    end
  end

  defp maybe_update_timeout(socket, _params), do: socket

  # Every run goes through here: the run button, pagination, filters, sorts and
  # the auto-run of a saved query. Ask once, in this one place.
  # Every run of the editor: a statement that changes data waits for the
  # person to say so (`confirm_write`), as running it again would change it
  # again.
  defp execute_query(socket, query) do
    repo = source_or_default(query.data_source, socket.assigns)

    case Authorization.authorize(socket.assigns, :query, repo) do
      :allow ->
        if writes?(query, repo),
          do: assign(socket, pending_write: %{query: query, source: repo}, running: false),
          else: start_query(socket, query, repo)

      {:deny, reason} ->
        assign(socket, running: false, result: nil, error: reason)
    end
  end

  # Whether a statement would change data on a source that takes writes.
  defp writes?(query, repo) do
    not Lotus.read_only?(repo) and Lotus.writes?(query.statement, repo: repo)
  rescue
    _error -> false
  end

  defp start_query(socket, query, repo, kind \\ :read) do
    # A source that can stop a running statement gives a token to stop it
    # with, as it starts: the Stop button's (`cancel_query`).
    run = make_ref()

    opts =
      socket
      |> run_opts(query, repo, kind)
      |> Actor.merge(socket.assigns)
      |> put_cancel_token(socket, repo, run)

    # The results grid keeps the rows it shows while the query runs.
    result = socket.assigns[:result]

    # The foreign keys of the result's columns, found once for a statement.
    key = {repo, query.statement, query.search_path}
    known = if socket.assigns[:references_key] == key, do: socket.assigns.result_references

    references_opts =
      Keyword.take(opts, [:context, :scope, :search_path])

    socket
    |> assign(running: true, error: nil, result: result, run: run, cancel_token: nil)
    |> assign(ran_write: kind == :write)
    # The filters the source runs, which the results grid offers.
    |> assign(filter_operators: Lotus.Source.supported_filter_operators(repo))
    |> start_async(:query_execution, fn ->
      with {:ok, result} <- Lotus.run_query(query, opts) do
        references =
          known ||
            References.for_result(repo, query.statement, result.columns, references_opts)

        {:ok, result, {key, references}}
      end
    end)
  end

  # What a run runs with. A statement that changes data runs as it is
  # written: pages, filters and sorts wrap a statement in a SELECT, which
  # only reads.
  defp run_opts(socket, query, repo, kind) do
    vars = Map.get(socket.assigns, :variable_values, %{})
    page_size = socket.assigns.page_size || @default_page_size
    page_index = socket.assigns.page_index || 0

    case kind do
      :read ->
        [
          repo: repo,
          vars: vars,
          filters: Map.get(socket.assigns, :filters, []),
          sorts: Map.get(socket.assigns, :sorts, []),
          window: [limit: page_size, offset: page_index * page_size, count: :exact]
        ]

      :write ->
        [repo: repo, vars: vars]
    end
    |> put_search_path(query.search_path)
    |> put_timeout(socket.assigns[:query_timeout])
  end

  defp put_search_path(opts, search_path) do
    if search_path && String.trim(search_path) != "",
      do: Keyword.put(opts, :search_path, search_path),
      else: opts
  end

  defp put_timeout(opts, timeout) when is_integer(timeout) and timeout > 0 do
    opts
    |> Keyword.put(:timeout, timeout)
    |> Keyword.put(:statement_timeout_ms, timeout)
  end

  defp put_timeout(opts, _timeout), do: opts

  # The token reaches the page as the statement starts; a page not mounted
  # as a component has no Stop button to show.
  defp put_cancel_token(
         opts,
         %{assigns: %{myself: %Phoenix.LiveComponent.CID{} = myself}},
         repo,
         run
       ) do
    if cancellable?(repo) do
      view = self()

      Keyword.put(opts, :on_cancel_token, fn token ->
        send_update(view, myself, %{action: :cancel_token, run: run, token: token})
      end)
    else
      opts
    end
  end

  defp put_cancel_token(opts, _socket, _repo, _run), do: opts

  # The row a foreign key references opens in a new query, in a new tab, for a
  # person who may query the source. The new query's page builds the
  # statement again from what the source describes (`follow_query/2`).
  defp follow_reference(socket, column, value) do
    query = query_to_run(socket.assigns)
    repo = source_or_default(query.data_source, socket.assigns)

    with %{} = ref <- Map.get(socket.assigns.result_references, column),
         text when is_binary(text) <- References.value_text(value),
         :allow <- Authorization.authorize(socket.assigns, :query, repo) do
      path =
        lotus_path(["queries", "new"], %{
          "follow_source" => repo,
          "follow_schema" => ref.schema,
          "follow_table" => ref.table,
          "follow_column" => ref.column,
          "follow_value" => text
        })

      push_event(socket, "open-blank", %{location: path})
    else
      {:deny, reason} -> deny(socket, reason)
      _ -> socket
    end
  end

  # A new query that opens a referenced row (`?follow_table=…`): for a source
  # the person may browse and query, a table and column the source describes
  # to them.
  defp follow_query(
         socket,
         %{
           "follow_source" => source,
           "follow_table" => table,
           "follow_column" => column,
           "follow_value" => value
         } = params
       )
       when is_binary(source) and is_binary(table) and is_binary(column) and is_binary(value) do
    if source in socket.assigns.data_source_names and
         Authorization.allowed?(socket.assigns, :query, source) do
      References.lookup(
        source,
        params["follow_schema"],
        table,
        column,
        value,
        Actor.opts(socket.assigns)
      )
    else
      :error
    end
  end

  defp follow_query(_socket, _params), do: :error

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
    resolved_options = resolve_variable_options(query, socket.assigns)
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
      "query_language" => query_language_for(current_query.data_source),
      "variables" => Enum.map(current_query.variables, &Variables.to_params/1)
    }
  end

  # The language a saved query is written in, recorded so core can reject the
  # query when its source is later repointed at an engine that speaks a
  # different language. Sources that no longer exist record nothing.
  defp query_language_for(data_source) when is_binary(data_source) and data_source != "" do
    Lotus.Source.query_language(data_source)
  rescue
    ArgumentError -> nil
  end

  defp query_language_for(_data_source), do: nil

  # Whether a query against this source can return a flat list of values to
  # populate a dropdown. Sources that answer `false` (Elasticsearch and other
  # document-shaped languages) get manual option entry only.
  defp dynamic_options?(data_source) when is_binary(data_source) and data_source != "" do
    Lotus.Source.supports_feature?(data_source, :dynamic_options)
  rescue
    ArgumentError -> false
  end

  defp dynamic_options?(_data_source), do: false

  # The query and its chart settings save together: a refused or failed write of
  # either leaves neither saved.
  defp perform_save_operation(socket, query_attrs) do
    with {:ok, stored} <- authorize_save(socket),
         :allow <- authorize_target_source(socket, stored, query_attrs) do
      opts = Actor.opts(socket.assigns)
      config = socket.assigns.visualization_config

      Lotus.repo().transaction(fn -> save_query_and_chart(stored, query_attrs, config, opts) end)
    end
  end

  # Runs inside the transaction: returns the query, or rolls back with the error.
  defp save_query_and_chart(stored, query_attrs, config, opts) do
    with {:ok, query} <- write_query(stored, query_attrs, opts),
         {:ok, _visualization} <- save_visualization(query, config, opts) do
      query
    else
      {:error, reason} -> Lotus.repo().rollback(reason)
    end
  end

  # Authorizes against the stored query, not the one in the editor, which
  # carries the user's unsaved changes. Returns the stored query, or nil for a
  # new one.
  defp authorize_save(%{assigns: %{page: %{mode: :edit, id: id}}} = socket) do
    with %Query{} = query <-
           Lotus.get_query(id, Actor.opts(socket.assigns)) || {:error, :not_found},
         :allow <- Authorization.authorize(socket.assigns, :update_query, query) do
      {:ok, query}
    end
  end

  defp authorize_save(socket) do
    with :allow <- Authorization.authorize(socket.assigns, :create_query), do: {:ok, nil}
  end

  # A save can put the query on another source. Keeping its stored source needs
  # nothing more. Any other source, and the source of a new query, needs :query
  # there, the same as running the query does.
  defp authorize_target_source(socket, stored, query_attrs) do
    target = source_or_default(query_attrs["data_source"], socket.assigns)

    if stored && source_or_default(stored.data_source, socket.assigns) == target,
      do: :allow,
      else: Authorization.authorize(socket.assigns, :query, target)
  end

  defp write_query(nil, attrs, opts), do: Lotus.create_query(attrs, opts)
  defp write_query(%Query{} = query, attrs, opts), do: Lotus.update_query(query, attrs, opts)

  # Saving on an existing query's page updates it; anything else creates one.
  defp save_permission(%{page: %{mode: :edit}, query: %Query{} = query}),
    do: {:update_query, query}

  defp save_permission(_assigns), do: {:create_query, nil}

  defp query_source(socket) do
    source_or_default(socket.assigns.query.data_source, socket.assigns)
  end

  # The flash belongs to the parent LiveView, so a component asks it to set one.
  defp deny(socket, reason) do
    send(self(), {:put_flash, [:error, reason]})
    socket
  end

  # Every AI entry point asks first. The controls are hidden, but an event can
  # still arrive from the editor context menu or a crafted client.
  defp authorize_ai(socket, fun) do
    case Authorization.authorize(socket.assigns, :ai_generate, resolve_data_source(socket)) do
      :allow -> fun.()
      {:deny, reason} -> {:noreply, deny(socket, reason)}
    end
  end

  defp missing_dependency_message do
    gettext(
      "The AI assistant needs the req_llm package. Add {:req_llm, \"~> 1.29\"} to your app's dependencies and restart it."
    )
  end

  defp ai_toggle_assistant(socket) do
    # Open also when AI is configured but cannot run: the panel says why.
    if Lotus.Web.AI.assistant?() do
      conversation =
        if socket.assigns.left_drawer == :ai_assistant do
          socket.assigns.ai_conversation
        else
          socket.assigns[:ai_conversation] || new_conversation()
        end

      new_drawer = if socket.assigns.left_drawer == :ai_assistant, do: nil, else: :ai_assistant

      # The assistant's suggestions are made of tables' columns: describe a
      # few, as the editor describes those its statements use.
      socket =
        if new_drawer == :ai_assistant,
          do:
            socket |> describe_columns(Map.keys(socket.assigns.editor_schema || %{})) |> elem(1),
          else: socket

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

  # What the user pointed at on the page (the AiPicker hook), as it sends it:
  # a few items of `kind`, `label` and `detail`, kept short.
  defp ai_context(json) when is_binary(json) and json != "" do
    case Lotus.JSON.decode(json) do
      {:ok, items} when is_list(items) ->
        items
        |> Enum.filter(&match?(%{"label" => label} when is_binary(label), &1))
        |> Enum.take(8)
        |> Enum.map(fn item ->
          Map.new(~w(kind label detail), &{&1, item[&1] |> to_string() |> String.slice(0, 500)})
        end)

      _ ->
        []
    end
  end

  defp ai_context(_json), do: []

  # The message the model reads: the user's, then what they pointed at.
  defp ai_prompt(message, []), do: message

  defp ai_prompt(message, context) do
    pointed = Enum.map_join(context, "\n", &"- #{&1["detail"] || &1["label"]}")
    message <> "\n\nI am pointing at, on the page:\n" <> pointed
  end

  defp ai_send_message(socket, message, context) do
    data_source = resolve_data_source(socket)

    if is_nil(data_source) or data_source == "" do
      conversation =
        add_error_message(
          socket.assigns.ai_conversation,
          gettext("Please select a data source first")
        )

      {:noreply, assign(socket, ai_conversation: conversation)}
    else
      prompt = ai_prompt(message, context)

      conversation =
        add_user_message(socket.assigns.ai_conversation, prompt,
          display: message,
          context: context
        )

      query_context = build_ai_query_context(socket.assigns)
      actor = Actor.opts(socket.assigns)

      socket =
        socket
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_ai(:ai_generation, :generate, data_source, fn ai_opts ->
          Lotus.AI.generate_query_with_context(
            [
              prompt: prompt,
              data_source: data_source,
              conversation: conversation,
              query_context: query_context
            ] ++ actor ++ ai_opts
          )
        end)

      {:noreply, socket}
    end
  end

  # An AI action runs in a `[:lotus_web, :ai]` span (`Lotus.Web.Telemetry`).
  # `fun` takes the options that tell this process about each tool the model
  # calls, so that the panel shows the work as it happens.
  defp start_ai(socket, name, action, data_source, fun) do
    metadata = %{
      action: action,
      source: data_source,
      context: socket.assigns[:context],
      client: socket.assigns[:client]
    }

    view = self()
    myself = socket.assigns.myself
    ai_opts = [on_tool_call: &send_update(view, myself, %{action: :ai_tool_call, event: &1})]

    # An explanation is read, so it shows as it is written.
    ai_opts =
      if action in [:explain, :explain_fragment],
        do: [{:on_text, &send_update(view, myself, %{action: :ai_text, text: &1})} | ai_opts],
        else: ai_opts

    socket
    |> assign(ai_steps: [], ai_draft: "", ai_action: action, ai_started_at: now_ms())
    |> start_async(name, fn ->
      Telemetry.span([:lotus_web, :ai], metadata, fn -> fun.(ai_opts) end)
    end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp ai_optimize_query(socket) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before optimizing"))}
    else
      data_source = resolve_data_source(socket)
      actor = Actor.opts(socket.assigns)

      conversation =
        add_user_message(socket.assigns.ai_conversation, gettext("Optimize this query"))

      socket =
        socket
        |> assign(left_drawer: :ai_assistant)
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_ai(:ai_optimization, :optimize, data_source, fn ai_opts ->
          Lotus.AI.suggest_optimizations(
            [
              statement: Statement.new(sql),
              data_source: data_source
            ] ++ actor ++ ai_opts
          )
        end)

      {:noreply, socket}
    end
  end

  defp ai_explain_query(socket) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before explaining"))}
    else
      data_source = resolve_data_source(socket)
      actor = Actor.opts(socket.assigns)

      conversation =
        add_user_message(socket.assigns.ai_conversation, gettext("Explain this query"))

      socket =
        socket
        |> assign(left_drawer: :ai_assistant)
        |> assign(ai_generating: true)
        |> assign(ai_conversation: conversation)
        |> start_ai(:ai_explanation, :explain, data_source, fn ai_opts ->
          Lotus.AI.explain_query(
            [
              statement: sql,
              data_source: data_source
            ] ++ actor ++ ai_opts
          )
        end)

      {:noreply, socket}
    end
  end

  defp ai_explain_fragment(socket, fragment) do
    sql = socket.assigns.query_form[:statement].value

    if is_nil(sql) or String.trim(sql) == "" do
      {:noreply, show_toast(socket, :error, gettext("Write a query first before explaining"))}
    else
      data_source = resolve_data_source(socket)
      actor = Actor.opts(socket.assigns)

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
        |> start_ai(:ai_explanation, :explain_fragment, data_source, fn ai_opts ->
          Lotus.AI.explain_query(
            [
              statement: sql,
              fragment: fragment,
              data_source: data_source
            ] ++ actor ++ ai_opts
          )
        end)

      {:noreply, socket}
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

    resolved_options = resolve_variable_options(updated_query, socket.assigns)

    socket
    |> update_query_state(changeset, [])
    |> assign(:resolved_variable_options, resolved_options)
  end

  defp fetch_dropdown_options(sql_query, repo, search_path, opts) do
    limit = Keyword.get(opts, :limit)
    use_cache = Keyword.get(opts, :cache, true)
    actor = Keyword.take(opts, [:context, :scope])

    try do
      limited_query =
        if limit do
          repo
          |> Lotus.Source.limit_query(Statement.new(sql_query), limit)
          |> Map.fetch!(:body)
        else
          sql_query
        end

      run_opts = Keyword.merge(actor, repo: repo)

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

  defp resolve_variable_options(%{data_source: nil}, _assigns), do: %{}
  defp resolve_variable_options(%{data_source: ""}, _assigns), do: %{}

  # An options query runs on the query's source, so it needs :query there too.
  defp resolve_variable_options(
         %{
           data_source: repo,
           search_path: search_path,
           variables: variables
         },
         assigns
       ) do
    if Authorization.allowed?(assigns, :query, repo) do
      opts = Actor.opts(assigns)

      Enum.reduce(variables, %{}, fn var, acc ->
        process_variable_options(var, acc, repo, search_path, opts)
      end)
    else
      %{}
    end
  end

  defp process_variable_options(var, acc, repo, search_path, opts) do
    case var.options_query do
      nil ->
        acc

      "" ->
        acc

      sql_query when is_binary(sql_query) ->
        case fetch_dropdown_options(sql_query, repo, search_path, opts) do
          {:ok, results} ->
            options = OptionsFormatter.to_select_options(results)
            Map.put(acc, var.name, options)

          {:error, _error} ->
            Map.put(acc, var.name, [])
        end
    end
  end

  defp generate_export_url(socket) do
    query = query_to_run(socket.assigns)
    vars = Map.get(socket.assigns, :variable_values, %{})
    repo = source_or_default(query.data_source, socket.assigns)

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

    # The rows as the person sees them: the results' filters and sort, over
    # every page, not only the one on screen.
    view = %{
      "filters" => Map.get(socket.assigns, :filters, []),
      "sorts" => Map.get(socket.assigns, :sorts, [])
    }

    # A saved query exports as saved, unless the person ran a part of it.
    export_params =
      case socket.assigns.page do
        %{mode: :edit, id: id} when is_nil(socket.assigns.ran_statement) ->
          %{
            "query_id" => id,
            "repo" => repo,
            "vars" => vars,
            "search_path" => search_path,
            "filename" => filename
          }

        _new_or_part ->
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
    token = ExportController.generate_token(endpoint, Map.merge(export_params, view))

    export_path = lotus_path([:export, :csv], %{token: URI.encode_www_form(token)})
    push_event(socket, "open-blank", %{location: export_path})
  end

  # Only a saved query's page has one to delete. The new query page has no id,
  # so a crafted event there does nothing.
  defp delete_query(%{assigns: %{page: %{mode: :edit, id: query_id}}} = socket) do
    case Lotus.get_query(query_id, Actor.opts(socket.assigns)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Query not found"))
         |> push_navigate(to: lotus_path(:queries), replace: true)}

      query ->
        with :allow <- Authorization.authorize(socket.assigns, :delete_query, query),
             {:ok, _} <- Lotus.delete_query(query, Actor.opts(socket.assigns)) do
          {:noreply,
           socket
           |> put_flash(:info, gettext("Query deleted successfully"))
           |> push_navigate(to: lotus_path(:queries), replace: true)}
        else
          {:deny, reason} ->
            {:noreply,
             socket
             |> deny(reason)
             |> push_event("close-modal", %{id: "delete-query-modal"})}

          {:error, {:halted, reason}} ->
            {:noreply,
             socket
             |> show_toast(:error, refused_message(reason))
             |> push_event("close-modal", %{id: "delete-query-modal"})}

          {:error, _} ->
            {:noreply,
             socket
             |> show_toast(:error, gettext("Failed to delete query"))
             |> push_event("close-modal", %{id: "delete-query-modal"})}
        end
    end
  end

  defp delete_query(socket), do: {:noreply, socket}

  # Visualization persistence

  defp save_visualization(_query, nil, _opts), do: {:ok, nil}
  defp save_visualization(_query, config, _opts) when config == %{}, do: {:ok, nil}

  defp save_visualization(query, config, opts) when is_map(config) do
    case Lotus.list_visualizations(query.id) do
      [] ->
        Lotus.create_visualization(
          query.id,
          %{name: "Default", position: 0, config: config},
          opts
        )

      [existing | _] ->
        Lotus.update_visualization(existing, %{config: config}, opts)
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

  defp has_valid_config?(config), do: Charts.valid_config?(config)

  defp maybe_put_config(map, _key, nil), do: map
  defp maybe_put_config(map, _key, ""), do: map
  defp maybe_put_config(map, key, value), do: Map.put(map, key, value)

  # For optional fields: remove key when empty, put when present
  defp put_or_remove_config(map, key, nil), do: Map.delete(map, key)
  defp put_or_remove_config(map, key, ""), do: Map.delete(map, key)
  defp put_or_remove_config(map, key, value), do: Map.put(map, key, value)

  # The chart's options (Charts.option_keys/1) that the form sent: a cleared
  # one is removed; an option the form does not show is left as it is.
  defp put_chart_options(config, params) do
    config["chart_type"]
    |> Charts.option_keys()
    |> Enum.filter(&Map.has_key?(params, &1))
    |> Enum.reduce(config, &put_or_remove_config(&2, &1, option_value(params[&1])))
  end

  # A list (the tooltip's fields) without the empty value that lets a form
  # send none; no list at all when that leaves nothing.
  defp option_value(values) when is_list(values) do
    case Enum.reject(values, &(&1 == "")) do
      [] -> nil
      values -> values
    end
  end

  defp option_value(value), do: value

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
      source_context: %{tables_analyzed: []},
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
      %{statement: sql, variables: Enum.map(assigns.query.variables, &variable_to_ai_context/1)}
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
      current_statement = socket.assigns.query.statement
      add_error_message(socket.assigns.ai_conversation, to_string(error_msg), current_statement)
    else
      socket.assigns.ai_conversation
    end
  end

  # `content` is what the model reads; `:display` and `:context`, what the
  # panel shows of it when they differ: the user's words and the chips of
  # what they pointed at.
  defp add_user_message(conversation, content, opts \\ []) do
    message =
      Map.merge(
        %{role: :user, content: content, statement: nil, timestamp: DateTime.utc_now()},
        Map.new(Keyword.take(opts, [:display, :context]))
      )

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_assistant_response(conversation, content, statement, variables) do
    message = %{
      role: :assistant,
      content: content,
      statement: statement,
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
      statement: nil,
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
      statement: nil,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  defp add_error_message(conversation, error_content, statement \\ nil) do
    message = %{
      role: :error,
      content: error_content,
      statement: statement,
      timestamp: DateTime.utc_now()
    }

    %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity: DateTime.utc_now()
    }
  end

  # The steps the model took and how long it took, kept with the message
  # they led to; and, for a query, the editor's statement it changes.
  defp keep_ai_work(%{messages: messages} = conversation, steps, elapsed, base) do
    case List.last(messages) do
      %{role: :user} ->
        conversation

      %{} = message ->
        message =
          message
          |> Map.put(:work, %{steps: steps, elapsed_ms: elapsed})
          |> then(&if &1.role == :assistant, do: Map.put(&1, :base, base), else: &1)

        %{conversation | messages: List.replace_at(messages, -1, message)}

      nil ->
        conversation
    end
  end

  defp put_ai_message(%{messages: messages} = conversation, index, key, value) do
    case Enum.at(messages, index) do
      %{} = message ->
        %{conversation | messages: List.replace_at(messages, index, Map.put(message, key, value))}

      nil ->
        conversation
    end
  end

  # A query the assistant wrote runs at once, read-only and for a few rows,
  # so that its answer shows what it returns. Only for an actor who may run
  # queries on the source, and a query that needs no variable.
  defp maybe_preview_ai_answer(socket) do
    messages = socket.assigns.ai_conversation.messages
    index = length(messages) - 1
    data_source = resolve_data_source(socket)

    with %{role: :assistant, statement: statement} <- List.last(messages),
         true <- AiPreview.previewable?(statement),
         :allow <- Authorization.authorize(socket.assigns, :query, data_source) do
      opts = Actor.opts(socket.assigns) ++ search_path_opts(socket.assigns.query)

      socket
      |> update(:ai_conversation, &put_ai_message(&1, index, :preview, AiPreview.loading()))
      |> start_async({:ai_preview, index}, fn -> AiPreview.run(statement, data_source, opts) end)
    else
      _ -> socket
    end
  end

  defp search_path_opts(%{search_path: path}) when is_binary(path) and path != "",
    do: [search_path: path]

  defp search_path_opts(_query), do: []

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
end
