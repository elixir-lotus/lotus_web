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
sections 1 and 2.

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

---

## 3. If you wrote a `Lotus.Web.Resolver`

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

---

## 4. If you overrode translations

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

## 5. If you render `AiAssistantComponent` yourself

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

## 6. Behaviour changes worth knowing

These need no code change, but they change what the dashboard does.

**Variable dropdowns populated from a query are gated per source.** The "From
query" mode appears only where the source declares core's `:dynamic_options`
feature — true for every SQL source, false for document-shaped ones such as
Elasticsearch, where a search returns shaped documents rather than a flat
column of values. A variable carrying an options query from an earlier source
opens on manual entry rather than on a mode it cannot use.

**Saved queries record their language.** The editor stores the source's
`query_language` (`"sql:postgres"`, `"json:elasticsearch"`, …) on save. If a
source is later repointed at an engine that speaks a different language, core
rejects the stored query instead of running it against the wrong engine.
Queries saved before this upgrade record nothing and keep the old
derive-from-adapter behavior.

**Rendered markdown drops embedded HTML.** AI responses and dashboard card
text render through `MDEx` with `unsafe: false`, replacing the retired
`earmark`. Raw HTML inside markdown is dropped rather than emitted. This
closed an XSS hole; if you relied on raw HTML in card text, it will no longer
render.

**The schema explorer no longer builds on the disconnected mount.** The first
paint stopped waiting on a schema and table listing for every configured
source. Nothing to change; pages just render sooner.

---

## 7. If you use the Elasticsearch adapter

The adapter cannot tell in advance which indices a query will touch, because
Elasticsearch targets indices through the HTTP URL rather than the JSON body.
So `extract_accessed_resources/2` returns `{:unrestricted, reason}` and core's
preflight blocks the query by default.

To run queries against it, opt the source in:

```elixir
config :lotus,
  data_sources: %{
    "logs" => %{
      adapter: :elasticsearch,
      url: "http://localhost:9200",
      allow_unrestricted_resources: true
    }
  }
```

Doing so means Lotus stops enforcing table-level visibility for that source.
Rely on Elasticsearch's own index permissions and RBAC instead.

---

## Checklist

- [ ] Elixir 1.18 or newer
- [ ] `{:lotus, "~> 1.0"}` and `{:lotus_web, "~> 1.0"}`
- [ ] `mix ecto.migrate`
- [ ] Config renamed: `storage_repo`, `default_source`, `data_sources`
- [ ] Host-app calls renamed — grep for `data_repo`, `run_sql`, `get_table_schema`
- [ ] Translation overrides re-merged if you have any
- [ ] `current_sql` and `@message.sql` renamed if you render the AI component
- [ ] `resolve_context/1` and `resolve_scope/1` added if you run access control
- [ ] `allow_unrestricted_resources: true` set if you use Elasticsearch

---

## Reporting upgrade issues

If something here is wrong or missing, open an issue on
[lotus_web](https://github.com/elixir-lotus/lotus_web/issues). If the problem
is in a core rename rather than the dashboard, report it on
[lotus](https://github.com/elixir-lotus/lotus/issues) instead.
