/**
 * Autocomplete for JSON query languages (Elasticsearch's search requests).
 *
 * The text is read as Lotus reads it (parser.js: `{{variables}}` in values
 * and keys, `[[ ]]` blocks), so a template that is not JSON yet still has a
 * path at the cursor: `query > bool > filter > [0] > term`. The adapter's
 * grammar (grammar.js) says what that position takes:
 *
 *   - keys: the keys of the object there (`must`, `filter`… in a `bool`),
 *     less those it has, each inserted with its value's opening (`"bool":
 *     { "must": [ | ] }`); field names where the object is keyed by field
 *     (`term`, `range`, `sort`); index names (`indices_boost`);
 *   - values: the field names a parameter takes (`"field": "|"` in a
 *     `date_histogram` offers date fields), with their mapping type; index
 *     names (`_index`); enum values, `true`/`false`; and where a query or
 *     an aggregation goes, each clause as a snippet;
 *   - `{{` anywhere: the template's variables.
 *
 * Field names come from the server, by index, as completion needs them
 * (`options.fetchFields(indices)`), with their mapping types.
 */
import { snippet as cmSnippet, startCompletion } from "@codemirror/autocomplete";
import { contextAt, jsonProfile, templateVariables } from "./parser.js";
import { Grammar } from "./grammar.js";

// The most indices whose fields completion asks the server for, and how
// many the server describes in one request.
export const MAX_INDICES = 24;
const BATCH = 8;

// The fields the server described, by source and index: [{name, type}].
const fieldCache = new Map();

export function clearFieldCache() {
  fieldCache.clear();
}

// A snippet that, once in, opens the completions where the cursor lands:
// the fields of `"field": "|"`, the clauses of `"must": [ | ]`.
function snippet(template) {
  const apply = cmSnippet(template);
  return (view, completion, from, to) => {
    apply(view, completion, from, to);
    if (/\$\{/.test(template)) setTimeout(() => view.dom.isConnected && startCompletion(view), 0);
  };
}

// What a key or value is typed with: letters, digits, _ . - @ and *.
const WORD = /[\w.@*-]*$/;

export class JsonDslCompletion {
  constructor(schema, config = {}, options = {}) {
    this.schema = schema || {};
    this.config = config || {};
    this.options = options;
    this.grammar = new Grammar(this.config.context_schema);
    // Without a schema, every keyword and field at every key.
    this.flat = !this.config.context_schema;
    this.profile = jsonProfile(this.config.tokenizer || null);
    this.pending = new Map();
    this.text = "";
  }

  updateSchema(newSchema) {
    this.schema = newSchema || {};
  }

  source() {
    const source = this.options.source;
    return (typeof source === "function" ? source() : source) || "";
  }

  createCompletionSource() {
    return (context) => this.complete(context.state.doc.toString(), context.pos, context.explicit);
  }

  /**
   * The completions at `pos`: `{from, to, options, validFor}`, null, or a
   * promise of one while the indices' fields load. Without `explicit`
   * (Ctrl-Space), only once something is typed or right after `{`, `[`,
   * `,`, `:` or a quote.
   */
  complete(text, pos, explicit = false) {
    this.text = text;
    const variable = this.variableCompletion(text, pos);
    if (variable) return variable;

    const ctx = contextAt(text, pos, this.profile);
    const range = this.range(text, pos, ctx);
    if (!explicit && !range.typed && !opensHere(text, pos, ctx)) return null;

    const plan = this.plan(ctx);
    if (!plan) return null;

    const missing = plan.needsFields ? this.missingIndices() : [];
    if (missing.length && this.options.fetchFields) {
      return this.load(missing).then(() => this.result(plan, range, ctx));
    }
    return this.result(plan, range, ctx);
  }

  /**
   * What is being typed: the range a completion replaces, `{from, to,
   * typed, quoted, quoteFrom, quoteTo}`. In a string the range is inside
   * its quotes (`quoteFrom`/`quoteTo` take the quotes in); outside, a bare
   * word.
   */
  range(text, pos, ctx) {
    const t = ctx.token;
    if (ctx.inString || (t && t.type === "string" && pos > t.start && pos < t.end)) {
      const raw = text.slice(t.start, t.end);
      const closed = raw.length >= 2 && raw.endsWith('"') && pos < t.end;
      // A string left open runs to the end of the text: replace the word.
      let to = closed ? t.end - 1 : pos;
      if (!closed) while (to < text.length && /[\w.@*-]/.test(text[to])) to++;
      return {
        from: t.start + 1,
        to,
        typed: true,
        quoted: true,
        quoteFrom: t.start,
        quoteTo: closed ? t.end : to,
      };
    }
    const word = WORD.exec(text.slice(0, pos))[0];
    let to = pos;
    while (to < text.length && /[\w.@*-]/.test(text[to])) to++;
    return { from: pos - word.length, to, typed: word.length > 0, quoted: false };
  }

  // ---------------------------------------------------------------------------
  // What the position takes
  // ---------------------------------------------------------------------------

  plan(ctx) {
    const g = this.grammar;

    if (ctx.position === "root") {
      if (ctx.root && ctx.root.kind !== "invalid") return null;
      return { kind: "root" };
    }
    if (ctx.position === "none") return null;

    if (ctx.position === "key" && this.flat) {
      const members = (this.config.keywords || []).map((key) => ({ key, member: { type: "any" } }));
      const keys = { members, fields: "any", names: null, indices: null, oneKey: false, closed: false };
      return { kind: "keys", keys, present: new Set(), valueFollows: false, needsFields: true };
    }

    if (ctx.position === "key") {
      const spec = g.typeAt(ctx.path);
      if (spec === null) return null;
      const keys = g.keysOf(spec);
      const present = new Set(
        (ctx.object ? ctx.object.members : [])
          .filter((m) => m !== ctx.editing && m.key && m.key.name !== undefined)
          .map((m) => m.key.name),
      );
      // A query clause holds one query.
      if (keys.oneKey && keys.members.some((m) => present.has(m.key))) return null;
      return {
        kind: "keys",
        keys,
        present,
        valueFollows: !!(ctx.editing && ctx.editing.colon !== null),
        needsFields: keys.fields !== null,
      };
    }

    // A value, or an array's item.
    const spec = g.typeAt(ctx.path);
    const lastKey = lastStepKey(ctx.path);
    const branches = spec === null ? [] : g.branches(spec);
    const needsFields = branches.some((b) => b === "field" || (b && b.field !== undefined));
    return { kind: "values", spec, branches, lastKey, needsFields };
  }

  result(plan, range, ctx) {
    let options = [];
    if (plan.kind === "root") options = this.rootOptions(range);
    else if (plan.kind === "keys") options = this.keyOptions(plan, range);
    else options = this.valueOptions(plan, range, ctx);

    if (options.length === 0) return null;
    return { from: range.from, to: range.to, options, validFor: /^[\w.@*-]*$/ };
  }

  // An empty editor: a request to start from.
  rootOptions(range) {
    if (range.quoted) return [];
    const starters = [
      ["match_all", "Every document", '{\n  "query": {\n    "match_all": {}\n  },\n  "size": ${100}\n}'],
      [
        "bool query",
        "Filter with term and range clauses",
        '{\n  "query": {\n    "bool": {\n      "filter": [\n        { "term": { "${field}": "${value}" } }\n      ]\n    }\n  },\n  "size": 100\n}',
      ],
      [
        "terms aggregation",
        "Count documents by a field's values",
        '{\n  "size": 0,\n  "aggs": {\n    "${by_field}": {\n      "terms": { "field": "${}", "size": 10 }\n    }\n  }\n}',
      ],
    ];
    return starters.map(([label, detail, body]) => ({
      label,
      detail,
      type: "text",
      apply: snippet(body),
      boost: 5,
    }));
  }

  keyOptions(plan, range) {
    const { keys, present, valueFollows } = plan;
    const options = [];

    for (const { key, member } of keys.members) {
      if (present.has(key)) continue;
      options.push(
        this.keyOption(key, range, valueFollows, {
          detail: typeLabel(this.grammar, member.type),
          info: member.doc,
          value: member.snippet || this.grammar.valueSnippet(member.type),
          type: "keyword",
          boost: 10,
        }),
      );
    }

    if (keys.fields !== null) {
      for (const field of this.fields()) {
        if (present.has(field.name)) continue;
        options.push(
          this.keyOption(field.name, range, valueFollows, {
            detail: field.detail,
            value: this.grammar.valueSnippet(keys.fields),
            type: "property",
            boost: 5,
          }),
        );
      }
    }

    if (keys.indices !== null) {
      for (const index of this.indices()) {
        options.push(
          this.keyOption(index, range, valueFollows, {
            detail: "index",
            value: this.grammar.valueSnippet(keys.indices),
            type: "class",
            boost: 5,
          }),
        );
      }
    }

    if (keys.names !== null && !range.quoted && !range.typed) {
      options.push({
        label: "name…",
        detail: "a name of yours",
        type: "text",
        apply: snippet(`"\${name}": ${this.grammar.valueSnippet(keys.names)}`),
        boost: -5,
      });
    }

    return options;
  }

  // A key, inserted with its quotes, its colon and its value's opening, as
  // `"bool": { ${} }`, unless a colon follows it already.
  keyOption(key, range, valueFollows, { detail, info, value, type, boost }) {
    const option = { label: key, type, boost };
    if (detail) option.detail = detail;
    if (info) option.info = info;

    if (valueFollows) {
      option.apply = range.quoted ? key : `"${key}"`;
      return option;
    }

    const template = `"${escapeSnippet(key)}": ${value}`;
    // `from` and `to` are the word as it is when the completion is taken,
    // more of it typed since it opened; in a string, its quotes go too.
    option.apply = (view, completion, from, to) => {
      const doc = view.state.doc;
      const start = range.quoted ? from - 1 : from;
      const end = range.quoted && doc.sliceString(to, to + 1) === '"' ? to + 1 : to;
      snippet(template)(view, completion, start, end);
    };
    return option;
  }

  valueOptions(plan, range, ctx) {
    const options = [];
    const { branches, lastKey } = plan;
    const quote = (s) => (range.quoted ? s : `"${s}"`);
    const seen = new Set();
    const add = (option) => {
      if (seen.has(option.label)) return;
      seen.add(option.label);
      options.push(option);
    };

    // An index name: `_index` (in a term on it, say).
    if (lastKey === "_index" || branches.includes("index")) {
      for (const index of this.indices()) {
        add({ label: index, type: "class", detail: "index", apply: quote(index), boost: 15 });
      }
    }

    // Field names, those of the types the parameter takes when there are.
    const fieldTypes = fieldPreference(branches);
    if (fieldTypes) {
      const fields = this.fields();
      const fitting = fieldTypes.length
        ? fields.filter((f) => f.types.some((t) => fieldTypes.includes(t)))
        : fields;
      for (const field of fitting.length ? fitting : fields) {
        add({ label: field.name, type: "property", detail: field.detail, apply: quote(field.name), boost: 10 });
      }
    }

    for (const b of branches) {
      if (b && Array.isArray(b.enum)) {
        for (const v of b.enum) {
          if (typeof v !== "string" && range.quoted) continue;
          add({
            label: String(v),
            type: "enum",
            detail: lastKey ? `${lastKey} value` : "value",
            apply: typeof v === "string" ? quote(v) : String(v),
            boost: 12,
          });
        }
      }
      if (b === "boolean" && !range.quoted) {
        add({ label: "true", type: "keyword", apply: "true", boost: 11 });
        add({ label: "false", type: "keyword", apply: "false", boost: 11 });
      }
    }

    // Where a query, an aggregation or another object goes, before its
    // brace: each clause as an object.
    if (!range.quoted && !(ctx.node && (ctx.node.kind === "object" || ctx.node.kind === "array"))) {
      for (const option of this.objectSnippets(plan.spec)) add(option);
    }

    // The template's variables.
    for (const name of this.variables()) {
      add({ label: `{{${name}}}`, type: "variable", detail: "variable", apply: `{{${name}}}`, boost: 1 });
    }

    return options;
  }

  // `{ "term": { … } }` for each clause of a query (or of any type that
  // holds one key); `[ ]` and `{ }` for a list or an object.
  objectSnippets(spec) {
    if (spec === null || spec === undefined) return [];
    const g = this.grammar;
    const options = [];
    const branches = g.branches(spec);
    const arrayOf = branches.find((b) => b && b.array !== undefined);
    const objects = branches.filter((b) => b && typeof b === "object" && b.object !== undefined);

    for (const o of objects) {
      const keys = g.keysOf(o);
      if (!keys.oneKey) continue;
      for (const { key, member } of keys.members) {
        const value = member.snippet || g.valueSnippet(member.type);
        options.push({
          label: key,
          type: "keyword",
          detail: "{ … }",
          info: member.doc,
          apply: snippet(`{ "${escapeSnippet(key)}": ${value} }`),
          boost: 8,
        });
      }
    }

    if (arrayOf) {
      options.push({ label: "[ ]", type: "text", detail: "a list", apply: snippet("[ ${} ]"), boost: 3 });
    }
    if (objects.length && options.length === 0) {
      options.push({ label: "{ }", type: "text", detail: "an object", apply: snippet("{ ${} }"), boost: 3 });
    }
    return options;
  }

  // ---------------------------------------------------------------------------
  // Variables
  // ---------------------------------------------------------------------------

  // After `{{`, in code or a string: the template's variables, and the one
  // being typed as a new one.
  variableCompletion(text, pos) {
    const m = /\{\{([A-Za-z_][A-Za-z0-9_]*)?$/.exec(text.slice(0, pos));
    if (!m) return null;
    const from = pos - m[0].length;
    let to = pos;
    while (to < text.length && /[A-Za-z0-9_]/.test(text[to])) to++;
    if (text.startsWith("}}", to)) to += 2;

    const names = this.variables(text, from, to);
    const typed = m[1] || "";
    const options = names.map((name) => ({
      label: `{{${name}}}`,
      type: "variable",
      detail: "variable",
      apply: `{{${name}}}`,
    }));
    if (typed && !names.includes(typed)) {
      options.push({ label: `{{${typed}}}`, type: "variable", detail: "new variable", apply: `{{${typed}}}` });
    }
    if (options.length === 0) return null;
    return { from, to, options, validFor: /^\{\{\w*$/ };
  }

  // The template's variables, but for the one at [from, to).
  variables(text = this.text, from = -1, to = -1) {
    const source = from >= 0 ? text.slice(0, from) + text.slice(to) : text;
    return [...new Set(templateVariables(source, this.profile))];
  }

  // ---------------------------------------------------------------------------
  // Indices and their fields
  // ---------------------------------------------------------------------------

  indices() {
    return Object.keys(this.schema);
  }

  cacheKey(index) {
    return `${this.source()}\u0000${index}`;
  }

  // An index's fields, [{name, type}], or null until described.
  fieldsOf(index) {
    const cached = fieldCache.get(this.cacheKey(index));
    if (cached) return cached;
    const known = this.schema[index];
    return Array.isArray(known) ? known.map((name) => ({ name, type: null })) : null;
  }

  missingIndices() {
    return this.indices()
      .slice(0, MAX_INDICES)
      .filter((index) => !fieldCache.has(this.cacheKey(index)) && !this.pending.has(index));
  }

  // Every field of the indices, once, with its types and its indices.
  fields() {
    const byName = new Map();
    for (const index of this.indices()) {
      for (const { name, type } of this.fieldsOf(index) || []) {
        const entry = byName.get(name) || { name, types: [], indices: [] };
        if (type && !entry.types.includes(type)) entry.types.push(type);
        entry.indices.push(index);
        byName.set(name, entry);
      }
    }
    return [...byName.values()].map((f) => ({
      ...f,
      detail: [
        f.types.join(" | "),
        f.indices.length > 2 ? `${f.indices.length} indices` : f.indices.join(", "),
      ]
        .filter(Boolean)
        .join(" · "),
    }));
  }

  // Asks the server for the fields of `indices`, a batch at a time, once an
  // index; an index it does not describe has none.
  load(indices) {
    const batches = [];
    for (let i = 0; i < indices.length; i += BATCH) batches.push(indices.slice(i, i + BATCH));

    const request = Promise.all(
      batches.map((batch) =>
        Promise.resolve(this.options.fetchFields(batch))
          .then((reply) => {
            const columns = (reply && reply.columns) || {};
            const types = (reply && reply.types) || {};
            for (const index of batch) {
              const names = Array.isArray(columns[index]) ? columns[index] : [];
              fieldCache.set(
                this.cacheKey(index),
                names.map((name) => ({ name, type: (types[index] || {})[name] || null })),
              );
            }
          })
          .catch(() => {}),
      ),
    ).finally(() => indices.forEach((index) => this.pending.delete(index)));

    indices.forEach((index) => this.pending.set(index, request));
    return request;
  }
}

// Completion opens by itself, without a character typed, right after `{`,
// `[`, `,`, `:` or an opening quote.
function opensHere(text, pos, ctx) {
  if (ctx.inString) return true;
  return /[{[,:]$/.test(text.slice(0, pos).trimEnd());
}

function lastStepKey(path) {
  for (let i = path.length - 1; i >= 0; i--) {
    if ("key" in path[i]) return path[i].key;
  }
  return null;
}

// The mapping types a field parameter prefers ([] for any), or null when
// the position takes no field.
function fieldPreference(branches) {
  let found = null;
  for (const b of branches) {
    if (b === "field") found = found || [];
    else if (b && Array.isArray(b.field)) found = [...(found || []), ...b.field];
  }
  return found;
}

function typeLabel(grammar, spec) {
  const [first] = grammar.branches(spec);
  if (first === undefined) return undefined;
  if (typeof first === "string") return first;
  if (first.array !== undefined) return "list";
  if (first.enum) return first.enum.slice(0, 3).join(" | ");
  if (first.field) return "field";
  return "object";
}

// A literal `$`, `{`, `}` or `\` in a snippet's text.
function escapeSnippet(text) {
  return text.replace(/[$\\{}]/g, (c) => `\\${c}`);
}
