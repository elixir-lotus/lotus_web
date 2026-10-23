# Visualizations

LotusWeb includes built-in charting capabilities to visualize your query results. This guide covers all available chart types, configuration options, and best practices.

## Overview

After running a query, you can switch between table and chart views to visualize your data:

- **20 chart types** across five categories — Charts, Distribution, Part of whole, Maps, and Single value
- **Flexible configuration** - Configure axes, grouping fields, and type-specific options
- **Dark mode support** - Charts automatically adapt to your theme
- **Interactive** - Hover a mark for its values (a line or area shows every series at that point), hover a legend entry to bring its series forward, move through the marks with the arrow keys, and read the chart's data as a table
- **Keyboard shortcuts** - Quick access to visualization features

Charts are drawn by [Fude](https://github.com/hattoriai/fude) as SVG in the page: the server compiles the chart from the result, and the browser only lays it out and animates it.

Charts are built from a result's columns and rows, so they work with any data source Lotus can run — the examples below are SQL because most sources are, but a JSON DSL source that returns tabular results charts the same way.

## Chart Types

Chart types are organized into five categories in the settings panel.

### Charts

#### Bar Chart

Best for comparing categorical data with discrete values.

**When to use:** Comparing values across categories (e.g. sales by region), displaying counts or totals, showing rankings.

**Config:** X-Axis Field, Y-Axis Field, optional Color/Series Field.

```sql
SELECT department, COUNT(*) as employee_count
FROM employees
GROUP BY department;
```

#### Horizontal Bar

Same as bar chart but with swapped axes — the category field is drawn on the Y-axis and the value field on the X-axis. Useful for long category labels.

**Config:** X-Axis Field (category), Y-Axis Field (value), optional Color/Series Field. The fields keep their names; only the rendering swaps.

#### Line Chart

Best for showing trends and changes over time.

**When to use:** Tracking metrics over time, showing continuous data, comparing multiple series.

**Config:** X-Axis Field (typically a date), Y-Axis Field, optional Color/Series Field.

```sql
SELECT DATE(created_at) as date, COUNT(*) as signups
FROM users
WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date;
```

#### Area Chart

Best for showing cumulative totals or volume over time. Like the line chart but with a filled area.

**Config:** X-Axis Field, Y-Axis Field, optional Color/Series Field.

```sql
SELECT DATE(order_date) as date, SUM(amount) as revenue
FROM orders
GROUP BY DATE(order_date)
ORDER BY date;
```

#### Combo Chart

Dual-axis chart combining bars and a line with independent Y scales: the bars on the left axis, the line on the right, each axis titled in its series' colour. Useful for overlaying two related metrics with different units.

**Config:** X-Axis Field, Y-Axis Field (bars), Y2 Field (line), optional Y2 Axis Title.

```sql
SELECT DATE(order_date) as date,
       COUNT(*) as order_count,
       SUM(amount) as revenue
FROM orders
GROUP BY DATE(order_date)
ORDER BY date;
```
Set X-Axis to `date`, Y-Axis to `order_count`, and Y2 Field to `revenue`.

### Distribution

#### Scatter Plot

Best for exploring relationships between two numeric variables.

**Config:** X-Axis Field, Y-Axis Field, optional Color/Series Field.

```sql
SELECT price, quantity_sold
FROM products
WHERE quantity_sold > 0;
```

#### Bubble Chart

Extends scatter with a third dimension — circle size varies by a numeric field.

**Config:** X-Axis Field, Y-Axis Field, optional Color/Series Field, optional Size Field.

```sql
SELECT price, quantity_sold, revenue
FROM products
WHERE quantity_sold > 0;
```
Set Size Field to `revenue` to make bubble size proportional to revenue.

#### Histogram

Shows the distribution of a single numeric variable as binned bars.

**Config:** Data Field (the numeric field to bin), Number of Bins (default 10, between 2 and 100), optional Color/Series Field.

```sql
SELECT salary FROM employees;
```

#### Heatmap

Color-encoded matrix showing the relationship between two categorical or ordinal fields.

**Config:** Column Field (X), Row Field (Y), optional Value Field for the colour intensity. Leave the Value Field empty to colour each cell by its number of rows.

```sql
SELECT day_of_week, hour_of_day, COUNT(*) as events
FROM activity_log
GROUP BY day_of_week, hour_of_day;
```

### Part of whole

#### Pie Chart

Shows proportions of a whole. Use sparingly — best with 5 or fewer categories.

**Config:** X-Axis Field (category), Y-Axis Field (value).

```sql
SELECT status, COUNT(*) as count
FROM orders
GROUP BY status;
```

#### Donut Chart

Same as the pie chart but with a hollow center. Uses the same configuration.

**Config:** X-Axis Field (category), Y-Axis Field (value).

#### Funnel Chart

Shows sequential stages with decreasing values — useful for conversion funnels.

**Config:** X-Axis Field (stage name), Y-Axis Field (value).

```sql
SELECT stage, user_count
FROM conversion_funnel
ORDER BY step_order;
```

#### Waterfall Chart

Stepped bar chart showing how an initial value is affected by a series of positive or negative changes, with a running total.

**Config:** X-Axis Field (category), Y-Axis Field (value).

```sql
SELECT category, amount
FROM budget_changes
ORDER BY display_order;
```

### Maps

#### Map

Colors each region (a country, or a US state) by a value: where the users are, revenue by state.

**Config:** Map (World or United States), Region Field, Value Field.

The region field holds a country's ISO code (`PRT` or `PT`), its number or its name; or a state's postal code (`CA`), FIPS number (`06`) or name. Regions the map does not know are listed in the browser's console.

```sql
SELECT country_code AS country, COUNT(*) AS users
FROM users
GROUP BY country_code;
```

#### Bubble Map

A circle at each region's center, sized by a value. Better than a map's colors when the value is a count or an amount: a large region with few stores stays small.

**Config:** Map, Region Field, Value Field.

The maps are loaded by the browser only when a map chart first draws.

### Single value

Four of these chart types use a **Value Field** instead of X/Y axes, and all four accept an optional **Label** that replaces the column name under the number.

#### KPI Card

Displays a single number prominently — ideal for dashboard headline metrics.

**Config:** Value Field, optional Label.

```sql
SELECT COUNT(*) as total_users FROM users;
```

#### Trend

KPI-style display with a delta comparison showing change against a comparison field.

**Config:** Value Field, optional Label, optional Comparison Field. Leave the Comparison Field empty to compare against the previous row.

```sql
SELECT
  SUM(CASE WHEN created_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 ELSE 0 END) as this_week,
  SUM(CASE WHEN created_at < CURRENT_DATE - INTERVAL '7 days'
           AND created_at >= CURRENT_DATE - INTERVAL '14 days' THEN 1 ELSE 0 END) as last_week
FROM orders;
```
Set Value Field to `this_week` and Comparison Field to `last_week`.

#### Gauge

Semicircular arc showing a value within a defined range.

**Config:** Value Field, optional Label, Min Value (default 0), Max Value (default 100).

```sql
SELECT AVG(score) as avg_score FROM reviews;
```

#### Progress Bar

Horizontal bar showing progress toward a goal.

**Config:** Value Field, optional Label, Goal Value (default 100).

```sql
SELECT COUNT(*) as completed FROM tasks WHERE status = 'done';
```

#### Sparkline

Compact inline line chart — useful in dashboards for showing trends without axis labels. Despite sitting in the Single value group, it plots a series: it takes X and Y fields like the cartesian charts.

**Config:** X-Axis Field (typically a date), Y-Axis Field. The Color/Series selector is offered but the sparkline ignores it — a sparkline draws one series.

```sql
SELECT DATE(event_time) as date, COUNT(*) as events
FROM activity_log
GROUP BY DATE(event_time)
ORDER BY date;
```

## Configuring Charts

### Opening the Settings Drawer

Access visualization settings in two ways:
- Click the **chart icon** in the editor toolbar
- Press **Cmd/Ctrl+Shift+V**

### Chart Type Tab

The first tab displays all 18 chart types organized into four groups: Charts, Distribution, Part of whole, and Single value. Click any icon to select that chart type.

Switching type keeps the fields the new type can still use and drops the rest, so moving between bar, line and area does not clear your axes.

### Configure Tab

The second tab shows configuration fields that vary by chart type:

**Standard charts** (bar, horizontal bar, line, area, scatter, bubble, pie, donut, funnel, waterfall, sparkline):

| Setting | Description | Required |
|---------|-------------|----------|
| **X-Axis Field** | The field for the horizontal axis | Yes |
| **Y-Axis Field** | The field for the vertical axis (should be numeric) | Yes |
| **Color/Series Field** | Optional field to group data by color | No |

**Bubble chart** adds:

| Setting | Description | Required |
|---------|-------------|----------|
| **Size Field** | Numeric field controlling circle size | No |

**Combo chart** replaces the series field with:

| Setting | Description | Required |
|---------|-------------|----------|
| **Y2 Field** | Field for the secondary Y-axis (line) | Yes |
| **Y2 Axis Title** | Custom label for the secondary axis | No |

**Histogram:**

| Setting | Description | Required |
|---------|-------------|----------|
| **Data Field** | The numeric field to bin | Yes |
| **Number of Bins** | 2 to 100, default 10 | No |
| **Color/Series Field** | Optional field to group bars by color | No |

**Heatmap:**

| Setting | Description | Required |
|---------|-------------|----------|
| **Column Field** | Categorical field for the X-axis | Yes |
| **Row Field** | Categorical field for the Y-axis | Yes |
| **Value Field** | Numeric field for colour intensity | No |

**Single value charts** (KPI, trend, gauge, progress):

| Setting | Description | Required |
|---------|-------------|----------|
| **Value Field** | The numeric field to display | Yes |
| **Label** | Custom caption under the number | No |
| **Comparison Field** | Field to compare against (trend only) | No |
| **Min Value / Max Value** | Range for gauge display | No |
| **Goal Value** | Target value for progress bar | No |

### Axis Options

Fine-tune your chart display. The Axis Display section appears for bar, horizontal bar, line, area, scatter and bubble charts:

- **Show Labels** - Toggle axis labels on/off
- **X-Axis Title** - Custom label for the horizontal axis
- **Y-Axis Title** - Custom label for the vertical axis

Without a title of its own, an axis is titled by its field's name in words: `total_revenue` is "Total revenue".

Axis titles are a query-editor setting; the dashboard card settings drawer does not expose them.

### Chart Options

Under the fields, both the query editor's settings and a dashboard card's settings offer the options of the chart type: only those it has.

| Option | Chart types | What it does |
|--------|-------------|--------------|
| **Values' format** | All | How the numbers read, on the axis, in the tooltips and on the marks: *Automatic* (Fude's choice), *Exact* (1,234,567.8), *Whole* (1,234,568), *Compact* (1.2M), *Percent* (0.42 is 42%) or *Currency*, with its code (USD, EUR…). A KPI shows its exact number with *Exact*. |
| **Decimals** | All | How many decimals the values write (0 to 3), with their format or alone: *Exact* with 0 decimals reads 6,893,914. |
| **Line's format** | Combo | The format of the line, on the right axis. |
| **Show values on the bars** | Bar, horizontal bar | Writes each bar's value at its end. On by default for horizontal bars. |
| **Series** | Bar, horizontal bar, area (with a series field) | *Stacked*, *Side by side* (*Overlapping* for areas), or *Stacked to 100%*, each series as its share. |
| **Order** | Bar, horizontal bar | The bars as the query returns them, largest or smallest first, or by name. |
| **Smooth lines** | Line, area, combo, sparkline | Curves through the points instead of straight segments. |
| **Start the axis at zero** | Line, scatter, bubble, combo (each axis) | By default these axes fit the data, so that a change reads clearly; from zero, they show sizes against nothing. Bars and areas always start at zero. |
| **Reference line** | Bar, horizontal bar, line, area, scatter, bubble, combo | A dashed line across the chart at a value, with a label: a goal, a limit, an average. |
| **Small multiples** | Bar, horizontal bar, line, area, scatter, bubble | The chart once for each value of a field, side by side on the same scales, in as many columns as you choose. Clearer than one chart of many series. |
| **Colors** | Bar, horizontal bar, line, area, scatter, bubble, pie, donut, histogram | The series' colors: Fude's own, or *Colorblind-safe* (Okabe–Ito), told apart with the common colour vision deficiencies. |
| **Colors** | Heatmap, map | The value's colors: a ramp (blue, green, orange, purple, gray, viridis), or one that diverges from red to blue or red to green through a neutral at a value you choose (0 unless given), for changes and differences. |
| **Stages** | Funnel | One color, a color for each stage, or each stage lighter than the one before; and the values beside the bars, in them, or none. |
| **Sparkline** | Sparkline | A fill under the line, dots on the last value or on the last, lowest and highest, and the last value written at the end of the line. |
| **Tooltip** | Bar, horizontal bar, line, area, scatter, bubble, pie, donut, heatmap, maps | More fields to show when a mark is hovered, beyond the chart's own. |
| **Mark the highest / lowest value** | Bar, line, area, combo | A callout on the highest or the lowest value, with the value ("Highest: 463K"). Not on stacked series, whose marks are not at their values. |
| **Shade a range** | Bar, line, area, combo, scatter, bubble | A shaded band across a range of the horizontal axis, with a label: a campaign, a holiday, an outage. Dates are written as `2026-03-01`, categories by name, numbers as numbers. |
| **Subtitle** and **Source** | All | Words above and below the chart: how it is measured, and where the data comes from. |

The query editor's chart also has **SVG** and **PNG** buttons under it, which save it as a file with its words and legend. A dashboard card saves its chart as PNG from the download button in its header.

When a dashboard card refreshes, or a dashboard filter changes, its chart stays on screen, dimmed, and its marks move to the new values.

### Configuration Status

A status indicator shows whether your chart is ready:
- **Green checkmark** - Configuration is valid
- **Amber warning** - Missing required fields, with a hint naming the field the chart type needs

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd/Ctrl+Shift+V | Toggle visualization settings drawer |
| Cmd/Ctrl+1 | Switch to table view |
| Cmd/Ctrl+2 | Switch to chart view |

With focus inside the editor, **Cmd/Ctrl+G** also toggles the visualization drawer, opening it on the Configure tab when the chart is already configured.

## Best Practices

### Choosing the Right Chart

| Data Type | Recommended Chart |
|-----------|-------------------|
| Categories with values | Bar or Horizontal Bar |
| Time series data | Line, Area, or Sparkline |
| Two metrics, different scales | Combo chart |
| Two numeric variables | Scatter or Bubble |
| Distribution of a variable | Histogram |
| Two-dimensional density | Heatmap |
| Simple proportions (≤5 items) | Pie or Donut |
| Sequential stages / conversion | Funnel |
| Running totals / changes | Waterfall |
| Single headline metric | KPI Card |
| Metric with period comparison | Trend |
| Value within a range | Gauge |
| Progress toward a goal | Progress Bar |

### Preparing Your Data

For the best visualization results:

1. **Ensure numeric Y-axis data** - The Y-axis field should contain numbers for most chart types
2. **Use dates for time series** - When charting over time, return date or timestamp values for the X-axis
3. **Limit categories** - For bar and pie charts, aim for fewer than 10 categories for readability
4. **Include grouping columns** - To create multi-series charts, include a category column for the Color/Series field
5. **Order your data** - For line and area charts, order by your date/time column in the query

Decimals, dates, times and UUID binaries returned by the source are normalized to chartable values before they reach the chart, so you do not have to cast them in the query.

### Common Query Patterns

**Grouped bar chart (multiple series):**
```sql
SELECT
  DATE_TRUNC('month', created_at) as month,
  status,
  COUNT(*) as count
FROM orders
GROUP BY DATE_TRUNC('month', created_at), status
ORDER BY month;
```
Set X-Axis to `month`, Y-Axis to `count`, and Color/Series to `status`.

**Time series with aggregation:**
```sql
SELECT
  DATE(event_time) as date,
  SUM(value) as total
FROM metrics
WHERE event_time >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(event_time)
ORDER BY date;
```
Set X-Axis to `date` and Y-Axis to `total`.

## Troubleshooting

### Chart Not Rendering

- **Check field selection** - Ensure the fields the chart type needs are selected: X and Y for cartesian charts, Value Field for KPI, trend, gauge and progress, Data Field for the histogram
- **Verify data types** - The Y-Axis field must contain numeric values
- **Check for empty results** - Run the query first and confirm data is returned

### Colors Not Showing

- **Add Color/Series field** - Select a grouping field to enable multi-series coloring
- **Verify distinct values** - The grouping field should have distinct values to differentiate series

### Chart Looks Wrong

- **Wrong chart type** - Consider if another chart type better suits your data
- **Too many categories** - Reduce categories or switch from pie to bar chart
- **Unordered time series** - For line and area charts, order the results by the time column

### Performance Issues

- **Limit result size** - Large datasets may slow chart rendering; bound or aggregate the result
- **Aggregate in the query** - Perform grouping and aggregation in your query rather than charting raw rows
