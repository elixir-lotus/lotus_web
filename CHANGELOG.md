# Changelog

## [Unreleased]

A resolver can now decide per action and per resource, not only once per
session. A resolver that does not implement the new callback keeps the
behaviour it had.

### Added

- **`c:Lotus.Web.Resolver.authorize/3` decides what a user may do.** The
  dashboard asks `authorize(user, action, resource)` and gets `:allow` or
  `{:deny, reason}`. The actions are `:query`, `:export`, `:create_query`,
  `:update_query`, `:delete_query`, `:share_query`, `:share_dashboard`,
  `:view_dashboard`, `:manage_dashboard`, `:ai_generate`, `:manage_source` and
  `:manage_cache`. Without the callback,
  the decision derives from `resolve_access/1`: `:all` allows every action,
  and `:read_only` allows `:query`, `:export` and `:view_dashboard`.
  `Lotus.Web.Authorization` is the one place the dashboard asks, and lists the
  resource each action takes.

- **The dashboard hides the controls a user may not use.** Save and delete on
  queries and dashboards, CSV export, the AI assistant and its editor context
  menu, the public link, Add Card, the filter edit controls and the "New" menu
  render only when the resolver allows them. The handlers ask again, so a
  crafted event is refused too.

### Changed

- **The CSV export route asks for `:query` and `:export` on the source and
  answers `403` on a deny.** Before, the route checked only the signed token,
  and the token carries the statement it runs. A `:read_only` user can still
  export; a user whose access is `:forbidden` now cannot.

- **The query editor lists only the sources the user may query.** The source
  selector, the schema explorer and the editor autocomplete no longer show the
  schemas, tables and columns of a denied source.

- **Card, filter and auto-refresh edits ask for `:manage_dashboard`.** A user
  who may not manage a dashboard no longer sees the card settings gear or the
  auto-refresh setting, and a crafted edit is refused.

- **With `strict_actor: true`, authorization raises for assigns that lack
  `:resolver` or `:access`**, the same as `Lotus.Web.Actor.opts/1` does for a
  missing actor. Without the option, the decision still falls back to full
  access.

- **Running a query, the AI assistant, the new dashboard page and opening a
  dashboard ask the resolver.** A denied run shows the reason in place of the
  results. A denied dashboard sends the user back to the dashboard list.

- **Dashboard cards and dropdown option queries ask for `:query` on their
  source.** Viewing a dashboard no longer runs a card whose source the user may
  not query; the card shows the reason instead. Adding a card asks for
  `:manage_dashboard`.

- **Saving a dashboard no longer writes its public link.** Only enabling and
  disabling sharing change it, so a save from a page opened before the link
  was turned off does not turn it back on.

- **A refused dashboard save or delete says "You don't have permission to
  modify dashboards".** The two messages were different before.

### Fixed

- **The query formatter's controls and error message are in French.**
  "Pretty-print query", its JSON sources hint and "Could not format query" had
  no French translation, so a French dashboard showed them in English.

## [1.1.0] - 2026-09-12

Two actor defects, and the guard rails that keep them from coming back. A host
resolver that the BEAM had not loaded yet was ignored, which gave every visitor
full access; and the schema explorer and source selector called Lotus with no
actor, so a scope-aware visibility resolver disagreed with itself. No host code
has to change.

### Fixed

- **The schema explorer and the source selector no longer lose the actor.**
  A `Phoenix.LiveComponent` holds only what its parent passes, and neither
  component was given `:context` or `:scope`, so `SourcesMap.build/1`,
  `Lotus.describe_table/3` and `Lotus.list_schemas/2` always ran unscoped.
  A scope-aware visibility resolver therefore showed one set of tables in
  the explorer and allowed another in the editor, every role shared one
  discovery cache entry, and middleware and telemetry recorded these calls
  with no user. The dashboard now carries the actor as a single `:actor`
  assign and hands it down to both components. The explorer also built its
  sources map in `mount/1`, before a parent's assigns arrive; it now builds
  in `update/2`, once the actor is known.

- **A host resolver that is not loaded yet no longer fails open.**
  `Lotus.Web.Resolver.call_with_fallback/3` asked `function_exported?/3`
  whether the host resolver implements a callback. That function answers
  `false` for a module the BEAM has not loaded, and modules load lazily
  outside a release, so the dashboard silently used its own permissive
  defaults: every visitor got `:all` access and the actor was `nil`. The
  check now loads the module first with `Code.ensure_loaded?/1`.

### Added

- **`config :lotus_web, strict_actor: true` catches a dashboard call that lost
  the actor.** Assigns with no `:context` key at all mean the actor never
  reached the component, which is a wiring mistake rather than an unscoped
  dashboard; the two used to look the same. With the option on,
  `Lotus.Web.Actor.opts/1` raises instead. Off by default, so production keeps
  degrading to an unscoped call rather than crashing.

- **A resolver module that does not exist now fails the compile.** The router
  accepted any atom for `:resolver`, so a typo in the module name left the
  dashboard on its permissive defaults and gave every visitor full access.
  `lotus_dashboard` now verifies the module through `@after_verify`, which
  runs after the host router is compiled — `Code.ensure_compiled/1` at macro
  expansion would deadlock on a resolver that uses `~p`.

## [1.0.0] - 2026-09-12

Aligns lotus_web with the Lotus core v1 adapter contract. The dashboard no longer assumes every data source is SQL: the editor picks its language from the source, non-SQL sources get JSON mode with structure-aware completions, and features a source cannot support are hidden rather than failing. Requires Lotus 1.0.

### Fixed

- **Date-range dashboard filters survive a page load.** The picker posts its
  two inputs under one filter name, so the value arrived as a nested
  `%{"start" => _, "end" => _}` map. That map went into the URL, but the
  code reading params back accepted only strings, so every reload fell back
  to the filter's default and silently discarded the range the user picked.
- **Date-range filter transforms are reachable from the dashboard.**
  `Lotus.Dashboards` applies `date_range_start` and `date_range_end` to a
  `"start,end"` string, but the dashboard produced the nested map above and
  nothing converted between the two, so mapping one date-range filter to a
  query's start and end variables could not work. Filter values now
  normalize to the string form on the way in, which is both what the URL
  round-trips and what the transforms parse. New
  `Lotus.Web.Dashboards.FilterValues` owns that shape, replacing helpers
  that were duplicated across the editor and public dashboard pages.

### Added

- **AI buttons are gated on what the source supports** — Explain and Optimize
  are disabled, with the adapter's own reason as the tooltip, for a data
  source whose adapter declares the feature unsupported. Core has exposed
  `Lotus.AI.supports?/2` and `unsupported_reason/2` since 1.0, but the
  dashboard never called them, so the buttons stayed live and the failure
  arrived as an inspected `{:ai_feature_unsupported, _, _}` tuple in the chat.
  That tuple is now rendered as the reason.
- **`Cmd/Ctrl+Shift+F` is listed in the keyboard shortcuts modal.** The
  pretty-print binding existed but was not discoverable.
- **The asset routes serve gzip** — `Lotus.Web.Assets` compresses the stylesheet and JS bundle once at compile time and answers with `content-encoding: gzip` when the client's `accept-encoding` allows it, with `vary: accept-encoding` on every response. A cold load moves roughly 0.8 MB instead of 2 MB, which matters for hosts that serve Lotus straight from Cowboy or Bandit with no compressing proxy (#148)
- **Open tabs reload after a deploy** — On a connected mount, `DashboardLive` compares the `phx-track-static` asset URLs the client is tracking with the hashes of the running build and issues a full-page redirect to the current URL when they differ, so a tab that stayed open through a release picks up the new bundle instead of running old JS against new server code. `Phoenix.LiveView.static_changed?/1` is not used because it only knows the host application's static manifest (#148)
- **The dashboard passes an actor into Lotus core** — two optional `Lotus.Web.Resolver` callbacks, `resolve_context/1` and `resolve_scope/1`, say who the dashboard is acting for and what data they may see. The resolved pair rides along as the `:context` and `:scope` options on every core call the UI makes: running a query from the editor or a dashboard card, streaming a CSV export, building the sources map, describing a table for editor autocomplete, listing schemas for the source picker, testing a dropdown's options query, and every AI generate / optimize / explain call. `:context` reaches middleware and telemetry; `:scope` reaches the visibility resolver and is hashed into the cache key, so two scopes never read each other's cached rows. Without this an access-control plug saw `nil` for everything a user did in the browser. Both callbacks are optional and default to `nil`, so a dashboard without a resolver calls core exactly as it did before — same middleware payloads, same cache keys. The new `Lotus.Web.Actor` module builds the options; see the [installation guide](guides/installation.md) for a worked resolver
- **Elasticsearch/OpenSearch dev server integration** — Added `lotus_elasticsearch` adapter to dev server with OpenSearch docker service (port 9209), `WebDev.SearchClient` module, `dev_logs` sample index with seed data, and an "Error Logs" sample query using JSON DSL
- **JSON language mode with context-aware autocomplete for JSON DSLs** — Non-SQL data sources (e.g. Elasticsearch) now get CodeMirror JSON syntax highlighting and structure-aware completions instead of SQL mode. `JsonDslCompletion` walks the `@lezer/json` syntax tree via `syntaxTree()` to determine the cursor's key path and consults the adapter's `context_schema` (new `editor_config/1` field in Lotus core) for the valid completion set: root-level keys inside `{↓}`, `must`/`should`/`filter` inside a `bool` block, schema field names inside `match`/`term`/`range`, range operators (`gte`/`lte`/…) inside a range-field object, and value literals (`asc`/`desc`, calendar-interval units, …) at value positions. Adapters that omit `context_schema` get a flat "every keyword at every position" behavior instead of structural suggestions. Added `@codemirror/lang-json` dependency and `JsonDslCompletion` class under `languages/json_dsl/`. `dialect_for_repo/1` preserves `"json:"`-prefixed language identifiers (elixir-lotus/lotus_web#126)
- **Pro UI integration mechanism** — `Lotus.Web.Pro` helper module enables `lotus_pro` to contribute pages, nav items, and slot content into the dashboard at runtime via `Code.ensure_loaded?/1`, with zero compile-time coupling. `DashboardLive.resolve_page/1` now falls back to Pro pages, and the layout renders Pro nav items when available (#9)
- **Pretty-print button in query editor toolbar** — For JSON-shaped query languages (currently Elasticsearch), a new `{}` toolbar button (and `Cmd/Ctrl+Shift+F` shortcut) reformats the query with structural indentation, same as Chrome's raw-JSON pretty-print. Button is hidden for SQL sources since SQL is already whitespace-agnostic and no lossless structural expansion exists. Dispatches on the adapter's `query_language`, so future JSON-shaped adapters (e.g. Mongo) get it for free

### Breaking

- **Elixir floor raised to 1.18** — Lotus core v1 requires `~> 1.18`, so a lotus_web declaring `~> 1.17` could not resolve it. The 1.17 / OTP 26 CI row is dropped.

- **Lotus v1 config key rename: `:ecto_repo` → `:storage_repo`** — `config :lotus, ecto_repo: ...` no longer works. Host apps must update their Lotus config to `config :lotus, storage_repo: ...`. Affects `config/config.exs`, `dev.exs`, and `test/test_helper.exs` in this repo; downstream apps must apply the same rename in their own configs.
- **`Lotus.get_table_schema/3` renamed to `Lotus.describe_table/3`** — Follows the Lotus core v1 callback rename that killed the "schema = namespace vs schema = column structure" double meaning. `SchemaBuilder.fetch_table_columns/3` and `SchemaExplorerComponent.navigate_to_table/3` updated accordingly. Downstream apps calling `Lotus.get_table_schema/3` directly must rename.
- **`Lotus.AI.Conversation.schema_context` field renamed to `source_context`** — Internal rename aligned with the Lotus core "schema → source" terminology sweep. Affects any host app that reaches into `Conversation.schema_context` directly (uncommon).
- **AI optimization suggestion type `"schema"` → `"structure"`** — Lotus core's AI optimization prompt now instructs the LLM to return `{"type": "structure", ...}` for schema-reshaping suggestions instead of `{"type": "schema", ...}`. The suggestion-type pill in `AiAssistantComponent` was updated to match. Pre-v1 LLM responses that still emit `"schema"` render with the default fallback color.
- **Replaced SQL-specific gettext strings with generic versions** — 14 gettext strings across 5 files no longer reference "SQL" explicitly (`"SQL Query"` → `"Query"`, `"Enter SQL to run query"` → `"Enter a query to run"`, etc.). French translations updated accordingly. Existing translation overrides for the old msgids will need updating (#123)
- **AI layer keys renamed from `sql` to `statement`** — Lotus core renamed every public AI key that named SQL. Conversation messages now carry `:statement`, `Lotus.AI.generate_query/1` returns `%{statement: ...}`, and `suggest_optimizations/1` / `explain_query/1` take `:statement` instead of `:sql`. `AiAssistantComponent` reads `@message.statement`, its `current_sql` attr is now `current_statement`, and the "use this query" button sends `phx-value-statement`. Host apps that render the component directly or build conversation messages themselves must rename the key.
- **`Lotus.Source.limit_query/3` is Statement-based** — the dropdown-options path now wraps the options query in a `%Lotus.Query.Statement{}` and unwraps the returned statement's `:body`, matching the core v1 callback that takes and returns a statement rather than SQL text.
- **Three more SQL-specific gettext strings replaced** — the AI assistant's empty-state hint and the explain/optimize button titles no longer say "SQL" (`"Analyze your SQL and suggest performance improvements"` → `"Analyze your query and suggest performance improvements"`, etc.). Translation overrides for the old msgids need updating (#123)

### Changed

- **Assets are served from routes instead of being inlined in every page** — The dashboard's stylesheet and JavaScript bundle now load from `<prefix>/css-<hash>` and `<prefix>/js-<hash>` (route helper `lotus_asset_path/3`), served by `Lotus.Web.Assets` with `cache-control: public, max-age=31536000, immutable`. A request for a hash this build did not produce returns 404 with `no-store`. Pages shrink by roughly 2 MB, browsers cache the bundle across page loads, and tools that inject markup before `</head>` or `</body>` (Tidewave, Phoenix LiveReloader) no longer corrupt the inlined script (#142, #143). Hosts with a CSP: a nonce still covers both tags; `style-src 'unsafe-inline'` on its own no longer allows the stylesheet, use a nonce or `'self'`. See the installation guide
- **Bumped `credo` to 1.7.19** — 1.7.12 crashes tokenizing sigils on the Elixir version this release is built against, so `mix credo` could not run at all
- **Dropdown options are gated on the source's `:dynamic_options` feature** — populating a variable's dropdown from a query only works where a query returns a flat list of values. The modal now offers the "From query" mode only when the selected source declares the new core `:dynamic_options` feature; document-shaped sources (Elasticsearch) get manual entry only, and a variable that carries an options query from an earlier source opens on manual entry rather than a mode it cannot use (#127)
- **`SourcesMap.build/0` no longer runs on the disconnected mount** — listing schemas and tables for every configured source ran twice, once for the static render nobody interacts with. `QueryEditorPage` and `SchemaExplorerComponent` now build it on the connected mount only, so the first paint no longer waits on those queries (#128)
- **Saved queries record their `query_language`** — the editor now stores the selected data source's language (e.g. `"sql:postgres"`, `"json:elasticsearch"`) on save, using the new core column. Core rejects a stored query whose source is later repointed at an engine that speaks a different language instead of running it against the wrong engine. Queries saved before this, and queries whose source no longer exists, record nothing and keep the old derive-from-adapter behavior
- **Refreshed `lotus_clickhouse` and `lotus_elasticsearch` to their v1 contract tips on `main`** — both adapter repos merged their v1 contract branches (`refactor/v1.0-contract`) to `main`. `mix.lock` SHAs updated to the new `main` tips so the dev server picks up Statement-based pipeline callbacks, `ai_context/0`, `describe_table/3`, `resolve_table_namespace/3`, and v1 visibility semantics
- **Elasticsearch dev source opts into `allow_unrestricted_resources`** — The ES adapter can't statically determine which indices a query will touch (ES targets indices via HTTP URL, not the JSON body), so `extract_accessed_resources/2` returns `{:unrestricted, reason}` and preflight blocks by default. The dev-server `data_sources` entry for `"elasticsearch"` is now a config map (`%{adapter: :elasticsearch, url: ..., allow_unrestricted_resources: true}`) so queries can execute. Host apps using the ES adapter in production should rely on ES's own cluster-level security (index permissions, RBAC) to enforce visibility
- **Dialect-aware editor with full tokenizer parity for external SQL adapters** — Adapters provide their own keywords, types, function completions, and (optionally) a `dialect_spec` through `editor_config/1`. The editor dynamically reconfigures syntax highlighting and completions when switching data sources, with client-side caching for instant re-switches. `BUILTIN_DIALECTS` now covers every CodeMirror 6 built-in: Postgres, MySQL, SQLite, MSSQL/SQL Server, MariaSQL, Cassandra/CQL, and PLSQL/Oracle. For non-built-in SQL dialects (ClickHouse, Trino, Hive, Spark), `resolveCodeMirrorDialect` forwards the adapter's camelCased `dialect_spec` (identifier quotes, operator chars, hash/slash/dollar-quoted string rules, PL/SQL quoting, backslash escapes, case-insensitive identifiers, …) into `SQLDialect.define()` so external adapters reach tokenization parity with the built-in Lezer grammars instead of accepting a vanilla fallback (elixir-lotus/lotus_web#126)
- **SchemaBuilder uses `default_schemas/1` from core** — `SchemaBuilder.default_schemas_for_database/2` and `SourcesMap.load_postgres_schemas/2` now call `Lotus.Source.Adapter.default_schemas/1` via `Lotus.Source.get_source!/1` instead of the removed `Lotus.Source.default_schemas/1` (#123)
- **Replaced `earmark` with `mdex` for Markdown rendering** — the retired, unmaintained `earmark` (which carries a security advisory) is swapped for the actively maintained `mdex`. `Lotus.Web.Markdown.to_safe_html/1` now renders via `MDEx.to_html/1` with safe defaults (`unsafe: false`), so embedded raw HTML is dropped rather than emitted; the `html_sanitize_ex` dependency is no longer needed and has been removed (#138)
- **search_path badge gated behind `supports_feature?`** — `EditorComponent` only shows the search_path badge when the source supports `:search_path`, and export params skip `search_path` for unsupported sources (#123)
- **SourcesMap uses `hierarchy_label` from core** — `load_simple_tables/1` now calls `Lotus.Sources.hierarchy_label/1` instead of hardcoding `"Tables"` for the schema display_name (#123)
- **Schema Explorer browse hint generalized** — replaced "databases, tables, and columns" with "data sources" (#123)
- **Replaced all `repo.__adapter__()` calls with adapter-level APIs** — `SourcesMap`, `QueryEditorPage`, and `SegmentedDataSelectorComponent` now use `Lotus.Sources.source_type/1`, `Lotus.Sources.supports_feature?/2`, `Lotus.Sources.query_language/1`, and `Lotus.Sources.limit_query/3` instead of pattern-matching on Ecto adapter modules directly. Renamed `SourcesMap.Database.adapter` field to `source_type` (atom) (#122)
- **Migrated all deprecated Lotus API calls** — Updated to use renamed Lotus APIs: `list_data_repo_names/0` → `list_data_source_names/0`, `default_data_repo/0` → `default_data_source/0`, `Config.get_data_repo!/1` → `Config.get_data_source!/1`, `run_sql/3` → `run_statement/3`. Renamed `data_repo` struct field access to `data_source` throughout. Updated config keys from `:data_repos`/`:default_repo` to `:data_sources`/`:default_source` in config.exs, test_helper.exs, and dev.exs
- **Centralized chart colors in `VegaSpecBuilder`** - 15+ scattered hex literals (gauge/progress fills, delta indicators, waterfall bars, combo accent line, neutral labels, track backgrounds) are now consolidated into a single `@chart_colors` module attribute, exposed via `VegaSpecBuilder.chart_colors/0`, so a future theme/dark-mode pass only has to touch one place (#107)
- **Extracted duplicated AI action buttons in `AiAssistantComponent`** - The "Explain query" / "Optimize query" buttons were duplicated between the empty state and the input area with slightly different sizing; both now render via a shared `ai_action_buttons` function component that takes a `:size` (`:lg` or `:sm`) and a `:generating` flag (#109)
- **Use a dedicated salt for export tokens** - `ExportController` now passes `"lotus_export"` as the salt to `Phoenix.Token.encrypt/decrypt` instead of prefixing the full `secret_key_base`. This follows the Phoenix convention and lets the framework handle key derivation internally (#108)
- **Extracted duplicated data source resolution in `QueryEditorPage`** - The four AI-related event handlers (`send_ai_message`, `optimize_query`, `explain_query`, `explain_fragment`) each inlined the same fallback-to-default-repo logic; this is now a single `resolve_data_source/1` private helper (#106)
- **Consolidated `PublicDashboardLive` into `DashboardLive`** - Removed ~95% duplicated callbacks by unifying the two LiveViews. The `/public/:token` route now mounts `DashboardLive`, which resolves a `:public_dashboard` page via `resolve_page/1` and branches mount defaults on the existing `public_view` assign (#104)
- **Dashboard filter text inputs are debounced** — the filter bar form runs on `phx-change`, so every keystroke in a text or number filter re-ran every card query on the dashboard. Against a large table this hammered the database once per character. Both free-text filter inputs now carry `phx-debounce="500"`, so the queries run once the user stops typing. Select, date, and date-range widgets are untouched: they change one time per user action and gain nothing from a delay (#132)

### Security

- **XSS via unsanitized markdown rendering** - `AiAssistantComponent` and dashboard `CardComponent` piped Earmark output straight into `Phoenix.HTML.raw/1`, allowing `<script>` tags, inline event handlers, and `javascript:` URLs to execute in the browser. Rendered markdown is now produced safely through the new `Lotus.Web.Markdown.to_safe_html/1` helper, which renders with MDEx safe defaults (`unsafe: false`) so embedded raw HTML is dropped rather than emitted
- **Content-Disposition header injection via unsanitized filename** - `ExportController` interpolated the token-supplied `filename` directly into the `Content-Disposition` header. Filenames are now sanitized to strip double quotes, backslashes, and control characters (including `\r`/`\n`), preventing HTTP response header injection as a defense-in-depth measure
- **LiveView process crash via crafted WebSocket events** - Replaced `String.to_existing_atom/1` on client-supplied values across LiveView event handlers with explicit allowlists. Affected handlers: `QueriesPage` (`switch_tab`), `QueryEditorPage` (`switch_variable_tab`, `set_view_mode`, `switch_visualization_tab`, `add_filter`, `set_sort`), `DashboardEditorPage` (`confirm_add_card`, `update_card_content`, `save_filter`), `AddCardModal` (`select_card_type`), and `DropdownOptionsModal` (`change_option_source`). A malicious client could previously send an unknown string to raise `ArgumentError` and crash the LiveView process, enabling targeted denial-of-service against individual user sessions. Also removed the unused `Lotus.Web.Helpers.decode_params/1` helper, which had a wildcard `String.to_existing_atom/1` over arbitrary URL parameter keys
- **Dependency security updates** — `mix hex.audit` reported 33 advisories across nine packages; every one is now resolved. Updated `phoenix` 1.8.1 → 1.8.13, `phoenix_live_view` 1.0.17 → 1.1.33, `plug` 1.19.1 → 1.20.3, `mint` 1.7.1 → 1.10.0, `req` 0.5.17 → 0.7.4, `postgrex` 0.22.0 → 0.22.4, `decimal` 2.4.1 → 3.1.1, `hpax` 1.0.3 → 1.0.4, and `bandit` 1.7.0 → 1.12.5. Only `mix.lock` moved; every fixed version already fell inside the ranges declared in `mix.exs`. The LiveView 1.1 upgrade swaps the test HTML engine from Floki to `lazy_html`, which is added as a test-only dependency

## [0.14.5] - 2026-04-25

### Fixed

- **Dashboard filter default values on page load** - Filters with configured default values now apply those defaults when the corresponding query parameter is missing from the URL, on both the dashboard editor and public dashboard pages

## [0.14.4] - 2026-03-11

### Fixed

- **`SourcesMap.load_database/1` no longer silently swallows exceptions** - The bare `rescue _ -> nil` clause now logs a warning with the database name and the exception message before returning `nil`, so configuration errors, connection failures, and adapter issues are diagnosable instead of silently dropping a database from the explorer (#105)
- **N+1 query on the Queries page dashboards tab** - `QueriesPage` previously issued one `list_dashboard_cards` query per dashboard while preloading card counts. It now uses the new `Lotus.list_dashboards(preload: [:cards])` option, collapsing the load into a single query (#103)
- **Graceful error handling for JSON encoding failures** - Wrapped `Lotus.JSON.encode!` calls in `ResultsComponent`, `CardComponent`, and `VegaSpecBuilder` with safe encoding that renders user-friendly error messages instead of crashing the LiveView process when results contain non-encodable values (e.g. raw UUID binaries)
- **Raw database value normalization** - `VegaSpecBuilder` and `ResultsComponent` now use `Lotus.Normalizer` to normalize raw database values (UUID binaries, Dates, Decimals, etc.) before JSON encoding
- **Results panel height** - Set to `h-full` instead of using CSS calc, increase min-h value

## [0.14.3] - 2026-03-10

### Fixed

- **CSP blocks TailwindPlus CDN script** - Added missing `nonce` attribute to the TailwindPlus CDN `<script>` tag in the root layout, which was blocked by `script-src-elem` CSP policies on browsers like Firefox

### Added

- **CSP nonce documentation** - Added Content Security Policy section to the installation guide covering nonce setup, required CSP directives, and an example plug

## [0.14.2] - 2026-03-08

### Fixed

- **Dashboard chart rendering crash** - Added missing `handle_event/3` for `chart_render_error` in `CardComponent`, so JS chart errors are displayed gracefully instead of crashing the LiveView process
- **Incomplete visualization config crash** - `CardComponent` now uses `VegaSpecBuilder.valid_config?/1` to guard chart rendering, preventing specs with missing x/y fields from being sent to Vega-Lite
- **Chart data normalization** - `VegaSpecBuilder.transform_data` now normalizes `Decimal`, `NaiveDateTime`, `DateTime`, `Date`, and `Time` values to JSON-safe primitives before encoding, fixing "Invalid datetime format" errors in Vega-Lite
- **Use `Lotus.JSON` instead of `Jason` directly** - Replaced all `Jason.encode!` calls in `CardComponent` and `ResultsComponent` with `Lotus.JSON.encode!` for consistent JSON encoding

### Improved

- **Preserve chart fields across type switches** - Changing chart type in both the dashboard card settings and query editor now retains compatible fields (x_field, y_field, series_field, etc.) instead of resetting them

### Added

- **VegaSpecBuilder tests** - Comprehensive test coverage for all public functions: `valid_config?/1`, `build_config/1`, `build/2` across all 18 chart types, data normalization, and type inference

## [0.14.1] - 2026-03-08

### Added

- **Service Error Message Role** - AI assistant now displays LLM provider errors (rate limits, auth failures, timeouts) with distinct amber styling instead of leaking raw error details

## [0.14.0] - 2026-03-08

### Added

- **Quick Filters on Query Results** - Right-click any cell value in the results table to filter by it via a context menu
  - Context menu offers all filter operators: `=`, `≠`, `>`, `<`, `≥`, `≤`, `LIKE`, `IS NULL`, `IS NOT NULL`
  - Active filters displayed as dismissible chips above the results table
  - Multiple filters stack with `AND`; duplicate filters are ignored
  - Running the query manually clears all filters
  - New `CellContextMenu` JS hook for right-click context menu positioning and interaction
  - New `funnel` and `funnel_x`
  - Result cells highlight on hover and stay highlighted while the context menu is open
- **Dashboard Filters** - Add interactive filter widgets to dashboards that dynamically filter query card data
  - Filter bar component with support for input, select, date picker, and date range picker widgets
  - Filter management UI in the dashboard editor: add, edit, and delete filters via a modal
  - Map filters to query variables per card in the card settings drawer
  - Filters persist to the database alongside dashboards
  - URL query parameters pre-fill filter values on both editor and public dashboard URLs
  - Typing in filter inputs updates the URL in real-time for shareable, bookmarkable filtered views
  - Clearing a filter removes it from the URL
  - Full support on public (shared) dashboards — filters render in read-only mode
  - French translations for all new filter-related strings
- **Query info in card settings** - Card settings drawer now shows the linked query name with a link to edit it in the query editor
- **11 New Chart Types** - Expanded from 5 to 16 chart types organized into four categories
  - **Charts**: Horizontal Bar (swapped axes), Combo (dual-axis bar+line with independent Y scales)
  - **Distribution**: Bubble (scatter with size encoding), Histogram, Heatmap
  - **Part of whole**: Donut (arc with inner radius), Funnel, Waterfall (stepped bar with running totals)
  - **Single value**: KPI Card, Trend (KPI with delta comparison), Gauge (semicircular arc), Progress Bar, Sparkline
  - New config options: `value_field`, `size_field`, `min_value`, `max_value`, `goal_value`, `comparison_field`, `y2_field`, `y2_axis_title`
  - Chart type selector reorganized into grouped sections (Charts, Distribution, Part of whole, Single value)
- **French Translations** - Added French translations for all new chart types and visualization settings
- **Column Statistics Popover** - Hover over any column header in the results table to view computed statistics
  - Numeric columns show min, max, avg, median, sum, and a distribution histogram
  - String columns show distinct count, top values with frequency bars, and min/max length
  - Temporal columns show earliest, latest, and a time distribution chart
  - Color-coded type badges (blue for numeric, green for string, amber for temporal)
  - Full dark mode support
  - Stats rendering integrated into `CellContextMenu` hook (no external tooltip library needed)
- **Column Sorting via Context Menu** - Right-click any column header to sort results ascending or descending
  - Sort indicator (chevron) displayed on the active sort column
  - Active sorts shown as dismissible purple chips above the results table
  - Sorting wraps the query in a CTE, working safely with any SQL complexity
  - New `chevron_up` icon component
- **AI Query Explanation** - "Explain query" button in the AI Assistant provides a plain-language explanation of the current SQL query
  - Quick-action button above the chat input (brain icon), enabled when a SQL query is present
  - Also available as a prominent action in the empty state
  - Explanations rendered as markdown with inline code, lists, and paragraphs
  - Opens the AI drawer automatically when triggered
  - Powered by `Lotus.AI.explain_query/1`
- **Fragment Explanation via Editor Selection** - Highlight any portion of SQL in the editor to get a focused explanation of just that fragment
  - Floating "Explain fragment" button appears near the selection when at least one word is selected
  - Clicking the button opens the AI Assistant drawer and explains only the selected fragment in context of the full query
  - Button dismisses on Escape, clicking elsewhere, or clearing the selection
  - Viewport-aware positioning keeps the button within screen bounds
  - Only visible when AI is enabled
- **AI Query Optimization** - "Optimize query" button in the AI Assistant analyzes the current SQL and suggests performance improvements
  - Quick-action button above the chat input (wrench icon), enabled when a SQL query is present
  - Also available as a prominent action in the empty state
  - Optimization suggestions rendered as cards with type pills (index/rewrite/schema/configuration) and impact badges (high/medium/low)
  - Shows "Your query is already well-optimized!" when no suggestions found
  - Opens the AI drawer automatically when triggered
  - Powered by `Lotus.AI.suggest_optimizations/1` with EXPLAIN plan analysis
- **AI-Generated Variables and Widgets** - The AI Assistant can now generate variable configurations alongside SQL queries
  - AI responses include variable metadata (type, widget, label, default, static options)
  - "Use this query" applies both SQL and variable settings in one action
  - Contextual button label ("Apply variable changes") when only variables differ from the current query
  - Variable summary displayed in AI conversation bubbles showing name and widget type
  - Current SQL and variable context sent to AI for more relevant suggestions
- **Visualization toolbar button** - Added a chart icon to the editor toolbar to toggle the visualization settings drawer
- **Keyboard shortcuts** - Wired up `⌘/Ctrl+Shift+V` for visualization toggle, `⌘/Ctrl+1` for table view, `⌘/Ctrl+2` for chart view
- **Query editor back link** - Added a back navigation chevron to the query editor header, consistent with the dashboard editor

### Changed

- Column stats popover is now triggered by hovering over column headers (600ms delay) instead of clicking, and no longer depends on Tippy.js
- Removed `ColumnStats` JS hook — stats rendering consolidated into `CellContextMenu` hook
- Column headers and result cells now show a context-menu cursor on hover
- Replaced drawer visibility booleans with a state machine (`left_drawer`, `right_drawer`, `modal` enums) for cleaner mutual exclusion
- Extracted pure variable data-transformation logic into `QueryEditor.Variables` module
- Extracted shared `chart_type_label/1` to `VegaSpecBuilder` — both `VisualizationSettingsComponent` and `CardSettingsDrawer` now delegate to it
- `ResultsComponent` delegates to `VegaSpecBuilder.valid_config?/1` instead of duplicating validation logic
- Reduced cyclomatic complexity in `VegaSpecBuilder` by extracting multi-head function clauses and helpers
- Changed AI loading overlay text from "Generating query..." to "AI is thinking..." to reflect broader AI capabilities

### Fixed

- Tab key no longer opens off-screen drawers in the query editor and dashboard pages
  - Added `inert` attribute to all slide-out drawers when hidden, preventing Tab focus from reaching off-screen elements

### BREAKING

- **Minimum Lotus Version** - Updated from 0.14.0 to 0.16.0 to align with Lotus core library requirements
  - Applications using Lotus 0.14.x or 0.15.x must upgrade to Lotus 0.16.0+ to use this version

## [0.13.1] - 2026-03-05

### Changed

- Added `locals_without_parens` export to `.formatter.exs` so `lotus_dashboard` calls are not reformatted with parentheses in consumer projects

### Fixed

- Bot icon in the Query Editor toolbar now turns pink when the AI Assistant drawer is open, matching the active-state behavior of other toolbar icons
- Dashboard text cards now render Markdown content as HTML instead of displaying raw text ([#67](https://github.com/elixir-lotus/lotus_web/issues/67))
  - Added `earmark` dependency for Markdown parsing
  - Added `@tailwindcss/typography` plugin so `prose` styles are applied to rendered content
- Navigating back from a dashboard now opens the Dashboards tab instead of defaulting to Queries
- Removed trailing slash from root path generated by `lotus_path/2` when route is empty

## [0.13.0] - 2026-02-16

### Added

- **List Variables for Multi-Value Query Parameters** - Variables can now accept multiple values for use in SQL `IN` clauses and similar patterns
  - New "Allow multiple values" checkbox in variable settings
  - Tag input widget for free-form multi-value entry with chip-style display (supports text and number types)
  - Multiselect widget for selecting multiple values from configured select options
  - Comma-separated value storage with automatic splitting at query execution time
  - Backspace-to-delete and scroll overflow for tag chips
- **Toast Notification System** - Replaced flash-based notifications with a push_event toast system
  - Dismissible, styled toast messages (info and error variants) with auto-timeout
  - New `Toast` LiveView hook and `toast.js` library

### Changed

- Bumped `lotus` dependency from `~> 0.13` to `~> 0.14`
- Bumped `gettext` dependency to `~> 0.26 or ~> 1.0`
- Widened toolbar widget inputs from `w-32` to `w-40` for better readability
- Variable values are now normalized on validate: defaults are applied, list values are split, and values are cleared when widget type or default changes
- Disabled default value input for select variables with no configured options

### Fixed

- Empty toolbar inputs no longer override variable default values on query run
- Flaky async test assertions replaced with `render_async`

## [0.12.0] - 2026-02-10

### Added

- **AI Assistant - Multi-Turn Conversation** - Upgraded from single-prompt to a full conversational interface
  - Chat-style message bubbles with user, assistant, and error roles
  - Conversation history with auto-scroll and message timestamps
  - "Use this query" button on each generated SQL to insert it into the editor
  - "Ask AI to fix this" button on error messages for automatic retry with context
  - Clear conversation button to start fresh
  - Empty state with example prompts to guide users
  - Query execution errors automatically appear in the conversation when the AI drawer is open
  - Conversation context sent to the AI provider for iterative query refinement
  - New JS hooks: `AIMessageInput` (Enter to send, auto-expand) and `AutoScrollAI`
  - New icons: `send`, `sparkles`, `corner_down_right`

### BREAKING

- **Minimum Lotus Version** - Updated from 0.12.0 to 0.13.0 to align with Lotus core library requirements
  - Applications using Lotus 0.12.x or earlier must upgrade to Lotus 0.13.0+ to use this version

## [0.11.0] - 2026-02-10

### Added

- **AI Query Assistant (EXPERIMENTAL, BYOK)** - Generate SQL queries from natural language descriptions
  - Left-side drawer interface with prompt input textarea
  - Schema-aware query generation using OpenAI, Anthropic, or Google Gemini models
  - Four AI tools for schema discovery: `list_schemas`, `list_tables`, `get_table_schema`, `get_column_values`
  - Automatic column value introspection to avoid guessing enum/status values
  - Security: Respects Lotus visibility rules - AI only sees tables/columns the user can access
  - Keyboard shortcut: `Cmd/Ctrl+K` to open AI Assistant drawer
  - BYOK (Bring Your Own Key) architecture - users provide their own API keys
  - Error handling with user-friendly messages and retry capability
  - Prompt persistence - prompts remain visible after generation for refinement
  - Localized UI strings (English and French)

### BREAKING

- **Minimum Elixir Version** - Updated from 1.16 to 1.17 to align with Lotus core library requirements
  - Applications using Elixir 1.16 must upgrade to Elixir 1.17+ to use this version

### Changed

- **CI Matrix** - Updated to test against Elixir 1.17 and 1.18 (removed 1.16)
- **Documentation** - Added AI Assistant guide to docs extras in mix.exs, also included missing dashboards guide

### Fixed

- **Gettext Translations** - Fixed 23 fuzzy English translations that were missing proper text

## [0.10.1] - 2026-02-04

### Fixed

- Fixed navbar regression where protected routes showed minimal nav (only theme switcher) instead of full nav (New button, keyboard shortcuts, theme switcher)

## [0.10.0] - 2026-02-04

### Added

- **Dashboard Support** - Interactive dashboards for combining queries into shareable views
  - Create and edit dashboards with a 12-column grid layout system
  - Four card types: Query results, Text, Headings, and Links
  - Manual layout positioning with x, y, width, and height controls
  - Auto-flow layout system - cards automatically reflow when heights change
  - Public sharing with secure token-based URLs
  - Auto-refresh configuration (1 min to 1 hour intervals)

## [0.9.0] - 2026-02-03

### Added

- Optional configuration for displaying UI query timeout selector
- **Query Results Visualizations** - Built-in charting capabilities to visualize query results
  - 5 chart types: Bar, Line, Area, Scatter, and Pie charts
  - Configurable X-axis, Y-axis, and optional Color/Series grouping fields
  - Axis customization with toggleable labels and custom titles
  - Dark mode support with automatic theme adaptation
  - Keyboard shortcuts: `Cmd/Ctrl+G` to toggle visualization settings, `Cmd/Ctrl+1` for table view, `Cmd/Ctrl+2` for chart view
  - Powered by Vega-Lite for performant, declarative chart rendering

## [0.7.0] - 2025-11-24

### Improved

- **Query Editor UX on Small Screens** - Enhanced results visibility and navigation
  - Results accessible via scrolling on all viewport sizes (no longer forced to minimize editor)
  - Floating pill indicator shows query success/error state when results are off-screen
  - Click-to-scroll navigation to results section
  - Sticky toolbar with always-accessible run button and editor controls
  - Intelligent visibility detection using IntersectionObserver scoped to parent container

### Internal

- Extracted floating results pill into dedicated `ResultsPillComponent` for better code organization and maintainability

## [0.6.2] - 2025-11-18

### Internal

- During build, ESBuild also generates a CSS, which was overriding the Tailwind CSS output, causing all the Tailwind classes to be lost. This has been fixed by updating the Tailwind args to output the CSS files to separate locations.
  - While ESBuild still outputs a CSS file, we don't use it because the Tailwind CSS output already contains all the CSS we need.

### Fixed

- Incorrect esbuild configuration was overriding the Tailwind CSS build output, causing missing styles in the published assets.

## [0.6.1] - 2025-11-18

### Internal

- Added a `release` mix task for use with new releases. `release` task ensures assets are always built before publishing.
- Changed tailwind config, removing `--watch=always` in `config.exs`, so that the `assets.build` task can be run without blocking.

### Fixed

- `assets.build` was not run for the 0.6.0 release, breaking the download functionality. 0.6.1 includes the built assets.

## [0.6.0] - 2025-11-14

### Changed

- Implement controller-based query export for chunking exports without creating a local temp file (#34):
  - Unsaved queries can no longer be exported; only saved queries can be exported. This was done to limit the token size in the URL and avoid exposing the data model (as the SQL query would need to be transmitted with the token).

- **INTERNAL:** Comprehensive Credo-based code quality improvements:
  - Added Credo static code analysis tool with custom configuration
  - Eliminated deeply nested functions by extracting helper functions across components
  - Reduced cyclomatic complexity in multiple modules (raised max to 10 for complex validation functions)
  - Improved predicate function naming conventions (e.g., `is_text_type?` → `text_type?`)
  - Refactored complex case statements and conditional logic for better readability
  - Added `@moduledoc false` annotations to internal modules
  - Configured selective exclusions for `MapJoin` warnings where pipe readability is prioritized
  - Enhanced code maintainability and testability without changing public APIs

## [0.5.2] - 2025-09-08

- Allow live view deps up to 1.2

## [0.5.1] - 2025-09-08

- Adds adjustments for mobile browsing

## [0.5.0] - 2025-09-07

### Added

- New `Lotus.Web.Resolver` behavior for customizing user resolution and access control
- **Async Query Execution with LiveView** - Non-blocking query execution using LiveView's async assigns
- **Query Pagination** - Cap rows at 1000 to avoid performance degration
- **Streaming CSV Export** - Memory-efficient CSV export using `Lotus.Export.stream_csv/2`

### Improved

- **Enhanced Flash Message System** - Redesigned flash notifications with improved UX

### Fixed

- Make schema explorer and variable settings asides sticky
- Fix scrolling issues

## [0.4.1] - 2025-09-04

### Fixed

- **UUID Formatting in Dropdown Variables** - Fixed 500 error when using UUIDs in dropdown variable SQL queries
  - Applied `Lotus.Value.to_display_string/1` formatting to query results to properly handle binary UUID data
  - Fixed unreadable HTML entity placeholders in dropdown options modal
  - Improved placeholder text clarity by showing only simple value format

## [0.4.0] - 2025-09-04

### Added

- **Dynamic Variable Options Configuration** - Configure query variable dropdown options from SQL queries
  - New dropdown options modal for configuring variable options with SQL queries
  - Support for fetching and testing variable options dynamically
  - Smart formatting that handles both simple string lists and value/label pairs
  - `VariableOptionsFormatter` module for converting between display and storage formats
  - Enhanced variable settings component with improved options handling
- **Multi-Database Schema Support** - Full support for PostgreSQL schemas and MySQL databases
  - Segmented data source selector with automatic schema detection
  - PostgreSQL search_path support with visual indicator in editor
  - Schema-aware SQL completions and table browsing
  - Persistent schema selection with form state management
- **Light/Dark Mode Theme System** - Complete theming with persistent storage across sessions
- **Global Query Shortcuts** - Query keyboard shortcuts (Cmd+Enter/Ctrl+Enter) now work anywhere on the query editor page, not just when focused in the CodeMirror editor
- **Smart SQL Completions** - Context-aware SQL completions with table and column suggestions
  - Table-aware column suggestions (e.g., typing after `FROM users WHERE` suggests columns from `users` table)
  - Table alias support for qualified column completion
  - Context-sensitive completions for SELECT, WHERE, ORDER BY, GROUP BY, and JOIN clauses
  - Built-in SQL functions and aggregate suggestions
  - Intelligent keyword detection to avoid interfering with SQL keyword completion
  - Dynamic completion theme switching that follows light/dark mode changes
- **Enhanced Query Results UI** - Improved results display with status indicators and actions
  - Results heading always shows when query has been executed
  - Success/Error status badges with appropriate icons and colors
  - Row count and execution time display below status indicators
  - Copy query to clipboard functionality with proper formatting preservation
  - Clipboard button in editor toolbar to copy SQL queries with line breaks preserved
  - CSV export functionality with automatic file downloads

### Changed

- **Improved Table Component** - Removed hardcoded margins from core table component for better flexibility
  - Table margins now controlled by parent containers for consistent spacing
  - Updated all table usages to include appropriate margin wrappers
- **Updated Dependencies** - Enforced Lotus dependency to version 0.9.0
- **Enhanced Copy to Clipboard** - Updated copy to clipboard keyboard shortcut functionality

## [0.3.1] - 2025-09-01

### Added

- **Variables and Widgets System** - Complete support for dynamic SQL queries with `{{variable}}` syntax
  - Variable detection and highlighting in SQL editor with CodeMirror plugin
  - Automatic toolbar widget generation for detected variables
  - Three variable types: Text (auto-quoted), Number, Date (ISO format)
  - Two widget types: Input fields and Dropdown lists with static options
  - Variable settings panel with Help and Settings tabs
  - Variable configurations persist with saved queries (types, widgets, labels, defaults)
  - User input values are not saved - widgets start empty unless defaults are set
- **Enhanced Query Editor Components**
  - Refactored query editor into modular LiveView components
  - New toolbar components for variables and query controls
  - Schema explorer component with improved UX
  - Results component with better formatting
- **New LiveView Components**
  - Theme selector dropdown component with icon-based triggers
  - Date picker component for date variables
  - Select component for dropdown widgets
  - Variable settings component with tabs and configuration options
  - Widget component for rendering different input types
- **Updated Documentation**
  - New Variables and Widgets guide with comprehensive usage examples
  - Updated Getting Started guide with variables section
  - README updated to reflect completed variables feature

### Changed
- Enhanced Tailwind CSS configuration with dark mode support and custom color palette
- Updated all UI components with comprehensive dark mode variants
- Improved CodeMirror editor styling for both light and dark themes
- Upgraded to Lotus v0.5.4 for enhanced variable support
- Improved aside panel toggling UX and scrolling behavior
- Enhanced JavaScript editor integration with variables plugin
- Auto-run queries now check for missing variables before execution using `Lotus.can_run?`

## [0.1.4] - 2025-08-25

- Upgrade to Lotus v0.3.3
- Improved cell formatting for HTML display

## [0.1.2] - 2025-08-25

Quick hotfix to safely format cell values for HTML display

## [0.1.1] - 2025-08-25

Add `priv/static` to package files

## [0.1.0] - 2025-08-25
- Initial release
