# Upgrading lotus_web to v2.0

This guide covers upgrading a host application from lotus_web 1.x to 2.0.
lotus_web 2.0 requires Lotus 2.0, so also read the [Lotus upgrade
guide](https://hexdocs.pm/lotus/upgrading-to-v2.html). This guide covers the
dashboard, and the steps from Lotus that every app takes for it.

For most apps the upgrade is sections 1 to 3. Read section 4 if your app sets
a Content-Security-Policy header, section 5 if it serves Lotus over MCP, and
section 8 if it creates queries or dashboards in code (seeds, an install
task).

---

## 1. Run Lotus's v7 migration first

Lotus v2.0 reads `owner_id` and `tenant_id` on every query and dashboard, so
a v2.0 dashboard on a database that is still at v6 fails on its first page.
Migrate, then deploy.

The migration that installed Lotus has already run, and Ecto will not run it
again. Generate a **new** migration for v7:

```bash
mix ecto.gen.migration upgrade_lotus_to_v7
```

```elixir
defmodule MyApp.Repo.Migrations.UpgradeLotusToV7 do
  use Ecto.Migration

  def up, do: Lotus.Migrations.up(version: 7)
  def down, do: Lotus.Migrations.down(version: 7)
end
```

`Lotus.Migrations.migrated_version()` says which version a database is at,
before and after. For MySQL and SQLite, and for the details, see the
Lotus upgrade guide.

On a host that runs migrations as a release command before the new code
starts (Fly's `release_command`, a Kubernetes init job), the deploy
migrates on its own. Otherwise, run the migration before the new release
takes traffic.

---

## 2. Bump the dependencies

```diff
 def deps do
   [
-    {:lotus, "~> 1.3"},
-    {:lotus_web, "~> 1.4"}
+    {:lotus, "~> 2.0"},
+    {:lotus_web, "~> 2.0"}
   ]
 end
```

---

## 3. AI needs `req_llm` in your deps

Lotus made [ReqLLM](https://hex.pm/packages/req_llm) optional, and lotus_web
lists it as optional too. An app that uses the AI assistant adds it:

```elixir
{:req_llm, "~> 1.29"}
```

Without it, the AI controls are hidden and the assistant's panel says which
dependency to add. An app without AI needs no change.

---

## 4. Charts are drawn by Fude, not Vega-Lite

Every chart (in the query editor, on dashboards, in the MCP chart app) is
drawn by [Fude](https://github.com/hattoriai/fude). The visualization configs
Lotus stores are read as before, so **no saved chart needs to change**.

### Content Security Policy

Vega compiled chart expressions with `new Function`, so a policy for Lotus's
pages had to allow `script-src 'unsafe-eval'`. Fude does not evaluate code.
**Remove `'unsafe-eval'`** from the policy of the dashboard's pages.

Nothing else changes in the policy. The maps (the world's countries, the US
states) are fetched from the mount path, which `connect-src 'self'` covers.
Charts are SVG with styles in attributes, which `style-src-attr` governs
when your policy sets it.

### Code that used the chart builder

`Lotus.Web.VegaSpecBuilder` is now `Lotus.Web.Charts`. Its config helpers
keep their names (`valid_config?/1`, `build_config/1`, `chart_type_ids/0`,
...). `build/2`, which returned a Vega-Lite spec, is replaced by `chart/2`
(a `Fude.Chart`, which a page draws with `Fude.Components.chart/1`) and
`spec/2` (the same chart as plain data, with its rows).

The MCP tool `show_chart` returns the chart's Fude spec instead of a
Vega-Lite spec.

### What a chart can do now

The charts have many more options (formats, stacking, reference lines,
small multiples, maps, KPI history, color schemes...), each stored in the
same visualization config. The [visualizations guide](visualizations.md) has
them as the settings show them, and section 8 has the keys for content made
in code.

---

## 5. MCP: `config :lotus, :mcp` no longer needs Lotus Web's callbacks

`Lotus.Web.MCP` tells Lotus to ask its resolver who may use MCP, and as which
actor. A config that still names Lotus Web's callbacks keeps working, because
an explicit setting wins. You can delete it:

```diff
 config :lotus_web, Lotus.Web.MCP, resolver: MyAppWeb.LotusResolver

-config :lotus, :mcp,
-  authorize: {Lotus.Web.MCP, :authorize?},
-  actor: {Lotus.Web.MCP, :actor}
```

Keep the block if it names callbacks of your own.

---

## 6. Resolvers: a new action, `:manage_schedule`

The dashboard asks `authorize(user, :manage_schedule, nil)` before it
creates, edits, pauses or deletes a report or an alert. A resolver whose
`authorize/3` falls through to `:allow` for the actions it does not name
allows it too. A resolver that lists the actions it allows must add this one
for people to manage schedules.

Nothing asks for it unless the `:schedules` feature is on (section 7).

---

## 7. Reports and alerts are opt-in

Schedules need both halves:

```elixir
# The dashboard: the "Reports & alerts" tab and its editor.
lotus_dashboard "/lotus", features: [:schedules]

# Lotus: the scheduler that runs them. Off by default.
config :lotus, scheduler: [enabled: true]
```

The v7 migration creates their tables whether or not you use them. Delivery
channels (email through your app's Swoosh mailer, Slack, webhook) are set up
in Lotus; see its [scheduling guide](https://hexdocs.pm/lotus/scheduling.html).
An app that sets neither sees no change.

---

## 8. Content you create in code

An app that seeds queries and dashboards (an install task, a release
command) keeps working: v2.0 reads the same records. Here is what is new on
those records.

**Charts.** A query card's `visualization_config`, and a query's own
visualization (`Lotus.create_visualization/3`, which the Queries gallery
sketches), take the keys `Lotus.Web.Charts` documents. Some are easy to miss:

| Key | Chart types | Example |
|---|---|---|
| `"number_format"`, `"currency"`, `"decimals"` | All | `"compact"`, `"currency"` with `"EUR"`, `0` |
| `"spark_field"` | `kpi`, `trend` | A date column: a small line of the value's history under the number |
| `"comparison_field"` | `trend` | Leave it out to compare with the second row |
| `"stack"` | Bars, areas with a series | `"stacked"`, `"grouped"`, `"normalized"` |
| `"sort"` | Bars | `"value_desc"`, `"value_asc"`, `"label"`, `"query"` |
| `"show_values"`, `"smooth"`, `"y_axis_zero"` | See the guide | Booleans |
| `"reference_value"`, `"reference_label"` | Cartesian charts | `100`, `"Goal"` |
| `"mark_max"`, `"mark_min"` | Bar, line, area, combo | Booleans: a callout on the highest or lowest value |
| `"band_from"`, `"band_to"`, `"band_label"` | Bar, line, area, combo, scatter, bubble | `"2026-03-01"`, `"2026-03-31"`, `"Launch"` |
| `"facet_field"`, `"facet_columns"` | Bar, line, area, scatter, bubble | Small multiples: a column, up to 6 columns |
| `"tooltip_fields"`, `"tooltip_adds"` | See the guide | `["visitors"]`, `["change", "share", "rank", "history"]` |
| `"color_scheme"`, `"scheme_mid"` | Series: `"okabe_ito"`. Heatmap, map: `"blue"`, `"viridis"`, `"red_blue"`... | |
| `"funnel_colors"`, `"funnel_labels"` | `funnel` | `"steps"` or `"stages"`; `"inside"` or `"none"` |
| `"sparkline_area"`, `"sparkline_points"`, `"sparkline_value"` | `sparkline` | `true`, `"last"` or `"extremes"`, `true` |
| `"map"` | `map`, `bubble_map` | `"world"` (default) or `"us-states"` |
| `"data_table"` | All | `"swap"` (default), `"below"`, `"none"` |
| `"subtitle"`, `"source"` | All | Words above and below the chart |

A heatmap reads its value from `"series_field"` (its rows from `"y_field"`),
and with no value it counts rows. `Lotus.Web.Charts.option_keys/1` lists the
options each chart type takes. `build_config/1` drops the keys a type does
not take, as the settings do when someone saves the card.

**Dashboards.**

- *Tabs* are the dashboard's `settings["tabs"]`, a list of
  `%{"id" => id, "name" => name}` in order. A card's tab is its layout's
  `"tab"`, the tab's id. A card with no tab is on the first one.
- *A card that starts folded* to its title has `"folded" => true` in its
  layout.
- *Headings*: a `:text` card with no title whose text is one Markdown heading
  (`%{"text" => "## Readers"}`) is drawn as a heading, with no frame. In edit
  mode the editor shows old `:heading` cards as such text cards, so new
  content should use text cards.
- *The grid* is 12 columns, as before. On a phone the cards stack in one
  column.

**Filters.** A dashboard filter sets a variable in each card it is mapped
to (`Lotus.create_filter_mapping/4`). A `:date_range` filter maps to two
variables with the `"date_range_start"` and `"date_range_end"` transforms:

```elixir
{:ok, filter} =
  Lotus.create_dashboard_filter(dashboard, %{
    name: "period",
    label: "Period",
    filter_type: :date_range,
    widget: :date_range_picker,
    default_value: "last_90_days",
    position: 0
  })

Lotus.create_filter_mapping(card, filter, "start_date", transform: %{"type" => "date_range_start"})
Lotus.create_filter_mapping(card, filter, "end_date", transform: %{"type" => "date_range_end"})
```

The query declares the variables with a type and a default, so that it also
runs on its own in the editor:

```elixir
Lotus.create_query(%{
  name: "Sign-ups",
  statement: "SELECT ... WHERE inserted_at >= {{start_date}} AND inserted_at < {{end_date}}",
  variables: [
    %{name: "start_date", type: :date, default: "2026-01-01"},
    %{name: "end_date", type: :date, default: "2027-01-01"}
  ]
})
```

**Updating what you seeded.** The records are ordinary rows, so an install
task can update them with `Lotus.update_query/3`,
`Lotus.update_dashboard_card/3`, and the rest. People can edit them too.
To keep their edits, update only when your seeds have changed: store your
seeds' version in the dashboard's `settings` (any key Lotus does not use,
for example `%{"seed_version" => 2}`) and rebuild when the code's version is
newer.

---

## Checklist

1. Generate a migration for v7 and run it (section 1).
2. Bump `lotus` and `lotus_web` to 2.0 (section 2).
3. Add `req_llm` if you use AI (section 3).
4. Remove `'unsafe-eval'` from the dashboard's CSP (section 4).
5. Delete `config :lotus, :mcp` if it only names Lotus Web's callbacks
   (section 5).
6. If your resolver lists the actions it allows, decide about
   `:manage_schedule` (section 6).
7. Turn on `:schedules` and the scheduler if you want reports and alerts
   (section 7).
