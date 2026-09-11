# Installation

This guide walks you through setting up LotusWeb in your Phoenix application.

## Requirements

- **Elixir 1.18+** and **OTP 26+**
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

### Access control and the actor

Pass a `:resolver` to tell the dashboard who is looking at it:

```elixir
lotus_dashboard "/lotus", resolver: MyAppWeb.LotusResolver
```

```elixir
defmodule MyAppWeb.LotusResolver do
  @behaviour Lotus.Web.Resolver

  # Who is here.
  def resolve_user(conn), do: conn.assigns.current_user

  # What they may do in the dashboard.
  def resolve_access(%{admin?: true}), do: :all
  def resolve_access(nil), do: :forbidden
  def resolve_access(_user), do: :read_only

  # Who Lotus core acts for. Reaches middleware and telemetry.
  def resolve_context(%{id: id, roles: roles}), do: %{user_id: id, roles: roles}
  def resolve_context(nil), do: nil

  # What data they may see. Reaches the visibility resolver, and is hashed
  # into the discovery and result cache keys so two tenants never read each
  # other's cached rows. Keep it low-cardinality.
  def resolve_scope(%{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
  def resolve_scope(nil), do: nil
end
```

`resolve_access/1` gates the dashboard UI. `resolve_context/1` and
`resolve_scope/1` gate the data: every query the dashboard runs, every schema
it lists and every table it describes carries them into Lotus core as the
`:context` and `:scope` options. Without them an access-control plug sees
`nil` for everything a user does in the browser, even though the same plug
sees a real actor for calls the host app makes itself.

Every callback is optional. A dashboard with no resolver, or one that
implements only `resolve_user/1`, calls core with no actor at all — the same
middleware payloads and the same cache keys as before.

The CSV export route resolves the actor the same way, from the conn.

## Content Security Policy (CSP)

If your application sets a `Content-Security-Policy` header (via `:put_secure_browser_headers`
or a custom plug), you'll need to configure it to allow the resources used by LotusWeb.

### Nonce-based CSP

LotusWeb serves its stylesheet and JavaScript bundle from two routes under the dashboard mount path (`<prefix>/css-<hash>` and `<prefix>/js-<hash>`) and loads the TailwindPlus module from a CDN. The `<link>` and `<script>` tags carry a nonce when you configure one, so a nonce-based policy covers all of them. To enable nonces:

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
        "style-src 'nonce-#{nonce}'; " <>
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
| `script-src` | `'nonce-<value>'` (or `'self'`) and `https://cdn.jsdelivr.net` | App JS bundle served from `<prefix>/js-<hash>`, and the TailwindPlus CDN module |
| `style-src` | `'nonce-<value>'` (or `'self'`) | App stylesheet served from `<prefix>/css-<hash>`. `'unsafe-inline'` alone does not allow an external stylesheet |
| `font-src` | `data:` | Embedded Inter font (base64-encoded) |
| `img-src` | `data:` | Data URI images |
| `connect-src` | `ws:` or `wss:` | LiveView WebSocket connection |

## Step 6: Visit the Dashboard

Start your Phoenix server and visit `/lotus` to access the dashboard.

## Next Steps

Continue with the [Getting Started](getting-started.md) guide to learn how to use LotusWeb.
