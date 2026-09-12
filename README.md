# Lotus Web

![Lotus Web](https://raw.githubusercontent.com/elixir-lotus/lotus_web/main/media/banner.png)

<p>
  <a href="https://hex.pm/packages/lotus_web">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/lotus_web.svg">
  </a>
  <a href="https://hexdocs.pm/lotus_web">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/elixir-lotus/lotus_web/actions">
    <img alt="CI Status" src="https://github.com/elixir-lotus/lotus_web/workflows/ci/badge.svg">
  </a>
</p>

**A LiveView-powered BI interface that mounts directly in your Phoenix app — query editor, dashboards, charts, and AI-powered query generation in plain English. No separate deployment needed.**

[Try the live demo](https://lotus.typhoon.works/)

<!-- TODO: Replace with a 30-second demo GIF showing: mount in router → open browser → write a query → see chart → save to dashboard -->

## Why Lotus Web?

You shouldn't need to deploy Metabase or Redash just to query your data. Lotus Web gives your team a full BI interface inside your existing Phoenix app — one dependency, one route, done. It shares your app's authentication, runs on your existing infrastructure, and is read-only by default.

Lotus Web 1.0 tracks the Lotus core v1 adapter contract, so a data source no longer has to be SQL on Ecto. Postgres, MySQL and SQLite work out of the box; ClickHouse and Elasticsearch work through adapter packages, and the editor switches language, autocomplete and source-specific affordances to match whichever source you pick.

> Lotus Web 1.0 is not a drop-in upgrade from 0.14.x: the Lotus core v1 config keys and public API were renamed with no compatibility shim. See the [upgrading guide](guides/upgrading-to-v1.md) before you bump.

## Quick Start

### 1. Add dependencies

```elixir
# mix.exs
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_web, "~> 1.0"}
  ]
end
```

### 2. Configure Lotus

```elixir
# config/config.exs
config :lotus,
  storage_repo: MyApp.Repo,
  default_source: "main",
  data_sources: %{
    "main" => MyApp.Repo
  }
```

`:storage_repo` is where Lotus keeps saved queries and dashboards; `:data_sources` are the sources you query. A non-Ecto source is a config map instead of a repo module — add its adapter package to your deps, list the adapter module under `:source_adapters`, and point the entry at it:

```elixir
config :lotus,
  source_adapters: [Lotus.Source.Adapters.Elasticsearch],
  data_sources: %{
    "main" => MyApp.Repo,
    "logs" => %{adapter: :elasticsearch, url: "http://localhost:9200"}
  }
```

### 3. Run the migration

```bash
mix ecto.gen.migration create_lotus_tables
```

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  def up, do: Lotus.Migrations.up()
  def down, do: Lotus.Migrations.down()
end
```

```bash
mix ecto.migrate
```

### 4. Mount in your router

```elixir
# lib/my_app_web/router.ex
import Lotus.Web.Router

scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  lotus_dashboard "/lotus"
end
```

### 5. Visit `/lotus` in your browser

That's it. Full BI dashboard, running inside your Phoenix app.

For authentication, CSP nonces, and a worked access-control resolver, see the [installation guide](guides/installation.md).

## Features

### Query Editor

Web-based query editor with syntax highlighting, autocomplete, and real-time execution powered by LiveView. Switch between configured data sources, run queries with Cmd/Ctrl+Enter, and see results instantly. Right-click cells to quick-filter results, right-click column headers to sort, and hover over headers to see column statistics (type, nulls, distribution).

The editor follows the source. SQL sources get their own dialect's keywords, types and tokenizer — including dialects CodeMirror doesn't ship, which adapters describe themselves. Non-SQL sources get JSON mode with structure-aware completions that know which keys are valid at the cursor, plus a pretty-print button (Cmd/Ctrl+Shift+F). Affordances a source can't support, such as the `search_path` badge, are hidden rather than failing.

See the [getting started guide](guides/getting-started.md) for more.

### Schema Explorer

Browse your tables, columns, and statistics interactively. Click to inspect table structures and understand your data before writing queries.

### Visualizations

Toggle between table and chart views for any query result. 18 chart types available across four categories — standard charts (bar, horizontal bar, line, area, combo), distribution (scatter, bubble, histogram, heatmap), part-of-whole (pie, donut, funnel, waterfall), and single-value displays (KPI, trend, gauge, progress bar, sparkline). Configure axes, color grouping, and type-specific options, then save the visualization alongside the query.

Keyboard shortcuts: Cmd/Ctrl+Shift+V (visualization settings), Cmd/Ctrl+1 (table view), Cmd/Ctrl+2 (chart view). Cmd/Ctrl+/ lists them all.

See the [visualizations guide](guides/visualizations.md) for chart configuration details.

### Dashboards

Combine saved queries into interactive dashboards with a 12-column grid layout. Add query result cards, text (markdown), headings, and links. Configure auto-refresh intervals and share dashboards publicly via secure token URLs.

Add **dashboard filters** — interactive widgets (input, select, date picker, date range) that map to query variables across cards. Text and number filters are debounced, so a filter no longer re-runs every card on each keystroke. Filter values are reflected in the URL for shareable, bookmarkable filtered views. Filters work on both the editor and public dashboards.

See the [dashboards guide](guides/dashboards.md) for layout, filters, and sharing details.

### Smart Variables and Widgets

Parameterize queries with `{{variable}}` syntax. Variables are automatically detected and rendered as input widgets. Supports text, number, and date types with configurable widgets — including dropdowns backed by static options or, where the source supports it, a live query. Enable "Allow multiple values" on any variable to use tag inputs or multiselect dropdowns for `IN`-style clauses.

See the [variables and widgets guide](guides/variables-and-widgets.md) for advanced usage.

### AI Query Assistant

Ask your data questions in plain English. The AI assistant discovers your schema, respects table visibility rules, and supports multi-turn conversations for iterative refinement — no other embeddable BI tool does this. Click "Explain query" for a plain-language breakdown of what your query does, or "Optimize query" for AI-powered performance suggestions based on query plan analysis. Highlight any portion of the query in the editor and click "Explain fragment" to get a focused explanation of just that selection. Bring your own API key for any provider supported by [ReqLLM](https://github.com/agentjido/req_llm). Open it with Cmd/Ctrl+K.

Each source describes itself to the model through its adapter — its language, an example query, syntax notes — and an adapter can decline generation, optimization or explanation, or opt out of AI entirely.

See the [AI assistant guide](guides/ai-assistant.md) for setup and configuration.

### Multiple Data Sources

Execute queries against every source in your `:data_sources` config and switch between them from the editor toolbar — useful for apps with separate analytics, reporting, or multi-tenant databases. Postgres, MySQL and SQLite are built in; ClickHouse and Elasticsearch are separate packages, [lotus_clickhouse](https://github.com/elixir-lotus/lotus_clickhouse) and [lotus_elasticsearch](https://github.com/elixir-lotus/lotus_elasticsearch).

## Configuration

### Mount Options

```elixir
# Default
lotus_dashboard "/lotus"

# Custom route name
lotus_dashboard "/admin/queries", as: :admin_queries

# Custom WebSocket settings
lotus_dashboard "/lotus",
  socket_path: "/live",
  transport: "websocket"

# Additional mount callbacks
lotus_dashboard "/lotus",
  on_mount: [MyAppWeb.RequireAdmin]

# Access control and actor resolution
lotus_dashboard "/lotus",
  resolver: MyApp.LotusResolver

# CSP nonces
lotus_dashboard "/lotus",
  csp_nonce_assign_key: %{style: :style_nonce, script: :script_nonce}

# Feature flags
lotus_dashboard "/lotus",
  features: [:timeout_options]
```

| Option | Description |
|--------|-------------|
| `:as` | Route name, defaults to `:lotus_dashboard` |
| `:on_mount` | Extra LiveView mount callbacks |
| `:socket_path` | Phoenix socket path, defaults to `"/live"` |
| `:transport` | `"websocket"` (default) or `"longpoll"` |
| `:resolver` | Module implementing `Lotus.Web.Resolver` |
| `:csp_nonce_assign_key` | Assign key (or `%{style:, script:}` map) holding your CSP nonces |
| `:features` | Optional feature flags, defaults to `[]` |

| Feature | Description |
|---------|-------------|
| `:timeout_options` | Adds a per-query timeout selector (5s to 5m, or none) to the editor toolbar |

### Access Control and the Actor

A `Lotus.Web.Resolver` decides who the dashboard is for and what they may do. All four callbacks are optional:

```elixir
defmodule MyApp.LotusResolver do
  @behaviour Lotus.Web.Resolver

  @impl true
  def resolve_user(conn), do: conn.assigns.current_user

  @impl true
  def resolve_access(%{admin?: true}), do: :all
  def resolve_access(_user), do: :read_only

  # Reaches Lotus middleware and telemetry as `:context`
  @impl true
  def resolve_context(%{id: id, roles: roles}), do: %{user_id: id, roles: roles}
  def resolve_context(nil), do: nil

  # Reaches the visibility resolver and the cache key as `:scope`
  @impl true
  def resolve_scope(%{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
  def resolve_scope(nil), do: nil
end
```

`resolve_context/1` and `resolve_scope/1` ride along on every core call the UI makes — running a query, streaming a CSV export, listing schemas, describing a table, and every AI call — so an access-control plug sees the actual user instead of `nil`. Scoped results are cached per scope, so two scopes never read each other's rows.

### Assets

The dashboard's stylesheet and JavaScript are served from `<prefix>/css-<hash>` and `<prefix>/js-<hash>`, gzipped and cached as immutable, instead of being inlined into every page. Pages are roughly 2 MB smaller, the bundle is cached across page loads, and tools that inject markup into the page — Tidewave, Phoenix LiveReloader — can no longer corrupt the bundle. A tab left open across a deploy detects the new hashes on reconnect and reloads itself, rather than running old JS against new server code.

If you set a Content Security Policy, a nonce covers both tags. `style-src 'unsafe-inline'` alone no longer allows the stylesheet — use a nonce or `'self'`.

### Caching (Optional, Recommended)

Add Lotus to your supervision tree and configure cache settings:

```elixir
# lib/my_app/application.ex
children = [
  MyApp.Repo,
  Lotus,          # Enables caching
  MyAppWeb.Endpoint
]
```

```elixir
# config/config.exs
config :lotus,
  cache: %{
    adapter: Lotus.Cache.ETS,
    namespace: "myapp_lotus",
    profiles: %{
      results: [ttl_ms: 60_000],
      schema: [ttl_ms: 3_600_000],
      options: [ttl_ms: 300_000]
    }
  }
```

### Internationalization

Lotus Web ships with a dedicated Gettext backend. To set the locale, store it in the Phoenix session:

```elixir
defp persist_user_locale(conn, _opts) do
  user_locale = get_session(conn, :user_locale) || "en"
  put_session(conn, :lotus_locale, user_locale)
end
```

To contribute translations, submit a PR with updates to `priv/gettext/<locale>/LC_MESSAGES/lotus.po`.

## Security

**Always mount behind authentication in production.** Lotus Web provides powerful query capabilities and should only be accessible to authorized users.

```elixir
# Always require authentication
scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]
  lotus_dashboard "/lotus"
end
```

Additional security layers:

- **Read-only execution** — all queries run in read-only transactions by default via Lotus (configurable with `read_only: false`)
- **Table visibility controls** — hide sensitive tables and columns from the interface
- **Scoped access** — a resolver's `resolve_scope/1` reaches Lotus's visibility resolver and is hashed into the cache key
- **Session safety** — secured by LiveView architecture with automatic session state restoration
- **Export security** — CSV exports use short-lived, signed, encrypted tokens
- **Safe markdown** — text cards and AI answers render with raw HTML dropped, not executed

Configure table visibility in Lotus:

```elixir
config :lotus,
  table_visibility: %{
    default: [
      allow: ["reports_users", "analytics_events"],
      deny: ["users", "admin_logs"]
    ]
  }
```

## How Lotus Web Compares

| | Lotus Web | Metabase | Redash | Blazer (Rails) | Livebook |
|---|---|---|---|---|---|
| **Deployment** | Mounts in your app | Separate service | Separate service | Mounts in your app | Separate service |
| **Extra infra** | None | Java + DB | Python + Redis + DB | None | None |
| **Auth** | Uses your app's auth | Separate system | Separate system | Uses your app's auth | Token-based |
| **SQL editor** | Yes | Yes | Yes | Yes | Code cells |
| **Dashboards** | Yes | Yes | Yes | No | No |
| **Charts** | 18 types | Many | Many | 3 types | Via libraries |
| **AI query gen** | Yes (BYOK) | No | No | No | No |
| **Read-only** | By default (configurable) | Configurable | Configurable | Configurable | No |
| **Cost** | Free | Free/Paid | Free | Free | Free |

## Requirements

| Lotus Web | Lotus | Elixir | Phoenix |
|-----------|-------|--------|---------|
| 1.0.0 | 1.0.0 | 1.18+ | 1.7+ |
| 0.14.x | 0.16.0+ | 1.17+ | 1.7+ |
| 0.13.x | 0.14.0+ | 1.17+ | 1.7+ |
| 0.12.x | 0.13.0+ | 1.17+ | 1.7+ |
| 0.11.x | 0.12.0+ | 1.17+ | 1.7+ |
| 0.10.x | 0.11.0+ | 1.17+ | 1.7+ |

Lotus Web 1.0 requires Phoenix LiveView 1.0 or 1.1 (`>= 1.0.0 and < 1.2.0`) and OTP 26+. CI runs Elixir 1.18, 1.19 and 1.20 on OTP 27 and 29.

## Development

```bash
mix deps.get

# Ensure placeholder assets exist for compilation
mkdir -p priv/static/css
touch priv/static/css/app.css && touch priv/static/app.js

# Install frontend deps
npm install --prefix assets

# Start dev server
mix dev
```

### Running Tests

```bash
mix test
```

### AI Assistant Setup (Optional)

```bash
mix lotus.gen.dev.secret
```

Edit `config/dev.secret.exs` with your API key and model, then restart the dev server. See the [AI assistant guide](guides/ai-assistant.md) for configuration.

## Releasing

New major and minor versions ship from `main`. Patch releases for a given line live on a maintenance branch cut from the release tag.

### Cutting a release branch

When starting a new release line (e.g., v1.x), create the branch at the release tag — not at the tip of `main`:

```bash
git branch release/v1.x v1.x.0
git push -u origin release/v1.x
```

`main` continues forward with ongoing development. `release/v1.x` is used only for patch releases (v1.x.1, v1.x.2, …).

### Hotfixes

Commit the fix on whichever branch owns it, then cherry-pick to the other if it still applies:

```bash
git checkout release/v1.x
# ... make the fix ...
git commit -m "fix: ..."
git push

git checkout main
git cherry-pick <sha>
git push
```

Tag patch releases on `release/v1.x`, not on `main`:

```bash
git tag -a v1.x.1 -m "Release 1.x.1"
git push origin v1.x.1
```

### Retiring a release branch

Once a release line is end-of-life, the branch can be deleted. Tags keep the commits reachable, so `git checkout v1.x.1` still works and the branch can be resurrected anytime with `git branch release/v1.x v1.x.1`.

## Contributing

We welcome contributions! When reporting bugs, please include your Elixir/OTP versions, dependency versions, and steps to reproduce.

## Acknowledgments

Lotus Web owes significant inspiration to:
- **[Oban Web](https://hexdocs.pm/oban_web/)** — for the Phoenix mounting patterns and LiveView architecture
- **[Blazer](https://github.com/ankane/blazer)** — for proving the value of simple, embedded BI tools
- **The Phoenix LiveView team** — for making rich web interfaces simple to build

## License

This project is licensed under the MIT License - see the LICENSE file for details.

Portions of the code are adapted from [Oban Web](https://github.com/sorentwo/oban),
(c) 2025 The Oban Team, licensed under the Apache License 2.0 - see the LICENSE-APACHE file for details.
