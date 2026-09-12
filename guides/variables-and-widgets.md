# Variables and Widgets Guide

LotusWeb's variables and widgets feature lets you build dynamic, reusable queries with user-friendly input controls. This guide covers everything you need to know about using variables effectively.

Variables are part of Lotus core's template syntax, not part of any one query language. They work the same way in a SQL query and in a JSON DSL query — what differs is how the source's adapter substitutes the value, which is covered under [Security](#security).

## Overview

Variables use a `{{variable_name}}` syntax that is detected automatically in your query. When detected, variables appear as input controls in the query toolbar, making your queries interactive and reusable.

## Basic Variable Syntax

### Adding Variables to Queries

Wrap any variable name in double curly braces:

```sql
SELECT *
FROM orders
WHERE status = {{order_status}}
  AND created_at >= {{start_date}}
  AND total_amount >= {{minimum_amount}}
```

The same query against an Elasticsearch source is a Query DSL object. Because the template has to stay valid JSON, wrap the placeholder in quotes — the adapter strips them when it inlines the encoded value:

```json
{"query": {"bool": {"filter": [{"term": {"status": "{{order_status}}"}}]}}}
```

### Variable Names

- Must contain only letters, numbers, and underscores
- Case-sensitive (`{{Status}}` and `{{status}}` are different variables)
- Automatically converted to friendly labels (e.g. `min_age` becomes "Min Age")

## Variable Types

A variable can be one of three types. This is the complete list — `Lotus.Storage.QueryVariable` rejects anything else.

### Text Variables
- **Purpose**: String values, text input
- **Usage**: `WHERE name = {{customer_name}}`
- **Binding**: Passed as a bound parameter, never concatenated into the query

### Number Variables
- **Purpose**: Integers and decimal numbers
- **Usage**: `WHERE price >= {{min_price}}`
- **Binding**: Validated as numeric before binding

### Date Variables
- **Purpose**: Date values with calendar picker
- **Usage**: `WHERE created_at >= {{start_date}}`
- **Input format**: ISO date (YYYY-MM-DD)
- **Widget**: Always uses the date picker — the widget choice is hidden for date variables

## Widget Types

A variable stores one of two widgets, `input` or `select`. The toolbar renders four controls from those two values plus the variable's type and its `list` flag.

### Input Widgets
- **Best for**: Free-form text and number entry
- **Available for**: Text and Number variables
- **User experience**: Simple text input field, typed `number` for number variables

### Dropdown Widgets
- **Best for**: Predefined lists of options
- **Available for**: Text and Number variables
- **Configuration**: Custom list, or a query, in the "Dropdown values" modal

A select widget must define either static options or an options query — the changeset rejects one with neither.

#### Static Options Format

**Simple values** (one option per line):
```
active
pending
completed
cancelled
```

**Value and label pairs** (using `|` separator):
```
active | Active
pending | Pending
completed | Completed
cancelled | Cancelled
```

#### Options from a Query

**Dynamic dropdown options** populated from the data source:

**Single column query** (value = label):
```sql
SELECT status FROM orders GROUP BY status ORDER BY status
```

**Two column query** (first = value, second = label):
```sql
SELECT user_id, email FROM users WHERE active = true ORDER BY email
```

**Query requirements**:
- Must return 1 or 2 columns
- If 2 or more columns, the first is used as value, the second as label
- Results are cached under Lotus's `:options` cache profile
- Runs against the query's own data source and search path, with the dashboard's resolved actor
- Built-in "Test Query" button validates and previews before saving

> **Not every source offers this.** The "From query" mode is shown only when the selected data source declares the `:dynamic_options` feature — that is, a query against it can return a flat list of values. Document-shaped sources such as Elasticsearch declare `false`, and the modal offers manual entry only. A variable that carries an options query from an earlier source opens on manual entry rather than a mode it cannot use.

### Date Picker Widgets
- **Automatic**: All date variables use the date picker
- **User experience**: Calendar interface
- **Input**: ISO date format

## List Variables (Multi-Value)

Variables can be configured to accept multiple values, which is useful for `IN` clauses and similar multi-value patterns.

### Enabling List Mode

1. Open the variable settings panel
2. Check **"Allow multiple values"** on any text or number variable
3. The widget automatically switches to a multi-value input

### Widget Behavior

The control depends on whether the variable has dropdown options configured:

- **Tag Input** (widget `input`) — A chip-style control where users type values and press Enter to add them. Each value appears as a tag with an X button to remove it. The inner field is typed `number` for number variables.
- **Multiselect** (widget `select`) — A multi-select dropdown that lets users pick several values from the configured static or query-backed options.

### How Values Are Stored

List variable values are stored as comma-separated strings internally and split into individual values at execution time. Entering tags `active`, `pending` and `completed` stores `"active,pending,completed"` and expands to three bound values.

### Example: Filtering with IN Clauses

```sql
SELECT *
FROM orders
WHERE status IN ({{statuses}})
  AND region IN ({{regions}})
```

**Variable Configuration**:
- `statuses`: Text, Dropdown with static options (`active`, `pending`, `completed`), **Allow multiple values** enabled
- `regions`: Text, Input, **Allow multiple values** enabled — users type region codes as free-form tags

### Default Values for List Variables

You can set a comma-separated default value for list variables. Setting the default to `active,pending` pre-populates the tag input with two chips, or pre-selects two options in the multiselect dropdown.

## Optional Clauses

Wrapping part of a query in `[[ ... ]]` makes the clause optional: if any variable inside it has no value, the whole block is removed before the query runs. A value can come from the widget or from the variable's default.

```sql
SELECT * FROM orders
WHERE 1 = 1
  [[AND status = {{order_status}}]]
  [[AND created_at >= {{start_date}}]]
```

Variables that appear only inside `[[ ]]` are marked with an **Optional** badge in the settings panel, and their toolbar widget shows "All" as the placeholder rather than "Enter value". A variable that is *not* optional and has neither a supplied value nor a default fails with `Missing required variable: <name>` instead of binding a NULL.

## Variable Settings Panel

### Accessing Settings
1. Add variables to your query using `{{variable_name}}` syntax
2. Variables automatically appear in the toolbar
3. Click the "Variable settings" {x} icon in the toolbar, or press **Cmd/Ctrl+X**
4. Settings panel opens on the right side

The settings panel has two tabs:
- **Help Tab** - Shows when no variables are configured, contains syntax examples and usage information
- **Settings Tab** - Shows when variables exist, allows configuration of variable types, widgets, labels and defaults

### Variable Persistence
When you save a query, **all variable configurations are saved with it**:
- Variable types (Text, Number, Date)
- Widget types (Input, Dropdown)
- Labels and static options
- Default values

**What is NOT saved**: The actual values users enter in the widgets. Each time the query loads, widgets start empty unless you set default values.

**Pro tip**: Set default values in the variable settings if you want the query to auto-run with meaningful values when loaded.

## Advanced Usage Examples

### Multi-Filter Dashboard Query
```sql
SELECT
  DATE(created_at) as date,
  status,
  COUNT(*) as order_count,
  SUM(total_amount) as total_revenue
FROM orders
WHERE status = {{order_status}}
  AND created_at BETWEEN {{start_date}} AND {{end_date}}
  AND total_amount >= {{min_amount}}
GROUP BY DATE(created_at), status
ORDER BY date DESC
```

**Variable Configuration**:
- `order_status`: Text, Dropdown with static options: "active|Active", "pending|Pending", "completed|Completed"
- `start_date`: Date (automatic date picker)
- `end_date`: Date (automatic date picker)
- `min_amount`: Number, Input with default value "0"

### User Analysis Query
```sql
SELECT
  u.email,
  u.created_at,
  COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at >= {{registration_date}}
  [[AND u.email LIKE '%' || {{user_email}} || '%']]
GROUP BY u.email, u.created_at
HAVING COUNT(o.id) >= {{min_orders}}
ORDER BY order_count DESC
```

**Variable Configuration**:
- `registration_date`: Date, default value "2024-01-01"
- `user_email`: Text, Input with label "Search Email" — optional, so the clause drops out when it is blank
- `min_orders`: Number, Input with default value "1"

### Dynamic Category Analysis Query
```sql
SELECT
  c.name as category_name,
  COUNT(p.id) as product_count,
  AVG(p.price) as avg_price
FROM categories c
LEFT JOIN products p ON c.id = p.category_id
WHERE c.id = {{category_id}}
  AND p.active = {{product_status}}
GROUP BY c.id, c.name
ORDER BY product_count DESC
```

**Variable Configuration**:
- `category_id`: Number, Dropdown populated by the query `SELECT id, name FROM categories WHERE active = true ORDER BY name`
- `product_status`: Text, Dropdown with static options: "true|Active", "false|Inactive"

### Elasticsearch Query with a Variable

```json
{
  "query": {
    "bool": {
      "filter": [
        {"term": {"level": "{{log_level}}"}},
        {"range": {"@timestamp": {"gte": "{{since}}"}}}
      ]
    }
  },
  "size": 50
}
```

**Variable Configuration**:
- `log_level`: Text, Dropdown with static options — the source does not support `:dynamic_options`, so the values are typed by hand
- `since`: Date

## Best Practices

### Naming Conventions
- Use descriptive names: `{{start_date}}` not `{{d1}}`
- Use underscores for multi-word variables: `{{min_amount}}` not `{{minamount}}`
- Be consistent across related queries

### Default Values
- Always provide sensible defaults for a better user experience
- Use common filter values (e.g. "last 30 days" for dates)
- Use `[[ ]]` rather than a blank default for filters that should simply disappear
- **Set defaults if you want queries to auto-run** - widgets start empty unless defaults are configured

### Widget Selection
- **Use Static Dropdowns** for:
  - Status fields with known values
  - Boolean-like choices (Active/Inactive)
  - Small, fixed lists that rarely change
  - Any dropdown on a source that does not support `:dynamic_options`
- **Use Query Dropdowns** for:
  - User lists, category selections
  - Dynamic lookups from source tables
  - Lists that change frequently
- **Use Input fields** for:
  - Free-form text search
  - Numeric thresholds
  - Custom values not in predefined lists
- **Enable "Allow multiple values"** for:
  - `IN` clause filters (multiple statuses, regions, or IDs)
  - Any parameter where users need to select more than one value

### Query Design
- Design queries so a blank filter is meaningful — usually with `[[ ]]`
- Test queries with different variable combinations

## Security

### Substitution Is Owned by the Adapter

`Lotus.Storage.Query.compile/2` never writes a value into the query text itself. It folds each variable through the adapter's `substitute_variable/5` (or `substitute_list_variable/5`) callback, and each adapter picks the safe strategy for its own language:

- **SQL adapters** add a placeholder (`$1`, `?`, …) to the statement body and push the value into the parameter list. Nothing is interpolated, so there is no SQL injection surface.
- **JSON and DSL adapters** inline the value as a literal encoded by the language's own encoder. That encoder is the escaping boundary — this is why the Elasticsearch template quotes `"{{status}}"` and the adapter removes the quotes for non-string values.
- **Adapters with no `{{var}}` model** return `{:error, :unsupported}`, and a query with variables will not compile against them.

### Type Safety
- Number variables are validated as numeric before binding
- Date variables use ISO format validation
- Column types detected from the source refine the cast where they are available

### Missing Values
- A required variable with no supplied value and no default fails with `Missing required variable: <name>` rather than silently binding NULL
- Variables inside `[[ ]]` are removed with their clause instead

## Troubleshooting

### Variables Not Appearing
- **Check syntax**: Must be exactly `{{variable_name}}`
- **Check name**: Only letters, numbers, underscores allowed
- **Refresh editor**: Sometimes requires re-typing the variable

### Dropdown Options Not Working
- **Static options format**: One option per line
- **Custom options**: Either `value` (doubles as value/label) or `value | label` syntax
- **Empty lines**: Remove empty lines between options
- **Options queries**: Use the "Test Query" button to validate before saving
- **Query columns**: Must return 1 or 2 columns (value, label)
- **No "From query" option**: The selected data source does not declare `:dynamic_options`; enter the values by hand

### Date Variables Issues
- **Widget type**: Date variables always use the date picker (no input/dropdown choice)
- **Format**: ISO date format (YYYY-MM-DD)
- **Timezone**: Uses the browser's local timezone for the date picker

## Configuration Modal

### Accessing Dropdown Options Configuration
1. Set a variable to use a Dropdown widget in Variable Settings
2. Click the "Configure options" button next to the dropdown widget selection
3. Where the source supports it, choose between **"Custom list"** and **"From query"**; otherwise the modal opens straight into the custom list

### Modal Features
- **Custom list**: Text area for entering static options (one per line)
- **From query**: Monospaced text area for the options query
- **Test Query**: Validate the query and preview the first 3 results before saving
- **Error handling**: Clear error messages for invalid queries or syntax

## Variables on Dashboards

Query variables are also used by **dashboard filters**. When you add a filter to a dashboard, you map it to a query variable on each card. When a user interacts with the filter widget, the mapped variable is substituted in the query and the card re-runs automatically.

This means:
- Design your queries with `{{variable}}` placeholders as usual
- Add filters to the dashboard and map them to these variables in the card settings
- Filter values are reflected in the URL for shareable, bookmarkable filtered views

See the [Dashboards Guide](dashboards.md) for full details on setting up dashboard filters.
