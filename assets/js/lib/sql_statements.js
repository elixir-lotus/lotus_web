/**
 * The statements of a SQL text, and the one under the cursor.
 *
 * Lotus runs one statement at a time, so a person who keeps several in the
 * editor runs the one they are on. A `;` ends a statement unless the
 * tokenizer (languages/sql/tokenizer.js, the server's lexical rules) finds it
 * in a string, a quoted identifier or a comment.
 */

import { scan, profileFor, TYPES } from "./languages/sql/tokenizer.js";

const SEMICOLON = TYPES.indexOf("semicolon");
const WHITESPACE = TYPES.indexOf("whitespace");
const COMMENT = TYPES.indexOf("comment");

/** The tokenizer's profile for an editor dialect name. */
export function dialectOptions(dialectName, serverProfile = null) {
  return profileFor(dialectName, serverProfile);
}

/**
 * Each statement of `text`, in order: `from` and `to` of its code (without
 * the whitespace and comments around it, or its `;`), and `start` and `end`
 * of the part of the text it owns (from after the previous `;` to its own
 * `;`). A part with only whitespace and comments has `from` and `to` null.
 * `profile` is the tokenizer's (`dialectOptions/1`); ANSI SQL without one.
 */
export function splitStatements(text, profile = undefined) {
  const statements = [];
  let start = 0;
  let from = null;
  let to = null;

  const { types, starts, count } = scan(text, profile);

  for (let k = 0; k < count; k++) {
    const type = types[k];
    if (type === SEMICOLON) {
      statements.push({ start, end: starts[k], from, to });
      start = starts[k + 1];
      from = null;
      to = null;
    } else if (type !== WHITESPACE && type !== COMMENT) {
      if (from === null) from = starts[k];
      to = starts[k + 1];
    }
  }

  statements.push({ start, end: text.length, from, to });
  return statements;
}

/**
 * The statement the cursor at `pos` is on, as `{from, to}`, or null when
 * the text has no statement. The cursor just after a `;`, or after it on
 * the same line, is on the statement the `;` ends; a cursor in a part with
 * no statement (a trailing comment) is on the one before it.
 */
export function statementAt(text, pos, options = undefined) {
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
export function countStatements(text, options = undefined) {
  return splitStatements(text, options).filter((s) => s.from !== null).length;
}

/**
 * What a run runs: `{scope, from, to, text}`.
 *
 *   - "selection": the text selected (`selection` is `{from, to}`);
 *   - "statement": the statement at the cursor, when the text has several;
 *   - "all": the whole text, as it is (`from` and `to` null).
 */
export function runTarget(text, selection, options = undefined) {
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
