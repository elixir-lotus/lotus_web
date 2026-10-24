defmodule Lotus.Web.Queries.QueryList do
  @moduledoc """
  The queries as their list shows them: each with the chart it is saved
  with (its first visualization), how many dashboards use it, its source
  and that source's language. Read in three queries for the whole list,
  not one a query.

  And a query's SQL as tokens for its preview: keywords, variables and the
  rest, each to render as text (never as HTML).
  """

  import Ecto.Query

  alias Lotus.Storage.DashboardCard
  alias Lotus.Storage.QueryVisualization

  @type entry :: %{
          query: struct(),
          chart: String.t() | nil,
          dashboards: non_neg_integer(),
          source: String.t(),
          dialect: String.t()
        }

  @doc "The queries, each with what its list shows of it."
  @spec entries([struct()]) :: [entry()]
  def entries([]), do: []

  def entries(queries) do
    ids = Enum.map(queries, & &1.id)
    charts = charts(ids)
    dashboards = dashboards(ids)
    default = default_source()

    Enum.map(queries, fn query ->
      source = query.data_source || default

      %{
        query: query,
        chart: Map.get(charts, query.id),
        dashboards: Map.get(dashboards, query.id, 0),
        source: source,
        dialect: dialect(source)
      }
    end)
  end

  # The chart type of each query's first visualization.
  defp charts(ids) do
    from(v in QueryVisualization,
      where: v.query_id in ^ids,
      order_by: [asc: v.position, asc: v.id],
      select: {v.query_id, v.config}
    )
    |> Lotus.repo().all()
    |> Enum.reduce(%{}, fn {id, config}, acc ->
      case config do
        %{"chart_type" => type} when is_binary(type) -> Map.put_new(acc, id, type)
        _ -> acc
      end
    end)
  end

  # How many dashboards have a card of each query.
  defp dashboards(ids) do
    from(c in DashboardCard,
      where: c.query_id in ^ids,
      group_by: c.query_id,
      select: {c.query_id, count(c.dashboard_id, :distinct)}
    )
    |> Lotus.repo().all()
    |> Map.new()
  end

  defp default_source do
    {name, _repo} = Lotus.default_data_source()
    name
  end

  defp dialect(nil), do: "sql"

  # The language of a source, by its adapter ("postgres", "mysql"…); a
  # source Lotus no longer knows reads as plain SQL.
  defp dialect(source) do
    source |> Lotus.Source.query_language() |> language()
  rescue
    _ -> "sql"
  end

  defp language("sql:" <> dialect), do: dialect
  defp language("json:" <> dialect), do: dialect
  defp language(_language), do: "sql"

  @keywords ~w(select from where group by order having join left right inner outer full on and or
               not as limit offset union all distinct case when then else end with in is null
               like ilike between asc desc insert update delete into values set)

  @doc """
  The first `lines` lines of a statement as tokens: `{:keyword, text}`,
  `{:variable, text}` (a `{{name}}`) and `{:text, text}`, and `:newline`.
  A statement written on one line has its clauses each on a line;
  `:one_line` gives the whole statement on one line.

      iex> Lotus.Web.Queries.QueryList.tokens("SELECT id FROM users WHERE name = {{name}}", 3)
      [{:keyword, "SELECT"}, {:text, " id"}, :newline, {:keyword, "FROM"}, {:text, " users"},
       :newline, {:keyword, "WHERE"}, {:text, " name = "}, {:variable, "{{name}}"}]
  """
  @spec tokens(String.t() | nil, pos_integer() | :one_line) :: [tuple() | :newline]
  def tokens(nil, _lines), do: []

  # The whole statement on one line: a line of a list.
  def tokens(statement, :one_line) do
    statement |> String.replace(~r/\s+/, " ") |> String.trim() |> line_tokens()
  end

  def tokens(statement, lines) do
    statement
    |> String.trim()
    |> lay_out()
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(lines)
    |> Enum.map(&line_tokens/1)
    |> Enum.intersperse([:newline])
    |> List.flatten()
  end

  # A statement written on one line, its clauses each on a line of their
  # own, as a reader would write it: a preview of a few lines reads.
  @clauses ~r/\s+(?=(?:FROM|WHERE|(?:LEFT|RIGHT|INNER|FULL|CROSS) JOIN|GROUP BY|ORDER BY|HAVING|LIMIT|UNION)\b)|(?<!LEFT|RIGHT|INNER|FULL|CROSS)\s+(?=JOIN\b)/i

  defp lay_out(statement) do
    if String.contains?(statement, "\n"),
      do: statement,
      else: Regex.replace(@clauses, statement, "\n")
  end

  defp line_tokens(line) do
    ~r/\{\{\s*\w+\s*\}\}|[A-Za-z_]+|[^A-Za-z_{]+|\{/
    |> Regex.scan(line)
    |> List.flatten()
    |> Enum.map(fn part ->
      cond do
        String.starts_with?(part, "{{") -> {:variable, part}
        String.downcase(part) in @keywords -> {:keyword, part}
        true -> {:text, part}
      end
    end)
    |> merge_text()
  end

  defp merge_text([{:text, a}, {:text, b} | rest]), do: merge_text([{:text, a <> b} | rest])
  defp merge_text([token | rest]), do: [token | merge_text(rest)]
  defp merge_text([]), do: []
end
