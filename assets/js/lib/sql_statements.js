/**
 * The statements of a SQL text, and the one under the cursor.
 *
 * Lotus runs one statement at a time, so a person who keeps several in the
 * editor runs the one they are on. A `;` ends a statement unless it is in a
 * string ('…', "…", `…`, $$…$$, $tag$…$tag$) or a comment (-- …, /* … *\/,
 * and # … in MySQL).
 */

// How each SQL dialect writes strings and comments, by the dialect name the
// editor has (see dialect_config.js).
const MYSQL = { backslashEscapes: true, hashComments: true, dollarQuotes: false };
const POSTGRES = { nestedComments: true };

const DIALECTS = {
  postgres: POSTGRES,
  postgresql: POSTGRES,
  mysql: MYSQL,
  mariadb: MYSQL,
  mariasql: MYSQL,
  clickhouse: { backslashEscapes: true, dollarQuotes: false },
};

const DEFAULTS = {
  backslashEscapes: false,
  hashComments: false,
  dollarQuotes: true,
  nestedComments: false,
};

export function dialectOptions(dialectName) {
  return { ...DEFAULTS, ...(DIALECTS[dialectName] || {}) };
}

const IDENT_CHAR = /[A-Za-z0-9_$]/;
const DOLLAR_TAG = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/;

/**
 * Each statement of `text`, in order: `from` and `to` of its code (without
 * the whitespace around it or its `;`), and `start` and `end` of the part of
 * the text it owns (from after the previous `;` to its own `;`). A part with
 * only whitespace and comments has `from` and `to` null.
 */
export function splitStatements(text, options = {}) {
  const opts = { ...DEFAULTS, ...options };
  const statements = [];
  const len = text.length;

  let start = 0;
  let from = null;
  let to = null;
  let i = 0;

  const code = (s, e) => {
    if (from === null) from = s;
    to = e;
  };

  while (i < len) {
    const ch = text[i];
    const next = text[i + 1];

    if (ch === ";") {
      statements.push({ start, end: i, from, to });
      start = i + 1;
      from = null;
      to = null;
      i += 1;
    } else if (ch === "-" && next === "-") {
      i = lineEnd(text, i);
    } else if (ch === "#" && opts.hashComments) {
      i = lineEnd(text, i);
    } else if (ch === "/" && next === "*") {
      i = blockCommentEnd(text, i, opts.nestedComments);
    } else if (ch === "'" || ch === '"' || ch === "`") {
      const escapes = opts.backslashEscapes || (ch === "'" && escapeString(text, i));
      const end = quotedEnd(text, i, ch, escapes && ch !== "`");
      code(i, end);
      i = end;
    } else if (ch === "$" && opts.dollarQuotes && !IDENT_CHAR.test(text[i - 1] || "")) {
      const tag = text.slice(i).match(DOLLAR_TAG);
      if (tag) {
        const close = text.indexOf(tag[0], i + tag[0].length);
        const end = close === -1 ? len : close + tag[0].length;
        code(i, end);
        i = end;
      } else {
        code(i, i + 1);
        i += 1;
      }
    } else if (/\s/.test(ch)) {
      i += 1;
    } else {
      code(i, i + 1);
      i += 1;
    }
  }

  statements.push({ start, end: len, from, to });
  return statements;
}

// Postgres's E'…' strings take backslash escapes.
function escapeString(text, i) {
  const prev = text[i - 1];
  return (prev === "E" || prev === "e") && !IDENT_CHAR.test(text[i - 2] || "");
}

function lineEnd(text, i) {
  const nl = text.indexOf("\n", i);
  return nl === -1 ? text.length : nl;
}

function blockCommentEnd(text, i, nested) {
  let depth = 1;
  let j = i + 2;

  while (j < text.length) {
    if (text[j] === "*" && text[j + 1] === "/") {
      depth -= 1;
      j += 2;
      if (depth === 0 || !nested) return j;
    } else if (nested && text[j] === "/" && text[j + 1] === "*") {
      depth += 1;
      j += 2;
    } else {
      j += 1;
    }
  }

  return text.length;
}

// The end of a quoted string or identifier: its closing quote, a doubled
// quote ('it''s') being part of it.
function quotedEnd(text, i, quote, escapes) {
  let j = i + 1;

  while (j < text.length) {
    const ch = text[j];
    if (escapes && ch === "\\") {
      j += 2;
    } else if (ch === quote) {
      if (text[j + 1] === quote) {
        j += 2;
      } else {
        return j + 1;
      }
    } else {
      j += 1;
    }
  }

  return text.length;
}

/**
 * The statement the cursor at `pos` is on, as `{from, to}`, or null when
 * the text has no statement. The cursor just after a `;`, or after it on
 * the same line, is on the statement the `;` ends; a cursor in a part with
 * no statement (a trailing comment) is on the one before it.
 */
export function statementAt(text, pos, options = {}) {
  const statements = splitStatements(text, options);
  const index = statements.findIndex((s) => pos >= s.start && pos <= s.end);
  if (index === -1) return null;

  const current = statements[index];
  const previous = previousStatement(statements, index);

  if (current.from !== null) {
    const leading = pos < current.from;
    const sameLine = !text.slice(current.start, pos).includes("\n");
    if (leading && sameLine && previous) return range(previous);
    return range(current);
  }

  if (previous) return range(previous);

  const following = statements.slice(index + 1).find((s) => s.from !== null);
  return following ? range(following) : null;
}

function previousStatement(statements, index) {
  for (let i = index - 1; i >= 0; i--) {
    if (statements[i].from !== null) return statements[i];
  }
  return null;
}

function range(statement) {
  return { from: statement.from, to: statement.to };
}

/** How many statements `text` has. */
export function countStatements(text, options = {}) {
  return splitStatements(text, options).filter((s) => s.from !== null).length;
}

/**
 * What a run runs: `{scope, from, to, text}`.
 *
 *   - "selection": the text selected (`selection` is `{from, to}`);
 *   - "statement": the statement at the cursor, when the text has several;
 *   - "all": the whole text, as it is (`from` and `to` null).
 */
export function runTarget(text, selection, options = {}) {
  if (selection && selection.to > selection.from) {
    const selected = text.slice(selection.from, selection.to);
    if (selected.trim() !== "") {
      const lead = selected.length - selected.trimStart().length;
      const trail = selected.length - selected.trimEnd().length;
      const from = selection.from + lead;
      const to = selection.to - trail;
      return { scope: "selection", from, to, text: text.slice(from, to) };
    }
  }

  if (countStatements(text, options) > 1) {
    const pos = selection ? selection.head ?? selection.to : 0;
    const statement = statementAt(text, pos, options);
    if (statement) {
      return { scope: "statement", ...statement, text: text.slice(statement.from, statement.to) };
    }
  }

  return { scope: "all", from: null, to: null, text };
}
