# Getting Started

This guide covers the basics of using LotusWeb to run queries and manage your data.

## Prerequisites

- LotusWeb installed and mounted (see [Installation](installation.md))
- At least one data source configured in Lotus (`:data_sources`)

## Accessing the Dashboard

Visit the mounted path in your browser (e.g., `/lotus`). You should see:

- **Query Editor** - Write and run queries
- **Queries List** - View saved queries
- **Schema Explorer** - Browse the objects in each data source

## Writing Your First Query

1. **Open the Query Editor** - Click "New Query" or navigate to the editor
2. **Select a data source** - Choose from the sources in your `:data_sources` config
3. **Write the query** - For a SQL source, enter something simple like:
   ```sql
   SELECT COUNT(*) as total_users FROM users;
   ```
   The editor picks its language from the source you selected, so a non-SQL
   source gets that source's own syntax instead. See
   [Working with Non-SQL Sources](#working-with-non-sql-sources).
4. **Run Query** - Click the play button or press Cmd+Enter
5. **View Results** - See the results displayed in a table

## Quick Filters

After running a query, you can quickly filter results without rewriting it — just right-click any cell value in the results table.

- **Right-click a cell** to open a context menu with filter operators (`=`, `≠`, `>`, `<`, `≥`, `≤`, `LIKE`, `IS NULL`, `IS NOT NULL`)
- **Choose an operator** to add a filter and re-run the query instantly
- **NULL cells** only show `IS NULL` and `IS NOT NULL` operators
- **LIKE filters** automatically wrap the value with `%…%` wildcards
- **Multiple filters** stack with `AND`, displayed as dismissible chips above the results
- **Remove a filter** by clicking the `×` on its chip, or click "Clear all" to remove all filters
- **Run the query manually** (play button or Cmd+Enter) to clear all filters and start fresh

Each source decides how filters are applied, and which operators it can honour. For SQL sources the original query is wrapped in a CTE, so filters work safely with any SQL complexity (joins, subqueries, unions, etc.), and the values are always sent as query parameters rather than interpolated.

## Sorting Results

You can sort query results by any column without modifying your SQL — just right-click a column header.

- **Right-click a column header** to open a context menu with "Sort ascending" and "Sort descending" options
- **Sort indicator** — the active sort column displays a chevron icon (up for ascending, down for descending)
- **Active sorts** are shown as purple chips above the results table
- **Remove a sort** by clicking the `×` on its chip, or click "Clear all" to remove all sorts
- **Running the query manually** (play button or Cmd+Enter) clears all sorts and starts fresh

Like filters, sorting on a SQL source wraps the original query in a CTE, so it works safely with any SQL complexity.

## Column Statistics

Hover over any column header to see a statistics popover with information about that column's data:

- **Numeric columns** — count, nulls, distinct values, min, max, avg, median, sum, and a distribution histogram
- **String columns** — count, nulls, distinct values, min/max length, and top values with frequency bars
- **Temporal columns** — count, nulls, distinct values, earliest, latest, and a time distribution chart

The popover appears after a short delay and dismisses when you move your mouse away.

## Using the AI Query Assistant (Optional)

> ⚠️ **Experimental Feature**: The AI Query Assistant is optional and requires setup. See the [AI Assistant Guide](ai-assistant.md) for details.

If AI features are enabled, you can generate and refine queries through a conversational interface:

1. **Click the robot icon** in the query editor toolbar to open the AI chat drawer
2. **Describe what you want** - e.g., "Show users who signed up in the last 7 days"
3. **Review the generated query** - The AI responds in a chat bubble with the query
4. **Click "Use this query"** to insert it into the editor
5. **Iterate naturally** - Send follow-up messages to refine ("Add a LIMIT 100", "Group by month instead")
6. **Fix errors automatically** - If a query fails while the AI drawer is open, the error appears in the conversation — click "Ask AI to fix this" to get a corrected query

The AI takes its language, example query and syntax notes from the selected source's adapter, so it writes in the language that source actually speaks, and it explores your data structure to generate accurate queries. The full conversation context is sent with each request for iterative refinement.

**Note:** AI features are disabled by default and require you to provide your own API key (BYOK) from OpenAI, Anthropic, or Google. See the [AI Assistant Guide](ai-assistant.md) for setup instructions.

## Visualizing Query Results

LotusWeb includes built-in charting to visualize your query results.

### Switching Between Views
- **Table View** - Default tabular display (Cmd/Ctrl+1)
- **Chart View** - Interactive visualization (Cmd/Ctrl+2)

### Common Chart Types
These are the ones to start with; the [Visualizations Guide](visualizations.md) lists the full set.

- **Bar Chart** - Compare categorical data
- **Line Chart** - Show trends over time
- **Area Chart** - Visualize cumulative trends
- **Scatter Plot** - Explore relationships between variables
- **Pie Chart** - Display proportions of a whole

### Quick Configuration
1. **Open Settings** - Click the chart icon or press Cmd/Ctrl+G
2. **Select Chart Type** - Choose from the Chart Type tab
3. **Configure Axes** - Set X-Axis, Y-Axis, and optional Color/Series fields
4. **View Chart** - Press Cmd/Ctrl+2 to see your visualization

For detailed chart configuration, best practices, and troubleshooting, see the [Visualizations Guide](visualizations.md).

## Exploring Your Schema

1. **Open Schema Explorer** - Click the tables icon in the editor
2. **Pick a data source** - The explorer lists every configured source
3. **Browse the hierarchy** - Sources that group their objects into namespaces show them; sources that do not show a flat list, labelled the way that source names its objects
4. **View Column Details** - Click a table to see its column information
5. **Go back** - Use the back arrow to step up a level

The explorer builds on the connected mount only, so the first paint no longer waits on a listing for every configured source.

## Saving Queries

1. **Write a Query** - Create a useful query in the editor
2. **Click Save** - Use the Save button in the editor
3. **Add Details** - Provide a name and optional description
4. **Save** - Your query is now saved and can be reused

## Managing Saved Queries

- **View All Queries** - Visit the Queries page to see all saved queries
- **Edit Queries** - Click on a query name to open and modify it
- **Delete Queries** - Use the Delete button when editing a query

## Working with Multiple Data Sources

If you have more than one entry in `:data_sources`:

1. **Switch sources** - Use the data source dropdown in the editor
2. **Source-specific queries** - A saved query remembers its `data_source`
3. **Recorded language** - A query also records the source's query language (`sql:postgres`, `json:elasticsearch`, …) when you save it. If that source is later repointed at an engine speaking a different language, Lotus refuses the query instead of running it against the wrong engine. Queries saved before 1.0 record nothing and keep the old derive-from-the-adapter behaviour
4. **Cross-source analysis** - Save different queries for different sources; a single query always runs against one source

## Working with Non-SQL Sources

A data source does not have to be SQL. The editor adapts to whatever the
selected source speaks:

- **Language mode** - A source whose query language starts with `json:` (Elasticsearch, for example) gets JSON syntax highlighting instead of SQL
- **Structure-aware completions** - In JSON mode, completions depend on where the cursor is: root-level keys at the top of the document, `must` / `should` / `filter` inside a `bool` block, field names inside `match` / `term` / `range`, range operators inside a range object, and value literals at value positions
- **Pretty-print** - JSON-shaped languages get a `{}` button in the toolbar (`Cmd/Ctrl+Shift+F`) that re-indents the query. SQL sources do not show it: SQL is whitespace-agnostic and has no lossless structural expansion
- **SQL-only affordances are hidden** - The `search_path` badge only appears for sources that support a search path, and the exported parameters skip it for the rest
- **Dropdown options from a query** - The "From query" mode in variable settings appears only for sources that can return a flat list of values. Document-shaped sources offer manual entry instead

## Security Features

LotusWeb inherits Lotus's security features:

- **Read-Only Queries** - Only read statements are allowed by default (set `read_only: false` in Lotus config to allow writes)
- **Table Visibility** - Tables, schemas and columns can be hidden by configuration or by a visibility resolver. Lotus checks visibility before the query runs, not only in the explorer
- **Safe Parameters** - Variable values are bound as parameters, never interpolated into the query text
- **Timeouts** - Long-running queries timeout automatically (default: 5 seconds)
- **Actor-aware** - If you configured `resolve_context/1` and `resolve_scope/1` on your resolver, everything the dashboard runs carries the current user into middleware, telemetry, visibility and the cache key. See [Installation](installation.md#access-control-and-the-actor)

### Configuring Query Timeouts

By default, queries timeout after 5 seconds. If you need to support long-running queries, enable the `:timeout_options` feature in your router:

```elixir
lotus_dashboard "/lotus",
  features: [:timeout_options]
```

This adds a timeout selector to the query editor toolbar where users can choose from preset durations (5s, 15s, 30s, 60s, 2m, 5m) or disable the timeout entirely on a per-query basis. Both the Lotus client timeout and the database statement timeout are set to the selected value.

## Using Variables in Queries

LotusWeb supports dynamic variables using the `{{variable_name}}` syntax. The syntax is the same for every source; each source adapter decides how a value is substituted — SQL sources bind it as a query parameter, JSON sources inline it through their own escaping.

### Adding Variables
1. **Type Variables** - In your query, use `{{variable_name}}` syntax:
   ```sql
   SELECT * FROM orders 
   WHERE status = {{status}} 
     AND created_at >= {{start_date}}
   ```
2. **Automatic Detection** - Variables appear automatically in the toolbar
3. **Configure Variables** - Click the "Variable settings" {x} icon in the toolbar to configure types and widgets

### Variable Types
- **Text** - Plain strings (automatically quoted for safety)
- **Number** - Integers and decimals  
- **Date** - Date picker with ISO format output

### Widget Types
- **Input** - Free text/number entry fields
- **Dropdown** - Select from predefined options (one option per line), or from a query where the source supports it
- **Date Picker** - Calendar interface for date variables
- **Tag Input** - Chip-style multi-value entry (when "Allow multiple values" is enabled)
- **Multiselect** - Multi-value dropdown (when "Allow multiple values" is enabled with dropdown options)

### Variable Settings
- **Access Settings** - Click the "Variable settings" {x} icon in the toolbar to open variable settings
- **Help Tab** - Contains detailed usage examples and syntax help
- **Settings Tab** - Configure labels, default values, and widget types

On SQL sources variables are always sent as prepared parameters, preventing SQL injection attacks.

**Important**: When you save a query, all variable configurations (types, widgets, labels, defaults) are saved with it. However, the actual values users enter are NOT saved - widgets start empty each time unless you set default values in the settings.

## Tips for Success

- **Start Simple** - Begin with basic SELECT queries
- **Use Descriptive Names** - Give your saved queries clear, meaningful names
- **Test First** - Run queries before saving them
- **Check Results** - Always verify your query results make sense
- **Use Variables** - Make queries reusable with `{{variable}}` syntax

## What's Next?

- Explore your database schema using the Schema Explorer
- Create useful reports by saving commonly-used queries
- Visualize your data with the built-in charting - see [Visualizations Guide](visualizations.md)
- Combine queries into interactive dashboards - see [Dashboards Guide](dashboards.md)
- Use variables to make your queries dynamic and reusable
- Read the [Variables and Widgets Guide](variables-and-widgets.md) for advanced variable usage