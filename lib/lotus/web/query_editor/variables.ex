defmodule Lotus.Web.QueryEditor.Variables do
  @moduledoc false

  alias Lotus.Storage.QueryVariable
  alias Lotus.Storage.QueryVariable.StaticOption
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter

  def normalize_query_params(params) do
    case Map.get(params, "variables") do
      nil ->
        params

      variables_map when is_map(variables_map) ->
        normalized_variables =
          variables_map
          |> Enum.map(fn {idx, var_attrs} ->
            {idx, normalize_attrs(var_attrs)}
          end)
          |> Map.new()

        Map.put(params, "variables", normalized_variables)

      _ ->
        params
    end
  end

  def normalize_attrs(attrs) when is_map(attrs) do
    case Map.get(attrs, "static_options") do
      options_string when is_binary(options_string) and options_string != "" ->
        options_maps = OptionsFormatter.from_display_format(options_string)
        Map.put(attrs, "static_options", options_maps)

      "" ->
        Map.put(attrs, "static_options", [])

      options_list when is_list(options_list) ->
        normalized_options = OptionsFormatter.normalize_to_maps(options_list)
        Map.put(attrs, "static_options", normalized_options)

      _ ->
        attrs
    end
  end

  def normalize_attrs(attrs), do: attrs

  def normalize_values(values, variables) do
    defaults = Map.new(variables, fn v -> {v.name, v.default} end)

    list_var_names =
      variables
      |> Enum.filter(&Map.get(&1, :list, false))
      |> MapSet.new(& &1.name)

    Map.new(values, fn {name, value} ->
      default = Map.get(defaults, name)
      value = if empty_value?(value) and not empty_value?(default), do: default, else: value

      if name in list_var_names and is_binary(value) do
        {name, value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)}
      else
        {name, value}
      end
    end)
  end

  def build_ordered(names, existing_variables, ai_variables) do
    existing_by_name = Map.new(existing_variables, &{&1.name, &1})

    ai_by_name =
      case ai_variables do
        vars when is_list(vars) and vars != [] ->
          Map.new(vars, fn v -> {v["name"], v} end)

        _ ->
          %{}
      end

    Enum.map(names, fn name ->
      case Map.get(ai_by_name, name) do
        nil -> Map.get(existing_by_name, name) || new_default(name)
        ai_config -> from_ai(name, ai_config)
      end
    end)
  end

  def merge_defaults(current_values, ordered_vars) do
    Enum.reduce(ordered_vars, current_values, fn v, acc ->
      Map.update(acc, v.name, v.default, & &1)
    end)
  end

  def new_default(name) do
    %QueryVariable{
      name: name,
      type: :text,
      widget: :input,
      label: format_label(name),
      default: nil,
      static_options: [],
      options_query: nil,
      options_query_id: nil
    }
  end

  def from_ai(name, ai_config) do
    static_options =
      case ai_config["static_options"] do
        opts when is_list(opts) and opts != [] ->
          opts |> Enum.map(&StaticOption.from_input/1) |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    %QueryVariable{
      name: name,
      type: parse_type(ai_config["type"]),
      widget: parse_widget(ai_config["widget"]),
      label: ai_config["label"] || format_label(name),
      default: ai_config["default"],
      list: ai_config["list"] || false,
      static_options: static_options,
      options_query: ai_config["options_query"]
    }
  end

  def parse_type("number"), do: :number
  def parse_type("date"), do: :date
  def parse_type(_), do: :text

  def parse_widget("select"), do: :select
  def parse_widget(_), do: :input

  def to_params(%QueryVariable{} = v) do
    %{
      "name" => v.name,
      "type" => v.type,
      "widget" => v.widget,
      "label" => v.label,
      "default" => v.default,
      "list" => v.list,
      "static_options" => static_options_to_params(v.static_options),
      "options_query" => v.options_query,
      "options_query_id" => v.options_query_id
    }
  end

  def static_options_to_params(static_options) do
    OptionsFormatter.static_options_to_storage(static_options)
  end

  def format_label(var_name) when is_binary(var_name) do
    var_name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_label(var_name), do: var_name

  def empty_value?(nil), do: true
  def empty_value?(""), do: true
  def empty_value?([]), do: true
  def empty_value?(_), do: false

  def get_data(form, variable_name) do
    variables = form[:variables].value || []

    case Enum.find(variables, &matches_name?(&1, variable_name)) do
      nil ->
        %{}

      %Ecto.Changeset{} = changeset ->
        Ecto.Changeset.apply_changes(changeset)

      variable ->
        variable
    end
  end

  def matches_name?(var, variable_name) do
    case var do
      %Ecto.Changeset{} = changeset ->
        Ecto.Changeset.get_field(changeset, :name) == variable_name

      %{name: name} ->
        name == variable_name

      _ ->
        false
    end
  end

  def clear_values_on_widget_change(values, new_variables, old_variables) do
    old_by_name = Map.new(old_variables, &{&1.name, &1})

    Enum.reduce(new_variables, values, fn var, acc ->
      maybe_clear_value(acc, var, Map.get(old_by_name, var.name))
    end)
  end

  def clear_values_on_default_change(values, new_variables, old_variables) do
    old_defaults = Map.new(old_variables, &{&1.name, &1.default})

    Enum.reduce(new_variables, values, fn var, acc ->
      old_default = Map.get(old_defaults, var.name)
      maybe_clear_for_default(acc, var, old_default)
    end)
  end

  defp maybe_clear_value(values, _var, nil), do: values

  defp maybe_clear_value(values, var, old) do
    widget_changed = Map.get(old, :widget) != var.widget
    list_changed = Map.get(old, :list, false) != Map.get(var, :list, false)

    if widget_changed or list_changed, do: Map.put(values, var.name, nil), else: values
  end

  defp maybe_clear_for_default(values, %{default: same}, same), do: values

  defp maybe_clear_for_default(values, var, old_default) do
    current = Map.get(values, var.name)

    if empty_value?(current) or matches_default?(current, old_default),
      do: Map.put(values, var.name, nil),
      else: values
  end

  defp matches_default?(value, default) when is_list(value) and is_binary(default) do
    value == String.split(default, ",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp matches_default?(value, default), do: value == default
end
