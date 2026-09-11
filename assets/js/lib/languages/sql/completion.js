import { SQL_DEFAULTS } from "./defaults.js";
import { SqlContextAnalyzer } from "./context_analyzer.js";

// Core SQL structural keywords where column/function suggestions mid-typing
// would be unwanted noise. Kept intentionally small — adapter-specific keywords
// (RELOAD, RENAME, RETENTION, etc.) are excluded to avoid suppressing completions
// for columns that share a prefix (e.g., "re" matching "revenue").
const STRUCTURAL_KEYWORDS = [
  "select", "from", "where", "join", "inner", "left", "right", "full",
  "outer", "cross", "on", "and", "or", "not", "in", "exists", "like",
  "ilike", "between", "case", "when", "then", "else", "end", "as",
  "distinct", "all", "union", "intersect", "except", "with", "insert",
  "into", "values", "update", "set", "delete", "create", "drop", "alter",
  "table", "group", "order", "having", "limit", "offset",
];

export class SqlCompletion {
  constructor(schema, config = {}) {
    this.schema = schema || {};
    this.config = {
      keywords: [...SQL_DEFAULTS.keywords, ...(config.keywords || [])],
      functions: [...SQL_DEFAULTS.functions, ...(config.functions || [])],
      contextBoundaries: [
        ...SQL_DEFAULTS.contextBoundaries,
        ...(config.contextBoundaries || []),
      ],
    };
    this.analyzer = new SqlContextAnalyzer(this.config);
  }

  updateSchema(newSchema) {
    this.schema = newSchema || {};
  }

  createCompletionSource() {
    return (context) => {
      const query = context.state.doc.toString();
      const cursorPos = context.pos;

      if (this.isTypingKeyword(query, cursorPos)) {
        return null;
      }

      const sqlContext = this.analyzer.analyzeContext(query, cursorPos);

      const completions = this.getContextualCompletions(sqlContext);

      if (completions.length === 0) {
        return null;
      }

      const wordBounds = this.getWordBounds(context);

      return {
        from: wordBounds.from,
        to: wordBounds.to,
        options: completions.map((completion) => {
          const option = {
            label: completion.label,
            type: completion.type || "property",
            detail: completion.detail,
            boost: completion.boost || 0,
          };

          if (completion.insertText) {
            option.insertText = completion.insertText;
          }

          return option;
        }),
      };
    };
  }

  getContextualCompletions(sqlContext) {
    const completions = [];

    switch (sqlContext.contextType) {
      case "after_from":
        completions.push(...this.getTableCompletions());
        break;

      case "after_select":
      case "select_columns":
        if (sqlContext.isAfterDot && sqlContext.currentTable) {
          // User typed "table." - suggest columns for that specific table
          completions.push(
            ...this.getColumnCompletions(sqlContext.currentTable, true),
          );
        } else {
          // Suggest columns from all referenced tables, plus * and functions
          completions.push(this.getStarCompletion());
          completions.push(...this.getRelevantColumnCompletions(sqlContext));
          completions.push(...this.getFunctionCompletions());
        }
        break;

      case "after_where":
      case "where_condition":
      case "after_having":
      case "after_order_by":
      case "after_group_by":
        if (sqlContext.isAfterDot && sqlContext.currentTable) {
          completions.push(
            ...this.getColumnCompletions(sqlContext.currentTable, true),
          );
        } else {
          completions.push(...this.getRelevantColumnCompletions(sqlContext));
          completions.push(...this.getFunctionCompletions());
        }
        break;

      case "after_on":
        // JOIN ON condition - suggest columns from both tables
        completions.push(...this.getRelevantColumnCompletions(sqlContext));
        break;
    }

    return completions.filter((c) => c.label); // Remove empty labels
  }

  getTableCompletions() {
    return Object.keys(this.schema).map((tableName) => ({
      label: tableName,
      type: "class",
      detail: `Table (${this.getColumnCount(tableName)} columns)`,
      boost: 10,
    }));
  }

  getColumnCompletions(tableName, isQualified = false) {
    const columns = this.schema[tableName] || [];
    const prefix = isQualified ? `${tableName}.` : "";

    return columns.map((columnName) => ({
      label: `${prefix}${columnName}`,
      type: "property",
      detail: `Column from ${tableName}`,
      boost: isQualified ? 15 : 5,
    }));
  }

  getRelevantColumnCompletions(sqlContext) {
    const completions = [];
    const relevantTables = this.analyzer.getTablesForContext(sqlContext);

    for (const tableName of relevantTables) {
      if (this.schema[tableName]) {
        const tableColumns = this.getColumnCompletions(tableName);
        completions.push(...tableColumns);

        if (relevantTables.length > 1) {
          const qualifiedColumns = this.getColumnCompletions(tableName, true);
          completions.push(...qualifiedColumns);
        }
      }
    }

    // If no specific tables found, suggest from all available tables
    if (completions.length === 0) {
      for (const tableName of Object.keys(this.schema)) {
        completions.push(...this.getColumnCompletions(tableName));
      }
    }

    return completions;
  }

  getStarCompletion() {
    return {
      label: "*",
      type: "keyword",
      detail: "Select all columns",
      boost: 20,
    };
  }

  getFunctionCompletions() {
    return this.config.functions.map((func) => ({
      label: func.name,
      type: "function",
      detail: func.detail,
      boost: 8,
      insertText:
        func.args === ""
          ? func.name
          : func.args === "()"
            ? `${func.name}()`
            : `${func.name}(`,
    }));
  }

  getWordBounds(context) {
    const doc = context.state.doc;
    const pos = context.pos;

    let from = pos;
    let to = pos;

    // Find start of current word
    while (from > 0) {
      const char = doc.sliceString(from - 1, from);
      if (/[a-zA-Z0-9_.]/.test(char)) {
        from--;
      } else {
        break;
      }
    }

    // Find end of current word
    while (to < doc.length) {
      const char = doc.sliceString(to, to + 1);
      if (/[a-zA-Z0-9_]/.test(char)) {
        to++;
      } else {
        break;
      }
    }

    return { from, to };
  }

  getColumnCount(tableName) {
    return (this.schema[tableName] || []).length;
  }

  getTableInfo(tableName) {
    const columns = this.schema[tableName] || [];
    if (columns.length === 0) return "Empty table";

    const preview = columns.slice(0, 5).join(", ");
    const suffix =
      columns.length > 5 ? `, ... (${columns.length - 5} more)` : "";
    return `Columns: ${preview}${suffix}`;
  }

  isTypingKeyword(query, cursorPos) {
    const wordBounds = this.getWordBoundsFromString(query, cursorPos);
    const currentWord = query
      .substring(wordBounds.from, wordBounds.to)
      .toLowerCase();

    // Only suppress completions for core SQL structural keywords where
    // column suggestions mid-typing would be noise. Don't check the full
    // dialect keyword list — adapter-specific keywords (RELOAD, RENAME, etc.)
    // share prefixes with common column names and would suppress too eagerly.
    for (const keyword of STRUCTURAL_KEYWORDS) {
      if (
        keyword.startsWith(currentWord) &&
        currentWord.length > 0 &&
        currentWord.length < keyword.length
      ) {
        return true;
      }
    }

    return false;
  }

  getWordBoundsFromString(text, pos) {
    let from = pos;
    let to = pos;

    // Find start of current word
    while (from > 0) {
      const char = text.charAt(from - 1);
      if (/[a-zA-Z0-9_.]/.test(char)) {
        from--;
      } else {
        break;
      }
    }

    // Find end of current word
    while (to < text.length) {
      const char = text.charAt(to);
      if (/[a-zA-Z0-9_]/.test(char)) {
        to++;
      } else {
        break;
      }
    }

    return { from, to };
  }
}
