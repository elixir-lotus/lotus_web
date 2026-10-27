/**
 * A JSON query template, read as Lotus reads it.
 *
 * Lotus runs a JSON source's statement (an Elasticsearch search request)
 * through its tokenizer with the JSON profile: `{{name}}` is a variable in
 * code and inside strings, and `[[ … ]]` is an optional block, kept when its
 * variables have values and dropped when they do not, where no single `[`
 * is open. The Elasticsearch adapter then binds each variable (a bare
 * `{{n}}`, or a string that is only `"{{n}}"`, to the value's JSON literal;
 * one inside a longer string to its text) and decodes the request as JSON.
 *
 * `parseTemplate` reads the template the same way, with the editor's copy
 * of Lotus's tokenizer, and gives back a tree of the request with positions
 * in the text, and the errors Lotus would meet: with the blocks kept (every
 * variable given) and with them dropped (none given). A variable is a
 * value; a string is a key or a value. The tree is built from any text, so
 * completion can read it while the request is being typed.
 */
import { tokenize, JSON_PROFILE, profileFor } from "../sql/tokenizer.js";

/** The tokenizer's profile for a JSON language, refined by the server's. */
export function jsonProfile(serverProfile = null) {
  return serverProfile ? profileFor("json", serverProfile) : JSON_PROFILE;
}

/**
 * The template's tokens, without whitespace, each `{type, start, end}`:
 * string, number, word, variable, block_open, block_close, comma, and an
 * operator (one character) for the rest.
 */
export function significantTokens(text, profile = JSON_PROFILE) {
  const out = [];
  for (const t of tokenize(text, profile)) {
    if (t.type === "whitespace" || t.type === "comment") continue;
    if (t.type === "operator" && t.end - t.start > 1 && text.charCodeAt(t.start) < 0xd800) {
      // A `[[` that opens no block: two brackets.
      for (let k = t.start; k < t.end; k++) out.push({ type: "operator", start: k, end: k + 1 });
    } else {
      out.push(t);
    }
  }
  return out;
}

/**
 * The tokens the request has when every block is kept (`mode: "kept"`) or
 * dropped (`mode: "dropped"`): the block markers go, and with "dropped",
 * what is between them.
 */
export function tokensFor(tokens, mode) {
  const out = [];
  let depth = 0;
  for (const token of tokens) {
    if (token.type === "block_open") {
      depth += 1;
      continue;
    }
    if (token.type === "block_close") {
      depth = Math.max(0, depth - 1);
      continue;
    }
    if (mode === "dropped" && depth > 0) continue;
    out.push(token);
  }
  return out;
}

/**
 * Parse `text`. Returns `{root, errors, warnings, hasBlocks}`, `root` being
 * the request as kept (null for an empty text), `errors` what makes Lotus
 * refuse it (`{from, to, message}`), with the blocks kept or dropped.
 */
export function parseTemplate(text, profile = JSON_PROFILE) {
  const tokens = significantTokens(text, profile);
  const hasBlocks = tokens.some((t) => t.type === "block_open");

  const kept = parseTokens(text, tokensFor(tokens, "kept"));
  const errors = [...kept.errors];
  const warnings = [...kept.warnings];

  if (hasBlocks) {
    const dropped = parseTokens(text, tokensFor(tokens, "dropped"));
    const seen = new Set(errors.map(errorKey));
    for (const error of dropped.errors) {
      if (seen.has(errorKey(error))) continue;
      errors.push({ ...error, message: `${error.message} (with the optional blocks left out)` });
    }
  }

  return { root: kept.root, errors, warnings, hasBlocks, tokens };
}

function errorKey(e) {
  return `${e.from}:${e.to}:${e.message}`;
}

const NUMBER = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$/;

/**
 * Parse a list of significant tokens into a tree.
 *
 * Nodes are `{kind, from, to}` with, by kind:
 *   object: members [{key, colon, value, from, end}], closed
 *     (a member's key is {from, to, name, variable, quoted}; `end` is where
 *     the member ends: its comma or the object's close)
 *   array: items [node], closed
 *   string: name (the decoded text, when it decodes); number; literal;
 *   variable: name; invalid
 */
export function parseTokens(text, tokens) {
  const p = new Parser(text, tokens);
  if (tokens.length === 0) return { root: null, errors: [], warnings: [] };

  const root = p.value();
  if (p.i < tokens.length) {
    const t = tokens[p.i];
    p.error(t.start, text.length, "Unexpected text after the end of the request");
  }
  if (root && root.kind !== "object" && root.kind !== "invalid") {
    p.error(root.from, root.to, "The request must be a JSON object, in { }");
  }
  return { root, errors: p.errors, warnings: p.warnings };
}

class Parser {
  constructor(text, tokens) {
    this.text = text;
    this.tokens = tokens;
    this.i = 0;
    this.errors = [];
    this.warnings = [];
  }

  peek() {
    return this.tokens[this.i];
  }

  raw(t) {
    return this.text.slice(t.start, t.end);
  }

  is(t, ch) {
    return t && t.type !== "string" && t.type !== "variable" && this.raw(t) === ch;
  }

  error(from, to, message) {
    this.errors.push({ from, to: Math.max(to, from + 1), message });
  }

  value() {
    const t = this.peek();
    if (!t) {
      this.error(this.text.length, this.text.length, "Expected a value");
      return null;
    }

    const raw = this.raw(t);

    if (t.type === "string") {
      this.i += 1;
      return this.string(t);
    }
    if (t.type === "variable") {
      this.i += 1;
      return { kind: "variable", from: t.start, to: t.end, name: raw.slice(2, -2) };
    }
    if (t.type === "number") {
      this.i += 1;
      return this.number(t.start, t.end);
    }
    if (raw === "-") {
      const next = this.tokens[this.i + 1];
      if (next && next.type === "number" && next.start === t.end) {
        this.i += 2;
        return this.number(t.start, next.end);
      }
    }
    if (t.type === "word") {
      this.i += 1;
      if (raw === "true" || raw === "false" || raw === "null") {
        return { kind: "literal", from: t.start, to: t.end, value: raw };
      }
      this.error(t.start, t.end, `Unexpected '${raw}': a string takes double quotes`);
      return { kind: "invalid", from: t.start, to: t.end, word: raw };
    }
    if (raw === "{" && this.text[t.end] === "{") {
      // `{{ x }}` or `{{1x}}`: a variable Lotus does not read as one.
      const close = this.text.indexOf("}}", t.end);
      const end = close === -1 ? t.end + 1 : close + 2;
      this.error(t.start, end, "A variable is {{name}}: a letter or _, then letters, digits or _");
      while (this.i < this.tokens.length && this.tokens[this.i].start < end) this.i += 1;
      return { kind: "invalid", from: t.start, to: end };
    }
    if (raw === "{") return this.object();
    if (raw === "[") return this.array();

    this.i += 1;
    this.error(t.start, t.end, this.unexpected(t));
    return { kind: "invalid", from: t.start, to: t.end };
  }

  // What a token where a comma goes is: a comment, or a missing comma.
  notSeparator(t, message) {
    const raw = this.raw(t);
    const next = this.text[t.end];
    if (raw === "/" && (next === "/" || next === "*")) return "Comments are not allowed in JSON";
    return message;
  }

  unexpected(t) {
    const raw = this.raw(t);
    const next = this.text[t.end];
    if (raw === "/" && (next === "/" || next === "*")) return "Comments are not allowed in JSON";
    if (raw === "'") return "Strings take double quotes";
    if (raw === "{" && next === "{") {
      return "A variable is {{name}}: a letter or _, then letters, digits or _";
    }
    return `Unexpected '${raw}'`;
  }

  string(t) {
    const raw = this.raw(t);
    const node = { kind: "string", from: t.start, to: t.end, raw };
    const closed = raw.length >= 2 && raw.endsWith('"') && !escapedAt(raw, raw.length - 1);

    if (!closed) {
      this.error(t.start, t.end, "The string is never closed");
      return node;
    }

    for (let k = 1; k < raw.length - 1; k++) {
      const c = raw.charCodeAt(k);
      if (c < 0x20) {
        this.error(t.start + k, t.start + k + 1, "A line break or tab in a string must be escaped (\\n, \\t)");
        return node;
      }
      if (c === 92) {
        const e = raw[k + 1];
        if (e === "u") {
          if (!/^[0-9a-fA-F]{4}$/.test(raw.slice(k + 2, k + 6))) {
            this.error(t.start + k, t.start + k + 2, "\\u takes four hex digits");
            return node;
          }
          k += 5;
        } else if ('"\\/bfnrt'.includes(e)) {
          k += 1;
        } else {
          this.error(t.start + k, t.start + k + 2, `Invalid escape '\\${e}'`);
          return node;
        }
      }
    }

    try {
      node.name = JSON.parse(raw);
    } catch {
      node.name = raw.slice(1, -1);
    }
    return node;
  }

  number(from, to) {
    const raw = this.text.slice(from, to);
    if (!NUMBER.test(raw)) this.error(from, to, `'${raw}' is not a JSON number`);
    return { kind: "number", from, to, raw };
  }

  object() {
    const open = this.peek();
    this.i += 1;
    const node = { kind: "object", from: open.start, to: this.text.length, members: [], closed: false };
    const names = new Map();

    for (;;) {
      const t = this.peek();
      if (!t) {
        this.error(open.start, open.end, "This { is never closed");
        return node;
      }
      if (this.is(t, "}")) {
        this.i += 1;
        node.to = t.end;
        node.closed = true;
        return node;
      }
      if (this.is(t, "]")) {
        this.error(t.start, t.end, "Expected '}' to close the object, not ']'");
        node.to = t.start;
        return node;
      }

      const member = this.member(t);
      node.members.push(member);
      if (member.key && member.key.name !== undefined && !member.key.variable) {
        const first = names.get(member.key.name);
        if (first !== undefined) {
          this.warnings.push({
            from: member.key.from,
            to: member.key.to,
            message: `Duplicate key "${member.key.name}": only one of them is sent`,
          });
        } else {
          names.set(member.key.name, member);
        }
      }

      const after = this.peek();
      if (!after) continue;
      if (this.is(after, ",")) {
        member.end = after.start;
        this.i += 1;
        const next = this.peek();
        if (next && this.is(next, "}")) {
          this.error(after.start, after.end, "Trailing comma: JSON takes none after the last property");
        }
      } else if (this.is(after, "}")) {
        member.end = after.start;
      } else {
        member.end = after.start;
        this.error(after.start, after.end, this.notSeparator(after, "Expected ',' or '}' after the property"));
        if (!this.startsKey(after)) {
          this.i += 1;
          if (this.is(after, "]")) node.to = after.start;
        }
      }
    }
  }

  startsKey(t) {
    return t.type === "string" || t.type === "variable" || t.type === "word";
  }

  member(t) {
    const member = { key: null, colon: null, value: null, from: t.start, end: this.text.length };
    const raw = this.raw(t);

    if (t.type === "string") {
      this.i += 1;
      const s = this.string(t);
      member.key = { from: t.start, to: t.end, name: s.name, quoted: true };
    } else if (t.type === "variable") {
      this.i += 1;
      member.key = { from: t.start, to: t.end, name: raw.slice(2, -2), variable: true };
    } else if (t.type === "word" || t.type === "number") {
      this.i += 1;
      member.key = { from: t.start, to: t.end, name: raw, bare: true };
      this.error(t.start, t.end, "A property name takes double quotes");
    } else if (this.is(t, ",")) {
      this.error(t.start, t.end, "Expected a property name before ','");
      return member;
    } else {
      this.i += 1;
      this.error(t.start, t.end, `Expected a property name, not '${raw}'`);
      return member;
    }

    const colon = this.peek();
    if (colon && this.is(colon, ":")) {
      member.colon = colon.start;
      this.i += 1;
    } else {
      this.error(member.key.to, member.key.to, "Expected ':' after the property name");
      if (!colon || this.is(colon, ",") || this.is(colon, "}")) return member;
    }

    const next = this.peek();
    if (!next || this.is(next, ",") || this.is(next, "}")) {
      this.error(member.colon ?? member.key.to, (member.colon ?? member.key.to) + 1, "Expected a value");
      return member;
    }
    member.value = this.value();
    return member;
  }

  array() {
    const open = this.peek();
    this.i += 1;
    const node = { kind: "array", from: open.start, to: this.text.length, items: [], closed: false };

    for (;;) {
      const t = this.peek();
      if (!t) {
        this.error(open.start, open.end, "This [ is never closed");
        return node;
      }
      if (this.is(t, "]")) {
        this.i += 1;
        node.to = t.end;
        node.closed = true;
        return node;
      }
      if (this.is(t, "}")) {
        this.error(t.start, t.end, "Expected ']' to close the array, not '}'");
        node.to = t.start;
        return node;
      }
      if (this.is(t, ",")) {
        this.i += 1;
        this.error(t.start, t.end, "Expected a value before ','");
        continue;
      }

      const item = this.value();
      if (item) node.items.push(item);

      const after = this.peek();
      if (!after) continue;
      if (this.is(after, ",")) {
        this.i += 1;
        const next = this.peek();
        if (next && this.is(next, "]")) {
          this.error(after.start, after.end, "Trailing comma: JSON takes none after the last item");
        }
      } else if (!this.is(after, "]")) {
        if (this.is(after, "[") && this.is(this.tokens[this.i + 1], "[") &&
            this.tokens[this.i + 1].start === after.end) {
          this.error(
            after.start,
            after.end + 1,
            "Lotus reads [[ ]] as an optional block only outside an array: make the clause an object member, as [[, \"must\": {…}]]",
          );
        } else {
          this.error(after.start, after.end, this.notSeparator(after, "Expected ',' or ']' after the item"));
        }
        if (this.is(after, "}")) {
          node.to = after.start;
          return node;
        }
        if (!(after.type === "string" || after.type === "number" || after.type === "variable" ||
              this.is(after, "{") || this.is(after, "["))) {
          this.i += 1;
        }
      }
    }
  }
}

// Whether the character at `k` of `raw` is escaped by backslashes.
function escapedAt(raw, k) {
  let n = 0;
  for (let j = k - 1; j >= 0 && raw[j] === "\\"; j--) n++;
  return n % 2 === 1;
}

// ---------------------------------------------------------------------------
// Variables, as Lotus finds them
// ---------------------------------------------------------------------------

const PLACEHOLDER = /\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/g;

/**
 * The names of the template's variables, in order, duplicates kept: the
 * `{{name}}` in code and inside strings, as `Lotus.Variables.extract_names/2`
 * finds them with the JSON profile. Blocks are read through.
 */
export function templateVariables(text, profile = JSON_PROFILE) {
  const names = [];
  for (const t of tokenize(text, profile)) {
    if (t.type === "variable") {
      names.push(text.slice(t.start + 2, t.end - 2));
    } else if (t.type === "string") {
      for (const m of stringPlaceholders(text.slice(t.start, t.end))) names.push(m.name);
    }
  }
  return names;
}

/**
 * The `{{name}}` placeholders of a string literal's raw text, each
 * `{name, start, end}` in it: the leftmost first, and after a `{{` that
 * starts none the search goes on from the next character, as Lotus does.
 */
export function stringPlaceholders(raw) {
  const out = [];
  PLACEHOLDER.lastIndex = 0;
  let from = 0;
  for (;;) {
    const at = raw.indexOf("{{", from);
    if (at === -1) break;
    PLACEHOLDER.lastIndex = at;
    const m = PLACEHOLDER.exec(raw);
    if (m && m.index === at) {
      out.push({ name: m[1], start: at, end: at + m[0].length });
      from = at + m[0].length;
    } else {
      from = at + 1;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// The position of the cursor
// ---------------------------------------------------------------------------

/**
 * Where `pos` is in the request: `{position, path, object, member, node,
 * token, inString}`.
 *
 *   position: "key" (a property name goes here), "value" (a value of the
 *     last step of `path`), "item" (an item of the array at `path`),
 *     "root" (nothing yet: the text is empty or not an object), or "none".
 *   path: the steps from the request to here, each {key} or {index}, with
 *     the JSON node at that step when there is one ({key, node}).
 *   object: the object whose key is being typed, for "key".
 *   member: the property whose value is being typed, for "value".
 *   node: the value already at the cursor, if any.
 */
export function contextAt(text, pos, profile = JSON_PROFILE) {
  const all = significantTokens(text, profile);
  const token = all.find((t) => t.start < pos && pos <= t.end) || null;
  const kept = parseTokens(text, tokensFor(all, "kept"));
  const root = kept.root;

  const inString = !!token && token.type === "string" && !closedBefore(text, token, pos);

  if (!root || root.kind !== "object") {
    return { position: "root", path: [], token, inString, root };
  }

  const found = locate(root, pos, []);
  return { ...found, token, inString, root };
}

// A string token closed at or before `pos`: the cursor is after it.
function closedBefore(text, token, pos) {
  const raw = text.slice(token.start, token.end);
  const closed = raw.length >= 2 && raw.endsWith('"') && !escapedAt(raw, raw.length - 1);
  return closed && pos >= token.end;
}

function inside(node, pos) {
  if (!node || (node.kind !== "object" && node.kind !== "array")) return false;
  if (pos <= node.from) return false;
  return node.closed ? pos < node.to : pos <= node.to;
}

function within(node, pos) {
  return node && pos >= node.from && pos <= node.to;
}

function locate(node, pos, path) {
  if (node.kind === "object") {
    for (const member of node.members) {
      const { key } = member;
      if (key && pos >= key.from && pos <= key.to) {
        return { position: "key", path, object: node, member, editing: member };
      }
      const valueStart = member.colon !== null ? member.colon + 1 : null;
      if (valueStart !== null && pos >= valueStart && pos <= member.end) {
        const step = { key: key ? key.name : null, variable: key ? !!key.variable : false };
        const value = member.value;
        if (value && inside(value, pos)) {
          return locate(value, pos, [...path, { ...step, node: value }]);
        }
        if (value && !within(value, pos) && pos > value.to) {
          // After the value, before its comma: no completion.
          return { position: "none", path, object: node, member };
        }
        return { position: "value", path: [...path, step], object: node, member, node: value };
      }
    }
    return { position: "key", path, object: node, member: null, editing: null };
  }

  // An array.
  for (let index = 0; index < node.items.length; index++) {
    const item = node.items[index];
    if (inside(item, pos)) return locate(item, pos, [...path, { index, node: item }]);
    if (within(item, pos) && item.kind !== "object" && item.kind !== "array") {
      return { position: "item", path: [...path, { index }], array: node, node: item };
    }
  }
  const index = node.items.filter((item) => item.to <= pos).length;
  return { position: "item", path: [...path, { index }], array: node, node: null };
}
