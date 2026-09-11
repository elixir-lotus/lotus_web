defmodule Lotus.Web.Queries.DropdownOptionsModal do
  @moduledoc """
  Modal component for configuring dropdown options, by hand or from a query.

  Query-based population is offered only where the data source declares the
  `:dynamic_options` feature. Sources whose query language returns shaped
  documents rather than a flat list of rows get manual entry only.
  """

  use Lotus.Web, :live_component

  alias Lotus.Storage.QueryVariable
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(:dynamic_options, false)
     |> assign(:option_source, :static)
     |> assign(:custom_options, "")
     |> assign(:sql_query, "")
     |> assign(:query_preview, [])
     |> assign(:query_full_results, [])
     |> assign(:query_error, nil)
     |> assign(:query_loading, false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("change_option_source", %{"source" => source}, socket) do
    option_source = parse_option_source(source, socket.assigns.dynamic_options)

    socket =
      socket
      |> assign(:option_source, option_source)
      |> assign(:query_preview, [])
      |> assign(:query_full_results, [])
      |> assign(:query_error, nil)

    {:noreply, socket}
  end

  def handle_event("update_custom_options", %{"value" => options}, socket) do
    {:noreply, assign(socket, :custom_options, options)}
  end

  def handle_event("update_sql_query", %{"value" => query}, socket) do
    socket =
      socket
      |> assign(:sql_query, query)
      |> assign(:query_preview, [])
      |> assign(:query_full_results, [])
      |> assign(:query_error, nil)

    {:noreply, socket}
  end

  def handle_event("test_sql_query", _, socket) do
    if String.trim(socket.assigns.sql_query) == "" do
      {:noreply, assign(socket, :query_error, gettext("Query cannot be empty"))}
    else
      socket =
        socket
        |> assign(:query_loading, true)
        |> assign(:query_error, nil)
        |> assign(:query_preview, [])
        |> assign(:query_full_results, [])

      send_update(socket.assigns.parent,
        id: socket.assigns.parent.cid,
        action: :test_dropdown_query,
        sql_query: socket.assigns.sql_query,
        modal_component: socket.assigns.myself
      )

      {:noreply, socket}
    end
  end

  def handle_event("save_options", _, socket) do
    case validate_and_save_options(socket) do
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
    ~H"""
    <div>
      <.modal id="dropdown-options-modal" show={true} on_cancel={JS.push("close_modal", target: @myself)}>
        <h3 class="text-lg font-semibold mb-4">
          <% variable_markup = "<span class=\"text-pink-600 dark:text-pink-400 font-mono\">#{@variable_name}</span>" %>
          <%= gettext("Dropdown values for the %{variable} widget",
            variable: variable_markup
          ) |> raw() %>
        </h3>

        <div class="grid grid-cols-5 gap-6">
          <div :if={@dynamic_options} class="col-span-1 space-y-3">
            <div phx-click="change_option_source" phx-value-source="static" phx-target={@myself}>
              <.input
                type="radio"
                name="option_source"
                value="static"
                label={gettext("Custom list")}
                checked={@option_source == :static}
              />
            </div>
            <div phx-click="change_option_source" phx-value-source="query" phx-target={@myself}>
              <.input
                type="radio"
                name="option_source"
                value="query"
                label={gettext("From query")}
                checked={@option_source == :query}
              />
            </div>
          </div>

          <div class={if @dynamic_options, do: "col-span-4 space-y-3", else: "col-span-5 space-y-3"}>
            <div>
              <textarea
                phx-keyup={if @option_source == :static, do: "update_custom_options", else: "update_sql_query"}
                phx-blur={if @option_source == :static, do: "update_custom_options", else: "update_sql_query"}
                phx-target={@myself}
                name={if @option_source == :static, do: "options", else: "query"}
                rows={if @option_source == :static, do: "6", else: "4"}
                class={[
                  "block w-full rounded-lg text-sm min-h-[6rem] text-text-light dark:text-text-dark dark:bg-input-dark border-zinc-300 dark:border-zinc-600 focus:border-zinc-400 dark:focus:border-zinc-500 focus:ring-0",
                  @option_source == :query && "font-mono"
                ]}
                placeholder={
                  if @option_source == :static do
                    gettext("Option 1\nOption 2\nOption 3")
                  else
                    gettext(
                      "SELECT value_column, label_column FROM table_name\n-- OR --\nSELECT value_column FROM table_name"
                    )
                  end
                }
              ><%= if @option_source == :static, do: @custom_options, else: @sql_query %></textarea>
              <div class="mt-2 text-xs text-gray-500 dark:text-gray-400">
                <%= if @option_source == :static do %>
                  <%= gettext("Enter one value per line. Use \"value | label\" format to add display labels.") %>
                <% else %>
                  <%= gettext("Write a query that returns value and label columns (or just a value column).") %>
                <% end %>
              </div>
            </div>

            <%= if @option_source == :query do %>
              <.button
                type="button"
                variant="light"
                phx-click="test_sql_query"
                phx-target={@myself}
                disabled={@query_loading || String.trim(@sql_query) == ""}
              >
                <%= if @query_loading do %>
                  <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <%= gettext("Testing...") %>
                <% else %>
                  <%= gettext("Test Query") %>
                <% end %>
              </.button>

              <%= if @query_preview != [] do %>
                <div class="mt-3">
                  <div class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    <%= gettext("Preview (first 3 results):") %>
                  </div>
                  <div class="bg-gray-50 dark:bg-gray-700 rounded-md p-3 space-y-1">
                    <%= for {label, value} <- @query_preview do %>
                      <div class="text-sm font-mono text-gray-600 dark:text-gray-400">
                        <%= if label == value do %>
                          "<%= value %>"
                        <% else %>
                          "<%= value %>" → <%= label %>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @query_error do %>
                <div class="mt-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-700 rounded-md">
                  <div class="text-sm text-red-600 dark:text-red-400">
                    <%= @query_error %>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <.button
            type="button"
            phx-click="save_options"
            phx-target={@myself}
            disabled={@option_source == :query && (@query_preview == [] || @query_error)}
            class={@option_source == :query && (@query_preview == [] || @query_error) && "opacity-50 cursor-not-allowed"}
          >
            <%= gettext("Done") %>
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  defp validate_and_save_options(socket) do
    case socket.assigns.option_source do
      :static ->
        if String.trim(socket.assigns.custom_options) == "" do
          {:error, gettext("Please enter at least one option")}
        else
          static_options = OptionsFormatter.from_display_format(socket.assigns.custom_options)
          {:ok, %{static_options: static_options, options_query: nil}}
        end

      :query ->
        if socket.assigns.query_full_results == [] do
          {:error, gettext("Please test your query first and ensure it returns results")}
        else
          {:ok, %{static_options: [], options_query: String.trim(socket.assigns.sql_query)}}
        end
    end
  end

  def handle_query_test_result(pid, results) when is_pid(pid) do
    send_update(pid, __MODULE__, id: :dropdown_options_modal, query_test_result: results)
  end

  def handle_query_test_result(component_id, results) do
    send_update(__MODULE__, id: component_id, query_test_result: results)
  end

  @impl Phoenix.LiveComponent
  def update(%{query_test_result: results} = assigns, socket) do
    case results do
      {:ok, data} ->
        select_options = OptionsFormatter.to_select_options(data)
        preview = Enum.take(select_options, 3)

        socket =
          socket
          |> assign(assigns)
          |> assign(:query_preview, preview)
          |> assign(:query_full_results, select_options)
          |> assign(:query_loading, false)
          |> assign(:query_error, nil)

        {:ok, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(assigns)
          |> assign(:query_preview, [])
          |> assign(:query_full_results, [])
          |> assign(:query_loading, false)
          |> assign(:query_error, error)

        {:ok, socket}
    end
  end

  def update(assigns, socket) do
    variable_data = assigns.variable_data || %{}

    option_source =
      variable_data
      |> QueryVariable.get_option_source()
      |> to_string()
      |> parse_option_source(assigns.dynamic_options)

    custom_options = OptionsFormatter.to_display_format(variable_data.static_options)
    sql_query = variable_data.options_query || ""

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:option_source, option_source)
     |> assign(:custom_options, custom_options)
     |> assign(:sql_query, sql_query)}
  end

  defp parse_option_source("query", true), do: :query
  defp parse_option_source(_source, _dynamic_options), do: :static
end
