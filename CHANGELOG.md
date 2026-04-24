# Changelog

## [1.0.0-rc.1] - 2026-04-23

Release candidate for v1.0. Aligns lotus_web with the Lotus core v1 adapter contract (elixir-lotus/lotus#218) and refreshes the sibling adapter deps to their v1 contract merges on `main`.

### Added

- **Elasticsearch/OpenSearch dev server integration** — Added `lotus_elasticsearch` adapter to dev server with OpenSearch docker service (port 9209), `WebDev.SearchClient` module, `dev_logs` sample index with seed data, and an "Error Logs" sample query using JSON DSL
- **JSON language mode with context-aware autocomplete for JSON DSLs** — Non-SQL data sources (e.g. Elasticsearch) now get CodeMirror JSON syntax highlighting and structure-aware completions instead of SQL mode. `JsonDslCompletion` walks the `@lezer/json` syntax tree via `syntaxTree()` to determine the cursor's key path and consults the adapter's `context_schema` (new `editor_config/1` field in Lotus core) for the valid completion set: root-level keys inside `{↓}`, `must`/`should`/`filter` inside a `bool` block, schema field names inside `match`/`term`/`range`, range operators (`gte`/`lte`/…) inside a range-field object, and value literals (`asc`/`desc`, calendar-interval units, …) at value positions. Adapters that omit `context_schema` get a flat "every keyword at every position" behavior instead of structural suggestions. Added `@codemirror/lang-json` dependency and `JsonDslCompletion` class under `languages/json_dsl/`. `dialect_for_repo/1` preserves `"json:"`-prefixed language identifiers (elixir-lotus/lotus_web#126)
- **Pro UI integration mechanism** — `Lotus.Web.Pro` helper module enables `lotus_pro` to contribute pages, nav items, and slot content into the dashboard at runtime via `Code.ensure_loaded?/1`, with zero compile-time coupling. `DashboardLive.resolve_page/1` now falls back to Pro pages, and the layout renders Pro nav items when available (#9)
- **Pretty-print button in query editor toolbar** — For JSON-shaped query languages (currently Elasticsearch), a new `{}` toolbar button (and `Cmd/Ctrl+Shift+F` shortcut) reformats the query with structural indentation, same as Chrome's raw-JSON pretty-print. Button is hidden for SQL sources since SQL is already whitespace-agnostic and no lossless structural expansion exists. Dispatches on the adapter's `query_language`, so future JSON-shaped adapters (e.g. Mongo) get it for free

### Breaking

- **Lotus v1 config key rename: `:ecto_repo` → `:storage_repo`** — `config :lotus, ecto_repo: ...` no longer works. Host apps must update their Lotus config to `config :lotus, storage_repo: ...`. Affects `config/config.exs`, `dev.exs`, and `test/test_helper.exs` in this repo; downstream apps must apply the same rename in their own configs.
- **`Lotus.get_table_schema/3` renamed to `Lotus.describe_table/3`** — Follows the Lotus core v1 callback rename that killed the "schema = namespace vs schema = column structure" double meaning. `SchemaBuilder.fetch_table_columns/3` and `SchemaExplorerComponent.navigate_to_table/3` updated accordingly. Downstream apps calling `Lotus.get_table_schema/3` directly must rename.
- **`Lotus.AI.Conversation.schema_context` field renamed to `source_context`** — Internal rename aligned with the Lotus core "schema → source" terminology sweep. Affects any host app that reaches into `Conversation.schema_context` directly (uncommon).
- **AI optimization suggestion type `"schema"` → `"structure"`** — Lotus core's AI optimization prompt now instructs the LLM to return `{"type": "structure", ...}` for schema-reshaping suggestions instead of `{"type": "schema", ...}`. The suggestion-type pill in `AiAssistantComponent` was updated to match. Pre-v1 LLM responses that still emit `"schema"` render with the default fallback color.
- **Replaced SQL-specific gettext strings with generic versions** — 14 gettext strings across 5 files no longer reference "SQL" explicitly (`"SQL Query"` → `"Query"`, `"Enter SQL to run query"` → `"Enter a query to run"`, etc.). French translations updated accordingly. Existing translation overrides for the old msgids will need updating (#123)

### Changed

- **Refreshed `lotus_clickhouse` and `lotus_elasticsearch` to their v1 contract tips on `main`** — both adapter repos merged their v1 contract branches (`refactor/v1.0-contract`) to `main`. `mix.lock` SHAs updated to the new `main` tips so the dev server picks up Statement-based pipeline callbacks, `ai_context/0`, `describe_table/3`, `resolve_table_namespace/3`, and v1 visibility semantics
- **Elasticsearch dev source opts into `allow_unrestricted_resources`** — The ES adapter can't statically determine which indices a query will touch (ES targets indices via HTTP URL, not the JSON body), so `extract_accessed_resources/2` returns `{:unrestricted, reason}` and preflight blocks by default. The dev-server `data_sources` entry for `"elasticsearch"` is now a config map (`%{adapter: :elasticsearch, url: ..., allow_unrestricted_resources: true}`) so queries can execute. Host apps using the ES adapter in production should rely on ES's own cluster-level security (index permissions, RBAC) to enforce visibility
- **Dialect-aware editor with full tokenizer parity for external SQL adapters** — Adapters provide their own keywords, types, function completions, and (optionally) a `dialect_spec` through `editor_config/1`. The editor dynamically reconfigures syntax highlighting and completions when switching data sources, with client-side caching for instant re-switches. `BUILTIN_DIALECTS` now covers every CodeMirror 6 built-in: Postgres, MySQL, SQLite, MSSQL/SQL Server, MariaSQL, Cassandra/CQL, and PLSQL/Oracle. For non-built-in SQL dialects (ClickHouse, Trino, Hive, Spark), `resolveCodeMirrorDialect` forwards the adapter's camelCased `dialect_spec` (identifier quotes, operator chars, hash/slash/dollar-quoted string rules, PL/SQL quoting, backslash escapes, case-insensitive identifiers, …) into `SQLDialect.define()` so external adapters reach tokenization parity with the built-in Lezer grammars instead of accepting a vanilla fallback (elixir-lotus/lotus_web#126)
- **SchemaBuilder uses `default_schemas/1` from core** — `SchemaBuilder.default_schemas_for_database/2` and `SourcesMap.load_postgres_schemas/2` now call `Lotus.Source.Adapter.default_schemas/1` via `Lotus.Source.get_source!/1` instead of the removed `Lotus.Source.default_schemas/1` (#123)
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

### Security

- **XSS via unsanitized markdown rendering** - `AiAssistantComponent` and dashboard `CardComponent` piped Earmark output straight into `Phoenix.HTML.raw/1`, allowing `<script>` tags, inline event handlers, and `javascript:` URLs to execute in the browser. Rendered markdown is now scrubbed via `HtmlSanitizeEx.markdown_html/1` through the new `Lotus.Web.Markdown.to_safe_html/1` helper
- **Content-Disposition header injection via unsanitized filename** - `ExportController` interpolated the token-supplied `filename` directly into the `Content-Disposition` header. Filenames are now sanitized to strip double quotes, backslashes, and control characters (including `\r`/`\n`), preventing HTTP response header injection as a defense-in-depth measure
- **LiveView process crash via crafted WebSocket events** - Replaced `String.to_existing_atom/1` on client-supplied values across LiveView event handlers with explicit allowlists. Affected handlers: `QueriesPage` (`switch_tab`), `QueryEditorPage` (`switch_variable_tab`, `set_view_mode`, `switch_visualization_tab`, `add_filter`, `set_sort`), `DashboardEditorPage` (`confirm_add_card`, `update_card_content`, `save_filter`), `AddCardModal` (`select_card_type`), and `DropdownOptionsModal` (`change_option_source`). A malicious client could previously send an unknown string to raise `ArgumentError` and crash the LiveView process, enabling targeted denial-of-service against individual user sessions. Also removed the unused `Lotus.Web.Helpers.decode_params/1` helper, which had a wildcard `String.to_existing_atom/1` over arbitrary URL parameter keys

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
