# Dashboards

Dashboards let you combine multiple queries into interactive, shareable views. They're perfect for creating reports, KPI displays, and data exploration interfaces.

## Overview

A dashboard consists of **cards** placed on a 12-column grid. Each card can display different types of content, making it easy to build comprehensive data views.

Query cards run saved queries, so a card works against any configured data source — a Postgres, MySQL or SQLite repo, or a non-SQL source such as ClickHouse or Elasticsearch through an adapter package. The dashboard never writes the query itself; it runs the saved one and renders the result.

## Creating a Dashboard

1. **Click "New"** in the top navigation
2. **Select "Dashboard"** from the dropdown
3. **Enter Details**
   - **Name**: Give your dashboard a descriptive name
   - **Description**: Optionally add context about what the dashboard shows
4. **Click "Save"** to create your dashboard

## Adding Cards

Once you've created a dashboard, you can add cards to display your data:

1. **Click "Add Card"** - The large dashed button at the bottom of your dashboard
2. **Choose Card Type**:
   - **Query** - Display results from a saved query
   - **Text** - Add explanatory text using Markdown
   - **Heading** - Create section headers
   - **Link** - Add clickable links to external resources
3. **Configure the Card**:
   - For **Query cards**: Select which saved query to display
   - For **Text/Heading/Link cards**: Enter your content
4. **Click "Add Card"**

A new card is placed in the first free slot on the grid, at a default size that depends on its type:

| Card type | Default width | Default height |
|-----------|---------------|----------------|
| Query | 6 | 4 |
| Text | 6 | 2 |
| Heading | 12 | 1 |
| Link | 6 | 1 |

## Card Layout System

Cards are placed on a **12-column grid**. Each card carries its own position and size, and the grid honours those values — there is no automatic reflow, so two cards given the same cell will overlap.

### Layout Properties

When you select a card, you can configure its layout using the settings drawer:

- **X Position** (0-11) - Which column the card starts at
- **Y Position** (0+) - Which row the card starts at
- **Width** (1-12) - How many columns the card spans
- **Height** (1+) - How many rows the card spans

Each row unit is worth 100px of minimum card height, so a card of height 4 is at least 400px tall. Rows themselves size to their content, so a tall card stretches the row it sits in.

### Layout Examples

```
Full-width header:
X: 0, Y: 0, W: 12, H: 2

Two side-by-side cards:
Left:  X: 0, Y: 2, W: 6, H: 4
Right: X: 6, Y: 2, W: 6, H: 4

Three equal columns:
Left:   X: 0, Y: 6, W: 4, H: 3
Middle: X: 4, Y: 6, W: 4, H: 3
Right:  X: 8, Y: 6, W: 4, H: 3
```

## Card Types in Detail

### Query Cards

Query cards display results from saved queries.

**Features:**
- Show query results as tables or visualizations
- Inherit visualization settings from the saved query
- Can override visualization on a per-card basis
- Display loading states while queries run
- Show error messages if queries fail

**To use:**
1. Create and save a query first
2. Add a Query card to your dashboard
3. Select the saved query from the dropdown
4. Optionally configure visualization in the card settings

**Non-SQL queries:** a card runs the saved query through its own data source, whatever the query language. A query saved against an Elasticsearch source runs as JSON DSL; a query saved against Postgres runs as SQL. A saved query records the language it was written in, so if its source is later repointed at an engine that speaks a different language, the card reports an error naming both languages instead of sending the query to an engine that cannot parse it.

### Text Cards

Add formatted text content using Markdown.

**Use cases:**
- Explain what the dashboard shows
- Add context to your data
- Create documentation
- Include analysis notes

**Markdown support:**
- Bold, italic, code formatting
- Lists (bulleted and numbered)
- Links
- Basic formatting

Markdown is rendered with raw HTML disabled, so `<script>` tags and inline event handlers in card content are dropped rather than executed.

### Heading Cards

Create section headers to organize your dashboard.

**Features:**
- Large, prominent text
- Helps structure multi-section dashboards
- In public view, renders without card wrapper for cleaner look

**Best practices:**
- Use to separate different metric categories
- Keep headings short and clear
- Use at the start of each section

### Link Cards

Add clickable links to external resources.

**Use cases:**
- Link to related dashboards
- Reference external documentation
- Connect to other tools
- Provide additional context

**URL handling:**
- Automatically adds `https://` if missing
- Opens in new tab with security attributes
- Shows link icon for clarity

## Card Configuration

Select any card to open the settings drawer on the right:

### General Settings
- **Card Title** - Custom name for the card (overrides the query name for Query cards)
- **Layout Position** - X, Y, Width, Height controls

### Query Card Settings
- **Query** - The linked query name, with a link to open it in the query editor
- **Visualization** - Chart type (18 types available) and its fields, configured directly in the card settings drawer
- **Filter Mappings** - Which dashboard filter feeds which query variable

### Text/Heading/Link Settings
- **Content** - The actual text or URL to display

## Dashboard Filters

Filters add interactive widgets to your dashboard that dynamically filter data across query cards. They work by mapping each filter to a query variable (`{{variable}}`) on one or more cards.

### How Filters Work

1. Your saved query uses a variable: `SELECT * FROM orders WHERE status = {{status}}`
2. You add a dashboard filter (e.g. named `status`)
3. In a card's settings, you map the `status` filter to the `status` query variable
4. When a user selects a filter value, the query re-runs with that value substituted

Values are passed to the query as variables, so each adapter substitutes them the way its engine expects — a bound parameter for SQL sources, a properly escaped literal for JSON DSL sources.

### Adding Filters

1. Click **"Add Filter"** in the filter bar at the top of your dashboard
2. Configure the filter:
   - **Name** — internal identifier, used in URL params and variable mapping. It must be a valid identifier: a letter or underscore, then letters, numbers or underscores.
   - **Label** — display label shown to users
   - **Type** — Text, Number, Date, Date Range, or Select
   - **Widget** — Input, Select, Date Picker, or Date Range Picker
   - **Default value** — optional pre-filled value. A Date or Date Range filter offers relative dates such as "Last 30 days" next to a fixed date (see [Relative Dates](#relative-dates))
   - **Options** — for select widgets, one value per line (e.g. `us`, `eu`, `apac` on three lines)
   - **Source Query** — for select widgets, a saved query that lists the options instead (see [Cascading Filters](#cascading-filters))
   - **Depends On** — another filter of the dashboard whose value goes to the source query
3. Click **"Save Filter"**

Filter names must be unique within a dashboard.

### Types and Widgets

Not every widget fits every type. The combinations that are accepted:

| Type | Allowed widgets |
|------|-----------------|
| Text | Input, Select |
| Number | Input, Select |
| Date | Date Picker, Input |
| Date Range | Date Range Picker |
| Select | Select |

Any other pairing is rejected when the filter is saved.

### Mapping Filters to Cards

Each query card maps dashboard filters to its own query variables:

1. Select a card and open its **Settings** drawer
2. Under **Filter Mappings**, each dashboard filter is listed
3. Choose which query variable the filter maps to (the list comes from the query's `{{variable}}` placeholders)
4. Different cards can map the same filter to different variable names

In the drawer, each filter maps to one variable per card. To feed a query's start and end variables from one date-range filter, create two mappings with transforms from code (see [Value Transforms](#value-transforms)). The drawer shows such a split, and a save of the dashboard keeps it. A new choice in the drawer replaces the split.

### Filter Widgets

| Widget | Best for | Input |
|--------|----------|-------|
| **Input** | Free-form text and numbers | Text field (a number field for Number filters), debounced |
| **Select** | Predefined choices | Dropdown with the configured options, plus an "All" entry that clears the filter |
| **Date Picker** | Single date values | Today, Yesterday, or a calendar input |
| **Date Range Picker** | Start/end date pairs | Relative date presets, or two calendar inputs sent as `start` and `end` |

Typing in a text or number filter no longer re-runs every card on each keystroke: those inputs are debounced by 500 ms, so the cards run once you stop typing. Select, date, and date-range widgets change one time per user action and fire immediately.

### Relative Dates

A Date Range filter can hold a relative date in place of fixed dates, so the dashboard shows current data every day:

| Group | Presets |
|-------|---------|
| Days | Today, Yesterday, Last 7 days, Last 30 days, Last 90 days |
| This period | This week, This month, This quarter, This year |
| Previous period | Last week, Last month, Last quarter, Last year |

A Date filter takes only Today and Yesterday.

- **In the filter editor**, the default value of a Date or Date Range filter is a list of these presets and a fixed date. The editor shows the dates the preset covers today.
- **On the dashboard**, the picker opens a list of the presets with the dates each covers. The bar shows the chosen preset and its dates. **Custom range** (or **Fixed date**) goes back to calendar inputs, starting from the dates the preset covers.

Each preset is stored and sent as its token, for example `last_30_days`. The token resolves to dates each time the cards run, and all cards of one run use the same day. The `last_N_days` presets include today. The week, month, quarter and year presets cover the full calendar period, and weeks start on Monday. See `Lotus.Dashboards.DateToken` for the rules.

### Cascading Filters

A select filter can get its options from a saved query, and can depend on another filter of the same dashboard. A `city` filter that depends on a `country` filter uses a source query such as:

```sql
SELECT DISTINCT city FROM locations WHERE country = {{country}} ORDER BY city
```

- The first column of each row is the option value and the second is the label. A one-column query uses that column for both.
- The value of the filter it depends on goes to the source query as the variable named after that filter (`country` above).
- When a filter value changes, the options of the filters that depend on it load again, down the whole chain (`country` → `city` → `district`).
- A dependent value that is not in the new options is cleared.
- While the parent has no value, the dependent dropdown is disabled and the source query does not run.
- When the source query fails, the error shows under the dropdown.

The filter editor rejects a source query on a filter without the select widget, a dependency without a source query, a dependency on the filter itself, and a dependency that makes a cycle.

In the dashboard editor, a source query runs with the `:context` and `:scope` of the user and needs `:query` on its data source, like a card query. On a public dashboard, it runs with no `:context` and no `:scope`, like the cards of that dashboard.

Deleting the source query makes the filter use its static options again. Deleting the parent filter removes the dependency.

### Shareable Filter URLs

Filter values are reflected in the URL as query parameters. For example:

```
/lotus/dashboards/42?status=active&region=us
```

- Changing a filter updates the URL
- Clearing a filter removes it from the URL
- Sharing the URL pre-fills the filters for the recipient
- Works on both the dashboard editor and public shared dashboards

On load, a filter takes its value from the URL parameter if present, and falls back to its configured default value otherwise. A date-range filter carries both dates in one parameter as a comma-separated `start,end` string, so a shared link restores the window the sender had. An open end keeps its comma, so `2026-01-01,` is a start with no end. A relative date stays a token in the URL, for example `?period=last_30_days`, so a shared link stays relative.

### Filters on Public Dashboards

Filters are fully supported on public (shared) dashboards:
- Filter widgets render in the filter bar
- Users can interact with filters to explore the data
- The "Add Filter" button and edit/delete controls are hidden
- URL parameters pre-fill filter values, so you can share filtered views

### Example

An "Orders Overview" dashboard filtered by status and by a date window:

1. **Create a query** with variables:
   - `SELECT COUNT(*) FROM orders WHERE status = {{status}} AND created_at >= {{start}} AND created_at <= {{end}}`
2. **Add filters** to the dashboard:
   - `status` — Select type, Select widget, with `active`, `pending` and `completed` on three lines
   - `start` — Date type, Date Picker widget
   - `end` — Date type, Date Picker widget
3. **Map filters** in the card's settings:
   - `status` → `status`
   - `start` → `start`
   - `end` → `end`
4. **Share** the filtered URL: `/lotus/public/<token>?status=active&start=2026-01-01`

## Who the Dashboard Runs As

Every card query the dashboard runs carries the actor resolved at mount. If your `Lotus.Web.Resolver` implements `resolve_context/1`, its return value is passed to Lotus core as `:context` and reaches middleware and telemetry. If it implements `resolve_scope/1`, the return value is passed as `:scope` and reaches the visibility resolver and the cache key, so two scopes never read each other's cached rows. Both callbacks are optional and default to `nil`.

Public dashboards have no signed-in user, so they run with no context and no scope. Treat a public link as data anyone can see, and only share dashboards whose queries are safe to publish.

See the [installation guide](installation.md) for a worked resolver.

## Dashboard Settings

Click the gear icon in the top-right to access dashboard settings:

### Auto-Refresh

Set an interval for automatic card refreshing:
- **Disabled** (default)
- 1 minute
- 5 minutes
- 10 minutes
- 30 minutes
- 1 hour

When enabled, all cards refresh automatically at the specified interval.

### Public Sharing

Share your dashboard via a secure, public link:

1. **Enable Public Link** - Click the button (dashboard must be saved first)
2. **Copy URL** - Use the clipboard icon to copy the public URL
3. **Share** - Send the URL to anyone who needs access

The public URL is your dashboard mount point plus the generated token, for example `https://example.com/lotus/public/9f2c…`.

**Public view features:**
- Read-only access - no editing allowed
- No login required
- Clean interface without edit controls
- All cards display their data
- Public links remain active until you disable sharing

**To disable:**
- Click "Disable Sharing" in the settings drawer
- The link immediately stops working

### Danger Zone

**Delete Dashboard** - Permanently removes the dashboard and all its cards.

⚠️ This action cannot be undone!

## Running a Dashboard From Code

Dashboards are stored by Lotus core, so you can build and run them without the UI. The functions live on `Lotus`:

```elixir
{:ok, dashboard} = Lotus.create_dashboard(%{name: "Orders Overview"})

{:ok, card} =
  Lotus.create_dashboard_card(dashboard, %{
    card_type: :query,
    query_id: query.id,
    position: 0,
    layout: %{x: 0, y: 0, w: 6, h: 4}
  })

{:ok, filter} =
  Lotus.create_dashboard_filter(dashboard, %{
    name: "status",
    label: "Status",
    filter_type: :select,
    widget: :select,
    position: 0,
    config: %{"options" => [%{"value" => "active", "label" => "Active"}]}
  })

{:ok, _mapping} = Lotus.create_filter_mapping(card, filter, "status")
```

`Lotus.run_dashboard/2` runs every query card and returns a **bare map** keyed by card id — it is not wrapped in an `{:ok, _}` tuple:

```elixir
Lotus.run_dashboard(dashboard, filter_values: %{"status" => "active"})
#=> %{
#=>   1 => {:ok, %Lotus.Result{}},
#=>   2 => {:error, "Missing required variable: status"}
#=> }
```

Cards run in parallel by default; pass `parallel: false` to run them in order, and `timeout:` to change the 30-second per-card limit. `Lotus.run_dashboard_card/2` runs a single card and returns `{:ok, %Lotus.Result{}} | {:error, term()}`.

### Value Transforms

A filter mapping can carry an optional transform, which splits one filter value across two variables. The transform types are `"date_range_start"` and `"date_range_end"`, and both expect the filter value to be a **comma-separated** `start,end` string:

```elixir
{:ok, _} = Lotus.create_filter_mapping(card, filter, "start", transform: %{type: "date_range_start"})
{:ok, _} = Lotus.create_filter_mapping(card, filter, "end", transform: %{type: "date_range_end"})

Lotus.run_dashboard(dashboard, filter_values: %{"window" => "2026-01-01,2026-03-31"})
```

A value with no comma is passed through unchanged to both variables. A date-range filter produces exactly this shape, and a relative date resolves to it before the transform, so a single date-range filter can feed a query's start and end variables through two mappings. The dashboard view and the public view apply the transforms too. The editor does not create transforms, so set them from code. The editor keeps them when it saves.

## Dashboard Workflow

### 1. Plan Your Dashboard
- Decide what metrics to show
- Create and save the necessary queries
- Sketch out the layout (which cards go where)

### 2. Build the Dashboard
- Create the dashboard
- Add a heading card for the title
- Add query cards for your metrics
- Add text cards for explanations
- Arrange cards using the layout settings

### 3. Configure Cards
- Set custom titles
- Configure visualizations
- Adjust layout positions
- Test with different screen sizes

### 4. Share
- Save your dashboard
- Enable public sharing if needed
- Copy the link and distribute

## Tips & Best Practices

### Layout
- Use full-width heading cards (W: 12) for section titles
- Keep related metrics together visually
- Give each card its own cells — overlapping positions stack on top of each other
- Leave some whitespace - don't fill every column
- Test on different screen sizes (dashboard is responsive)

### Query Cards
- Keep queries focused - one metric per card works best
- Use visualizations for trends, tables for detailed data
- Name queries clearly - the name shows in the card header
- Test queries independently before adding to dashboard

### Organization
- Group related cards in rows
- Use consistent card heights within a row
- Add text cards to explain complex metrics
- Use headings to create clear sections

### Performance
- Be mindful of query complexity on dashboards
- Use auto-refresh judiciously - shorter intervals mean more load
- Consider query timeouts for long-running queries
- Enable the Lotus result cache so a shared dashboard doesn't re-run every card per viewer

## What's Next?

- Learn more about [query variables](variables-and-widgets.md) to make your queries dynamic — dashboard filters map directly to these variables
- Explore [visualization options](visualizations.md) for better data presentation
- Read the [Getting Started guide](getting-started.md) for general LotusWeb usage
