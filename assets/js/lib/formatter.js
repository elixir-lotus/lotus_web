import {
  formatDialect,
  sql,
  postgresql,
  mysql,
  mariadb,
  sqlite,
  clickhouse,
  duckdb,
  transactsql,
  plsql,
} from "sql-formatter";

/**
 * Language-aware formatting for the query editor.
 *
 * JSON-shaped languages get a structural pretty-print: the same
 * transformation Chrome's "Pretty print" applies to a raw response.
 *
 * SQL gets a formatter (sql-formatter), in the dialect of the source. SQL is
 * whitespace-agnostic, so a formatter has to invent line breaks and
 * indentation, which is why SQL was left out at first. People keep long
 * statements, pasted from logs or written on one line, that they want to read,
 * so the editor now formats them too: keywords keep their case, and Lotus's
 * `{{variables}}` and `[[optional clauses]]` stay exactly as written.
 *
 * `supportsFormatting(dialectName)` gates the UI affordance; the server
 * offers it only for SQL and JSON sources.
 */

// The editor's dialect names (see dialect_config.js) and sql-formatter's.
const SQL_DIALECTS = {
  postgres: postgresql,
  postgresql: postgresql,
  mysql: mysql,
  mariadb: mariadb,
  mariasql: mariadb,
  sqlite: sqlite,
  clickhouse: clickhouse,
  duckdb: duckdb,
  mssql: transactsql,
  sqlserver: transactsql,
  tsql: transactsql,
  oracle: plsql,
  plsql: plsql,
};

const VARIABLE = /\{\{\s*\w+\s*\}\}/g;
const OPTIONAL = /\[\[[\s\S]*?\]\]/g;

export function supportsFormatting(dialectName) {
  return typeof dialectName === "string" && dialectName !== "";
}

function isJson(dialectName) {
  return dialectName.startsWith("json:");
}

/**
 * Format `content` using the formatter for `dialectName`.
 *
 * Returns `{ ok: true, content }` on success, `{ ok: false, error }` on
 * parse failure or when no formatter applies. Callers show `error` in a
 * toast; the editor content is left untouched on failure.
 */
export function format(content, dialectName) {
  if (!supportsFormatting(dialectName)) {
    return { ok: false, error: "formatting not supported for this source" };
  }

  if (isJson(dialectName)) {
    return formatJson(content);
  }

  return formatSql(content, dialectName);
}

function formatJson(content) {
  const trimmed = content.trim();
  if (trimmed === "") return { ok: true, content: "" };

  try {
    const parsed = JSON.parse(trimmed);
    return { ok: true, content: JSON.stringify(parsed, null, 2) };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

/**
 * Format SQL in the dialect `dialectName` (plain SQL for one sql-formatter
 * does not know).
 *
 * An optional clause (`[[AND status = {{status}}]]`) is set aside as a
 * placeholder variable, which the formatter keeps as one token, and put back
 * as it was written; brackets mean other things in some dialects (SQLite's
 * quoted identifiers, Postgres's arrays).
 */
export function formatSql(content, dialectName) {
  if (content.trim() === "") return { ok: true, content };

  const optionals = [];
  const tag = placeholderTag(content);
  const protectedSql = content.replace(OPTIONAL, (clause) => {
    optionals.push(clause);
    return `{{${tag}${optionals.length - 1}}}`;
  });

  let formatted;
  try {
    formatted = formatDialect(protectedSql, {
      dialect: SQL_DIALECTS[dialectName] || sql,
      keywordCase: "preserve",
      paramTypes: { custom: [{ regex: String.raw`\{\{\s*\w+\s*\}\}` }] },
    });
  } catch (err) {
    return { ok: false, error: shortError(err) };
  }

  let restored = formatted;
  for (let i = 0; i < optionals.length; i++) {
    const placeholder = `{{${tag}${i}}}`;
    if (!restored.includes(placeholder)) {
      return { ok: false, error: "an optional clause was lost" };
    }
    restored = restored.replace(placeholder, () => optionals[i]);
  }

  if (!sameVariables(content, restored)) {
    return { ok: false, error: "a variable was changed" };
  }

  return { ok: true, content: restored };
}

// A placeholder name the text does not have already.
function placeholderTag(content) {
  let tag = "lotus_optional_";
  while (content.includes(tag)) tag = `_${tag}`;
  return tag;
}

function sameVariables(before, after) {
  const list = (text) => (text.match(VARIABLE) || []).sort().join("\n");
  return list(before) === list(after);
}

// sql-formatter's parse errors go on for many lines; the first says where.
function shortError(err) {
  const message = (err && err.message) || String(err);
  return message.split("\n")[0].trim();
}
