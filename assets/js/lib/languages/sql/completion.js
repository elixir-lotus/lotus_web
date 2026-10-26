import { SQL_DEFAULTS } from "./defaults.js";
import { SqlContextAnalyzer } from "./context_analyzer.js";
import { profileFor } from "./tokenizer.js";

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

const COLUMN_CONTEXTS = new Set([
  "select_columns",
  "where_condition",
  "after_on",
  "after_group_by",
  "after_order_by",
  "after_having",
]);

// The most tables whose columns one completion asks the server for.
export const MAX_TABLES = 8;

// The columns the server described, by source and table, for every editor
// on the page: a table is described once.
const columnCache = new Map();

export function clearColumnCache() {
  columnCache.clear();
}

/**
 * SQL autocomplete. `schema` maps each table ("orders", or "reporting.orders"
 * when several schemas are selected) to its columns, or to null until they
 * are described; `options.fetchColumns(keys)` asks the server for them (a
 * promise of `{key: columns}`), `options.source()` names the source and
 * `options.schemas()` the selected schemas.
 */
export class SqlCompletion {
  constructor(schema, config = {}, options = {}) {
    this.schema = schema || {};
    this.config = {
      keywords: [...SQL_DEFAULTS.keywords, ...(config.keywords || [])],
      functions: [...SQL_DEFAULTS.functions, ...(config.functions || [])],
      contextBoundaries: [
        ...SQL_DEFAULTS.contextBoundaries,
        ...(config.contextBoundaries || []),
      ],
    };
    this.options = options;
    this.analyzer = new SqlContextAnalyzer(
      this.config,
      options.profile || profileFor(options.dialect || "sql", config.tokenizer),
    );
    this.pending = new Map();
  }

  updateSchema(newSchema) {
    this.schema = newSchema || {};
  }

  source() {
    const source = this.options.source;
    return (typeof source === "function" ? source() : source) || "";
  }

  selectedSchemas() {
    const schemas = this.options.schemas;
    return (typeof schemas === "function" ? schemas() : schemas) || [];
  }

  createCompletionSource() {
    return (context) => this.complete(context.state.doc.toString(), context.pos);
  }

  /**
   * The completions at `pos`: `{from, to, options}`, null, or a promise of
   * one while the columns of the statement's tables load.
   */
  complete(text, pos) {
    if (this.isTypingKeyword(text, pos)) return null;

    const analysis = this.analyzer.analyzeContext(text, pos);
    const missing = this.missingColumns(analysis);

    if (missing.length && this.options.fetchColumns) {
      return this.load(missing).then(() => this.result(analysis));
    }

    return this.result(analysis);
  }

  result(analysis) {
    const completions = this.getContextualCompletions(analysis).filter((c) => c.label);
    if (completions.length === 0) return null;

    return {
      from: analysis.word.from,
      to: analysis.word.to,
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
  }

  getContextualCompletions(analysis) {
    if (analysis.qualifier) return this.qualifiedCompletions(analysis);

    const type = analysis.contextType;
    if (type === "after_from") {
      return [...this.getTableCompletions(), ...this.cteCompletions(analysis)];
    }
    if (!COLUMN_CONTEXTS.has(type)) return [];

    const completions = [];
    if (type === "select_columns") completions.push(this.getStarCompletion());
    completions.push(...this.sourceColumnCompletions(analysis));
    if (type !== "after_on") completions.push(...this.getFunctionCompletions());
    return completions;
  }

  // After `x.`: the columns of the table or alias x, or the tables of the
  // schema x; after `s.t.`, the columns of s.t.
  qualifiedCompletions(analysis) {
    const target = this.resolveQualifier(analysis.qualifier, analysis);
    if (!target) return [];

    if (target.tables) {
      return target.tables.map((key) => ({
        label: key.slice(key.indexOf(".") + 1),
        type: "class",
        detail: this.tableDetail(key),
        boost: 10,
      }));
    }

    const columns = target.key ? this.columnsOf(target.key) : target.columns;
    return (columns || []).map((column) => ({
      label: column,
      type: "property",
      detail: `Column from ${target.label}`,
      boost: 15,
    }));
  }

  // What a qualifier names, in this order: a source of the statement by its
  // alias or name, a WITH query, a table, a schema.
  resolveQualifier(names, analysis) {
    if (names.length >= 2) {
      const key = this.tableKey(names.slice(-2));
      return key ? { key, label: key } : null;
    }

    const name = names[0];
    const source = findByName(analysis.sources, name);
    const target = source && this.sourceTarget(source, analysis);
    if (target) return target;

    if (name in analysis.ctes) {
      return { columns: analysis.ctes[name] || [], label: name };
    }

    const key = this.tableKey([name]);
    if (key) return { key, label: key };

    const tables = this.schemaTables(name);
    return tables ? { tables } : null;
  }

  sourceTarget(source, analysis) {
    if (source.kind === "cte") {
      return { columns: analysis.ctes[source.parts[0]] || [], label: source.parts[0] };
    }
    if (source.kind === "subquery") return { columns: [], label: source.name };

    const key = this.tableKey(source.parts);
    return key ? { key, label: key } : null;
  }

  // The schema's key for a table's name parts (["orders"], ["reporting",
  // "orders"]): exact, then without regard to case (an unquoted name).
  tableKey(parts) {
    const keys = Object.keys(this.schema);
    const table = parts[parts.length - 1];

    if (parts.length >= 2) {
      const schemaName = parts[parts.length - 2];
      const qualified = findKey(keys, `${schemaName}.${table}`);
      if (qualified) return qualified;
      const selected = this.selectedSchemas().some(
        (s) => s.toLowerCase() === schemaName.toLowerCase(),
      );
      return selected ? findKey(keys, table) : null;
    }

    return (
      findKey(keys, table) ||
      keys.find((k) => k.endsWith(`.${table}`)) ||
      keys.find((k) => k.toLowerCase().endsWith(`.${table.toLowerCase()}`)) ||
      null
    );
  }

  // The tables of a schema, or null when no schema has that name.
  schemaTables(name) {
    const lower = name.toLowerCase();
    const keys = Object.keys(this.schema);
    const qualified = keys.filter((k) => k.toLowerCase().startsWith(`${lower}.`));
    if (qualified.length) return qualified;

    const selected = this.selectedSchemas();
    if (selected.length === 1 && selected[0].toLowerCase() === lower) return keys;
    return null;
  }

  columnsOf(key) {
    const known = this.schema[key];
    if (Array.isArray(known)) return known;
    return columnCache.get(this.cacheKey(key)) || null;
  }

  cacheKey(key) {
    return `${this.source()}\u0000${key}`;
  }

  // The tables of the statement (or of the qualifier) whose columns are not
  // known yet.
  missingColumns(analysis) {
    const keys = new Set();

    if (analysis.qualifier) {
      const target = this.resolveQualifier(analysis.qualifier, analysis);
      if (target && target.key) keys.add(target.key);
    } else if (COLUMN_CONTEXTS.has(analysis.contextType)) {
      for (const source of analysis.sources) {
        if (source.kind !== "table") continue;
        const key = this.tableKey(source.parts);
        if (key) keys.add(key);
      }
    }

    return [...keys]
      .filter((key) => this.columnsOf(key) === null && !this.pending.has(key))
      .slice(0, MAX_TABLES);
  }

  // Asks the server for the columns of `keys`, once a table; a table it
  // does not describe has none.
  load(keys) {
    const request = Promise.resolve(this.options.fetchColumns(keys))
      .then((columns) => {
        for (const key of keys) {
          const list = columns && Array.isArray(columns[key]) ? columns[key] : [];
          columnCache.set(this.cacheKey(key), list);
        }
      })
      .catch(() => {})
      .finally(() => keys.forEach((key) => this.pending.delete(key)));

    keys.forEach((key) => this.pending.set(key, request));
    return request;
  }

  getTableCompletions() {
    return Object.keys(this.schema).map((tableName) => ({
      label: tableName,
      type: "class",
      detail: this.tableDetail(tableName),
      boost: 10,
    }));
  }

  tableDetail(key) {
    const columns = this.columnsOf(key);
    return columns ? `Table (${columns.length} columns)` : "Table";
  }

  cteCompletions(analysis) {
    return Object.keys(analysis.ctes).map((name) => ({
      label: name,
      type: "class",
      detail: "WITH query",
      boost: 12,
    }));
  }

  // The columns of the statement's sources; qualified by each source's name
  // too when it reads several. With no source, every known column.
  sourceColumnCompletions(analysis) {
    const sources = analysis.sources
      .map((source) => ({ source, target: this.sourceTarget(source, analysis) }))
      .filter(({ target }) => target);

    if (sources.length === 0) {
      return Object.keys(this.schema).flatMap((key) =>
        (this.columnsOf(key) || []).map((column) => ({
          label: column,
          type: "property",
          detail: `Column from ${key}`,
          boost: 5,
        })),
      );
    }

    const completions = [];
    const seen = new Set();

    for (const { source, target } of sources) {
      const columns = target.key ? this.columnsOf(target.key) || [] : target.columns;
      for (const column of columns) {
        if (!seen.has(column)) {
          seen.add(column);
          completions.push({
            label: column,
            type: "property",
            detail: `Column from ${target.label}`,
            boost: 5,
          });
        }
        if (sources.length > 1 && source.name) {
          completions.push({
            label: `${source.name}.${column}`,
            type: "property",
            detail: `Column from ${target.label}`,
            boost: 4,
          });
        }
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

    while (from > 0 && /[a-zA-Z0-9_.]/.test(text.charAt(from - 1))) from--;
    while (to < text.length && /[a-zA-Z0-9_]/.test(text.charAt(to))) to++;

    return { from, to };
  }
}

function findKey(keys, name) {
  if (keys.includes(name)) return name;
  const lower = name.toLowerCase();
  return keys.find((k) => k.toLowerCase() === lower) || null;
}

function findByName(sources, name) {
  return (
    sources.find((s) => s.name === name) ||
    sources.find((s) => s.name && s.name.toLowerCase() === name.toLowerCase()) ||
    null
  );
}
