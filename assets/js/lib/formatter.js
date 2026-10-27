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
import { parseTemplate, significantTokens } from "./languages/json_dsl/parser.js";

/**
 * Language-aware formatting for the query editor.
 *
 * JSON-shaped languages get a structural pretty-print, two spaces an
 * indent, as `JSON.stringify(…, null, 2)` lays out a request, on the
 * template as Lotus reads it: `{{variables}}` (bare or in strings) and
 * `[[ ]]` blocks stay as written, and so do strings and numbers.
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
  if (content.trim() === "") return { ok: true, content: "" };

  const { errors } = parseTemplate(content);
  if (errors.length) return { ok: false, error: errors[0].message };

  return { ok: true, content: layoutJson(content) };
}

/**
 * Lay out a JSON template that parses: a line for each property and item,
 * `{}` and `[]` kept on one line, a block's `[[` on a line of its own
 * (`[[, "from": {{offset}}]]`).
 */
export function layoutJson(content) {
  const tokens = significantTokens(content);
  const raw = (t) => content.slice(t.start, t.end);
  let out = "";
  let depth = 0;
  const newline = () => {
    out = out.replace(/[ \t]+$/, "");
    out += "\n" + "  ".repeat(depth);
  };

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    const text = raw(t);
    const next = tokens[i + 1];
    const prev = tokens[i - 1];

    if (t.type === "block_open") {
      if (out.trim() !== "" && !/\n *$/.test(out)) newline();
      out += "[[";
    } else if (t.type === "block_close") {
      out += "]]";
    } else if (t.type === "operator" && (text === "{" || text === "[")) {
      const close = text === "{" ? "}" : "]";
      if (next && next.type === "operator" && raw(next) === close) {
        out += text + close;
        i += 1;
      } else {
        out += text;
        depth += 1;
        newline();
      }
    } else if (t.type === "operator" && (text === "}" || text === "]")) {
      depth = Math.max(0, depth - 1);
      newline();
      out += text;
    } else if (t.type === "comma") {
      out += ",";
      if (prev && prev.type === "block_open") out += " ";
      else if (!(next && next.type === "block_close")) newline();
    } else if (t.type === "operator" && text === ":") {
      out += ": ";
    } else {
      out += text;
    }
  }

  return out.replace(/[ \t]+$/gm, "");
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
