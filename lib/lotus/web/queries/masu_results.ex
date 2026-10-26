defmodule Lotus.Web.Queries.MasuResults do
  @moduledoc false

  # The results table, drawn by Masu. Masu is only the view. Lotus runs the
  # query: the grid shows the rows of the page Lotus read, and gives back
  # the person's sort and filters (`on_query`), which the query editor turns
  # into Lotus's filters and sorts and runs.

  use Phoenix.Component

  use Gettext, backend: Lotus.Web.Gettext

  import Masu.Components

  alias Lotus.Web.Queries.MasuMessages

  alias Lotus.Query.Filter
  alias Lotus.Query.Sort

  # Masu's filters and the Lotus operator each runs as: = ≠ > < ≥ ≤,
  # contains, starts with and ends with (text as written, without regard to
  # case), null and not null. Masu also offers between, as ≥ and ≤.
  @lotus_ops [
    eq: :eq,
    neq: :neq,
    gt: :gt,
    lt: :lt,
    gte: :gte,
    lte: :lte,
    contains: :contains,
    starts_with: :starts_with,
    ends_with: :ends_with,
    is_nil: :is_null,
    not_nil: :is_not_null
  ]

  attr(:id, :string, required: true)
  attr(:result, :map, required: true)
  attr(:running, :boolean, default: false)
  attr(:target, :any, required: true)
  # The `Lotus.Query.Filter` operators the source runs: the grid offers
  # the filters of those only.
  attr(:operators, :list, default: [])
  attr(:stats, :map, default: %{})

  # The result's foreign key columns and the tables they reference
  # (`Lotus.Web.Queries.References`): their cells open the row.
  attr(:references, :map, default: %{})

  def grid(assigns) do
    target = assigns.target

    assigns =
      assign(assigns,
        follows:
          for {column, ref} <- Enum.sort(assigns.references) do
            %{
              column: column,
              label: gettext("Open %{table} row", table: ref.table),
              on_action: &follow(target, column, &1)
            }
          end,
        rows: grid_rows(assigns.result, assigns.references),
        # A cell's item reads its row by the row's id: a cell of a foreign
        # key needs one (`with_row_ids/1`); the rest are by their place.
        row_id: if(assigns.references == %{}, do: :position, else: &List.last/1),
        columns: columns(assigns.result, filters_for(assigns.operators)),
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
        row_id={@row_id}
        on_query={@on_query}
        loading={@running}
        multi_sort={false}
        row_height={40}
        cell_menu
        messages={@messages}
        locale={@locale}
        label={gettext("Results")}
        class="lotus-results"
        height="100%"
      >
        <:cell_action
          :for={follow <- @follows}
          label={follow.label}
          columns={[follow.column]}
          on_action={follow.on_action}
        />
        <:header_action :let={action} label={gettext("Column stats")}>
          <div
            id={"#{@id}-stats-#{action.column}"}
            phx-hook="ColumnStats"
            data-stats={stats_json(@stats[action.column])}
          >
          </div>
        </:header_action>
      </.data_grid>
    </div>
    """
  end

  @doc """
  A dashboard card's table: its result in a read-only grid that fills the
  card, compact, sorted and filtered in the browser's page from its rows (a
  card's result is in memory), with each column's menu on its header and
  no bar above it.
  """
  attr(:id, :string, required: true)
  attr(:result, :map, required: true)
  attr(:label, :string, default: nil)

  attr(:row_actions, :list,
    default: [],
    doc: "Lotus Pro's actions on each row (`Lotus.Web.Pro.row_actions/2`)"
  )

  def card(%{row_actions: [_ | _] = actions} = assigns) do
    assigns =
      assign(assigns,
        rows: assigns.result |> rows() |> with_row_ids(),
        columns: card_columns(assigns.result),
        messages: MasuMessages.messages(),
        locale: Gettext.get_locale(Lotus.Web.Gettext),
        on_actions:
          for(%{on_action: fun} = action <- actions, do: %{action | on_action: without_id(fun)}),
        links:
          for(%{navigate: fun} = action <- actions, do: %{action | navigate: without_id(fun)})
      )

    ~H"""
    <.data_grid
      id={@id}
      rows={@rows}
      columns={@columns}
      row_id={&List.last/1}
      density={:compact}
      filter_bar={false}
      messages={@messages}
      locale={@locale}
      label={@label}
      class="lotus-results lotus-card-table"
      height="100%"
    >
      <:row_action :for={action <- @on_actions} label={action.label} on_action={action.on_action} />
      <:row_action :for={action <- @links} label={action.label} navigate={action.navigate} />
    </.data_grid>
    """
  end

  def card(assigns) do
    assigns =
      assign(assigns,
        rows: rows(assigns.result),
        columns: card_columns(assigns.result),
        messages: MasuMessages.messages(),
        locale: Gettext.get_locale(Lotus.Web.Gettext)
      )

    ~H"""
    <.data_grid
      id={@id}
      rows={@rows}
      columns={@columns}
      row_id={:position}
      density={:compact}
      filter_bar={false}
      messages={@messages}
      locale={@locale}
      label={@label}
      class="lotus-results lotus-card-table"
      height="100%"
    />
    """
  end

  # A foreign key's cell opens the row it references, in the query editor
  # (`:follow_reference`); an empty cell references none.
  defp follow(_target, _column, %{value: nil}),
    do: {:error, gettext("This cell is empty: it references no row")}

  defp follow(target, column, %{value: value}) do
    Phoenix.LiveView.send_update(target, %{
      action: :follow_reference,
      column: column,
      value: value
    })

    :ok
  end

  defp grid_rows(result, references) when references == %{}, do: rows(result)
  defp grid_rows(result, _references), do: result |> rows() |> with_row_ids()

  # Row actions need a row's id to stay the same from one run to the next: a
  # hash of its values and of how many rows with the same values came
  # before it, after its cells. Pro's actions get the row without it.
  defp with_row_ids(rows) do
    {rows, _seen} =
      Enum.map_reduce(rows, %{}, fn row, seen ->
        n = Map.get(seen, row, 0)
        {row ++ [:erlang.phash2({row, n})], Map.put(seen, row, n + 1)}
      end)

    rows
  end

  defp without_id(fun) do
    fn
      %{row: row} = context when is_list(row) -> fun.(%{context | row: Enum.drop(row, -1)})
      row when is_list(row) -> fun.(Enum.drop(row, -1))
      other -> fun.(other)
    end
  end

  # A card's columns, each as wide as its longest value, or as its name
  # and its header's menu button (in a card, the columns fit before they
  # scroll): 7 pixels a character, the cell's padding, from 64 to 240.
  defp card_columns(%{columns: columns, rows: rows}) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {name, i} ->
      value =
        rows
        |> Enum.take(200)
        |> Enum.map(&(&1 |> Enum.at(i) |> cell() |> to_string() |> String.length()))
        |> Enum.max(fn -> 0 end)

      width = max(value * 7 + 24, String.length(name) * 8 + 72)
      %{key: name, label: name, raw: true, width: width |> max(64) |> min(240)}
    end)
  end

  # The columns as Lotus names them, of the types of their values, with the
  # filters Lotus runs; their values as Lotus's table shows them (`raw`),
  # not formatted for the locale.
  defp columns(%{columns: columns}, filters),
    do: for(name <- columns, do: %{key: name, label: name, filters: filters, raw: true})

  @doc "Masu's filters of the Lotus operators a source runs."
  def filters_for(operators),
    do: for({masu, lotus} <- @lotus_ops, lotus in operators, do: masu)

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

      op when op in [:contains, :starts_with, :ends_with] ->
        [Filter.new(key, op, value)]

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
