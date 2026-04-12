defmodule Lotus.Web.Queries.SegmentedDataSelectorComponent do
  @moduledoc """
  A segmented selector component for data sources and their schemas/databases.

  This component provides a two-part selector:
  - Left: Data source (repository)
  - Right: Schema/Database (adapter-aware)

  The right selector adapts based on the selected source's adapter type:
  - PostgreSQL: Shows "Schema" with multi-select support for search_path
  - MySQL: Shows "Database" with single select
  - SQLite: Hidden (no schema concept)
  """

  use Lotus.Web, :live_component

  alias Lotus.Web.Queries.ToolbarComponents, as: Toolbar

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <div class="w-40">
        <.live_component
          module={Lotus.Web.SelectComponent}
          id={@source_id || "source-selector"}
          name={@source_field.name}
          label={gettext("Source")}
          floating_label={true}
          value={@source_field.value}
          options={@source_options}
          prompt={gettext("Select source")}
          disabled={@disabled}
          errors={@source_field.errors}
          show_icons={true}
        />
      </div>

      <%= if @schema_visible do %>
        <div class="w-40">
          <%= if @schema_multiple do %>
            <Toolbar.input
              type="multiselect"
              id={@schema_id || "schema-selector"}
              name={@schema_field && @schema_field.name}
              label={@schema_label}
              value={@schema_field && @schema_field.value}
              options={@schema_options}
              prompt={gettext("Select %{label}", label: String.downcase(@schema_label || ""))}
              search_prompt={gettext("Search")}
              disabled={@disabled or @schema_loading}
              errors={(@schema_field && @schema_field.errors) || []}
              show_icons={false}
            />
          <% else %>
            <.live_component
              module={Lotus.Web.SelectComponent}
              id={@schema_id || "schema-selector"}
              name={@schema_field && @schema_field.name}
              label={@schema_label}
              floating_label={true}
              value={@schema_field && @schema_field.value}
              options={@schema_options}
              prompt={gettext("Select %{label}", label: String.downcase(@schema_label || ""))}
              disabled={@disabled or @schema_loading}
              errors={(@schema_field && @schema_field.errors) || []}
              show_icons={false}
              phx-target={@parent}
            />
          <% end %>
        </div>
      <% end %>

      <%= if @schema_loading do %>
        <div class="flex items-center ml-2">
          <svg class="animate-spin h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </div>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_load_schemas()

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("source_changed", %{"value" => source}, socket) do
    send(socket.assigns.parent, {:source_changed, source, socket.assigns.target_field})
    {:noreply, assign(socket, schema_loading: true)}
  end

  defp maybe_load_schemas(socket) do
    source = socket.assigns.source_field.value

    if source && source != "" do
      case get_adapter_info(source) do
        %{show: false} ->
          assign_hidden_schema(socket)

        %{type: _adapter_type, label: label, multiple: multiple, show: true} ->
          load_schemas_for_source(socket, source, label, multiple)
      end
    else
      assign_hidden_schema(socket)
    end
  end

  defp assign_hidden_schema(socket) do
    assign(socket,
      schema_visible: false,
      schema_loading: false,
      schema_options: [],
      schema_label: gettext("Schema"),
      schema_multiple: false
    )
  end

  defp load_schemas_for_source(socket, source, label, multiple) do
    case Lotus.list_schemas(source) do
      {:ok, schemas} ->
        options = Enum.map(schemas, &{&1, &1})

        assign(socket,
          schema_visible: true,
          schema_loading: false,
          schema_options: options,
          schema_label: label,
          schema_multiple: multiple
        )

      {:error, _} ->
        assign(socket,
          schema_visible: true,
          schema_loading: false,
          schema_options: [],
          schema_label: label,
          schema_multiple: multiple
        )
    end
  end

  defp get_adapter_info(repo_name) do
    source_type = Lotus.Source.source_type(repo_name)

    {label, multiple, show} =
      case source_type do
        :postgres -> {gettext("Schema"), true, true}
        :mysql -> {gettext("Database"), false, false}
        _ -> {gettext("Schema"), false, false}
      end

    %{type: source_type, label: label, multiple: multiple, show: show}
  end
end
