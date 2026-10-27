defmodule Lotus.Web.Queries.WidgetComponent do
  use Lotus.Web, :html

  alias Lotus.Web.Queries.ToolbarComponents, as: Toolbar
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter

  @moduledoc """
  Renders a single variable widget for the toolbar.

  Props:
    * var               - %QueryVariable{} or map with keys:
                          :name, :type (:text|:number|:date),
                          :widget (:input|:select|:date),
                          :label, :default, :static_options
    * value             - current value override (from @variable_values); falls back to var.default
    * class             - extra classes for outer wrapper
    * resolved_options  - pre-resolved Phoenix select options [{label, value}] for SQL-based dropdowns;
                          takes precedence over static_options when provided
    * options_error     - why the options of a dropdown from a query could not load
  """

  attr(:var, :map, required: true)
  attr(:value, :any, default: nil)
  attr(:class, :string, default: nil)
  attr(:resolved_options, :list, default: nil)
  attr(:options_error, :string, default: nil)
  attr(:optional, :boolean, default: false)

  def widget(assigns) do
    base_label = assigns.var.label || format_label(assigns.var.name)

    assigns =
      assigns
      |> assign_new(:name, fn -> "variables[#{assigns.var.name}]" end)
      |> assign_new(:label, fn -> base_label end)
      |> assign_new(:id, fn -> "variable_#{assigns.var.name}" end)
      |> assign_new(:value, fn -> assigns.value || assigns.var.default end)
      |> assign_new(:widget, fn -> widget_type(assigns.var) end)
      |> assign_new(:options, fn ->
        if assigns.resolved_options && assigns.resolved_options != [] do
          assigns.resolved_options
        else
          OptionsFormatter.to_select_options(assigns.var.static_options)
        end
      end)
      |> assign_new(:placeholder, fn ->
        if assigns.optional, do: gettext("All"), else: gettext("Enter value")
      end)

    ~H"""
    <div class={["flex items-center gap-2 min-w-32", @class]}>
      <%= case @widget do %>
        <% :date -> %>
          <Toolbar.input
            id={@id}
            type="date"
            name={@name}
            label={@label}
            value={@value}
            class="min-w-48 w-48"
          />

        <% :multiselect -> %>
          <Toolbar.input
            id={@id <> "_ms"}
            type="multiselect"
            name={@name}
            label={@label}
            value={encode_list_value(@value)}
            options={@options}
            prompt={gettext("Select values")}
            disabled={@options == []}
            errors={if @options_error, do: [gettext("Options failed")], else: []}
            class="min-w-40 w-40"
          />

        <% :tag_input -> %>
          <.tag_input
            id={@id}
            name={@name}
            label={@label}
            value={@value}
            input_type={if @var.type == :number, do: "number", else: "text"}
            class="min-w-40 w-64"
          />

        <% :select -> %>
          <Toolbar.input
            id={@id}
            type="select"
            name={@name}
            label={@label}
            value={@value}
            options={@options}
            prompt={gettext("Select value")}
            disabled={@options == []}
            errors={if @options_error, do: [gettext("Options failed")], else: []}
            class="min-w-40 w-40"
          />

        <% _ -> %>
          <Toolbar.input
            id={@id}
            type={if @var.type == :number, do: "number", else: "text"}
            name={@name}
            label={@label}
            value={@value}
            placeholder={@placeholder}
            class="min-w-40 w-40"
          />
      <% end %>
      <span
        :if={@options_error}
        id={@id <> "-options-error"}
        phx-hook="Tippy"
        data-title={@options_error}
        aria-label={gettext("The options could not load: %{reason}", reason: @options_error)}
        role="img"
        class="text-rose-500 dark:text-rose-400"
      >
        <Icons.exclamation_triangle class="h-4 w-4" />
      </span>
    </div>
    """
  end

  defp tag_input(assigns) do
    tags = parse_tags(assigns.value)

    assigns =
      assigns
      |> assign(:tags, tags)
      |> assign(:has_value, tags != [])
      |> assign(:hidden_value, Enum.join(tags, ","))
      |> assign(:formatted_label, format_label(assigns[:label]))
      |> assign(:tag_input_id, assigns.id <> "_tag")
      |> assign(:hidden_id, assigns.id <> "_tag_hidden")

    ~H"""
    <fieldset class={[
      "group border rounded-md bg-white dark:bg-input-dark",
      @has_value && "border-pink-600",
      !@has_value && "border-gray-300 dark:border-gray-600 focus-within:border-pink-600"
    ]}>
      <legend :if={@label} class="ml-1 px-1 text-xs font-medium text-gray-700 dark:text-gray-300">
        {@formatted_label}
      </legend>
      <input
        type="hidden"
        name={@name}
        value={@hidden_value}
        id={@hidden_id}
        phx-hook="DispatchChangeOnUpdate"
      />
      <div class={[
        "flex overflow-hidden items-center px-2 cursor-text",
        @class
      ]}>
        <div :if={@has_value} class="overflow-x-auto scrollbar-hide flex items-center shrink min-w-0">
          <span :for={{tag, idx} <- Enum.with_index(@tags)} class="inline-flex shrink-0 items-center gap-0.5 rounded bg-pink-100 dark:bg-pink-900/30 px-1 mr-1 text-xs font-medium text-pink-700 dark:text-pink-300">
            {tag}
            <button
              type="button"
              data-tag-remove={idx}
              data-hidden-id={@hidden_id}
              phx-hook="TagRemove"
              id={@tag_input_id <> "_rm_" <> to_string(idx)}
              class="text-pink-500 hover:text-pink-700 dark:text-pink-400 dark:hover:text-pink-200"
            >
              <Icons.x_mark class="h-3 w-3" />
            </button>
          </span>
        </div>
        <input
          type={@input_type}
          id={@tag_input_id}
          phx-hook="TagInput"
          data-hidden-id={@hidden_id}
          data-tag-count={length(@tags)}
          placeholder={if(!@has_value, do: gettext("Enter values"), else: "")}
          class={[
            "border-0 bg-transparent focus:ring-0 text-sm py-1.5 focus:placeholder:hidden",
            @has_value && "shrink-0 w-[72px]",
            !@has_value && "w-full",
            @has_value && "text-pink-600 focus:text-gray-900 dark:focus:text-gray-100",
            !@has_value && "text-gray-900 dark:text-gray-100"
          ]}
        />
      </div>
    </fieldset>
    """
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []
  defp parse_tags(value) when is_binary(value), do: String.split(value, ",", trim: true)
  defp parse_tags(value) when is_list(value), do: value
  defp parse_tags(_), do: []

  defp widget_type(%{type: :date}), do: :date
  defp widget_type(%{list: true, widget: :select}), do: :multiselect
  defp widget_type(%{list: true}), do: :tag_input
  defp widget_type(%{widget: :select}), do: :select
  defp widget_type(_), do: :input

  defp encode_list_value(value) when is_list(value), do: Enum.join(value, ",")
  defp encode_list_value(value), do: value

  defp format_label(name) when is_binary(name) do
    name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_label(name), do: to_string(name)
end
