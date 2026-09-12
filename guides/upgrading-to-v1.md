# Upgrading lotus_web to v1.0

This guide covers upgrading a host application from lotus_web 0.14.x to 1.0.

lotus_web 1.0 tracks Lotus core 1.0, which locks the public API for the 1.x
line. Most of what you have to change comes from core rather than from the
dashboard itself, so **read the [core upgrade
guide](https://hexdocs.pm/lotus/upgrading-to-v1.html) first** and apply the
config and API renames it lists. This guide covers only what is specific to
lotus_web.

If you never wrote a `Lotus.Web.Resolver`, never overrode a translation, and
never rendered `Lotus.Web.AiAssistantComponent` yourself, the whole upgrade is
sections 1 and 2 — plus section 3 if you set a Content-Security-Policy header,
which is the one change in this release that can break a working dashboard
without any code of yours being involved.

---

## 1. Elixir floor is now 1.18

Core 1.0 declares `elixir: "~> 1.18"`, so a host app on 1.17 cannot resolve
this release. Upgrade your toolchain before bumping the dependency.

---

## 2. Bump the dependencies and migrate

```diff
 def deps do
   [
-    {:lotus, "~> 0.16"},
-    {:lotus_web, "~> 0.14"}
+    {:lotus, "~> 1.0"},
+    {:lotus_web, "~> 1.0"}
   ]
 end
```

```bash
mix deps.get
mix ecto.migrate
```

The migration is core's, not the dashboard's. It renames the `lotus_queries`
`data_repo` column to `data_source` and adds the `query_language` column. See
the core guide for the Postgres, MySQL and SQLite details.

Watch for `data_repo:` **attribute keys** while you are there — in
`Lotus.create_query/1` and `Lotus.update_query/2` attrs, in seeds, and in test
fixtures. In 1.0 the changeset rejects the stale key outright rather than
letting `cast/3` drop it:

```
data_source: "was given as `data_repo`, which was renamed to `data_source` in Lotus v1.0"
```

That is a deliberate change. Dropping the key used to save a query with no
source at all, so a dashboard card built from it ran against the default
source instead of the one you named. You now get a failed changeset at the
call site instead.

Then apply core's config renames, which the dashboard inherits:

```diff
 config :lotus,
-  ecto_repo: MyApp.Repo,
+  storage_repo: MyApp.Repo,
-  default_repo: "main",
+  default_source: "main",
-  data_repos: %{"main" => MyApp.Repo}
+  data_sources: %{"main" => MyApp.Repo}
```

There is no compatibility shim. Core validates its config at boot and raises
an `ArgumentError` naming each old key and its replacement, so you find out at
start-up rather than at the first query.

### A new NIF enters your build

`mdex` replaces `earmark` as the markdown renderer (§7 covers what that
changes on screen), and `mdex` is a Rust NIF that arrives through
`rustler_precompiled`. For most hosts `mix deps.get` downloads a prebuilt
artifact and nothing else changes, but plan for it if any of this is true:

- You build releases in a slim container. The precompiled artifact is fetched
  at `deps.get` time, so it must be in the image layer you copy forward.
- You target an architecture with no prebuilt artifact, or you set
  `RUSTLER_PRECOMPILED_FORCE_BUILD`. Then the build needs a Rust toolchain.
- You vendor dependencies or audit checksums. There is a new
  `rustler_precompiled` entry and a new fetch at build time to account for.

---

## 3. The stylesheet and JS bundle are no longer inlined

Before 1.0 the dashboard inlined its whole stylesheet and JavaScript bundle
into every page — roughly 2 MB of markup per request, re-sent on every
navigation, and vulnerable to any tool that injects markup before `</head>`
or `</body>` (Tidewave, Phoenix LiveReloader) landing in the middle of the
inlined script.

They now load from two routes under your mount path, added by
`lotus_dashboard/2` itself:

- `<prefix>/css-<hash>`
- `<prefix>/js-<hash>`

`Lotus.Web.Assets` serves them with
`cache-control: public, max-age=31536000, immutable`, gzipped when the
client's `accept-encoding` allows it, and answers a hash this build did not
produce with a 404 and `cache-control: no-store`. The route helper is
`lotus_asset_path/3`.

**Nothing to configure.** The routes are declared inside your existing
`scope`, so they go through the same pipeline the dashboard does. They do not
touch `Plug.Static`, your endpoint's `:only` list, or your asset build.

### If you set a Content-Security-Policy, check it

This is the part that can break a working dashboard. Both tags still carry a
nonce when you pass `:csp_nonce_assign_key`, so a nonce-based policy keeps
working unchanged. What no longer works is allowing the stylesheet with
`style-src 'unsafe-inline'` alone: `'unsafe-inline'` governs inline style
content, and the stylesheet is now an external request. Same for the bundle
and `script-src`.

```diff
-  "style-src 'unsafe-inline'; " <>
+  "style-src 'nonce-#{nonce}'; " <>
```

`'self'` works too, if you would rather not run nonces. The
[installation guide](installation.md#content-security-policy-csp) has the full
directive table.

### Tabs stay current across a deploy

On the connected mount the dashboard compares the `phx-track-static` URLs the
client is tracking against the hashes of the running build, and issues a
full-page redirect when they differ. A tab left open through a release picks
up the new bundle instead of running old JavaScript against new server code.
`Phoenix.LiveView.static_changed?/1` is not used for this — it only knows the
host application's static manifest, not Lotus's.

---

## 4. If you wrote a `Lotus.Web.Resolver`

Nothing you already implemented changed. Two **optional** callbacks were
added, and without them the dashboard calls core exactly as it did before —
same middleware payloads, same cache keys.

They matter if you run access control, multi-tenancy, or per-user auditing.
Before 1.0 the dashboard ran every query with no actor, so a middleware plug
or a visibility resolver saw `nil` for everything a person did in the browser.

```elixir
defmodule MyApp.LotusResolver do
  @behaviour Lotus.Web.Resolver

  # Who is acting. Reaches middleware and telemetry.
  @impl true
  def resolve_context(%MyApp.User{id: id, roles: roles}), do: %{user_id: id, roles: roles}
  def resolve_context(nil), do: nil

  # What they may see. Reaches the visibility resolver, and is hashed into
  # the cache key so two scopes never read each other's cached rows.
  @impl true
  def resolve_scope(%MyApp.User{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
  def resolve_scope(nil), do: nil
end
```

The resolved pair rides along as `:context` and `:scope` on every core call
the UI makes: running a query from the editor or a dashboard card, streaming a
CSV export, building the sources map, describing a table for autocomplete,
listing schemas for the source picker, testing a dropdown's options query, and
every AI generate, optimize and explain call.

Both callbacks take the value `resolve_user/1` returned, and both are rebuilt
on every mount, so neither has to survive a session round trip. Keep the scope
low-cardinality — a tenant id, not a user id with a timestamp — because it is
hashed into the cache key, and a scope that differs per request stops the
caches earning their keep.

One route is deliberately outside all of this: the public dashboard at
`<prefix>/public/:token` mounts with no resolver, so it has no user, no
context and no scope, and it is fixed at `:read_only`. That was already true
before 1.0, and adding the two callbacks does not change it: if you rely on a
middleware plug or a scoped visibility resolver to hide rows, a public
dashboard never gets that protection.

---

## 5. If you overrode translations

Seventeen gettext strings were rewritten to drop "SQL", because the dashboard
now speaks to non-SQL sources too — `"SQL Query"` became `"Query"`,
`"Enter SQL to run query"` became `"Enter a query to run"`, and the AI
assistant's hint and its explain and optimize button titles changed the same
way.

Gettext keys off the source string, so **an override attached to an old msgid
silently stops applying** — no error, the default English just comes back.
Re-run `mix gettext.extract --merge` and re-translate whatever lands in the
new msgids.

---

## 6. If you render `AiAssistantComponent` yourself

Core renamed every public AI key that named SQL. The component followed.

| Before | Now |
|---|---|
| `current_sql` attr | `current_statement` |
| `@message.sql` | `@message.statement` |
| `phx-value-sql` on the "use this query" button | `phx-value-statement` |

The same rename reaches anything that builds conversation messages by hand,
or that reads `Lotus.AI.generate_query/1`, `suggest_optimizations/1` or
`explain_query/1` results. `Lotus.AI.Conversation`'s `schema_context` field is
now `source_context`.

If you style AI optimization suggestions by type, the schema-reshaping type is
now `"structure"` rather than `"schema"`. A response from an older model that
still says `"schema"` renders with the fallback color rather than crashing.

---

## 7. Behaviour changes worth knowing

These need no code change, but they change what the dashboard does.

**Variable dropdowns populated from a query are gated per source.** The "From
query" mode appears only where the source declares core's `:dynamic_options`
feature, which every SQL source does. Nothing changes for a SQL-only
dashboard; the gate exists so that a source whose query language returns
shaped documents rather than a flat column of values offers manual entry
instead of a mode it cannot serve.

**Saved queries record their language.** The editor stores the source's
`query_language` (`"sql:postgres"`, `"sql:mysql"`, …) on save. If a
source is later repointed at an engine that speaks a different language, core
rejects the stored query instead of running it against the wrong engine. The
comparison is exact, not family-level: `sql:postgres` and `sql:clickhouse`
share a family but are not interchangeable. Queries saved before this upgrade
record nothing and keep the old derive-from-adapter behavior.

**The editor takes its language from the source.** A source whose
`query_language` starts with `json:` gets CodeMirror JSON mode with
structure-aware completions rather than SQL mode, and a `{}` pretty-print
button (`Cmd/Ctrl+Shift+F`). SQL sources are unaffected — they keep their
dialect's highlighting and completions, and do not show the button, because
SQL has no lossless structural expansion.

**SQL-only affordances are hidden rather than broken.** The `search_path`
badge appears only where the source supports a search path, and export
parameters skip `search_path` for the rest. A SQL-only dashboard sees no
difference.

**Rendered markdown drops embedded HTML.** AI responses and dashboard card
text render through `MDEx` with `unsafe: false`, replacing the retired
`earmark`. Raw HTML inside markdown is dropped rather than emitted. This
closed an XSS hole; if you relied on raw HTML in card text, it will no longer
render.

**The schema explorer no longer builds on the disconnected mount.** The first
paint stopped waiting on a schema and table listing for every configured
source. Nothing to change; pages just render sooner.

---

## Checklist

- [ ] Elixir 1.18 or newer
- [ ] `{:lotus, "~> 1.0"}` and `{:lotus_web, "~> 1.0"}`
- [ ] `mix ecto.migrate`
- [ ] Config renamed: `storage_repo`, `default_source`, `data_sources` — core
      raises at boot on the old keys
- [ ] Host-app calls renamed — grep for `data_repo`, `run_sql`,
      `get_table_schema` (now `run_statement/3` and `describe_table/3`)
- [ ] `data_repo:` attribute keys renamed in `create_query/1` and
      `update_query/2` attrs, seeds and fixtures — the old key now fails the
      changeset
- [ ] CSP checked — `style-src`/`script-src` must allow an external request
      (nonce or `'self'`), not only `'unsafe-inline'`
- [ ] A Rust NIF (`mdex` via `rustler_precompiled`) is in the dep tree — check
      your release or container build
- [ ] Translation overrides re-merged if you have any
- [ ] `current_sql` and `@message.sql` renamed if you render the AI component
- [ ] `resolve_context/1` and `resolve_scope/1` added if you run access control

---

## Reporting upgrade issues

If something here is wrong or missing, open an issue on
[lotus_web](https://github.com/elixir-lotus/lotus_web/issues). If the problem
is in a core rename rather than the dashboard, report it on
[lotus](https://github.com/elixir-lotus/lotus/issues) instead.
