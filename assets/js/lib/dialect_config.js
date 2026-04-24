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

// snake_case (Elixir) → camelCase (CodeMirror SQLDialectSpec). Unknown
// keys pass through so adapters can ship forward-compat fields without
// a frontend bump.
// See @codemirror/lang-sql/dist/index.d.ts (SQLDialectSpec) for the
// authoritative surface.
const DIALECT_SPEC_KEY_MAP = {
  identifier_quotes: "identifierQuotes",
  operator_chars: "operatorChars",
  hash_comments: "hashComments",
  slash_comments: "slashComments",
  double_quoted_strings: "doubleQuotedStrings",
  double_dollar_quoted_strings: "doubleDollarQuotedStrings",
  backslash_escapes: "backslashEscapes",
  space_after_dashes: "spaceAfterDashes",
  case_insensitive_identifiers: "caseInsensitiveIdentifiers",
  char_set_casts: "charSetCasts",
  plsql_quoting_mechanism: "plsqlQuotingMechanism",
  unquoted_bit_literals: "unquotedBitLiterals",
  treat_bits_as_bytes: "treatBitsAsBytes",
  special_var: "specialVar",
  builtin: "builtin",
};

export function toDialectSpec(spec) {
  if (!spec || typeof spec !== "object") return {};
  return Object.fromEntries(
    Object.entries(spec).map(([k, v]) => [DIALECT_SPEC_KEY_MAP[k] ?? k, v]),
  );
}

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

  // Non-SQL languages (JSON DSL, etc.) pass through without merging SQL
  // defaults. context_schema (if supplied) rides along unchanged for
  // JsonDslCompletion to consume.
  if (config.language && config.language.startsWith("json:")) {
    return config;
  }

  // Preserve the optional widened fields alongside the merged SQL
  // defaults. dialect_spec is snake_case at the server boundary; the
  // camelCase conversion happens at resolveCodeMirrorDialect so this
  // function stays a pure shape adapter.
  const merged = {
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

  if (config.dialect_spec) merged.dialect_spec = config.dialect_spec;
  if (config.context_schema) merged.context_schema = config.context_schema;

  return merged;
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
