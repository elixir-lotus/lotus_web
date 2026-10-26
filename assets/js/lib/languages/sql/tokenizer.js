/**
 * A SQL tokenizer for the editor: one pass over the text, by character
 * codes, with no regular expressions.
 *
 * Its lexical rules are those of Lotus's server-side tokenizer
 * (`Lotus.Query.Tokenizer` and `Lotus.Query.Tokenizer.Profile`): which
 * quotes make strings and quoted identifiers, which comments a dialect has,
 * Postgres's dollar quotes and nested block comments, MySQL's backslash
 * escapes, and Lotus's `{{variable}}` and `[[optional]]` blocks. A string,
 * identifier or comment left open runs to the end of the text.
 *
 * Each token is `{type, start, end}`; the tokens cover the text exactly.
 * Types: word, quoted (a quoted identifier), string, number, operator, dot,
 * comma, lparen, rparen, semicolon, comment, whitespace, variable
 * (`{{name}}`), block_open (`[[`), block_close (`]]`).
 */

// The profile of a dialect: the server's `Profile` fields, in camelCase,
// and the rules the editor applies on top of them.
//
//   stringQuotes, identifierQuotes ("[" for [bracketed] identifiers),
//   lineComments, blockComments, nestedBlockComments, dollarQuotes,
//   backslashEscapes: as `Lotus.Query.Tokenizer.Profile`;
//   escapeStrings: Postgres's E'…' strings take backslash escapes;
//   dashCommentNeedsSpace: MySQL's `--` is a comment only before a space;
//   executableComments: MySQL's /*! … *\/ is code.
const ANSI = {
  stringQuotes: ["'"],
  identifierQuotes: ['"'],
  lineComments: ["--"],
  blockComments: true,
  nestedBlockComments: false,
  dollarQuotes: false,
  backslashEscapes: false,
  escapeStrings: false,
  dashCommentNeedsSpace: false,
  executableComments: false,
};

const POSTGRES = {
  ...ANSI,
  dollarQuotes: true,
  nestedBlockComments: true,
  escapeStrings: true,
};

const MYSQL = {
  ...ANSI,
  stringQuotes: ["'", '"'],
  identifierQuotes: ["`"],
  lineComments: ["--", "#"],
  backslashEscapes: true,
  dashCommentNeedsSpace: true,
  executableComments: true,
};

const SQLITE = { ...ANSI, identifierQuotes: ['"', "`", "["] };

const PROFILES = {
  postgres: POSTGRES,
  postgresql: POSTGRES,
  mysql: MYSQL,
  mariadb: MYSQL,
  mariasql: MYSQL,
  sqlite: SQLITE,
  mssql: { ...ANSI, identifierQuotes: ['"', "["] },
  sqlserver: { ...ANSI, identifierQuotes: ['"', "["] },
};

// The server's profile fields (`Profile`, snake_case, with `?`), and the
// editor's names for them.
const SERVER_KEYS = {
  string_quotes: "stringQuotes",
  identifier_quotes: "identifierQuotes",
  line_comments: "lineComments",
  "block_comments?": "blockComments",
  "nested_block_comments?": "nestedBlockComments",
  "dollar_quotes?": "dollarQuotes",
  "backslash_escapes?": "backslashEscapes",
  "escape_strings?": "escapeStrings",
  "dash_comment_needs_space?": "dashCommentNeedsSpace",
  "executable_comments?": "executableComments",
};

/**
 * The profile for an editor dialect name ("postgres", "mysql", …), refined
 * by the server's profile for the source (`tokenizer` in its editor config),
 * when it sent one.
 */
export function profileFor(dialectName, serverProfile = null) {
  const profile = { ...(PROFILES[dialectName] || ANSI) };

  if (serverProfile && typeof serverProfile === "object") {
    for (const key in serverProfile) {
      const name = SERVER_KEYS[key] || (key in ANSI ? key : null);
      if (name && serverProfile[key] !== null && serverProfile[key] !== undefined) {
        profile[name] = serverProfile[key];
      }
    }
    // The server's ANSI profile has no [bracketed] identifiers; a dialect
    // that has them keeps them.
    const base = PROFILES[dialectName] || ANSI;
    if (base.identifierQuotes.includes("[") && !profile.identifierQuotes.includes("[")) {
      profile.identifierQuotes = [...profile.identifierQuotes, "["];
    }
  }

  return profile;
}

// Character codes.
const TAB = 9;
const LF = 10;
const SPACE = 32;
const DQUOTE = 34;
const HASH = 35;
const DOLLAR = 36;
const QUOTE = 39;
const LPAREN = 40;
const RPAREN = 41;
const STAR = 42;
const COMMA = 44;
const DASH = 45;
const DOT = 46;
const SLASH = 47;
const ZERO = 48;
const NINE = 57;
const SEMI = 59;
const UPPER_A = 65;
const UPPER_E = 69;
const UPPER_Z = 90;
const LBRACKET = 91;
const BACKSLASH = 92;
const RBRACKET = 93;
const UNDERSCORE = 95;
const BACKTICK = 96;
const LOWER_A = 97;
const LOWER_E = 101;
const LOWER_Z = 122;
const LBRACE = 123;
const RBRACE = 125;
const BANG = 33;

function isLetter(c) {
  return (c >= UPPER_A && c <= UPPER_Z) || (c >= LOWER_A && c <= LOWER_Z);
}

function isDigit(c) {
  return c >= ZERO && c <= NINE;
}

// A character of an identifier: a letter, a digit, _, $, or any non-ASCII.
export function isIdentChar(c) {
  return isLetter(c) || isDigit(c) || c === UNDERSCORE || c === DOLLAR || c > 127;
}

function isIdentStart(c) {
  return isLetter(c) || c === UNDERSCORE || c > 127;
}

function isSpace(c) {
  return c === SPACE || (c >= TAB && c <= 13) || c === 0xa0 || c === 0xfeff;
}

// One shape for every token, which keeps a megabyte's tokens cheap.
class Token {
  constructor(type, start, end) {
    this.type = type;
    this.start = start;
    this.end = end;
  }
}

// Token types, as `scan/2` stores them.
const T_WHITESPACE = 0;
const T_COMMENT = 1;
const T_WORD = 2;
const T_QUOTED = 3;
const T_STRING = 4;
const T_NUMBER = 5;
const T_OPERATOR = 6;
const T_DOT = 7;
const T_COMMA = 8;
const T_LPAREN = 9;
const T_RPAREN = 10;
const T_SEMICOLON = 11;
const T_VARIABLE = 12;
const T_BLOCK_OPEN = 13;
const T_BLOCK_CLOSE = 14;

/** The token types, by their number in `scan/2`'s `types`. */
export const TYPES = [
  "whitespace",
  "comment",
  "word",
  "quoted",
  "string",
  "number",
  "operator",
  "dot",
  "comma",
  "lparen",
  "rparen",
  "semicolon",
  "variable",
  "block_open",
  "block_close",
];

/**
 * The tokens of `text` under `profile` (see `profileFor/2`), packed: `types`
 * (numbers, see `TYPES`) and `starts`, `count` of them; a token ends where
 * the next starts, the last at the end of the text. No object per token, so
 * a megabyte scans in a few milliseconds; `tokenize/2` makes the objects.
 */
export function scan(text, profile = ANSI) {
  const p = { ...ANSI, ...profile };
  const len = text.length;
  const types = new Uint8Array(len);
  const starts = new Int32Array(len + 1);
  let count = 0;

  const stringQuote = quoteSet(p.stringQuotes);
  const identQuote = quoteSet(p.identifierQuotes);
  const hashComments = p.lineComments.includes("#");
  const dashComments = p.lineComments.includes("--");
  const slashComments = p.lineComments.includes("//");

  let i = 0;
  // Open [[ blocks, and whether a /*! … */ is open.
  let blocks = 0;
  let executable = false;

  const push = (type, start) => {
    types[count] = type;
    starts[count] = start;
    count += 1;
  };

  while (i < len) {
    const c = text.charCodeAt(i);
    const next = i + 1 < len ? text.charCodeAt(i + 1) : -1;
    const prev = i > 0 ? text.charCodeAt(i - 1) : -1;

    if (isSpace(c)) {
      let j = i + 1;
      while (j < len && isSpace(text.charCodeAt(j))) j++;
      push(T_WHITESPACE, i);
      i = j;
    } else if (
      (c === DASH && next === DASH && dashComments && dashComment(text, i + 2, p)) ||
      (c === HASH && hashComments) ||
      (c === SLASH && next === SLASH && slashComments)
    ) {
      const j = lineEnd(text, i);
      push(T_COMMENT, i);
      i = j;
    } else if (c === SLASH && next === STAR && p.blockComments) {
      if (p.executableComments && i + 2 < len && text.charCodeAt(i + 2) === BANG) {
        push(T_OPERATOR, i);
        executable = true;
        i += 3;
      } else {
        const j = blockCommentEnd(text, i + 2, p.nestedBlockComments);
        push(T_COMMENT, i);
        i = j;
      }
    } else if (c === STAR && next === SLASH && executable) {
      push(T_OPERATOR, i);
      executable = false;
      i += 2;
    } else if (c < 128 && stringQuote[c] === 1) {
      const j = quotedEnd(text, i + 1, c, p.backslashEscapes);
      push(T_STRING, i);
      i = j;
    } else if (c < 128 && identQuote[c] === 1 && c !== LBRACKET) {
      const j = quotedEnd(text, i + 1, c, false);
      push(T_QUOTED, i);
      i = j;
    } else if (c === LBRACE && next === LBRACE) {
      const j = variableEnd(text, i + 2);
      if (j > 0) {
        push(T_VARIABLE, i);
        i = j;
      } else {
        push(T_OPERATOR, i);
        i += 1;
      }
    } else if (c === LBRACKET && next === LBRACKET && blockMayOpen(prev)) {
      push(T_BLOCK_OPEN, i);
      blocks += 1;
      i += 2;
    } else if (c === RBRACKET && next === RBRACKET && blocks > 0) {
      push(T_BLOCK_CLOSE, i);
      blocks -= 1;
      i += 2;
    } else if (c === LBRACKET && identQuote[LBRACKET] === 1) {
      // A [bracketed] identifier: to the next ], with no escapes.
      let j = i + 1;
      while (j < len && text.charCodeAt(j) !== RBRACKET) j++;
      j = j < len ? j + 1 : len;
      push(T_QUOTED, i);
      i = j;
    } else if (c === DOLLAR && p.dollarQuotes && !isIdentChar(prev)) {
      const tagEnd = dollarTagEnd(text, i + 1);
      if (tagEnd > 0) {
        const tag = text.slice(i, tagEnd);
        const close = text.indexOf(tag, tagEnd);
        const j = close === -1 ? len : close + tag.length;
        push(T_STRING, i);
        i = j;
      } else {
        const j = wordEnd(text, i + 1);
        push(T_WORD, i);
        i = j;
      }
    } else if (
      (c === UPPER_E || c === LOWER_E) &&
      next === QUOTE &&
      p.escapeStrings &&
      !isIdentChar(prev)
    ) {
      // Postgres's E'…': a string with backslash escapes.
      const j = quotedEnd(text, i + 2, QUOTE, true);
      push(T_STRING, i);
      i = j;
    } else if (isIdentStart(c) || c === DOLLAR) {
      const j = wordEnd(text, i + 1);
      push(T_WORD, i);
      i = j;
    } else if (isDigit(c) || (c === DOT && isDigit(next))) {
      const j = numberEnd(text, i);
      push(T_NUMBER, i);
      i = j;
    } else if (c === DOT) {
      push(T_DOT, i);
      i += 1;
    } else if (c === COMMA) {
      push(T_COMMA, i);
      i += 1;
    } else if (c === LPAREN) {
      push(T_LPAREN, i);
      i += 1;
    } else if (c === RPAREN) {
      push(T_RPAREN, i);
      i += 1;
    } else if (c === SEMI) {
      push(T_SEMICOLON, i);
      i += 1;
    } else {
      // A character of a surrogate pair stays whole.
      const j = c >= 0xd800 && c <= 0xdbff && i + 1 < len ? i + 2 : i + 1;
      push(T_OPERATOR, i);
      i = j;
    }
  }

  starts[count] = len;
  return { types, starts, count };
}

/**
 * The tokens of `text` under `profile`, each `{type, start, end}`.
 */
export function tokenize(text, profile = ANSI) {
  const { types, starts, count } = scan(text, profile);
  const tokens = new Array(count);
  for (let k = 0; k < count; k++) {
    tokens[k] = { type: TYPES[types[k]], start: starts[k], end: starts[k + 1] };
  }
  return tokens;
}

// The ASCII quote characters of a profile, as a table by character code.
function quoteSet(quotes) {
  const table = new Uint8Array(128);
  for (const q of quotes || []) {
    if (q.length === 1 && q.charCodeAt(0) < 128) table[q.charCodeAt(0)] = 1;
  }
  return table;
}

// MySQL's `--` starts a comment only before a space, a control character or
// the end of the text (`5--1` is arithmetic).
function dashComment(text, at, profile) {
  if (!profile.dashCommentNeedsSpace) return true;
  if (at >= text.length) return true;
  const c = text.charCodeAt(at);
  return c <= SPACE;
}

// Lotus's [[ opens a block where it cannot be an array's: not after an
// identifier, a ] or a ) (`ARRAY[[1,2]]`, `arr[1][2]`).
function blockMayOpen(prev) {
  return prev === -1 || !(isIdentChar(prev) || prev === RBRACKET || prev === RPAREN);
}

function lineEnd(text, i) {
  const nl = text.indexOf("\n", i);
  return nl === -1 ? text.length : nl;
}

function blockCommentEnd(text, i, nested) {
  const len = text.length;
  let depth = 1;
  let j = i;

  while (j < len) {
    const c = text.charCodeAt(j);
    if (c === STAR && j + 1 < len && text.charCodeAt(j + 1) === SLASH) {
      depth -= 1;
      j += 2;
      if (depth === 0) return j;
    } else if (nested && c === SLASH && j + 1 < len && text.charCodeAt(j + 1) === STAR) {
      depth += 1;
      j += 2;
    } else {
      j += 1;
    }
  }

  return len;
}

// The end of a quoted string or identifier opened before `i`: after its
// closing quote, a doubled quote ('it''s') being part of it.
function quotedEnd(text, i, quote, escapes) {
  const len = text.length;
  let j = i;

  while (j < len) {
    const c = text.charCodeAt(j);
    if (escapes && c === BACKSLASH) {
      j += 2;
    } else if (c === quote) {
      if (j + 1 < len && text.charCodeAt(j + 1) === quote) {
        j += 2;
      } else {
        return j + 1;
      }
    } else {
      j += 1;
    }
  }

  return len;
}

// `{{name}}`: the end after its }}, or 0 when it is not one.
function variableEnd(text, i) {
  const len = text.length;
  if (i >= len) return 0;
  const first = text.charCodeAt(i);
  if (!(isLetter(first) || first === UNDERSCORE)) return 0;

  let j = i + 1;
  while (j < len) {
    const c = text.charCodeAt(j);
    if (isLetter(c) || isDigit(c) || c === UNDERSCORE) {
      j += 1;
    } else if (c === RBRACE && j + 1 < len && text.charCodeAt(j + 1) === RBRACE) {
      return j + 2;
    } else {
      return 0;
    }
  }
  return 0;
}

// `$$` or `$tag$` starting at the $ before `i`: the end of the tag, or 0.
function dollarTagEnd(text, i) {
  const len = text.length;
  if (i >= len) return 0;
  const first = text.charCodeAt(i);
  if (first === DOLLAR) return i + 1;
  if (!(isLetter(first) || first === UNDERSCORE)) return 0;

  let j = i + 1;
  while (j < len) {
    const c = text.charCodeAt(j);
    if (c === DOLLAR) return j + 1;
    if (!(isLetter(c) || isDigit(c) || c === UNDERSCORE)) return 0;
    j += 1;
  }
  return 0;
}

function wordEnd(text, i) {
  const len = text.length;
  let j = i;
  while (j < len && isIdentChar(text.charCodeAt(j))) j++;
  return j;
}

// Digits, a decimal point, an exponent (1e-5) and hex or binary digits
// (0x1F); letters run on so 1abc stays one token.
function numberEnd(text, i) {
  const len = text.length;
  let j = i;

  while (j < len) {
    const c = text.charCodeAt(j);
    if (isDigit(c) || isLetter(c) || c === UNDERSCORE) {
      if ((c === UPPER_E || c === LOWER_E) && j + 1 < len) {
        const n = text.charCodeAt(j + 1);
        if ((n === 43 || n === DASH) && j + 2 < len && isDigit(text.charCodeAt(j + 2))) {
          j += 3;
          continue;
        }
      }
      j += 1;
    } else if (c === DOT && j + 1 < len && isDigit(text.charCodeAt(j + 1))) {
      j += 1;
    } else if (c === DOT && !(j + 1 < len && text.charCodeAt(j + 1) === DOT)) {
      // 1. is a number
      j += 1;
    } else {
      break;
    }
  }

  return j;
}

/** The text of a token. */
export function tokenText(text, token) {
  return text.slice(token.start, token.end);
}

/** Whether a token is code the engine reads (not whitespace or a comment). */
export function isCode(token) {
  return token.type !== "whitespace" && token.type !== "comment";
}

/**
 * The name a word or quoted identifier stands for: a quoted one without its
 * quotes (doubled quotes undone), a word as written.
 */
export function identifierName(text, token) {
  const raw = text.slice(token.start, token.end);
  if (token.type !== "quoted") return raw;

  const open = raw.charCodeAt(0);
  const close = open === LBRACKET ? RBRACKET : open;
  const closed = raw.length > 1 && raw.charCodeAt(raw.length - 1) === close;
  const inner = raw.slice(1, closed ? -1 : raw.length);
  if (open === LBRACKET) return inner;
  const q = String.fromCharCode(open);
  return inner.split(q + q).join(q);
}
