# Installation

This guide walks you through setting up LotusWeb in your Phoenix application.

## Requirements

- **Elixir 1.17+** and **OTP 25+**
- **Phoenix 1.7+** for LiveView compatibility
- **[Lotus 1.0.0-rc.1](https://hex.pm/packages/lotus)** configured in your application

> **Version Compatibility**: LotusWeb 1.0.0-rc.1 requires Lotus 1.0.0-rc.1. The v1 contract renamed several config keys (`:ecto_repo` → `:storage_repo`, `:data_repos` → `:data_sources`, `:default_repo` → `:default_source`); see the Lotus [Upgrading to v1.0](https://hexdocs.pm/lotus/upgrading-to-v1.html) guide if you're coming from 0.x.

## Step 1: Add Dependency

Add `lotus` and `lotus_web` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0.0-rc.1"},
    {:lotus_web, "~> 1.0.0-rc.1"}
  ]
end
```

Run `mix deps.get` to fetch the dependencies.

## Step 2: Configure Lotus (if not already done)

LotusWeb requires Lotus to be configured. Add to your `config/config.exs`:

```elixir
config :lotus,
  storage_repo: MyApp.Repo,
  default_source: "main",       # Default source for query execution
  data_sources: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo  # Optional: multiple data sources
  },
  # Recommended: Enable caching for better dashboard performance
  cache: %{
    adapter: Lotus.Cache.ETS,
    namespace: "myapp_lotus"
    # Lotus includes built-in profiles that work great with LotusWeb:
    # - :results (60s TTL) - User query results
    # - :schema (1h TTL) - Table introspection (used by dashboard)
    # - :options (5m TTL) - Dropdown options and reference data
  }
```

## Step 3: Run Lotus Migration (if not already done)

```bash
mix ecto.gen.migration create_lotus_tables
```

Add the migration content:

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end
```

Run the migration:

```bash
mix ecto.migrate
```

## Step 4: Add Lotus to Supervision Tree (Required for Caching)

For caching to work, Lotus must be started as part of your application's supervision tree. Add Lotus to your application supervisor:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    # Add Lotus for caching support (required for optimal dashboard performance)
    Lotus,
    MyAppWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Note**: Without this step, caching will be disabled and dashboard performance may be slower due to repeated database introspection queries.

## Step 5: Mount LotusWeb Dashboard

Add to your router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import Lotus.Web.Router

  # ... other routes

  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user] # ⚠️ Add auth!

    lotus_dashboard "/lotus"
  end
end
```

**⚠️ Security Warning**: Always mount behind authentication in production.

**Note**: Your `:browser` pipeline must include `fetch_session` and `fetch_flash` plugs for LotusWeb to work correctly. Most Phoenix apps have these by default.

### Optional Features

You can enable additional features by passing the `features` option:

```elixir
lotus_dashboard "/lotus",
  features: [:timeout_options]
```

| Feature | Description |
|---------|-------------|
| `:timeout_options` | Adds a per-query timeout selector to the query editor toolbar, allowing users to override the default 5-second query timeout for long-running queries. |

## Content Security Policy (CSP)

If your application sets a `Content-Security-Policy` header (via `:put_secure_browser_headers`
or a custom plug), you'll need to configure it to allow the resources used by LotusWeb.

### Nonce-based CSP

LotusWeb supports CSP nonces for inline scripts and styles. To enable them:

1. **Generate a nonce** in a custom plug and store it in `conn.assigns`:

```elixir
defmodule MyAppWeb.CSPPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce =
      24
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(
      "content-security-policy",
      "default-src 'self'; " <>
        "script-src 'nonce-#{nonce}' https://cdn.jsdelivr.net; " <>
        "style-src 'nonce-#{nonce}' 'unsafe-inline'; " <>
        "font-src 'self' data:; " <>
        "img-src 'self' data:; " <>
        "connect-src 'self' ws: wss:;"
    )
  end
end
```

2. **Add the plug** to your browser pipeline, **after** `:put_secure_browser_headers`
   (so it overrides Phoenix's default CSP):

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug MyAppWeb.CSPPlug
end
```

3. **Pass the nonce key** when mounting the dashboard:

```elixir
lotus_dashboard "/lotus",
  csp_nonce_assign_key: :csp_nonce
```

You can also use separate keys for script and style nonces:

```elixir
lotus_dashboard "/lotus",
  csp_nonce_assign_key: %{script: :script_csp_nonce, style: :style_csp_nonce}
```

### Required CSP directives

LotusWeb uses the following resources that your CSP policy must allow:

| Directive | Required value | Reason |
|-----------|---------------|--------|
| `script-src` | `'nonce-<value>'` and `https://cdn.jsdelivr.net` | Inline app script and TailwindPlus CDN module |
| `style-src` | `'nonce-<value>'` or `'unsafe-inline'` | Inline app stylesheet |
| `font-src` | `data:` | Embedded Inter font (base64-encoded) |
| `img-src` | `data:` | Data URI images |
| `connect-src` | `ws:` or `wss:` | LiveView WebSocket connection |

## Step 6: Visit the Dashboard

Start your Phoenix server and visit `/lotus` to access the dashboard.

## Next Steps

Continue with the [Getting Started](getting-started.md) guide to learn how to use LotusWeb.
