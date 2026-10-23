defmodule Lotus.Web.Queries.SchemaDiagramComponent do
  @moduledoc """
  The schema diagram of a data source, over the page: the tables of its
  active schema and their foreign keys, on a canvas people pan, zoom and
  arrange (Hakushi). The tables are read from the database as it opens, and
  laid out before they show; what people move is theirs, for this page.
  """
  use Lotus.Web, :live_component

  import Hakushi.Components, only: [canvas: 1]

  alias Lotus.Web.Actor
  alias Lotus.Web.SchemaDiagram
  alias Lotus.Web.SourcesMap

  # Props:
  # - database: string - the data source
  # - search_path: string | nil - the query's, for its active schema
  # - source_names: [string] - the sources the user may query
  # - actor: the actor
  # - parent: Phoenix.LiveComponent.CID - closes it ("close_schema_diagram")

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id="schema-diagram"
      class="fixed inset-0 z-50 flex bg-black/40 p-0 sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="schema-diagram-title"
      phx-window-keydown="close_schema_diagram"
      phx-key="Escape"
      phx-target={@parent}
    >
      <div class="flex flex-1 flex-col overflow-hidden bg-white dark:bg-gray-800 shadow-xl sm:rounded-lg">
        <div class="flex items-center justify-between gap-4 px-4 py-3 border-b border-gray-200 dark:border-gray-700">
          <div class="min-w-0">
            <h3 id="schema-diagram-title" class="text-sm font-medium text-text-light dark:text-text-dark">
              <%= gettext("Schema diagram") %>
            </h3>
            <div class="flex items-center gap-3 mt-1 text-xs text-gray-600 dark:text-gray-400">
              <span class="flex items-center">
                <Icons.database class="h-3 w-3 mr-1" />
                <%= @database %>
              </span>
              <span :if={@loaded && @loaded.schema} class="flex items-center">
                <Icons.layers class="h-3 w-3 mr-1" />
                <%= @loaded.schema %>
              </span>
              <span :if={@loaded} class="flex items-center">
                <Icons.tables class="h-3 w-3 mr-1" />
                <%= ngettext("%{count} table", "%{count} tables", @loaded.tables, count: @loaded.tables) %>
              </span>
            </div>
          </div>
          <button
            type="button"
            phx-click="close_schema_diagram"
            phx-target={@parent}
            aria-label={gettext("Close")}
            class="p-1 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-400"
          >
            <Icons.x_mark class="h-4 w-4" />
          </button>
        </div>

        <div class="relative flex-1">
          <%= cond do %>
            <% @failed -> %>
              <p class="absolute inset-0 flex items-center justify-center text-sm text-gray-500 dark:text-gray-400">
                <%= gettext("The tables of this source could not be read.") %>
              </p>
            <% is_nil(@loaded) -> %>
              <p class="absolute inset-0 flex items-center justify-center text-sm text-gray-500 dark:text-gray-400">
                <%= gettext("Reading the tables…") %>
              </p>
            <% @loaded.tables == 0 -> %>
              <p class="absolute inset-0 flex items-center justify-center text-sm text-gray-500 dark:text-gray-400">
                <%= gettext("This schema has no tables.") %>
              </p>
            <% true -> %>
              <.canvas
                id="schema-diagram-canvas"
                class="lotus-diagram absolute inset-0"
                graph={@loaded.graph}
                kits={[Hakushi.Kits.Schema]}
                readonly={:arrange}
                tidy
                fit={:readable}
                layout={:force}
                locale={@locale}
                label={gettext("The tables of %{schema}", schema: @loaded.schema || @database)}
              />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, loaded: nil, failed: false, started: false)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(locale: Gettext.get_locale(Lotus.Web.Gettext))

    {:ok, maybe_load(socket)}
  end

  # The tables are read once, when the browser is there, away from the page.
  defp maybe_load(%{assigns: %{started: false}} = socket) do
    if connected?(socket) do
      %{database: name, search_path: path, source_names: names} = socket.assigns
      opts = Actor.opts(socket.assigns.actor)

      socket
      |> assign(started: true)
      |> start_async(:load, fn -> load(name, path, names, opts) end)
    else
      socket
    end
  end

  defp maybe_load(socket), do: socket

  @impl Phoenix.LiveComponent
  def handle_async(:load, {:ok, {:ok, loaded}}, socket) do
    {:noreply, assign(socket, loaded: loaded)}
  end

  def handle_async(:load, _failed, socket) do
    {:noreply, assign(socket, failed: true)}
  end

  @doc false
  # Only a source the user may query, that draws a diagram.
  def load(name, search_path, source_names, opts) do
    with true <- name in source_names,
         database when database != nil <-
           SourcesMap.get_database(SourcesMap.build(opts, [name]), name),
         true <- SchemaDiagram.supported?(database),
         schema when schema != nil <- SchemaDiagram.active_schema(database, search_path) do
      SchemaDiagram.load(database, schema, opts)
    else
      _refused -> {:error, :unavailable}
    end
  end
end
