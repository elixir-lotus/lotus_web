import {
  SQLDialect,
  sql,
  PostgreSQL,
  MySQL,
  SQLite,
} from "@codemirror/lang-sql";
import { SQL_DEFAULTS } from "./languages/sql/defaults.js";

// Use official CodeMirror dialects when available — they have richer
// tokenizer rules and keyword sets than SQLDialect.define() can provide.
// Fall back to SQLDialect.define() for dialects without a built-in.
const BUILTIN_DIALECTS = {
  postgres: PostgreSQL,
  postgresql: PostgreSQL,
  mysql: MySQL,
  sqlite: SQLite,
};

const cache = new Map();

export function getDialectConfig(dialectName, fetchFn) {
  if (cache.has(dialectName)) {
    return Promise.resolve(cache.get(dialectName));
  }

  return fetchFn(dialectName).then((serverConfig) => {
    const merged = mergeWithDefaults(serverConfig);
    cache.set(dialectName, merged);
    return merged;
  });
}

export function getCachedDialectConfig(dialectName) {
  return cache.get(dialectName) || null;
}

export function isJsonLanguage(dialectName) {
  return dialectName && dialectName.startsWith("json:");
}

function mergeWithDefaults(config) {
  if (!config || (config.language !== "sql" && !config.language?.startsWith("json:"))) {
    return config || emptyConfig();
  }

  // Non-SQL languages (JSON DSL, etc.) pass through without merging SQL defaults
  if (config.language && config.language.startsWith("json:")) {
    return config;
  }

  return {
    language: "sql",
    keywords: [
      ...SQL_DEFAULTS.keywords,
      ...(config.keywords || []).map((k) => k.toLowerCase()),
    ],
    types: [
      ...SQL_DEFAULTS.types,
      ...(config.types || []).map((t) => t.toLowerCase()),
    ],
    functions: [...SQL_DEFAULTS.functions, ...(config.functions || [])],
    contextBoundaries: [
      ...SQL_DEFAULTS.contextBoundaries,
      ...(config.context_boundaries || []),
    ],
  };
}

function emptyConfig() {
  return {
    language: "sql",
    keywords: [...SQL_DEFAULTS.keywords],
    types: [...SQL_DEFAULTS.types],
    functions: [...SQL_DEFAULTS.functions],
    contextBoundaries: [...SQL_DEFAULTS.contextBoundaries],
  };
}

/**
 * Resolve the CodeMirror dialect for a given dialect name and config.
 * Prefers official built-in dialects (PostgreSQL, MySQL, SQLite) for
 * richer syntax highlighting; falls back to SQLDialect.define() for
 * dialects without a built-in (e.g., ClickHouse).
 */
export function resolveCodeMirrorDialect(dialectName, config) {
  const builtin = BUILTIN_DIALECTS[dialectName];
  if (builtin) return builtin;

  // Don't put functions in `builtin` — CodeMirror's upperCaseKeywords
  // would uppercase them, breaking case-sensitive dialects like ClickHouse.
  // Our SqlCompletion handles function completions with correct casing.
  return SQLDialect.define({
    keywords: config.keywords.join(" "),
    types: config.types.join(" "),
  });
}

export function buildSqlExtension(
  config,
  schema,
  completionInstance,
  dialectName,
) {
  const dialect = resolveCodeMirrorDialect(dialectName, config);

  const cfg = {
    upperCaseKeywords: true,
    dialect,
  };
  if (schema) cfg.schema = schema;

  const sqlLang = sql(cfg);

  if (completionInstance) {
    return [
      sqlLang,
      sqlLang.language.data.of({
        autocomplete: completionInstance.createCompletionSource(),
      }),
    ];
  }

  return sqlLang;
}
