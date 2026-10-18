defmodule Lotus.Web.Queries.MasuResults do
  @moduledoc false

  # The results table drawn by Masu (a trial: `config :lotus_web,
  # results_table: :masu`). Masu is only the view. Lotus runs the query, as
  # for its own table: the grid shows the rows of the page Lotus read, and
  # gives back the person's sort and filters (`on_query`), which the query
  # editor turns into Lotus's filters and sorts and runs.

  use Phoenix.Component

  use Gettext, backend: Lotus.Web.Gettext

  import Masu.Components

  alias Lotus.Web.Queries.MasuMessages

  alias Lotus.Query.Filter
  alias Lotus.Query.Sort

  # The filters Lotus runs: = ≠ > < ≥ ≤, LIKE (contains, starts with, ends
  # with), null and not null. Masu offers those, and between (≥ and ≤).
  @masu_filters [
    :eq,
    :neq,
    :gt,
    :lt,
    :gte,
    :lte,
    :contains,
    :starts_with,
    :ends_with,
    :is_nil,
    :not_nil
  ]

  @doc "Whether the results table is Masu's."
  def enabled?, do: Application.get_env(:lotus_web, :results_table, :table) == :masu

  attr(:id, :string, required: true)
  attr(:result, :map, required: true)
  attr(:running, :boolean, default: false)
  attr(:target, :any, required: true)
  attr(:stats, :map, default: %{})

  def grid(assigns) do
    target = assigns.target

    assigns =
      assign(assigns,
        rows: rows(assigns.result),
        columns: columns(assigns.result),
        on_query: &Phoenix.LiveView.send_update(target, %{action: :masu_query, report: &1}),
        messages: MasuMessages.messages(),
        locale: Gettext.get_locale(Lotus.Web.Gettext)
      )

    ~H"""
    <div class="h-full py-2">
      <.data_grid
        id={@id}
        rows={@rows}
        columns={@columns}
        row_id={:position}
        on_query={@on_query}
        loading={@running}
        multi_sort={false}
        row_height={52}
        cell_menu
        messages={@messages}
        locale={@locale}
        label={gettext("Results")}
        class="lotus-results"
        height="100%"
      >
        <:header_action :let={action} label={gettext("Column stats")}>
          <div
            id={"#{@id}-stats-#{action.column}"}
            phx-hook="MasuColumnStats"
            data-stats={stats_json(@stats[action.column])}
          >
          </div>
        </:header_action>
      </.data_grid>
    </div>
    """
  end

  # The columns as Lotus names them, of the types of their values, with the
  # filters Lotus runs; their values as Lotus's table shows them (`raw`),
  # not formatted for the locale.
  defp columns(%{columns: columns}),
    do: for(name <- columns, do: %{key: name, label: name, filters: @masu_filters, raw: true})

  # Each value as Masu reads it: numbers, decimals, dates and booleans as
  # they are, so that they sort, filter and align by their type; the rest
  # (binaries, JSON, arrays, UUIDs) as Lotus shows them.
  defp rows(%{rows: rows}), do: Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)

  defp cell(value) when is_nil(value) or is_number(value) or is_boolean(value), do: value
  defp cell(%Decimal{} = value), do: value
  defp cell(%Date{} = value), do: value
  defp cell(%DateTime{} = value), do: value
  defp cell(%NaiveDateTime{} = value), do: value
  defp cell(%Time{} = value), do: value

  defp cell(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Lotus.Value.to_display_string(value)
  end

  defp cell(value), do: Lotus.Value.to_display_string(value)

  defp stats_json(nil), do: "{}"

  defp stats_json(stats) do
    stats
    |> Map.new(fn {key, value} -> {key, Lotus.Normalizer.normalize(value)} end)
    |> Lotus.Web.Helpers.safe_json_encode_or_empty()
  end

  @doc """
  Lotus's filters and sorts for the person's view in the grid
  (`%Masu.Query{}`): the filters Lotus runs, the one sort.
  """
  def lotus_query(%Masu.Query{filters: filters, sorts: sorts}) do
    {Enum.flat_map(filters, &lotus_filters/1), Enum.map(Enum.take(sorts, 1), &lotus_sort/1)}
  end

  defp lotus_filters(%Masu.Filter{key: key, op: op, value: value}) do
    case op do
      op when op in [:eq, :neq, :gt, :lt, :gte, :lte] ->
        [Filter.new(key, op, value)]

      :between ->
        [Filter.new(key, :gte, Enum.at(value, 0)), Filter.new(key, :lte, Enum.at(value, 1))]

      :contains ->
        [Filter.new(key, :like, "%#{value}%")]

      :starts_with ->
        [Filter.new(key, :like, "#{value}%")]

      :ends_with ->
        [Filter.new(key, :like, "%#{value}")]

      :is_nil ->
        [Filter.new(key, :is_null)]

      :not_nil ->
        [Filter.new(key, :is_not_null)]

      # Masu offers no other (the columns' filters).
      _other ->
        []
    end
  end

  defp lotus_sort(%Masu.Sort{key: key, direction: direction}), do: Sort.new(key, direction)
end
