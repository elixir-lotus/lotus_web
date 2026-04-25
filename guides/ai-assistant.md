# AI Query Assistant

> ⚠️ **Experimental Feature**: The AI Query Assistant is experimental and disabled by default. The feature and API may change in future versions.

The AI Query Assistant helps you generate SQL queries from natural language descriptions. This guide covers how to use it effectively.

## Overview

The AI Assistant:
- **Conversational** - Multi-turn chat interface for iterative query building and refinement
- **BYOK (Bring Your Own Key)** - You provide and manage your own API keys
- **Schema-aware** - Automatically understands your database structure
- **Respects visibility** - Only sees tables and columns you can access
- **Read-only by default** - Only generates SELECT queries unless `read_only: false` is configured
- **Query explanation** - Get a plain-language breakdown of what any SQL query does
- **Query optimization** - Analyzes your SQL with EXPLAIN plans and suggests performance improvements
- **Multi-provider** - Works with any provider supported by [ReqLLM](https://github.com/agentjido/req_llm) (OpenAI, Anthropic, Google, Groq, Mistral, and more)

## Enabling the Feature

AI features are disabled by default. To enable them, configure Lotus with your API key. See the [Lotus AI documentation](https://github.com/typhoonworks/lotus#ai-query-generation-experimental-byok) for detailed setup instructions.

Quick example:

```elixir
# config/runtime.exs
config :lotus, :ai,
  enabled: true,
  model: "openai:gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY")
```

## Using the AI Assistant

### 1. Opening the Assistant

Click the **robot icon** in the query editor toolbar. A conversational drawer slides in from the left with a chat interface. If this is your first time, you'll see example prompts to help you get started.

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

The AI responds in a chat bubble with the generated SQL. **Always review the query** before using it:

1. Check that it queries the right tables
2. Verify JOINs are correct
3. Confirm filters match your intent
4. Check for appropriate LIMITs

Click the **"Use this query"** button on any AI message containing SQL to insert it into the editor.

### 4. AI-Generated Variables

When your query uses `{{variable}}` placeholders, the AI can also generate variable configurations alongside the SQL — including type, widget, label, default value, and static options.

- A **variable summary** is displayed in each AI response bubble showing the variable names and widget types
- Clicking **"Use this query"** applies both the SQL and the variable settings in one action
- If only the variable configuration differs from the current query, the button label changes to **"Apply variable changes"**
- The AI receives your current SQL and variable context, so follow-up messages can refine both the query and its variables

**Example prompt:**
```
Show orders filtered by status with a dropdown, and by date range
```

The AI may generate a query like `SELECT * FROM orders WHERE status = {{status}} AND created_at >= {{start_date}}` along with variable configs: `status` as a select widget with options from the `status` column, and `start_date` as a date input.

### 5. Iterating with Follow-Up Messages

The conversation keeps full context, so you can refine queries naturally:
- "Add a LIMIT 100 to that"
- "Group by month instead of day"
- "Also include the customer email"
- "That's not right — the status column is called `state`"

### 6. Fixing Errors Automatically

When a query execution fails while the AI drawer is open, the error appears in the conversation. Click **"Ask AI to fix this"** to send the error context to the AI, which will attempt to generate a corrected query.

### 7. Managing the Conversation

- The header shows the message count and how many queries have been generated
- Click the **trash icon** to clear the conversation and start fresh
- Scroll through conversation history — the chat auto-scrolls to new messages

## Explaining Queries

The AI Assistant can explain what any SQL query does in plain language — useful for understanding complex queries, onboarding teammates, or documenting existing SQL.

### Using the Explain Button

There are two ways to trigger an explanation:

1. **Quick-action button** — Above the chat input, click the **"Explain query"** button (brain icon). It's enabled whenever the editor has a non-empty SQL query.
2. **Empty state** — When the conversation is empty, click **"Explain query"** in the welcome screen.

Clicking either button:
- Adds an "Explain this query" message to the conversation
- Sends the current SQL to the AI for analysis
- Displays the explanation as formatted text with inline code, bullet points, and paragraphs

The explanation covers what the query does step by step — tables accessed, joins, filters, aggregations, and the shape of the result set.

### Explaining a Fragment

You can also explain a specific portion of a query by selecting it directly in the editor:

1. **Highlight text** — Select any portion of SQL in the CodeMirror editor (at least one word)
2. **Click the floating button** — An "Explain fragment" button (brain icon) appears near your selection
3. **Read the explanation** — The AI Assistant drawer opens and explains only the selected fragment, using the full query for context

This is useful for understanding individual clauses (e.g., a JOIN, a window function, or a subquery) without getting a full query breakdown.

The button dismisses automatically when you clear the selection, press Escape, or click elsewhere in the editor.

## Optimizing Queries

The AI Assistant can analyze your current SQL query and suggest performance improvements.

### Using the Optimize Button

There are two ways to trigger optimization:

1. **Quick-action button** — Above the chat input, click the **"Optimize query"** button (wrench icon). It's enabled whenever the editor has a non-empty SQL query.
2. **Empty state** — When the conversation is empty, click **"Optimize query"** in the welcome screen.

Clicking either button:
- Adds an "Optimize this query" message to the conversation
- Sends the current SQL to the AI for EXPLAIN plan analysis
- Displays results as suggestion cards

### Reading Optimization Suggestions

Each suggestion is rendered as a card with:
- **Type pill** — The kind of optimization: `index`, `rewrite`, `schema`, or `configuration`
- **Impact pill** — Expected improvement level: `high` (red), `medium` (yellow), or `low` (green)
- **Title** — A short summary of the suggestion
- **Details** — Full explanation, often including exact SQL (e.g., `CREATE INDEX` statements)

If the query is already well-optimized, you'll see a success message instead.

### Lotus Variable Syntax

Queries using `{{variable}}` placeholders and `[[optional clauses]]` work seamlessly — the optimizer sanitizes the syntax for EXPLAIN while preserving the original query for AI analysis.

## How It Works

### Schema Discovery

The AI uses four tools to understand your database:

1. **`list_schemas()`** - Discovers available schemas (e.g., `public`, `reporting`)
2. **`list_tables()`** - Gets schema-qualified table names
3. **`get_table_schema(table)`** - Retrieves column details, types, constraints
4. **`get_column_values(table, column)`** - Checks actual enum/status values

All tools respect your Lotus visibility rules.

### Example: Smart Status Handling

Instead of guessing status values:

```
Prompt: "Show invoices that aren't paid"
```

The AI will:
1. Find the `invoices` table
2. Get its schema and see a `status` column
3. Call `get_column_values("invoices", "status")`
4. Discover actual values: `["open", "paid", "overdue"]`
5. Generate: `WHERE status IN ('open', 'overdue')`

✅ Uses actual data instead of guessing!

## Tips for Better Results

### 1. Mention Table Names

Help the AI find the right tables:

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
- Schemas in your search path

Hidden tables (via Lotus visibility rules) are not visible to the AI.

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

### When AI Can't Help

The AI will refuse to generate queries for:
- Non-database questions ("What's the weather?")
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
3. A data source is selected

### Slow Response Times

Query generation typically takes 2-10 seconds depending on:
- Database complexity (more tables = more tool calls)
- LLM model
- Network latency

This is normal! The AI is introspecting your schema.

### Incorrect Queries

If generated queries are wrong:
- Try being more specific in your prompt
- Mention exact table/column names
- Reference relationships explicitly ("join orders with customers")
- Review and manually adjust the generated SQL

## Privacy

- **Your data stays private** - API calls go directly from your application to your LLM provider
- **No intermediaries** - Lotus doesn't proxy or log AI requests
- **BYOK model** - You control API keys and can revoke access anytime

## Getting Help

- [Lotus GitHub Issues](https://github.com/typhoonworks/lotus/issues)
- [Lotus Documentation](https://hexdocs.pm/lotus)
- [LotusWeb GitHub Issues](https://github.com/elixir-lotus/lotus_web/issues)
