# AI Query Assistant

> ⚠️ **Experimental Feature**: The AI Query Assistant is experimental and disabled by default. The feature and API may change in future versions.

The AI Query Assistant helps you write queries from natural language descriptions. It is not SQL-only: each data source tells the AI layer what language it speaks, so the same drawer generates SQL for a Postgres source and Elasticsearch Query DSL for an Elasticsearch source.

## Overview

The AI Assistant:
- **Conversational** - Multi-turn chat interface for iterative query building and refinement
- **BYOK (Bring Your Own Key)** - You provide and manage your own API keys
- **Adapter-driven** - The source's adapter supplies the query language, an example query, and syntax notes through its `ai_context/1` callback
- **Source-aware** - Introspects the selected data source before it answers
- **Respects visibility** - Only sees tables and columns you can access, for the actor the dashboard is running as
- **Read-only by default** - The adapter decides what counts as a write; pass `read_only: false` to core to allow write statements
- **Query explanation** - Get a plain-language breakdown of what a query does
- **Query optimization** - Analyzes your query, with an execution plan where the engine can produce one, and suggests improvements
- **Multi-provider** - Works with any provider supported by [ReqLLM](https://github.com/agentjido/req_llm) (OpenAI, Anthropic, Google, Groq, Mistral, and more)

## Enabling the Feature

AI features are disabled by default. To enable them, configure Lotus with your API key. See the [Lotus AI documentation](https://hexdocs.pm/lotus/ai_query_generation.html) for detailed setup instructions.

Quick example:

```elixir
# config/runtime.exs
config :lotus, :ai,
  enabled: true,
  model: "openai:gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY")
```

## AI Support Is Per Source

Every adapter answers `ai_context/1`. What it returns decides what the assistant can do with that source:

- `:language` — the language identifier, e.g. `"sql:postgres"` or `"json:elasticsearch"`. Core labels the fenced statement in the prompt with the family part (`sql`, `json`).
- `:example_query` — one worked example in the source's own language.
- `:syntax_notes` — how to write, and how to optimize, a query for this engine.
- `:error_patterns` — regexes plus hints, used to turn an engine error into an actionable suggestion.
- `:capabilities` — a per-feature map of `generation`, `optimization` and `explanation`, each `true` or `{false, reason}`.

An adapter that returns `{:error, _}` from `ai_context/1` opts its sources out of AI completely.

Core gates each entry point on the matching capability. `Lotus.AI.generate_query/1`, `generate_query_with_context/1`, `suggest_optimizations/1` and `explain_query/1` return `{:error, {:ai_feature_unsupported, feature, reason}}` before they call the model. You can ask the same question yourself:

```elixir
Lotus.AI.supports?("elasticsearch", :optimization)
# => true

Lotus.AI.unsupported_reason("my_source", :optimization)
# => "Query plans are not available for this engine."
```

In this release the dashboard does not pre-check those two functions — the **Explain query** and **Optimize query** buttons are enabled whenever the editor holds a non-empty query. Asking for a feature the source does not support returns the refusal as an error bubble in the conversation instead of a disabled button.

### The Trust Boundary

`:example_query`, `:syntax_notes`, `:generation_notes`, `:read_only_notes`, `:error_patterns` and capability reasons are free-form text that ends up inside the LLM prompt. Only adapters listed in `:trusted_source_adapters` have that text passed through unchanged:

```elixir
config :lotus,
  trusted_source_adapters: [MyApp.ClickHouseAdapter]
```

The built-in Ecto adapter and its per-dialect wrappers are always trusted. For any other adapter core keeps only `:language`, strips the free-form fields, and replaces capability reasons with a generic message. Add a third-party adapter to the allowlist only when you trust the code that ships it.

## Using the AI Assistant

### 1. Opening the Assistant

Click the **robot icon** in the query editor toolbar, or press **Cmd/Ctrl+K**. A conversational drawer slides in from the left with a chat interface. If this is your first time, you'll see example prompts to help you get started.

The icon appears only when AI is enabled and configured. Clicking it without configuration raises a flash message instead of opening the drawer.

### 2. Writing Prompts

Type your message in the input at the bottom of the drawer and press **Enter** to send (Shift+Enter for newlines). Be specific and descriptive:

**Good prompts:**
- "Show all users who signed up in the last 7 days"
- "Which customers have unpaid invoices with total amount owed"
- "Calculate monthly revenue grouped by product category"

**Too vague:**
- "Show users"
- "Data"

### 3. Reviewing Generated Queries

The AI responds in a chat bubble with the generated query. **Always review the query** before using it:

1. Check that it reads the right tables or indices
2. Verify joins, or the equivalent shape for your engine, are correct
3. Confirm filters match your intent
4. Check that the result set is bounded

Click the **"Use this query"** button on any AI message containing a query to insert it into the editor.

### 4. AI-Generated Variables

When your query uses `{{variable}}` placeholders, the AI can also generate variable configurations alongside the query — including type, widget, label, default value, and static options.

- A **variable summary** is displayed in each AI response bubble showing the variable names and widget types
- Clicking **"Use this query"** applies both the query and the variable settings in one action
- If only the variable configuration differs from the current query, the button label changes to **"Apply variable changes"**
- The AI receives your current query and variable context, so follow-up messages can refine both the query and its variables

Generated variables use the same vocabulary as the settings panel: type `text`, `number` or `date`, and widget `input` or `select`. See the [Variables and Widgets guide](variables-and-widgets.md).

**Example prompt:**
```
Show orders filtered by status with a dropdown, and by date range
```

Against a Postgres source the AI may generate `SELECT * FROM orders WHERE status = {{status}} AND created_at >= {{start_date}}` along with variable configs: `status` as a select widget with options from the `status` column, and `start_date` as a date input.

### 5. Iterating with Follow-Up Messages

The conversation keeps full context, so you can refine queries naturally:
- "Only return 100 rows"
- "Group by month instead of day"
- "Also include the customer email"
- "That's not right — the status column is called `state`"

### 6. Fixing Errors Automatically

When a query execution fails while the AI drawer is open, the error appears in the conversation, with the failed query behind a **"Show failed query"** disclosure. Click **"Ask AI to fix this"** to send the error context to the AI, which will attempt to generate a corrected query.

Where the adapter declares `:error_patterns`, a matching engine error also contributes a hint to the fix suggestions — for example, the Elasticsearch adapter turns `index_not_found_exception` into "The index does not exist. List available indices via list_tables."

### 7. Managing the Conversation

- The header shows the message count and how many queries have been generated
- Click the **trash icon** to clear the conversation and start fresh
- Scroll through conversation history — the chat auto-scrolls to new messages

Provider-level failures (rate limits, authentication, timeouts) render as amber **Service Unavailable** bubbles, distinct from red query errors.

## Explaining Queries

The AI Assistant can explain what a query does in plain language — useful for understanding complex queries, onboarding teammates, or documenting queries you inherited.

### Using the Explain Button

There are two ways to trigger an explanation:

1. **Quick-action button** — Above the chat input, click the **"Explain query"** button (brain icon). It's enabled whenever the editor holds a non-empty query.
2. **Empty state** — When the conversation is empty, click **"Explain query"** in the welcome screen.

Clicking either button:
- Adds an "Explain this query" message to the conversation
- Sends the current query to the AI for analysis
- Displays the explanation as formatted text with inline code, bullet points, and paragraphs

The explanation covers what the query does step by step — what it reads, how it combines and filters, any aggregation, and the shape of the result set.

### Explaining a Fragment

You can also explain a specific portion of a query by selecting it directly in the editor:

1. **Highlight text** — Select any portion of the query in the CodeMirror editor (at least one word)
2. **Click the floating button** — An "Explain fragment" button (brain icon) appears near your selection
3. **Read the explanation** — The AI Assistant drawer opens and explains only the selected fragment, using the full query for context

This is useful for understanding individual clauses (a JOIN, a window function, a subquery, or a `bool.filter` block in a JSON DSL) without getting a full query breakdown.

The button dismisses automatically when you clear the selection, press Escape, or click elsewhere in the editor.

## Optimizing Queries

The AI Assistant can analyze your current query and suggest performance improvements.

### Using the Optimize Button

There are two ways to trigger optimization:

1. **Quick-action button** — Above the chat input, click the **"Optimize query"** button (wrench icon). It's enabled whenever the editor holds a non-empty query.
2. **Empty state** — When the conversation is empty, click **"Optimize query"** in the welcome screen.

Clicking either button:
- Adds an "Optimize this query" message to the conversation
- Wraps the editor content in a `%Lotus.Query.Statement{}` and sends it to `Lotus.AI.suggest_optimizations/1`
- Displays results as suggestion cards

Core runs the adapter's `prepare_for_analysis/2` and `query_plan/3` first. SQL sources contribute an `EXPLAIN` plan; engines that cannot produce a plan return nothing and the AI works from the statement alone, so the suggestions are structural rather than plan-driven.

### Reading Optimization Suggestions

Each suggestion is rendered as a card with:
- **Type pill** — The kind of optimization: `index`, `rewrite`, `structure`, or `configuration`
- **Impact pill** — Expected improvement level: `high` (red), `medium` (yellow), or `low` (green)
- **Title** — A short summary of the suggestion
- **Details** — Full explanation, often including an exact statement (for example a `CREATE INDEX`)

If the query is already well-optimized, you'll see a success message instead.

> The `structure` type replaces the pre-1.0 `schema` type. A model that still emits `{"type": "schema", ...}` renders with the neutral fallback colour.

### Lotus Variable Syntax

Queries using `{{variable}}` placeholders and `[[optional clauses]]` work seamlessly — the optimizer neutralizes the template syntax before asking the engine for a plan, while the AI still sees the original query.

## How It Works

### Source Discovery

For generation the AI has five tools:

1. **`list_schemas()`** - Discovers available namespaces (e.g. `public`, `reporting`)
2. **`list_tables()`** - Gets qualified table, or index, names
3. **`describe_table(table)`** - Retrieves column details, types, constraints
4. **`get_column_values(table, column)`** - Checks actual enum/status values
5. **`validate_statement(statement)`** - Asks the adapter to validate a candidate query before returning it

Explanation and optimization use `describe_table` only — they already have the query in hand.

All tools run through Lotus core with the actor the dashboard resolved for the current user, so they respect your visibility rules and reach your middleware with the right context.

### Example: Smart Status Handling

Instead of guessing status values:

```
Prompt: "Show invoices that aren't paid"
```

The AI will:
1. Find the `invoices` table
2. Describe it and see a `status` column
3. Call `get_column_values("invoices", "status")`
4. Discover actual values: `["open", "paid", "overdue"]`
5. Generate: `WHERE status IN ('open', 'overdue')`

✅ Uses actual data instead of guessing!

## Non-SQL Sources

Nothing above is SQL-specific. When the selected source declares a non-SQL language the editor and the assistant adapt together:

- The editor switches to JSON mode, with completions driven by the adapter's `context_schema` — root keys inside `{}`, `must`/`should`/`filter` inside a `bool` block, mapped field names inside `match`/`term`/`range`, range operators inside a range object, and value literals at value positions.
- A **pretty-print** button (`{}` icon, **Cmd/Ctrl+Shift+F**) appears in the toolbar. It is hidden for SQL sources, where there is no lossless structural expansion.
- SQL-only affordances are hidden. The `search_path` badge only shows for sources that declare the `:search_path` feature.
- The AI prompt carries that adapter's example query and syntax notes, so a request against an Elasticsearch source comes back as Query DSL JSON, fenced as `json`.

## Tips for Better Results

### 1. Mention Table or Index Names

Help the AI find the right data:

```
"Show sales from the orders table in the last month"
```

### 2. Be Explicit About Time Ranges

```
"Users created in the last 30 days" ✅
"Recent users" ❌
```

### 3. Specify Aggregations

```
"Total revenue grouped by month" ✅
"Show revenue" ❌
```

### 4. Use Schema Explorer

Keep the schema explorer open (right side) while using the AI assistant (left side). Reference table and column names from it.

## Visibility and Security

### What the AI Can See

The AI assistant sees **exactly what you see** in the schema explorer:

- Tables you have access to
- Columns that aren't masked or omitted
- Namespaces in your search path

Hidden tables (via Lotus visibility rules) are not visible to the AI. If your dashboard implements the `resolve_scope/1` resolver callback, the AI's introspection runs under that same scope — it cannot see more than the person it is acting for.

### Example

If your visibility config hides sensitive tables:

```elixir
config :lotus,
  table_visibility: %{
    default: [
      deny: [
        {"public", "api_keys"},
        {"public", "user_sessions"}
      ]
    ]
  }
```

And you ask: "Show me all API keys"

The AI will respond: `UNABLE_TO_GENERATE: api_keys table not available`

## Limitations

### Current Limitations

- **English recommended** - Other languages may work but aren't tested
- **Session-only history** - Conversation is not persisted across page reloads
- **No per-feature button gating** - The dashboard does not yet grey out actions a source cannot support; the refusal arrives as an error message in the conversation

### When AI Can't Help

The AI will refuse to generate queries for:
- Non-data questions ("What's the weather?")
- Data not in visible tables
- Action requests ("Send emails to customers")

You'll see an error like: `UNABLE_TO_GENERATE: [reason]`

## Cost Management

Each AI query generation consumes tokens from your LLM provider. Costs vary by provider and model — refer to your provider's pricing page for current rates.

### Reducing Costs

1. Use cheaper models for simple queries (Gemini Flash, GPT-4o-mini)
2. Be specific in prompts to minimize tool calls
3. Save and reuse frequently-needed queries instead of regenerating

## Troubleshooting

### "AI features are not configured"

AI is disabled. Check your Lotus configuration includes:

```elixir
config :lotus, :ai,
  enabled: true,
  model: "openai:gpt-4o",
  api_key: "..."
```

### Robot Icon Not Visible

The robot icon only appears when:
1. AI is enabled in configuration
2. You have a valid API key

The assistant also needs a selected data source before it will send a message — without one it answers "Please select a data source first".

### An Action Reports the Source Does Not Support It

The adapter declared `{false, reason}` for that capability, or opted out of AI entirely. Check with `Lotus.AI.supports?/2` and `Lotus.AI.unsupported_reason/2`. Nothing in the dashboard configuration changes this — it is the adapter's own declaration.

### Slow Response Times

Query generation typically takes 2-10 seconds depending on:
- Source complexity (more tables = more tool calls)
- LLM model
- Network latency

This is normal! The AI is introspecting your data source.

### Incorrect Queries

If generated queries are wrong:
- Try being more specific in your prompt
- Mention exact table/column names
- Reference relationships explicitly ("join orders with customers")
- Review and manually adjust the generated query

## Privacy

- **Your data stays private** - API calls go directly from your application to your LLM provider
- **No intermediaries** - Lotus doesn't proxy or log AI requests
- **BYOK model** - You control API keys and can revoke access anytime

## Getting Help

- [Lotus GitHub Issues](https://github.com/elixir-lotus/lotus/issues)
- [Lotus Documentation](https://hexdocs.pm/lotus)
- [LotusWeb GitHub Issues](https://github.com/elixir-lotus/lotus_web/issues)
