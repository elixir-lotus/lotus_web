defmodule Lotus.Web.Dashboards.FilterOptions do
  @moduledoc """
  The options of the select filters of a dashboard, for the current filter values.

  A select filter gets its options from `Lotus.list_dashboard_filter_options/2`:
  the static `config["options"]`, or the rows of its source query. A filter that
  depends on another filter gets the value of that filter as a query variable,
  so `resolve/3` walks the filters parent first, and a `city` filter sees the
  `country` value that `resolve/3` already checked.

  Core does not check a value against the options, so `resolve/3` does. When the
  options of a dependent filter change, its value stays only if it is one of the
  new options, and otherwise becomes `""`. The clear goes down the chain
  (`country` → `city` → `district`).

  The filters can be `Lotus.Storage.DashboardFilter` structs or the maps the
  dashboard editor keeps for filters not saved yet, whose ids are strings.
  """

  alias Lotus.Storage.DashboardFilter

  @typedoc """
  The options state of one select filter:

    * `{:ok, options}` - the options, each `%{value: term(), label: term()}`
    * `{:error, reason}` - the source query failed or may not run
    * `:waiting` - the filter depends on a filter that has no value
  """
  @type state :: {:ok, [%{value: term(), label: term()}]} | {:error, term()} | :waiting

  @doc """
  Resolves the options of every select filter.

  Returns the state of each select filter by name, and the filter values with
  the values that are no longer an option cleared.

  ## Options

    * `:run_opts` - options for the source query, such as `:context` and `:scope`
    * `:authorize` - a function that takes a source query id and returns
      `:allow` or `{:deny, reason}`. Defaults to allowing every query.
  """
  @spec resolve([map()], map(), keyword()) :: {%{String.t() => state()}, map()}
  def resolve(filters, filter_values, opts \\ []) do
    filters_by_id = Map.new(filters, &{&1.id, &1})

    filters
    |> Enum.filter(&(&1.widget == :select))
    |> Enum.reduce({%{}, filter_values}, &resolve_filter(&1, filters_by_id, opts, &2, []))
  end

  defp resolve_filter(filter, filters_by_id, opts, {options, _values} = acc, path) do
    if Map.has_key?(options, filter.name) do
      acc
    else
      parent = parent(filter, filters_by_id, path)

      {options, values} =
        if parent && parent.widget == :select,
          do: resolve_filter(parent, filters_by_id, opts, acc, [filter.id | path]),
          else: acc

      state = filter_state(filter, parent, values, opts)
      {Map.put(options, filter.name, state), clear_value(values, filter, parent, state)}
    end
  end

  # A dependency counts only with a source query, as in core. A parent already on
  # the path is a cycle in filters not saved yet, and counts as no parent.
  defp parent(%{source_query_id: nil}, _filters_by_id, _path), do: nil
  defp parent(%{depends_on_filter_id: nil}, _filters_by_id, _path), do: nil

  defp parent(filter, filters_by_id, path) do
    parent_id = filter.depends_on_filter_id

    if parent_id in path, do: nil, else: Map.get(filters_by_id, parent_id)
  end

  defp filter_state(%{source_query_id: nil} = filter, _parent, _values, _opts),
    do: list_options(filter, nil, %{}, [])

  defp filter_state(filter, parent, values, opts) do
    parent_values = parent_values(parent, values)
    authorize = Keyword.get(opts, :authorize, fn _query_id -> :allow end)

    if parent != nil and parent_values == %{} do
      :waiting
    else
      case authorize.(filter.source_query_id) do
        :allow -> list_options(filter, parent, parent_values, Keyword.get(opts, :run_opts, []))
        {:deny, reason} -> {:error, reason}
      end
    end
  end

  defp parent_values(nil, _values), do: %{}

  defp parent_values(parent, values) do
    case Map.get(values, parent.name) do
      value when is_binary(value) and value != "" -> %{parent.name => value}
      _blank -> %{}
    end
  end

  # The parent goes in already loaded, so core does not read it from the
  # database: an unsaved parent has no row, and a saved one may have unsaved
  # edits. Its default is left out, because the values already carry it.
  #
  # The structs carry only the fields core reads. An unsaved filter has no
  # position or timestamps, so they are built with struct!/2.
  defp list_options(filter, parent, parent_values, run_opts) do
    {parent_id, core_parent} =
      if parent, do: {parent.id, core_parent(parent)}, else: {nil, nil}

    core_filter =
      struct!(DashboardFilter, %{
        id: filter.id,
        name: filter.name,
        filter_type: filter.filter_type,
        widget: filter.widget,
        config: filter.config || %{},
        source_query_id: filter.source_query_id,
        depends_on_filter_id: parent_id,
        depends_on_filter: core_parent
      })

    Lotus.list_dashboard_filter_options(
      core_filter,
      Keyword.put(run_opts, :filter_values, parent_values)
    )
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp core_parent(parent) do
    struct!(DashboardFilter, %{id: parent.id, name: parent.name, filter_type: parent.filter_type})
  end

  defp clear_value(values, _filter, nil, _state), do: values
  defp clear_value(values, _filter, _parent, {:error, _reason}), do: values

  defp clear_value(values, filter, _parent, state) do
    value = Map.get(values, filter.name)

    if value in [nil, ""] or option?(state, value),
      do: values,
      else: Map.put(values, filter.name, "")
  end

  defp option?({:ok, options}, value),
    do: Enum.any?(options, &(to_string(&1.value) == to_string(value)))

  defp option?(:waiting, _value), do: false
end
