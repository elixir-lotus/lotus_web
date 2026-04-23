defmodule Lotus.Web.Queries.SchemaExplorerComponent do
  @moduledoc """
  A drawer component for browsing data source schemas.
  """
  use Lotus.Web, :live_component

  alias Lotus.Web.SourcesMap

  # Props:
  # - visible: boolean - whether the drawer is visible
  # - parent: Phoenix.LiveComponent.CID - parent component
  # - initial_db: string - initial database to show

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      class={[
        "fixed sm:absolute top-0 right-0 h-full w-full sm:w-80 bg-white dark:bg-gray-800 border-l-0 sm:border-l border-gray-200 dark:border-gray-700 z-20 transition-transform duration-300 ease-in-out overflow-hidden",
        if(@visible, do: "translate-x-0", else: "translate-x-full")
      ]}
      inert={!@visible}
    >
      <%= if @visible do %>
        <div class="h-full flex flex-col">
          <.header {assigns} />
          <.content {assigns} />
        </div>
      <% end %>
    </div>
    """
  end

  defp header(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700">
      <div class="flex items-center justify-between">
        <.header_title {assigns} />
        <.close_button parent={@parent} />
      </div>
      <.header_subtitle {assigns} />
    </div>
    """
  end

  defp header_title(assigns) do
    ~H"""
    <%= case @view_mode do %>
      <% :databases -> %>
        <h3 class="text-sm font-medium text-text-light dark:text-text-dark"><%= gettext("Data Reference") %></h3>
      <% :tables -> %>
        <div class="flex items-center">
          <.back_button target={@myself} />
          <h3 class="text-sm font-medium text-text-light dark:text-text-dark"><%= @current_db %></h3>
        </div>
      <% :columns -> %>
        <div class="flex items-center">
          <.back_button target={@myself} />
          <h3 class="text-sm font-medium text-text-light dark:text-text-dark"><%= @current_table %></h3>
        </div>
    <% end %>
    """
  end

  defp back_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="navigate_back"
      phx-target={@target}
      class="p-1 mr-2 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
    >
      <Icons.chevron_left class="h-3 w-3" />
    </button>
    """
  end

  defp close_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="close_schema_explorer"
      phx-target={@parent}
      class="p-1 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
    >
      <Icons.x_mark class="h-4 w-4" />
    </button>
    """
  end

  defp header_subtitle(assigns) do
    ~H"""
    <%= case @view_mode do %>
      <% :databases -> %>
        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
          <%= gettext("Browse the contents of your data sources. Pick one to get started.") %>
        </p>
      <% :tables -> %>
        <%= if @current_db do %>
          <div class="flex items-center gap-3 mt-2 text-xs text-gray-600 dark:text-gray-400">
            <%= if @current_db_info && @current_db_info.supports_schemas do %>
              <div class="flex items-center">
                <Icons.layers class="h-3 w-3 mr-1" />
                <%= schema_count = SourcesMap.get_schema_count(@current_db_info) %>
                <%= ngettext("%{count} schema", "%{count} schemas", schema_count, count: schema_count) %>
              </div>
            <% end %>
            <div class="flex items-center">
              <Icons.tables class="h-3 w-3 mr-1" />
              <%= table_count = if(@current_db_info, do: SourcesMap.get_table_count(@current_db_info), else: 0) %>
              <%= ngettext("%{count} table", "%{count} tables", table_count, count: table_count) %>
            </div>
          </div>
        <% end %>
      <% :columns -> %>
        <%= if @current_db do %>
          <div class="flex items-center gap-3 mt-2 text-xs text-gray-600 dark:text-gray-400">
            <div class="flex items-center">
              <Icons.database class="h-3 w-3 mr-1" />
              <%= @current_db %>
            </div>
            <%= if @current_db_info && @current_db_info.supports_schemas && @current_schema != "default" do %>
              <div class="flex items-center">
                <Icons.layers class="h-3 w-3 mr-1" />
                <%= @current_schema %>
              </div>
            <% end %>
            <div class="flex items-center">
              <Icons.tables class="h-3 w-3 mr-1" />
              <%= column_count = length(@columns) %>
              <%= ngettext("%{count} column", "%{count} columns", column_count, count: column_count) %>
            </div>
          </div>
        <% end %>
    <% end %>
    """
  end

  defp content(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto">
      <%= case @view_mode do %>
        <% :databases -> %>
          <.databases_list sources_map={@sources_map} target={@myself} />
        <% :tables -> %>
          <.tables_list sources_map={@sources_map} current_db={@current_db} current_db_info={@current_db_info} target={@myself} />
        <% :columns -> %>
          <.columns_list columns={@columns} />
      <% end %>
    </div>
    """
  end

  defp databases_list(assigns) do
    ~H"""
    <div class="p-2">
      <div :for={database <- @sources_map.databases} class="flex items-center py-2 px-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer" phx-click="select_database" phx-value-database={database.name} phx-target={@target}>
        <div class="flex-shrink-0 mr-3">
          <Icons.database class="h-4 w-4 text-blue-500" />
        </div>
        <span class="text-blue-600 dark:text-blue-400 font-mono text-sm"><%= database.name %></span>
      </div>
    </div>
    """
  end

  defp tables_list(assigns) do
    ~H"""
    <%= if @current_db_info do %>
      <div class="p-2">
        <div :for={schema <- @current_db_info.schemas}>
          <span class="sr-only"><%= gettext("Schema Header") %></span>
          <%= if @current_db_info.supports_schemas do %>
            <div class="flex items-center py-2 px-2 text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
              <div class="flex-shrink-0 mr-2">
                <Icons.layers class="h-3 w-3" />
              </div>
              <div class="flex items-center gap-2 flex-1">
                <span><%= schema.display_name %></span>
                <%= if schema.is_default do %>
                  <span class="text-xs bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300 px-1 py-0.5 rounded lowercase">
                    <%= gettext("default") %>
                  </span>
                <% end %>
              </div>
              <span class="text-xs text-gray-400"><%= length(schema.tables) %></span>
            </div>
          <% end %>

          <span class="sr-only"><%= gettext("Tables in Schema") %></span>
          <div class={["ml-5", if(@current_db_info.supports_schemas, do: "border-l border-gray-200 dark:border-gray-700", else: "ml-0")]}>
            <div :for={table <- schema.tables} class="flex items-center py-1.5 px-3 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-r cursor-pointer" phx-click="select_table" phx-value-schema={schema.name} phx-value-table={table} phx-target={@target}>
              <div class="flex-shrink-0 mr-3">
                <Icons.tables class="h-4 w-4 text-green-500" />
              </div>
              <span class="text-blue-600 dark:text-blue-400 font-mono text-sm"><%= table %></span>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp columns_list(assigns) do
    ~H"""
    <div class="p-2">
      <div :for={column <- @columns} class="flex items-center py-2 px-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 rounded cursor-pointer">
        <div class="flex-shrink-0 mr-3">
          <.column_icon column={column} />
        </div>
        <span class="text-blue-600 font-mono text-sm"><%= column.name %></span>
      </div>
    </div>
    """
  end

  defp column_icon(assigns) do
    ~H"""
    <%= case get_column_icon_type(@column) do %>
      <% :id -> %>
        <Icons.key class="h-4 w-4 text-blue-500" />
      <% :text -> %>
        <Icons.text_type class="h-4 w-4 text-gray-500" />
      <% :number -> %>
        <Icons.file_digit class="h-4 w-4 text-green-500" />
      <% :decimal -> %>
        <Icons.decimals class="h-4 w-4 text-green-500" />
      <% :datetime -> %>
        <Icons.calendar class="h-4 w-4 text-purple-500" />
      <% :foreign_key -> %>
        <Icons.key class="h-4 w-4 text-orange-500" />
      <% :boolean -> %>
        <Icons.toggle_boolean class="h-4 w-4 text-indigo-500" />
    <% end %>
    """
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket =
      socket
      |> assign(visible: false)
      |> assign(view_mode: :databases)
      |> assign(sources_map: SourcesMap.build())
      |> clear_db_state()
      |> clear_table_state()
      |> refresh_current_db_info()

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(params, socket) do
    socket =
      socket
      |> assign(params)
      |> maybe_navigate_to_database(params[:initial_db])
      |> refresh_current_db_info()

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_database", %{"database" => database_name}, socket) do
    socket = navigate_to_database(socket, database_name)
    {:noreply, socket}
  end

  def handle_event("select_table", %{"schema" => schema, "table" => table}, socket) do
    socket = navigate_to_table(socket, schema, table)
    {:noreply, socket}
  end

  def handle_event("navigate_back", _params, socket) do
    {:noreply, navigate_back(socket)}
  end

  defp maybe_navigate_to_database(socket, nil), do: socket
  defp maybe_navigate_to_database(socket, ""), do: socket

  defp maybe_navigate_to_database(socket, initial_db) do
    if initial_db != socket.assigns.current_db do
      navigate_to_database(socket, initial_db)
    else
      socket
    end
  end

  defp refresh_current_db_info(socket) do
    current_db_info =
      SourcesMap.get_database(socket.assigns.sources_map, socket.assigns.current_db)

    assign(socket, current_db_info: current_db_info)
  end

  defp navigate_to_database(socket, database_name) do
    case SourcesMap.get_database(socket.assigns.sources_map, database_name) do
      nil ->
        socket

      database ->
        socket
        |> assign(view_mode: :tables)
        |> assign(current_db: database_name)
        |> assign(current_db_info: database)
        |> clear_table_state()
    end
  end

  defp navigate_to_table(socket, schema, table) do
    opts = if schema != "default", do: [search_path: schema], else: []

    case Lotus.describe_table(socket.assigns.current_db, table, opts) do
      {:ok, columns} ->
        socket
        |> assign(view_mode: :columns)
        |> assign(current_table: table)
        |> assign(current_schema: schema)
        |> assign(columns: columns)

      {:error, _reason} ->
        socket
    end
  end

  defp navigate_back(socket) do
    case socket.assigns.view_mode do
      :tables ->
        socket
        |> assign(view_mode: :databases)
        |> clear_db_state()

      :columns ->
        socket
        |> assign(view_mode: :tables)
        |> clear_table_state()

      _ ->
        socket
    end
  end

  defp clear_db_state(socket) do
    socket
    |> assign(current_db: nil)
    |> assign(current_db_info: nil)
  end

  defp clear_table_state(socket) do
    socket
    |> assign(columns: [])
    |> assign(current_table: nil)
    |> assign(current_schema: nil)
  end

  defp get_column_icon_type(column) do
    cond do
      column.primary_key -> :id
      foreign_key?(column) -> :foreign_key
      datetime_type?(column.type) -> :datetime
      boolean_type?(column.type) -> :boolean
      decimal_type?(column.type) -> :decimal
      integer_type?(column.type) -> :number
      text_type?(column.type) -> :text
      true -> :text
    end
  end

  defp foreign_key?(column) do
    String.contains?(column.name, "_id") and not column.primary_key
  end

  defp datetime_type?(type) do
    String.contains?(type, "timestamp") or String.contains?(type, "date")
  end

  defp boolean_type?(type) do
    String.contains?(type, "boolean")
  end

  defp decimal_type?(type) do
    String.contains?(type, "numeric") or String.contains?(type, "decimal")
  end

  defp integer_type?(type) do
    String.contains?(type, "int") or String.contains?(type, "bigint")
  end

  defp text_type?(type) do
    String.contains?(type, "varchar") or String.contains?(type, "text") or
      String.contains?(type, "character")
  end

  def show(socket) do
    assign(socket, visible: true)
  end

  def hide(socket) do
    assign(socket, visible: false)
  end
end
