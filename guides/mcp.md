# MCP

Lotus has an MCP server, `Lotus.MCP` (see the MCP guide of Lotus): Claude
Code, Claude Desktop or any MCP client signs in through your app's login
and works with your Lotus data, its saved queries and dashboards, without
opening the dashboard. Lotus Web adds two things to it in
`Lotus.Web.MCP`:

- **Your resolver decides, as in the dashboard.** The `Lotus.Web.Resolver`
  you already wrote for the dashboard says who may use MCP and what each
  person may do there: the same access levels, the same `authorize/3`
  decisions, the same actor.
- **Charts in the conversation.** The `show_chart` tool charts a saved
  query or a statement with Lotus Web's charts, and hosts that render MCP
  Apps (Claude on the web and desktop, and others) draw it inline, in
  light or dark.

Serve `Lotus.Web.MCP` instead of `Lotus.MCP`; it has every Lotus tool.

## Setup

Set up Sake's authorization first, as the Lotus MCP guide says: the
`{:sake, "~> 0.3"}` dependency, a subject module, the `Sake` child and the
OAuth routes. List `Lotus.Web.MCP` in the `Sake` child's `servers:`, then:

```elixir
# router.ex
scope "/" do
  sake_endpoint "/lotus/mcp", server: Lotus.Web.MCP, auth: true
end
```

```elixir
# config/config.exs
config :lotus_web, Lotus.Web.MCP, resolver: MyApp.LotusResolver

config :lotus, :mcp,
  authorize: {Lotus.Web.MCP, :authorize?},
  actor: {Lotus.Web.MCP, :actor}
```

```
claude mcp add --transport http lotus https://myapp.example.com/lotus/mcp
```

The principal your subject module's `fetch/1` returns is the `user` your
resolver's callbacks receive, as `resolve_user/1`'s is in the dashboard.
If the two differ (a subject that loads an account, a resolver that
expects the conn's current scope), make the subject return what the
resolver expects.

## Who may do what

- **`resolve_access/1`** decides who may use MCP at all: `:all` and
  `:read_only` may, anything else may not. A resolver without
  `resolve_access/1` lets nobody in: the dashboard's default of `:all`
  relies on your router's pipeline, which an MCP endpoint does not have.
- **`authorize/3`** decides each call, with the action the dashboard
  would ask about:

  | Tool | Action | Resource |
  |---|---|---|
  | `list_data_sources`, `list_schemas`, `list_tables`, `describe_table` | `:discover` or `:query` | the data source |
  | `get_column_values`, `run_sql` | `:query` | the data source |
  | `list_queries`, `get_query`, `run_query`, `show_chart` | `:query` | the query's data source |
  | `save_query` | `:create_query`, and `:query` | `nil`, and the data source |
  | `update_query`, `save_chart` | `:update_query` | the query |
  | `list_dashboards`, `get_dashboard`, `run_dashboard` | `:view_dashboard` | the dashboard |
  | `create_dashboard` | `:manage_dashboard` | `nil` |
  | `add_dashboard_card` | `:manage_dashboard`, and `:query` for a query card | the dashboard, and the query's data source |

  Without `authorize/3`, the access level decides, as in the dashboard: a
  `:read_only` person may discover, query and view dashboards, and gets
  no tool that saves.
- **`resolve_context/1` and `resolve_scope/1`** are the actor Lotus gets,
  so your middleware and visibility resolver see the same person they see
  in the dashboard.

The tool list shows what the person's access level allows; a call then
asks `authorize/3` about its resource, and a refusal comes back to the
client with your resolver's reason. The list tools leave out the data
sources, queries and dashboards the person may not see. The OAuth scopes
(`lotus:read`, `lotus:query`, `lotus:write`) still apply on top: a token
without `lotus:write` saves nothing, whatever the resolver says.

## Charts

```
"Chart signups by week as a line chart"
→ run_sql to find the data, then show_chart with chart_type "line"

"Show me the Revenue query's chart"
→ show_chart with the query's id: its own chart, as Lotus Web shows it
```

`show_chart` takes a saved query (`query_id`, with `vars`) or a
statement (`data_source` and `statement`), and either the chart
arguments (`chart_type`, `x_field`, `y_field`, `series_field`,
`value_field`, ...) or, for a saved query, nothing: the chart saved with
it. Fields that are not columns of the result are refused with the
columns there are. It saves nothing; `save_chart` keeps a chart with a
saved query, and `add_dashboard_card` puts it on a dashboard.

The chart is an MCP App, `ui://lotus/chart`: one self-contained document
(Vega-Lite, with no network access), drawn from the tool's result, in the
host's light or dark theme. A host that does not render apps, such as
Claude Code in a terminal, gets the result as data: the chart's Vega-Lite
spec with its rows, at most 500.

## Mounting in your own server

```elixir
defmodule MyApp.MCP do
  use Sake.Server, name: "my-app", version: "1.0.0"
  tools [MyApp.MCP.SearchOrders]
  mount Lotus.Web.MCP, prefix: "lotus"
end
```

The resolver's decisions and the chart app come with the mount; tool
names take the prefix (`lotus_show_chart`).

## Assets

The chart app's script is built with the dashboard's own assets
(`mix assets.build` runs `esbuild mcp_chart`, which writes
`priv/static/mcp_chart.js`). The Hex package ships it built; working from
a Git checkout of Lotus Web, build the assets before compiling.
