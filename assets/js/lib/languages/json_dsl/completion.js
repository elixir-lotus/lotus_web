/**
 * JSON DSL completion for non-SQL query languages (Elasticsearch, etc.).
 *
 * Walks the @lezer/json syntax tree to determine the cursor's
 * structural context (enclosing object's key path, key vs. value
 * position), then consults the adapter's context_schema to decide
 * what's valid here.
 *
 * Falls back to the flat "every keyword anywhere" behavior when the
 * adapter doesn't ship a context_schema, so adapters can adopt the
 * richer shape incrementally.
 */
import { syntaxTree } from "@codemirror/language";

// Marker values in context_schema.children. Stored as strings on the
// wire (Elixir atoms serialize to strings through Jason) so we compare
// against the string form here.
const MARKER_FIELDS = "fields";
const MARKER_ARRAY_OF_QUERY = "array_of_query";
const MARKER_NAMED_AGGREGATION = "named_aggregation";
const MARKER_RANGE_OPERATORS = "range_operators";

// Elasticsearch range-style operators. We apply these when the
// grandparent in the path has a :fields rule — i.e., we're inside the
// second object of a {"range": {"field": {...}}} structure.
const RANGE_OPERATORS = [
  "gte",
  "gt",
  "lte",
  "lt",
  "format",
  "time_zone",
  "boost",
];

export class JsonDslCompletion {
  constructor(schema, config = {}) {
    this.schema = schema || {};
    this.keywords = config.keywords || [];
    this.functions = config.functions || [];
    this.types = config.types || [];
    this.contextSchema = config.context_schema || null;
  }

  updateSchema(newSchema) {
    this.schema = newSchema || {};
  }

  createCompletionSource() {
    return (context) => {
      const ctx = this.analyzeJsonContext(context.state, context.pos);
      if (!ctx) return null;

      const completions = this.getCompletions(ctx);
      if (!completions || completions.length === 0) return null;

      return {
        from: ctx.wordFrom,
        to: ctx.wordTo,
        options: completions.map((c) => ({
          label: c.label,
          type: c.type || "property",
          detail: c.detail,
          boost: c.boost || 0,
          apply: applyFor(c.label, ctx),
        })),
      };
    };
  }

  /**
   * Walk the syntax tree from the cursor up to the root, collecting
   * the key path (names of Property nodes whose value objects enclose
   * the cursor) and determining whether the cursor sits in a key or
   * value position.
   */
  analyzeJsonContext(state, pos) {
    const tree = syntaxTree(state);
    const leaf = tree.resolveInner(pos, -1);

    const path = [];
    let cur = leaf;

    while (cur) {
      if (cur.name === "Property") {
        const keyNode = cur.getChild("PropertyName");
        // Only include this Property's key when the cursor is past
        // it — i.e., we're inside the value subtree of this property,
        // not inside (or before) its key. Otherwise we'd prepend the
        // partially-typed key onto its own lookup path.
        if (keyNode && pos >= keyNode.to) {
          const raw = state.sliceDoc(keyNode.from, keyNode.to);
          path.unshift(stripQuotes(raw));
        }
      }
      cur = cur.parent;
    }

    // Determining key vs. value position from the syntax tree alone is
    // unreliable for mid-typing / malformed inputs (Lezer is
    // error-tolerant but produces ambiguous trees when a value is
    // missing). A simple char-based scan of the doc immediately to the
    // left of the cursor is more robust: `:` means value, `{`/`,` mean
    // key, a partial `"` can be either — fall through to the String/
    // PropertyName node kind for disambiguation.
    const inKey = this.isInKeyPosition(state, leaf, pos);
    const { wordFrom, wordTo } = this.quotedWordBounds(state, pos);

    // Whether the cursor is inside a partial `"…"` string literal —
    // quotedWordBounds advances wordFrom past an opening quote when
    // it finds one, so inspecting doc[wordFrom - 1] tells us the
    // surrounding quote state without re-scanning.
    const doc = state.doc.toString();
    const inQuotes = wordFrom > 0 && doc[wordFrom - 1] === '"';

    // For key position, check whether a `:` already follows the
    // current word — if so, don't append another one on accept.
    let hasColonAfter = false;
    for (let i = wordTo; i < doc.length; i++) {
      const ch = doc[i];
      if (ch === '"') continue;
      if (/\s/.test(ch)) continue;
      hasColonAfter = ch === ":";
      break;
    }

    return {
      path,
      inKey,
      inValue: !inKey,
      inQuotes,
      hasColonAfter,
      wordFrom,
      wordTo,
    };
  }

  /**
   * A cursor is in key position when:
   *   - It sits inside a PropertyName token (the key string).
   *   - It sits inside a String that is the value of a Property.
   *     Stripped out here; those are value positions.
   *   - Otherwise we fall through to a char-based scan (the syntax
   *     tree is unreliable on malformed / mid-typing inputs so the
   *     last-non-whitespace char before the cursor is authoritative).
   */
  isInKeyPosition(state, leaf, pos) {
    // Tree-first for the unambiguous cases: a PropertyName token is
    // always a key, and any other String node (one that made it past
    // the PropertyName check) is the value of its Property.
    let cur = leaf;
    while (cur) {
      if (cur.name === "PropertyName") return true;
      if (cur.name === "String") return false;
      cur = cur.parent;
    }

    // Cursor sits between tokens (whitespace, mid-typing before a
    // value was written, etc.) — the syntax tree can't disambiguate,
    // so fall back to the last-non-whitespace char.
    return isInKeyPositionByChar(state.doc.toString(), pos);
  }

  /**
   * Compute the replacement range for the token under the cursor.
   * When inside a string literal, strip the enclosing quotes so we
   * don't eat the `"` when the user accepts a completion.
   */
  quotedWordBounds(state, pos) {
    const doc = state.doc.toString();
    let wordFrom = pos;
    let wordTo = pos;

    // Scan left.
    let i = pos - 1;
    while (i >= 0) {
      const ch = doc[i];
      if (ch === '"') {
        wordFrom = i + 1;
        break;
      }
      if (ch === ":" || ch === "," || ch === "{" || ch === "[" || /\s/.test(ch)) {
        wordFrom = i + 1;
        break;
      }
      i--;
    }
    if (i < 0) wordFrom = 0;

    // Scan right.
    let j = pos;
    while (j < doc.length) {
      const ch = doc[j];
      if (ch === '"' || ch === ":" || ch === "," || ch === "}" || ch === "]") break;
      if (/\s/.test(ch)) break;
      j++;
    }
    wordTo = j;

    return { wordFrom, wordTo };
  }

  getCompletions(ctx) {
    if (ctx.inKey) return this.getKeyCompletionsForPath(ctx.path);
    return this.getValueCompletionsForPath(ctx.path);
  }

  getKeyCompletionsForPath(path) {
    if (!this.contextSchema) return this.fallbackKeyCompletions();

    if (path.length === 0) {
      return (this.contextSchema.root || []).map(toKeywordCompletion);
    }

    // Walk bottom-up through the path, consulting context_schema.children
    // for the nearest rule.
    const children = this.contextSchema.children || {};
    const lastKey = path[path.length - 1];
    const rule = children[lastKey];

    if (rule === undefined || rule === null) {
      // Check grandparent for :fields expansion into :range_operators —
      // handles {"range": {"field": {↓}}} where we need gte/lte/etc.
      if (path.length >= 2) {
        const grandparent = path[path.length - 2];
        const grandparentRule = children[grandparent];
        if (grandparentRule === MARKER_FIELDS) {
          if (grandparent === "range") {
            return RANGE_OPERATORS.map(toKeywordCompletion);
          }
          // For other :fields rules, no second-level keys are meaningful.
          return [];
        }
      }
      return [];
    }

    if (Array.isArray(rule)) return rule.map(toKeywordCompletion);

    if (rule === MARKER_FIELDS) return this.getFieldCompletions();

    if (rule === MARKER_ARRAY_OF_QUERY) {
      const queryRule = children.query;
      return Array.isArray(queryRule) ? queryRule.map(toKeywordCompletion) : [];
    }

    if (rule === MARKER_NAMED_AGGREGATION) {
      // Free-form bucket names — no key suggestions make sense.
      return [];
    }

    if (rule === MARKER_RANGE_OPERATORS) {
      return RANGE_OPERATORS.map(toKeywordCompletion);
    }

    return [];
  }

  getValueCompletionsForPath(path) {
    if (!this.contextSchema) return null;
    if (path.length === 0) return null;

    const lastKey = path[path.length - 1];
    const literals = (this.contextSchema.value_literals || {})[lastKey];
    if (!Array.isArray(literals)) return null;

    return literals.map((v) => ({
      label: v,
      type: "enum",
      detail: `${lastKey} value`,
      boost: 10,
    }));
  }

  getFieldCompletions() {
    const completions = [];
    for (const indexName of Object.keys(this.schema)) {
      const fields = this.schema[indexName] || [];
      for (const field of fields) {
        completions.push({
          label: field,
          type: "property",
          detail: `Field in ${indexName}`,
          boost: 5,
        });
      }
    }
    return completions;
  }

  // Flat fallback used when the adapter doesn't supply a
  // context_schema — suggest every keyword + every field at every
  // key position.
  fallbackKeyCompletions() {
    const completions = this.keywords.map((kw) => ({
      label: kw,
      type: "keyword",
      detail: "Query keyword",
      boost: 10,
    }));

    for (const indexName of Object.keys(this.schema)) {
      const fields = this.schema[indexName] || [];
      for (const field of fields) {
        completions.push({
          label: field,
          type: "property",
          detail: `Field in ${indexName}`,
          boost: 5,
        });
      }
    }

    return completions;
  }
}

function toKeywordCompletion(kw) {
  return {
    label: kw,
    type: "keyword",
    detail: "Query keyword",
    boost: 10,
  };
}

function stripQuotes(s) {
  if (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"') {
    return s.slice(1, -1);
  }
  return s;
}

// Produces the string CodeMirror inserts when the user accepts a
// completion. JSON requires keys/strings to be double-quoted, so we
// wrap the label unless the cursor is already inside a partial `"…"`
// literal (in which case we'd double-quote and produce `""aggs""`).
// For key position outside quotes we also append `: ` so the user
// lands directly at the value position. If a `:` is already present
// after the cursor we skip adding another.
function applyFor(label, ctx) {
  if (ctx.inQuotes) return label;
  if (ctx.inKey) return ctx.hasColonAfter ? `"${label}"` : `"${label}": `;
  return `"${label}"`;
}

function isInKeyPositionByChar(doc, pos) {
  for (let i = pos - 1; i >= 0; i--) {
    const ch = doc[i];
    if (/\s/.test(ch)) continue;
    if (ch === "{" || ch === ",") return true;
    if (ch === ":") return false;
    if (ch === '"') return true; // we're inside a partial key string
    return true;
  }
  return true;
}
