import { SQL_DEFAULTS } from "./defaults.js";
import {
  scan,
  tokenize,
  TYPES,
  profileFor,
  identifierName,
  isCode,
} from "./tokenizer.js";

/**
 * What the cursor is in, in a SQL statement, for autocomplete: read from
 * the tokens of the whole statement around the cursor (tokenizer.js), not
 * from the text before it, so an alias defined after the cursor counts.
 *
 * `analyzeContext(text, pos)` gives:
 *
 *   - `contextType`: "after_from" (a table goes here), "select_columns",
 *     "where_condition", "after_on", "after_group_by", "after_order_by",
 *     "after_having", "alias" (a name being given), "none" (in a string or
 *     a comment) or "unknown";
 *   - `qualifier`: the names before a `.` at the cursor (`r.` is ["r"],
 *     `public.orders.` is ["public", "orders"]), or null;
 *   - `sources`: what the statement reads, each `{name, parts, kind}`: the
 *     name it goes by (its alias, or its table's name), the table's name
 *     parts (["reporting", "orders"]), and its kind, "table", "cte" or
 *     "subquery" (a subquery's or a function's columns are unknown);
 *   - `ctes`: the statement's WITH queries, name to their columns (null when
 *     their select list is not plain names);
 *   - `word`: `{from, to}` of the word the cursor is on.
 */

const SEMICOLON = TYPES.indexOf("semicolon");

// Words that end a table reference: a name after a table is its alias
// unless it is one of these.
const NOT_ALIAS = new Set([
  "where", "join", "inner", "left", "right", "full", "outer", "cross",
  "natural", "lateral", "on", "using", "group", "order", "having", "limit",
  "offset", "union", "intersect", "except", "window", "fetch", "for", "as",
  "set", "values", "select", "from", "returning", "into", "when", "then",
  "else", "end", "and", "or", "not", "qualify", "prewhere", "sample",
  "final", "array", "settings", "format", "with", "tablesample", "partition",
]);

// Words after which a table name goes.
const TABLE_KEYWORDS = new Set(["from", "join", "into", "update", "table"]);

// The clause a keyword starts, for the cursor after it.
const CLAUSES = {
  select: "select_columns",
  where: "where_condition",
  on: "after_on",
  having: "after_having",
  from: "from",
  join: "from",
  into: "from",
  update: "from",
  set: "where_condition",
  limit: "unknown",
  offset: "unknown",
  values: "unknown",
  using: "unknown",
};

export class SqlContextAnalyzer {
  constructor(config = {}, profile = null) {
    const allKeywords = [
      ...SQL_DEFAULTS.keywords,
      ...(config.keywords || []).map((k) => k.toLowerCase()),
    ];
    this.keywords = new Set(allKeywords);
    this.contextBoundaries = new Set(
      (config.contextBoundaries || []).map((b) => b.toLowerCase()),
    );
    this.profile = profile || profileFor("sql", config.tokenizer);
  }

  analyzeContext(text, pos) {
    const { from: stmtFrom, to: stmtTo, inside } = this.locate(text, pos);
    const empty = {
      contextType: "none",
      qualifier: null,
      sources: [],
      ctes: {},
      word: { from: pos, to: pos },
    };
    if (inside) return empty;

    const slice = text.slice(stmtFrom, stmtTo);
    const tokens = tokenize(slice, this.profile)
      .filter(isCode)
      .map((t) => ({
        type: t.type,
        start: t.start + stmtFrom,
        end: t.end + stmtFrom,
        text: slice.slice(t.start, t.end),
        name: identifierName(slice, t),
        lower: t.type === "word" ? slice.slice(t.start, t.end).toLowerCase() : null,
      }));

    // The word the cursor is on, and the tokens before it.
    let before = tokens.filter((t) => t.end <= pos);
    let word = { from: pos, to: pos };
    const current = tokens.find((t) => isName(t) && t.start < pos && t.end >= pos);
    if (current) {
      word = { from: current.start, to: current.end };
      before = tokens.filter((t) => t.end <= current.start);
    }

    const ctes = this.withQueries(tokens);
    const sources = this.sources(tokens, scopeOf(tokens, pos), ctes);
    const qualifier = this.qualifierBefore(before);
    const contextType = this.clauseAt(before, qualifier);

    return { contextType, qualifier, sources, ctes, word };
  }

  // The statement the cursor is in, by the semicolons in code, and whether
  // the cursor is inside a string, quoted identifier or comment.
  locate(text, pos) {
    const { types, starts, count } = scan(text, this.profile);
    let from = 0;
    let to = text.length;
    let inside = false;

    for (let k = 0; k < count; k++) {
      const start = starts[k];
      const end = starts[k + 1];
      const type = TYPES[types[k]];

      if (types[k] === SEMICOLON) {
        if (end <= pos) {
          from = end;
        } else if (start >= pos) {
          to = start;
          break;
        }
      } else if (start < pos && pos <= end && insideToken(text, type, start, end, pos)) {
        inside = true;
      }
    }

    return { from, to, inside };
  }

  // The names before a `.` that ends the tokens before the cursor.
  qualifierBefore(before) {
    let k = before.length - 1;
    if (k < 0 || before[k].type !== "dot") return null;

    const names = [];
    while (k >= 1 && before[k].type === "dot" && isName(before[k - 1])) {
      names.unshift(before[k - 1].name);
      k -= 2;
    }
    return names.length ? names : null;
  }

  // The clause the cursor is in: the last clause keyword before it, outside
  // any parentheses closed before it.
  clauseAt(before, qualifier) {
    const n = before.length;
    // The tokens before the qualifier, if any.
    const end = qualifier ? n - qualifier.length * 2 : n;
    let depth = 0;

    for (let k = end - 1; k >= 0; k--) {
      const t = before[k];
      if (t.type === "rparen") {
        depth += 1;
        continue;
      }
      if (t.type === "lparen") {
        if (depth > 0) depth -= 1;
        continue;
      }
      if (depth > 0 || t.type !== "word") continue;

      const w = t.lower;
      if (this.contextBoundaries.has(w)) {
        return w === "prewhere" ? "where_condition" : `after_${w}`;
      }
      if (w === "by") {
        const kw = before[k - 1] && before[k - 1].lower;
        if (kw === "group") return "after_group_by";
        if (kw === "order") return "after_order_by";
        if (kw === "partition") return "select_columns";
        continue;
      }
      if (w in CLAUSES) {
        const clause = CLAUSES[w];
        return clause === "from" ? this.fromPosition(before, k, end, qualifier) : clause;
      }
    }

    return "unknown";
  }

  // In a FROM or JOIN clause: a table goes right after the keyword, after a
  // comma, or after a schema's `.`; after a table, its alias.
  fromPosition(before, keywordIndex, end, qualifier) {
    if (qualifier) return "after_from";
    const prev = before[end - 1];
    if (end - 1 === keywordIndex) return "after_from";
    if (prev.type === "comma") return "after_from";
    if (prev.type === "word" && TABLE_KEYWORDS.has(prev.lower)) return "after_from";
    if (prev.type === "word" && (prev.lower === "lateral" || prev.lower === "only")) {
      return "after_from";
    }
    if (prev.type === "word" && prev.lower === "as") return "alias";
    if (isName(prev) || prev.type === "rparen") {
      return prev.type === "word" && NOT_ALIAS.has(prev.lower) ? "unknown" : "alias";
    }
    return "unknown";
  }

  // The statement's WITH queries: name to their columns, or null.
  withQueries(tokens) {
    const ctes = {};
    let k = 0;
    if (!(tokens[k] && tokens[k].lower === "with")) return ctes;
    k += 1;
    if (tokens[k] && tokens[k].lower === "recursive") k += 1;

    while (k < tokens.length && isName(tokens[k])) {
      const name = tokens[k].name;
      k += 1;

      let columns = null;
      if (tokens[k] && tokens[k].type === "lparen") {
        const close = matching(tokens, k);
        columns = tokens
          .slice(k + 1, close)
          .filter(isName)
          .map((t) => t.name);
        k = close + 1;
      }

      if (!(tokens[k] && tokens[k].lower === "as")) break;
      k += 1;
      while (tokens[k] && (tokens[k].lower === "not" || tokens[k].lower === "materialized")) {
        k += 1;
      }
      if (!(tokens[k] && tokens[k].type === "lparen")) break;

      const close = matching(tokens, k);
      if (!columns) columns = selectListNames(tokens.slice(k + 1, close));
      ctes[name] = columns;
      k = close + 1;

      if (tokens[k] && tokens[k].type === "comma") {
        k += 1;
      } else {
        break;
      }
    }

    return ctes;
  }

  // What the query the cursor is in reads (the tokens `scope` gives, outside
  // their parentheses): each table, WITH query, subquery or function after
  // FROM or JOIN (and comma-joined ones), with its alias.
  sources(tokens, [first, last], ctes) {
    const sources = [];
    const cteNames = new Set(Object.keys(ctes));
    let depth = 0;

    for (let k = first; k < last; k++) {
      const t = tokens[k];
      if (t.type === "lparen") depth += 1;
      if (t.type === "rparen") depth -= 1;
      if (depth !== 0 || t.type !== "word") continue;
      const isFrom = t.lower === "from";
      if (!(isFrom || t.lower === "join" || t.lower === "update" || t.lower === "into")) continue;

      let i = k + 1;
      for (;;) {
        while (tokens[i] && (tokens[i].lower === "lateral" || tokens[i].lower === "only")) i += 1;
        const read = this.tableReference(tokens, i, cteNames, isFrom || t.lower === "join");
        if (!read) break;
        sources.push(read.source);
        i = read.next;
        if (isFrom && tokens[i] && tokens[i].type === "comma") {
          i += 1;
        } else {
          break;
        }
      }
    }

    return sources;
  }

  // A table reference at `i`: a (subquery), or a name with its schema, maybe
  // a function's call, and its alias.
  tableReference(tokens, i, cteNames, calls) {
    const t = tokens[i];
    if (!t) return null;

    let source;
    let k;

    if (t.type === "lparen") {
      k = matching(tokens, i) + 1;
      source = { name: null, parts: null, kind: "subquery" };
    } else if (isName(t) && !(t.type === "word" && NOT_ALIAS.has(t.lower))) {
      const parts = [t.name];
      k = i + 1;
      while (tokens[k] && tokens[k].type === "dot" && isName(tokens[k + 1])) {
        parts.push(tokens[k + 1].name);
        k += 2;
      }
      let kind = parts.length === 1 && cteNames.has(parts[0]) ? "cte" : "table";
      // A function's rows (generate_series(1, 10) g); after INTO, the
      // parentheses list columns.
      if (calls && tokens[k] && tokens[k].type === "lparen") {
        k = matching(tokens, k) + 1;
        kind = "subquery";
      }
      source = { name: parts[parts.length - 1], parts, kind };
    } else {
      return null;
    }

    // Its alias: AS name, or a name that is no keyword.
    if (tokens[k] && tokens[k].lower === "as" && isName(tokens[k + 1])) {
      source.name = tokens[k + 1].name;
      k += 2;
    } else if (
      tokens[k] &&
      isName(tokens[k]) &&
      !(tokens[k].type === "word" && (NOT_ALIAS.has(tokens[k].lower) || this.isKeyword(tokens[k].lower)))
    ) {
      source.name = tokens[k].name;
      k += 1;
    }

    // A column list after the alias: t AS x (a, b).
    if (tokens[k] && tokens[k].type === "lparen" && source.kind !== "table") {
      k = matching(tokens, k) + 1;
    }

    return { source, next: k };
  }

  isKeyword(word) {
    return this.keywords.has(word) && NOT_ALIAS.has(word);
  }
}

// The tokens of the query the cursor is in, [first, last): those of the
// innermost (SELECT …) or (WITH …) around it, or the whole statement's
// outside its WITH queries.
function scopeOf(tokens, pos) {
  // The parentheses open at the cursor.
  const open = [];
  for (let k = 0; k < tokens.length && tokens[k].start < pos; k++) {
    if (tokens[k].type === "lparen") open.push(k);
    if (tokens[k].type === "rparen") open.pop();
  }

  const scope = innermostQuery(tokens, open);
  if (scope !== null) return [scope + 1, matching(tokens, scope)];

  // The main query: after the WITH queries, if any.
  let first = 0;
  if (tokens[0] && tokens[0].lower === "with") {
    let depth = 0;
    for (let k = 0; k < tokens.length; k++) {
      if (tokens[k].type === "lparen") depth += 1;
      if (tokens[k].type === "rparen") depth -= 1;
      if (depth === 0 && tokens[k].type === "rparen") first = k + 1;
      if (depth === 0 && tokens[k].lower === "select" && k > first) break;
    }
  }
  return [first, tokens.length];
}

// Of the parentheses open at the cursor, the innermost that holds a query.
function innermostQuery(tokens, open) {
  for (let i = open.length - 1; i >= 0; i--) {
    const next = tokens[open[i] + 1];
    if (next && (next.lower === "select" || next.lower === "with")) return open[i];
  }
  return null;
}

function isName(t) {
  return t && (t.type === "word" || t.type === "quoted");
}

// The index of the ) that closes the ( at `open`, or the last token's.
function matching(tokens, open) {
  let depth = 0;
  for (let k = open; k < tokens.length; k++) {
    if (tokens[k].type === "lparen") depth += 1;
    if (tokens[k].type === "rparen") {
      depth -= 1;
      if (depth === 0) return k;
    }
  }
  return tokens.length - 1;
}

// The names of a SELECT's columns, when each is a column (`a`, `t.a`) or
// named (`… AS a`); null otherwise (`*`, an unnamed expression).
function selectListNames(tokens) {
  if (!(tokens[0] && tokens[0].lower === "select")) return null;

  let k = 1;
  if (tokens[k] && (tokens[k].lower === "distinct" || tokens[k].lower === "all")) k += 1;

  const names = [];
  let item = [];
  let depth = 0;

  const close = () => {
    const name = itemName(item);
    item = [];
    if (name === null) return false;
    names.push(name);
    return true;
  };

  for (; k < tokens.length; k++) {
    const t = tokens[k];
    if (t.type === "lparen") depth += 1;
    if (t.type === "rparen") depth -= 1;
    if (depth === 0 && t.type === "word" && t.lower === "from") break;
    if (depth === 0 && t.type === "comma") {
      if (!close()) return null;
      continue;
    }
    item.push(t);
  }

  if (!close()) return null;
  return names;
}

function itemName(item) {
  const n = item.length;
  if (n === 0) return null;
  if (n === 1 && isName(item[0])) return item[0].name;
  if (n === 3 && isName(item[0]) && item[1].type === "dot" && isName(item[2])) {
    return item[2].name;
  }
  if (n >= 3 && item[n - 2].lower === "as" && isName(item[n - 1])) return item[n - 1].name;
  return null;
}

// Whether the cursor at `pos` is inside a string, quoted identifier or
// comment that starts before it: within it, or at the end of one left open
// (a line comment runs to its line's end).
function insideToken(text, type, start, end, pos) {
  if (type === "comment") {
    return pos < end || text.charCodeAt(start + 1) !== 42 || !closedBlock(text, start, end);
  }
  if (type === "string" || type === "quoted") {
    return pos < end || !closedQuote(text, start, end);
  }
  return false;
}

function closedBlock(text, start, end) {
  return end - start >= 4 && text.charCodeAt(end - 2) === 42 && text.charCodeAt(end - 1) === 47;
}

function closedQuote(text, start, end) {
  if (end - start < 2) return false;
  const open = text.charCodeAt(start);
  const close = text.charCodeAt(end - 1);
  if (open === 91) return close === 93;
  if (open === 36) return close === 36 && end - start >= 4;
  return close === open || close === 39;
}
