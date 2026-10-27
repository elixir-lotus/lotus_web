/**
 * The shape of a JSON query language's requests, from the adapter's editor
 * config (`context_schema.grammar`; see the Elasticsearch adapter's
 * `EditorGrammar` for the format), read along the path at the cursor.
 *
 * An adapter that sends only the flat schema (`root`, `children`,
 * `value_literals`) gets the same reading: `fromLegacy` turns it into a
 * grammar where a key's children are the same wherever the key is.
 */

const PRIMITIVES = new Set(["string", "number", "integer", "boolean", "any", "field", "index"]);

export class Grammar {
  constructor(contextSchema) {
    const schema = contextSchema || {};
    const grammar = schema.grammar && schema.grammar.types ? schema.grammar : fromLegacy(schema);
    this.start = grammar.start;
    this.types = grammar.types || {};
    this.legacy = !(schema.grammar && schema.grammar.types);
    this.literals = schema.value_literals || {};
  }

  /** The type of the request. */
  root() {
    return this.start ? this.start : null;
  }

  /** A type's alternatives, named types followed: a list of maps or primitive names. */
  branches(spec, seen = new Set()) {
    if (spec === null || spec === undefined) return [];
    if (typeof spec === "string") {
      if (PRIMITIVES.has(spec)) return [spec];
      if (seen.has(spec)) return [];
      seen.add(spec);
      return this.branches(this.types[spec], seen);
    }
    if (spec.type !== undefined && !isSpec(spec)) return this.branches(spec.type, seen);
    if (Array.isArray(spec.one_of)) return spec.one_of.flatMap((s) => this.branches(s, seen));
    return [spec];
  }

  /** The branches that take a JSON value of `kind` (object, array, string…), or all. */
  branchesFor(spec, kind) {
    const all = this.branches(spec);
    if (!kind) return all;
    return all.filter((b) => accepts(b, kind));
  }

  /**
   * The type at the end of `path` (steps {key} or {index}, with the JSON
   * node there when there is one), from the request's type. Null when the
   * grammar does not say.
   */
  typeAt(path) {
    let spec = this.root();
    for (const step of path) {
      spec = this.child(spec, step);
      if (spec === null) return null;
    }
    return spec;
  }

  child(spec, step) {
    const kind = step.node ? nodeKind(step.node) : null;
    if ("index" in step) {
      const arrays = this.branchesFor(spec, "array").filter((b) => b.array !== undefined);
      // The flat schema knows no arrays: an item is read as its list.
      if (arrays.length === 0) return this.legacy ? spec : null;
      return arrays.length === 1 ? arrays[0].array : { one_of: arrays.map((a) => a.array) };
    }

    const key = step.key;
    const objects = this.branches(spec).filter(isObject);
    const found = [];
    for (const o of objects) {
      const member = o.object && key !== null && Object.prototype.hasOwnProperty.call(o.object, key)
        ? o.object[key]
        : undefined;
      if (member !== undefined) found.push(memberType(member));
    }
    if (found.length === 0 && this.legacy && key !== null) {
      // The flat schema: a key's children are the same wherever it is.
      if (this.types[`key:${key}`]) found.push(`key:${key}`);
      else if (Array.isArray(this.literals[key])) found.push({ enum: this.literals[key] });
    }
    if (found.length === 0) {
      for (const o of objects) {
        if (o.fields !== undefined) found.push(o.fields);
        else if (o.names !== undefined) found.push(o.names);
        else if (o.indices !== undefined) found.push(o.indices);
        else if (o.open) found.push("any");
      }
    }
    if (found.length === 0) return null;
    const spec2 = found.length === 1 ? found[0] : { one_of: found };
    return kind ? this.narrow(spec2, kind) : spec2;
  }

  narrow(spec, kind) {
    const fits = this.branchesFor(spec, kind);
    if (fits.length === 0) return spec;
    return fits.length === 1 ? fits[0] : { one_of: fits };
  }

  /**
   * What an object of type `spec` takes as keys: `{members: [{key,
   * member}], fields, names, indices, oneKey, closed}`; `fields`, `names`
   * and `indices` are the types of such keys' values, when it takes them.
   */
  keysOf(spec) {
    const out = { members: [], fields: null, names: null, indices: null, oneKey: false, closed: true };
    const seen = new Set();
    for (const o of this.branches(spec).filter(isObject)) {
      for (const [key, member] of Object.entries(o.object || {})) {
        if (seen.has(key)) continue;
        seen.add(key);
        out.members.push({ key, member: normalizeMember(member) });
      }
      if (o.fields !== undefined) out.fields = o.fields;
      if (o.names !== undefined) out.names = o.names;
      if (o.indices !== undefined) out.indices = o.indices;
      if (o.one_key) out.oneKey = true;
      if (o.open || o.fields !== undefined || o.names !== undefined || o.indices !== undefined) {
        out.closed = false;
      }
    }
    if (this.legacy) out.closed = false;
    return out;
  }

  /** Whether `spec` takes an object at all. */
  takesObject(spec) {
    return this.branches(spec).some(isObject) || this.branches(spec).includes("any");
  }

  /** The member of `key` in an object of type `spec`, or null. */
  memberOf(spec, key) {
    for (const o of this.branches(spec).filter(isObject)) {
      if (o.object && Object.prototype.hasOwnProperty.call(o.object, key)) {
        return normalizeMember(o.object[key]);
      }
    }
    return null;
  }

  /**
   * The JSON a value of `spec` starts as, for a snippet after `"key": `.
   * CodeMirror snippet syntax: `${}` is where the cursor goes.
   */
  valueSnippet(spec) {
    const [first] = this.branches(spec);
    if (first === undefined || first === "any") return "${}";
    if (first === "string" || first === "field" || first === "index") return '"${}"';
    if (first === "number" || first === "integer") return "${}";
    if (first === "boolean") return "${true}";
    if (first.enum) {
      const v = first.enum[0];
      return typeof v === "string" ? `"\${${v}}"` : `\${${v}}`;
    }
    if (first.field) return '"${}"';
    if (first.array !== undefined) return "[ ${} ]";
    if (isObject(first)) return "{ ${} }";
    return "${}";
  }
}

function isSpec(spec) {
  return (
    spec.object !== undefined ||
    spec.array !== undefined ||
    spec.one_of !== undefined ||
    spec.enum !== undefined ||
    spec.field !== undefined ||
    spec.fields !== undefined ||
    spec.names !== undefined ||
    spec.indices !== undefined
  );
}

function isObject(b) {
  return (
    typeof b === "object" &&
    b !== null &&
    (b.object !== undefined || b.fields !== undefined || b.names !== undefined || b.indices !== undefined)
  );
}

function memberType(member) {
  return member && typeof member === "object" && member.type !== undefined && !isSpec(member)
    ? member.type
    : member;
}

function normalizeMember(member) {
  if (member && typeof member === "object" && member.type !== undefined && !isSpec(member)) {
    return member;
  }
  return { type: member };
}

/** The kind of a JSON node, as a branch takes it. */
export function nodeKind(node) {
  if (!node) return null;
  if (node.kind === "object" || node.kind === "array" || node.kind === "string") return node.kind;
  if (node.kind === "number") return "number";
  if (node.kind === "literal") return node.value === "null" ? "null" : "boolean";
  return null;
}

function accepts(branch, kind) {
  if (branch === "any") return true;
  if (kind === "object") return isObject(branch);
  if (kind === "array") return typeof branch === "object" && branch.array !== undefined;
  if (kind === "string") {
    return (
      branch === "string" ||
      branch === "field" ||
      branch === "index" ||
      (typeof branch === "object" && (branch.field !== undefined ||
        (branch.enum && branch.enum.some((v) => typeof v === "string"))))
    );
  }
  if (kind === "number") {
    return branch === "number" || branch === "integer" ||
      (typeof branch === "object" && branch.enum && branch.enum.some((v) => typeof v === "number"));
  }
  if (kind === "boolean") return branch === "boolean";
  return false;
}

// ---------------------------------------------------------------------------
// The flat schema
// ---------------------------------------------------------------------------

/**
 * A grammar from the flat schema: `root` keys, `children` by key (a list of
 * keys, or a marker), `value_literals` by key. A key's children are the
 * same wherever it is, as the flat schema has them.
 */
export function fromLegacy(schema) {
  const children = schema.children || {};
  const literals = schema.value_literals || {};
  const types = {};

  const typeOfKey = (key) => {
    if (Array.isArray(literals[key])) return { enum: literals[key] };
    if (children[key] !== undefined) return `key:${key}`;
    return "any";
  };

  const objectOf = (keys) => ({
    object: Object.fromEntries(keys.map((k) => [k, typeOfKey(k)])),
    open: true,
  });

  for (const [key, rule] of Object.entries(children)) {
    if (Array.isArray(rule)) {
      types[`key:${key}`] = objectOf(rule);
    } else if (rule === "fields") {
      types[`key:${key}`] = {
        object: {},
        fields: key === "range" ? objectOf(["gte", "gt", "lte", "lt", "format", "time_zone", "boost"]) : "any",
      };
    } else if (rule === "array_of_query") {
      const query = Array.isArray(children.query) ? "key:query" : "any";
      types[`key:${key}`] = { one_of: [query, { array: query }] };
    } else if (rule === "named_aggregation") {
      types[`key:${key}`] = { object: {}, names: { object: {}, open: true } };
    } else if (rule === "range_operators") {
      types[`key:${key}`] = objectOf(["gte", "gt", "lte", "lt", "format", "time_zone", "boost"]);
    } else {
      types[`key:${key}`] = { object: {}, open: true };
    }
  }

  types["key:"] = objectOf(schema.root || []);
  return { start: "key:", types };
}
