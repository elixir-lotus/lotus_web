defmodule Lotus.Web.Queries.DropdownOptionsModal do
  @moduledoc """
  Modal component for configuring dropdown options. They come from:

    * a custom list typed by hand
    * a column picked from a table, which writes the SQL
    * SQL, in the editor the query has
    * a saved query

  Picking a column and writing SQL are offered only where the data source
  declares the `:dynamic_options` feature. Sources whose query language returns
  shaped documents rather than a flat list of rows get the custom list and the
  saved queries. A test run previews the options of every source but the custom
  list: which column is the value and which the label, how many options there
  are, and what in the rows makes a poor dropdown.
  """

  use Lotus.Web, :live_component

  alias Lotus.Storage.QueryVariable
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter
  alias Lotus.Web.QueryEditor.DropdownOptions

  import Lotus.Web.Components.QueryPicker

  @select_class "w-full border border-gray-300 dark:border-gray-600 rounded-lg p-2 text-sm bg-white dark:bg-input-dark text-text-light dark:text-text-dark focus:ring-pink-500 focus:border-pink-500"

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(:initialized, false)
     |> assign(:dynamic_options, false)
     |> assign(:data_source, nil)
     |> assign(:search_path, nil)
     |> assign(:tables, [])
     |> assign(:saved_queries, [])
     |> assign(:option_source, :static)
     |> assign(:custom_options, "")
     |> assign(:sql_query, "")
     |> assign(:saved_query_id, nil)
     |> assign(:column_table, nil)
     |> assign(:table_columns, [])
     |> assign(:columns_loading, false)
     |> assign(:value_column, nil)
     |> assign(:label_column, nil)
     |> reset_preview()}
  end

  @impl Phoenix.LiveComponent
  def update(%{query_test_result: result}, socket) do
    socket = assign(socket, :query_loading, false)

    case result do
      {:ok, preview} ->
        {:ok, socket |> assign(:preview, preview) |> assign(:query_error, nil)}

      {:error, error} ->
        {:ok, socket |> assign(:preview, nil) |> assign(:query_error, error)}
    end
  end

  def update(%{table_columns: {table, columns}}, socket) do
    if table == socket.assigns.column_table do
      {:ok,
       socket
       |> assign(:table_columns, columns)
       |> assign(:columns_loading, false)
       |> assign(:value_column, List.first(columns))}
    else
      {:ok, socket}
    end
  end

  # The parent renders the modal again whenever it changes, with the same
  # variable: what the person chose here stays.
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns.initialized,
      do: {:ok, socket},
      else: {:ok, init_from_variable(socket, assigns.variable_data || %{})}
  end

  defp init_from_variable(socket, variable_data) do
    variable =
      case variable_data do
        %QueryVariable{} = variable -> variable
        attrs -> struct(QueryVariable, attrs)
      end

    option_source =
      case QueryVariable.get_option_source(variable) do
        :saved_query -> :saved_query
        :query -> if socket.assigns.dynamic_options, do: :query, else: :static
        :static -> :static
      end

    socket
    |> assign(:initialized, true)
    |> assign(:option_source, option_source)
    |> assign(:custom_options, OptionsFormatter.to_display_format(variable.static_options))
    |> assign(:sql_query, variable.options_query || "")
    |> assign(:saved_query_id, variable.options_query_id)
  end

  @impl Phoenix.LiveComponent
  def handle_event("change_option_source", %{"source" => source}, socket) do
    {:noreply,
     socket
     |> assign(:option_source, parse_option_source(source, socket.assigns))
     |> reset_preview()}
  end

  def handle_event("update_custom_options", %{"value" => options}, socket) do
    {:noreply, assign(socket, :custom_options, options)}
  end

  def handle_event("update_sql_query", %{"value" => query}, socket) do
    if query == socket.assigns.sql_query,
      do: {:noreply, socket},
      else: {:noreply, socket |> assign(:sql_query, query) |> reset_preview()}
  end

  def handle_event("change_columns", params, socket) do
    table = blank_to_nil(params["table"])
    socket = reset_preview(socket)

    if table != socket.assigns.column_table do
      if table do
        send_update(socket.assigns.parent,
          id: socket.assigns.parent.cid,
          action: :describe_option_table,
          table: table
        )
      end

      {:noreply,
       socket
       |> assign(:column_table, table)
       |> assign(:table_columns, [])
       |> assign(:columns_loading, table != nil)
       |> assign(:value_column, nil)
       |> assign(:label_column, nil)}
    else
      {:noreply,
       socket
       |> assign(:value_column, blank_to_nil(params["value_column"]))
       |> assign(:label_column, blank_to_nil(params["label_column"]))}
    end
  end

  def handle_event("change_saved_query", %{"saved_query_id" => id}, socket) do
    {:noreply, socket |> assign(:saved_query_id, parse_id(id)) |> reset_preview()}
  end

  def handle_event("test_sql_query", _params, socket) do
    case options_source(socket.assigns) do
      {:error, error} ->
        {:noreply, socket |> assign(:preview, nil) |> assign(:query_error, error)}

      {:ok, options_source} ->
        send_update(socket.assigns.parent,
          id: socket.assigns.parent.cid,
          action: :test_dropdown_query,
          options_source: options_source
        )

        {:noreply,
         socket
         |> assign(:query_loading, true)
         |> assign(:query_error, nil)
         |> assign(:preview, nil)}
    end
  end

  def handle_event("save_options", _, socket) do
    case validate_and_save_options(socket.assigns) do
      {:ok, options_data} ->
        send_update(socket.assigns.parent,
          id: socket.assigns.parent.cid,
          action: :save_dropdown_options,
          variable_name: socket.assigns.variable_name,
          options_data: options_data
        )

        {:noreply, socket}

      {:error, error} ->
        {:noreply, assign(socket, :query_error, error)}
    end
  end

  def handle_event("close_modal", _, socket) do
    send_update(socket.assigns.parent,
      id: socket.assigns.parent.cid,
      action: :close_dropdown_options_modal
    )

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assigns
      |> assign(:select_class, @select_class)
      |> assign(:sources, sources(assigns))
      |> assign(:column_sql, column_sql(assigns))
      |> assign(:can_save, can_save?(assigns))
      |> assign_title()

    ~H"""
    <div>
      <.modal id="dropdown-options-modal" show={true} on_cancel={JS.push("close_modal", target: @myself)}>
        <h3 class="text-lg font-semibold mb-4">
          <%= @title_before %><span class="text-pink-600 dark:text-pink-400 font-mono"><%= @variable_name %></span><%= @title_after %>
        </h3>

        <div class="flex gap-6">
          <div :if={length(@sources) > 1} class="w-36 shrink-0 space-y-3" role="radiogroup">
            <div
              :for={{source, label} <- @sources}
              phx-click="change_option_source"
              phx-value-source={source}
              phx-target={@myself}
            >
              <.input
                type="radio"
                name="option_source"
                value={to_string(source)}
                label={label}
                checked={@option_source == source}
              />
            </div>
          </div>

          <div class="flex-1 space-y-3 min-w-0">
            <%= case @option_source do %>
              <% :static -> %>
                <.static_options custom_options={@custom_options} myself={@myself} />
              <% :columns -> %>
                <.source_line data_source={@data_source} search_path={@search_path} />
                <.column_picker
                  tables={@tables}
                  column_table={@column_table}
                  table_columns={@table_columns}
                  columns_loading={@columns_loading}
                  value_column={@value_column}
                  label_column={@label_column}
                  column_sql={@column_sql}
                  select_class={@select_class}
                  myself={@myself}
                />
              <% :query -> %>
                <.source_line data_source={@data_source} search_path={@search_path} />
                <div
                  id={"options-sql-editor-#{@variable_name}"}
                  phx-hook="OptionsSqlEditor"
                  phx-update="ignore"
                  phx-target={@myself}
                  data-page="#query-editor-page"
                  data-value={@sql_query}
                  class="rounded-lg border border-zinc-300 dark:border-zinc-600 overflow-hidden bg-editor-light dark:bg-editor-dark"
                >
                  <div data-options-editor class="min-h-[8rem] max-h-64 overflow-auto text-sm"></div>
                </div>
                <.column_rules />
              <% :saved_query -> %>
                <.saved_query_picker
                  saved_queries={@saved_queries}
                  saved_query_id={@saved_query_id}
                  myself={@myself}
                />
                <.column_rules />
            <% end %>

            <div :if={@option_source != :static} class="flex items-center gap-3">
              <.button
                type="button"
                variant="light"
                phx-click="test_sql_query"
                phx-target={@myself}
                disabled={@query_loading || not testable?(assigns)}
              >
                <%= if @query_loading, do: gettext("Testing..."), else: gettext("Test Query") %>
              </.button>
              <span :if={@option_source == :query} class="text-xs text-gray-500 dark:text-gray-400">
                <%= gettext("or press Ctrl + Enter in the editor") %>
              </span>
            </div>

            <.preview :if={@preview} preview={@preview} />

            <div
              :if={@query_error}
              id="dropdown-options-error"
              class="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-700 rounded-md"
            >
              <div class="text-sm text-red-600 dark:text-red-400 break-words"><%= @query_error %></div>
            </div>
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <.button
            type="button"
            phx-click="save_options"
            phx-target={@myself}
            disabled={not @can_save}
            class={not @can_save && "opacity-50 cursor-not-allowed"}
          >
            <%= gettext("Done") %>
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  # The title names the variable in a translated sentence, with the name
  # marked up: the sentence is split where the name goes.
  defp assign_title(assigns) do
    marker = "\u0001"
    title = gettext("Dropdown values for the %{variable} widget", variable: marker)

    case String.split(title, marker, parts: 2) do
      [before, after_name] -> assign(assigns, title_before: before, title_after: after_name)
      [title] -> assign(assigns, title_before: title <> " ", title_after: "")
    end
  end

  defp static_options(assigns) do
    ~H"""
    <div>
      <textarea
        phx-keyup="update_custom_options"
        phx-blur="update_custom_options"
        phx-target={@myself}
        name="options"
        rows="6"
        class="block w-full rounded-lg text-sm min-h-[6rem] text-text-light dark:text-text-dark dark:bg-input-dark border-zinc-300 dark:border-zinc-600 focus:border-zinc-400 dark:focus:border-zinc-500 focus:ring-0"
        placeholder={gettext("Option 1\nOption 2\nOption 3")}
      ><%= @custom_options %></textarea>
      <div class="mt-2 text-xs text-gray-500 dark:text-gray-400">
        <%= gettext("Enter one value per line. Use \"value | label\" format to add display labels.") %>
      </div>
    </div>
    """
  end

  attr(:data_source, :string, default: nil)
  attr(:search_path, :string, default: nil)

  defp source_line(assigns) do
    ~H"""
    <p id="dropdown-options-source" class="text-xs text-gray-500 dark:text-gray-400">
      <%= gettext("Runs on") %>
      <span class="font-medium font-mono text-gray-700 dark:text-gray-300"><%= @data_source %></span>
      <%= if @search_path not in [nil, ""] do %>
        · <%= gettext("search path") %>
        <span class="font-medium font-mono text-gray-700 dark:text-gray-300"><%= @search_path %></span>
      <% end %>
      · <%= gettext("the query's own source") %>
    </p>
    """
  end

  defp column_rules(assigns) do
    ~H"""
    <p class="text-xs text-gray-500 dark:text-gray-400">
      <%= gettext("The first column is the value the query receives, the second (optional) is the label people see. Any other column is left out.") %>
    </p>
    """
  end

  defp column_picker(assigns) do
    ~H"""
    <form id="dropdown-options-columns" phx-change="change_columns" phx-target={@myself} class="space-y-3">
      <div>
        <label for="dropdown-options-table" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          <%= gettext("Table") %>
        </label>
        <select id="dropdown-options-table" name="table" class={@select_class}>
          <option value=""><%= gettext("Choose a table") %></option>
          <option :for={table <- @tables} value={table} selected={table == @column_table}><%= table %></option>
        </select>
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label for="dropdown-options-value-column" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            <%= gettext("Value column") %>
          </label>
          <select
            id="dropdown-options-value-column"
            name="value_column"
            class={@select_class}
            disabled={@table_columns == []}
          >
            <option :if={@columns_loading} value=""><%= gettext("Loading columns...") %></option>
            <option :for={column <- @table_columns} value={column} selected={column == @value_column}><%= column %></option>
          </select>
        </div>
        <div>
          <label for="dropdown-options-label-column" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            <%= gettext("Label column") %>
            <span class="font-normal text-gray-400">(<%= gettext("optional") %>)</span>
          </label>
          <select
            id="dropdown-options-label-column"
            name="label_column"
            class={@select_class}
            disabled={@table_columns == []}
          >
            <option value=""><%= gettext("Same as the value") %></option>
            <option :for={column <- @table_columns} value={column} selected={column == @label_column}><%= column %></option>
          </select>
        </div>
      </div>
      <div :if={@column_sql}>
        <div class="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1"><%= gettext("The SQL it runs") %></div>
        <pre
          id="dropdown-options-column-sql"
          class="text-xs font-mono whitespace-pre-wrap break-words rounded-md p-2 bg-gray-50 dark:bg-gray-700 text-gray-700 dark:text-gray-300"
        ><%= @column_sql %></pre>
        <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          <%= gettext("Saved as SQL: open these options again to edit it under Write SQL.") %>
        </p>
      </div>
    </form>
    """
  end

  defp saved_query_picker(assigns) do
    ~H"""
    <form id="dropdown-options-saved-query" phx-change="change_saved_query" phx-target={@myself} class="space-y-2">
      <div id="dropdown-options-saved-query-label" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        <%= gettext("Saved query") %>
      </div>
      <%= if @saved_queries == [] and is_nil(@saved_query_id) do %>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          <%= gettext("There are no saved queries yet. Save a query that lists the options, then pick it here.") %>
        </p>
      <% else %>
        <.query_picker
          id="dropdown-options-saved-query-id"
          name="saved_query_id"
          value={@saved_query_id}
          queries={@saved_queries}
          missing={@saved_query_id && gettext("Query #%{id} (not found)", id: @saved_query_id)}
          label_id="dropdown-options-saved-query-label"
        />
        <.link
          :if={@saved_query_id}
          navigate={lotus_path(["queries", @saved_query_id])}
          target="_blank"
          class="inline-block text-xs text-pink-600 dark:text-pink-400 hover:underline"
        >
          <%= gettext("Open this query") %>
        </.link>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          <%= gettext("The options follow the query: an edit to it changes them. It runs read only, with its own variables' defaults.") %>
        </p>
      <% end %>
    </form>
    """
  end

  defp preview(assigns) do
    ~H"""
    <div id="dropdown-options-preview" class="space-y-2">
      <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-sm">
        <span class="font-medium text-gray-700 dark:text-gray-300">
          <%= if @preview.more? do %>
            <%= gettext("More than %{count} options, the first %{count} shown", count: @preview.count) %>
          <% else %>
            <%= ngettext("1 option", "%{count} options", @preview.count) %>
          <% end %>
        </span>
        <span :if={@preview.value_column} class="text-xs text-gray-500 dark:text-gray-400">
          <%= gettext("value") %> ←
          <code class="font-mono text-gray-700 dark:text-gray-300"><%= @preview.value_column %></code>
          · <%= gettext("label") %> ←
          <code class="font-mono text-gray-700 dark:text-gray-300"><%= @preview.label_column %></code>
        </span>
      </div>

      <ul
        :if={@preview.warnings != []}
        id="dropdown-options-warnings"
        class="space-y-1 text-xs text-amber-700 dark:text-amber-400"
      >
        <li :for={warning <- @preview.warnings} class="flex gap-1.5">
          <Icons.exclamation_triangle class="h-4 w-4 shrink-0" />
          <span><%= warning %></span>
        </li>
      </ul>

      <div
        :if={@preview.options != []}
        class="bg-gray-50 dark:bg-gray-700 rounded-md p-3 space-y-1 max-h-48 overflow-y-auto"
      >
        <div :for={option <- @preview.options} class="text-sm font-mono text-gray-600 dark:text-gray-400">
          <%= if option.label == option.value do %>
            "<%= option.value %>"
          <% else %>
            "<%= option.value %>" → <%= option.label %>
          <% end %>
        </div>
      </div>

      <p :if={@preview.options == []} class="text-sm text-amber-700 dark:text-amber-400">
        <%= gettext("The query returned no rows, so the dropdown would be empty.") %>
      </p>
    </div>
    """
  end

  defp sources(assigns) do
    [
      {:static, gettext("Custom list")},
      assigns.dynamic_options && {:columns, gettext("Pick a column")},
      assigns.dynamic_options && {:query, gettext("Write SQL")},
      {:saved_query, gettext("Saved query")}
    ]
    |> Enum.filter(& &1)
  end

  defp parse_option_source("columns", %{dynamic_options: true}), do: :columns
  defp parse_option_source("query", %{dynamic_options: true}), do: :query
  defp parse_option_source("saved_query", _assigns), do: :saved_query
  defp parse_option_source(_source, _assigns), do: :static

  defp reset_preview(socket) do
    socket
    |> assign(:preview, nil)
    |> assign(:query_error, nil)
    |> assign(:query_loading, false)
  end

  defp column_sql(%{option_source: :columns, column_table: table, value_column: value} = assigns)
       when is_binary(table) and is_binary(value) do
    DropdownOptions.column_sql(assigns.data_source, table, value, assigns.label_column)
  rescue
    _error -> nil
  end

  defp column_sql(_assigns), do: nil

  defp testable?(%{option_source: :columns} = assigns), do: column_sql(assigns) != nil
  defp testable?(%{option_source: :query, sql_query: sql}), do: String.trim(sql) != ""
  defp testable?(%{option_source: :saved_query, saved_query_id: id}), do: id != nil
  defp testable?(_assigns), do: false

  defp can_save?(%{option_source: :static, custom_options: options}),
    do: String.trim(options) != ""

  defp can_save?(%{preview: %{options: [_ | _]}, query_error: nil}), do: true
  defp can_save?(_assigns), do: false

  defp options_source(%{option_source: :columns} = assigns) do
    case column_sql(assigns) do
      nil -> {:error, gettext("Choose a table and a value column")}
      sql -> {:ok, {:sql, sql}}
    end
  end

  defp options_source(%{option_source: :query, sql_query: sql}) do
    if String.trim(sql) == "",
      do: {:error, gettext("Query cannot be empty")},
      else: {:ok, {:sql, String.trim(sql)}}
  end

  defp options_source(%{option_source: :saved_query, saved_query_id: nil}),
    do: {:error, gettext("Choose a saved query")}

  defp options_source(%{option_source: :saved_query, saved_query_id: id}),
    do: {:ok, {:saved_query, id}}

  defp validate_and_save_options(%{option_source: :static} = assigns) do
    if String.trim(assigns.custom_options) == "" do
      {:error, gettext("Please enter at least one option")}
    else
      static_options = OptionsFormatter.from_display_format(assigns.custom_options)
      {:ok, %{static_options: static_options, options_query: nil, options_query_id: nil}}
    end
  end

  defp validate_and_save_options(assigns) do
    if can_save?(assigns) do
      case options_source(assigns) do
        {:ok, {:sql, sql}} ->
          {:ok, %{static_options: [], options_query: sql, options_query_id: nil}}

        {:ok, {:saved_query, id}} ->
          {:ok, %{static_options: [], options_query: nil, options_query_id: id}}

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, gettext("Please test your query first and ensure it returns results")}
    end
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
