if Code.ensure_loaded?(Sake.Server) do
  defmodule Lotus.Web.MCP.ShowChart do
    @moduledoc false
    alias Lotus.MCP.{Chart, Support}
    alias Lotus.Web.Charts
    alias Lotus.Web.MCP.ChartApp

    require Chart

    use Sake.Tool,
      name: "show_chart",
      title: "Show a chart",
      description:
        "Chart a saved query (with its own chart, or chart_type and fields) or a read-only " <>
          "statement on a data source. Hosts that render apps draw the chart in the " <>
          "conversation; the result is the chart's Fude spec with its rows. Nothing " <>
          "is saved: save_chart keeps a chart with a saved query.",
      scope: "lotus:query",
      annotations: [read_only: true, idempotent: true, open_world: false],
      ui: Lotus.Web.MCP.ChartApp

    arg :query_id, :integer, description: "A saved query to chart"
    arg :data_source, :string, description: "Without query_id: the data source to run on"

    arg :statement, :string,
      max_length: 100_000,
      description: "Without query_id: the read-only statement to chart"

    arg :vars, :any, description: "Values for the saved query's variables, by name"
    arg :title, :string, max_length: 255, description: "The chart's title"

    arg :limit, :integer,
      default: 500,
      min: 1,
      description: "Rows to chart (at most the server's cap, 500 by default)"

    Chart.args()

    @impl true
    def execute(args, ctx) do
      window = Support.window(args[:limit] || 500, 0)
      actor = Support.actor_opts(ctx)

      with {:ok, title, run, saved} <- source(args, ctx),
           {:ok, result} <- run.([read_only: true, window: window] ++ actor),
           {:ok, config} <- config(args, saved, result.columns) do
        shaped = Support.result(result, window)

        {:ok,
         %{
           title: args[:title] || title,
           chart: config,
           spec: Charts.spec(result, config),
           html: ChartApp.html(result, config),
           num_rows: shaped.num_rows,
           has_more: shaped.has_more
         }}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    # What runs, its title, and the saved query's own chart (or nil).
    defp source(%{query_id: id} = args, ctx) when is_integer(id) do
      with {:ok, query} <- Support.fetch_query(id, ctx) do
        # A chart only reads, as every MCP tool does.
        run = fn opts ->
          Lotus.run_query(query, [vars: Support.vars(args[:vars]), read_only: true] ++ opts)
        end

        {:ok, query.name, run, saved_chart(query)}
      end
    end

    defp source(%{data_source: ds, statement: statement}, _ctx)
         when is_binary(ds) and is_binary(statement) do
      with {:ok, ds} <- Support.data_source(ds) do
        {:ok, nil, &Lotus.run_statement(statement, [], [repo: ds] ++ &1), nil}
      end
    end

    defp source(_args, _ctx),
      do: {:error, "Give query_id, or data_source and statement"}

    defp saved_chart(query) do
      case Lotus.list_visualizations(query.id) do
        [%{config: %{"chart_type" => _} = config} | _] -> config
        _ -> nil
      end
    end

    # The chart the arguments describe, checked against the result's
    # columns; else the saved query's own chart.
    defp config(%{chart_type: type} = args, _saved, columns) when is_binary(type),
      do: Chart.config(args, columns)

    defp config(_args, %{} = saved, _columns) do
      if Charts.valid_config?(saved),
        do: {:ok, saved},
        else: {:error, "The saved query's chart is incomplete: give chart_type and its fields"}
    end

    defp config(_args, nil, _columns),
      do: {:error, "Give chart_type and its fields: the query has no chart of its own"}
  end
end
