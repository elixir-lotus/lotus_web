# Installation

This guide walks you through setting up LotusWeb in your Phoenix application.

## Requirements

- **Elixir 1.18+** and **OTP 26+**
- **Phoenix 1.7+** for LiveView compatibility
- **[Lotus 1.0](https://hex.pm/packages/lotus)** configured in your application

> **Version Compatibility**: LotusWeb 1.0 requires Lotus 1.0. The v1 contract renamed several config keys (`:ecto_repo` → `:storage_repo`, `:data_repos` → `:data_sources`, `:default_repo` → `:default_source`). There is no compatibility shim — Lotus raises at boot if it finds an old key. See the Lotus [Upgrading to v1.0](https://hexdocs.pm/lotus/upgrading-to-v1.html) guide if you're coming from 0.x, and the lotus_web [Upgrading to v1.0](upgrading-to-v1.md) guide for what changes in the dashboard.

## Step 1: Add Dependency

Add `lotus` and `lotus_web` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_web, "~> 1.0"}
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
    # A non-Ecto source is a config map instead of a repo module, e.g.
    # "logs" => %{adapter: :elasticsearch, url: "http://localhost:9200"}
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

### Router options

`lotus_dashboard/2` accepts these options. Any other option raises an
`ArgumentError` at compile time.

| Option | Default | Description |
|--------|---------|-------------|
| `:as` | `:lotus_dashboard` | Route and live session name. Change it if you mount the dashboard more than once. |
| `:on_mount` | `[]` | Extra `on_mount` hooks, run before Lotus's own `Lotus.Web.Locale` and `Lotus.Web.Authentication` hooks. |
| `:socket_path` | `"/live"` | Path of the Phoenix LiveView socket the dashboard connects to. Set it if your endpoint mounts the socket elsewhere. |
| `:transport` | `"websocket"` | LiveView transport, either `"websocket"` or `"longpoll"`. |
| `:resolver` | `Lotus.Web.Resolver` | Module implementing `Lotus.Web.Resolver` for authentication, access control and the actor. See below. |
| `:csp_nonce_assign_key` | `nil` | Assign key (or a `%{script: key, style: key}` map) holding the CSP nonce. See [Content Security Policy](#content-security-policy-csp). |
| `:features` | `[]` | Optional feature flags. See below. |

The macro mounts more than the main LiveViews: it also adds the two asset
routes, the CSV export route, and a second live session for public dashboards
at `<prefix>/public/:token` that skips the resolver entirely. Every one of
them is declared inside your `scope`, so they all go through the same
pipeline — mounting behind `:require_authenticated_user` protects the assets
and the export route too.

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

Every query, chart, dashboard, card, filter and filter mapping the dashboard
creates, updates or deletes carries `:context` too, so a
`:before_content_change` plug knows who made the change. When such a plug
halts, the dashboard shows that the change was refused, with the plug's reason
when it is a string, and writes nothing. A dashboard save is one transaction.

Every callback is optional. A dashboard with no resolver, or one that
implements only `resolve_user/1`, calls core with no actor at all — the same
middleware payloads and the same cache keys as before.

The CSV export route resolves the actor the same way, from the conn.

#### Fine-grained permissions

`resolve_access/1` gives one level for the whole session. To decide per action,
implement `authorize/3`. The dashboard asks it before it renders a control, and
does not render the control on a deny. It asks again in the event handler and
shows the reason to the user. The CSV export route asks for `:query` and
`:export` on the source and answers `403` with the reason.

The query editor offers, browses and autocompletes only the sources the user
may `:discover` or `:query`, so the schemas, tables and columns of a denied
source are never listed. Running a query and its dropdown options needs
`:query`. A save that puts a query on a source other than its stored one, or
saves a new query, needs `:query` on that source too.

```elixir
defmodule MyAppWeb.LotusResolver do
  @behaviour Lotus.Web.Resolver

  def authorize(%{role: :admin}, _action, _resource), do: :allow

  def authorize(%{role: :analyst}, action, _resource)
      when action in [:query, :export, :view_dashboard, :create_query],
      do: :allow

  def authorize(_user, action, _resource),
    do: {:deny, "Your role does not allow #{action}"}
end
```

| Action | Resource |
|---|---|
| `:query` | the data source name |
| `:export` | the data source name |
| `:ai_generate` | the data source name |
| `:discover` | the data source name |
| `:create_query` | `nil` |
| `:update_query` | the stored `%Lotus.Storage.Query{}` |
| `:delete_query` | the `%Lotus.Storage.Query{}` |
| `:share_query` | the `%Lotus.Storage.Query{}` (no dashboard control asks it yet) |
| `:share_dashboard` | the `%Lotus.Dashboards.Dashboard{}` whose public link changes |
| `:view_dashboard` | the `%Lotus.Dashboards.Dashboard{}` |
| `:manage_dashboard` | `nil` for a new dashboard, else the `%Lotus.Dashboards.Dashboard{}` |
| `:manage_source` | `nil` |
| `:manage_cache` | `nil` |

Without `authorize/3`, the decision derives from `resolve_access/1`:

| `resolve_access/1` | Decision |
|---|---|
| `:all` | allow every action |
| `:read_only` | allow `:query`, `:export`, `:discover` and `:view_dashboard`; deny the rest |
| `:forbidden` | deny every action (the dashboard redirects before it asks) |

To keep that default for some actions, call
`Lotus.Web.Authorization.default_decision(resolve_access(user), action)` from
your callback.

The dashboard calls `authorize/3` on every render. Do not do I/O in each call:
load the policy once and cache it. A public dashboard never calls it, because
it has no user.

With `strict_actor: true` (see below), a component that asks without the
dashboard's `:resolver` and `:access` assigns raises instead of falling back
to full access.

#### Catching an actor that never arrived

A dashboard component holds only the assigns its parent passes it, so a
component nobody hands the actor to calls core unscoped, and does it silently:
`context: nil` from a deliberately unscoped dashboard and `context` never set
at all look the same at the call site. Turn on the strict check while you
develop:

```elixir
# config/dev.exs and config/test.exs
config :lotus_web, strict_actor: true
```

Lotus then raises instead of quietly dropping the actor. Leave it off in
production, where an unscoped call is better than a crashed dashboard.

The public dashboard route (`<prefix>/public/:token`) is deliberately outside
this: it mounts with no resolver, so it has no user, no context and no scope,
and it is fixed at `:read_only` access. A public dashboard therefore runs its
cards with whatever visibility your static configuration allows. Publish a
dashboard only if every card is safe to show unauthenticated.

## Assets

The dashboard's stylesheet and JavaScript bundle ship inside the `lotus_web`
package and are served from two routes under the mount path:

- `<prefix>/css-<hash>`
- `<prefix>/js-<hash>`

`<hash>` is the MD5 of the compiled asset, so the URL changes whenever the
bundle does. `Lotus.Web.Assets` answers with
`cache-control: public, max-age=31536000, immutable`, and with
`content-encoding: gzip` when the request's `accept-encoding` allows it
(`vary: accept-encoding` is always set). A request for a hash this build did
not produce gets a 404 with `cache-control: no-store`, so a stale URL from an
old node during a rolling deploy can never poison a cache.

There is nothing to add to your endpoint: the routes come from
`lotus_dashboard/2` and do not go through `Plug.Static` or your asset
pipeline. The route helper is `lotus_asset_path/3` if you need to build the
URLs yourself.

A browser tab that stays open across a deploy is handled too. On the
connected mount the dashboard compares the `phx-track-static` URLs the client
is tracking against the hashes of the running build, and issues a full-page
redirect when they differ, so the tab picks up the new bundle instead of
running old JavaScript against new server code.

## Content Security Policy (CSP)

If your application sets a `Content-Security-Policy` header (via `:put_secure_browser_headers`
or a custom plug), you'll need to configure it to allow the resources used by LotusWeb.

> **Changed in 1.0**: the stylesheet used to be inlined in the page and is now
> an external request to `<prefix>/css-<hash>`. A policy that allowed it with
> `style-src 'unsafe-inline'` alone no longer does — `'unsafe-inline'` governs
> inline style content, not external stylesheets. Use a nonce or `'self'`.
> The same applies to the JavaScript bundle and `script-src`.

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
