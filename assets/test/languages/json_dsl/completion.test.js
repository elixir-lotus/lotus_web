import { describe, it, expect, beforeEach } from "vitest";
import { EditorView } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import {
  JsonDslCompletion,
  clearFieldCache,
} from "../../../js/lib/languages/json_dsl/completion.js";
import esConfig from "../../fixtures/elasticsearch_editor_config.json";

// The text with the cursor where `|` is.
const at = (marked) => [marked.replace("|", ""), marked.indexOf("|")];
const labels = (result) => (result ? result.options.map((o) => o.label) : []);

// The indices' fields, as the server describes them (`editor_columns`).
const FIELDS = {
  orders: {
    customer: "text",
    "customer.keyword": "keyword",
    status: "keyword",
    total: "double",
    created_at: "date",
    lines: "nested",
    "lines.sku": "keyword",
  },
  "logs-2026.10": { level: "keyword", "@timestamp": "date", latency_ms: "long" },
};

function fetchFields(indices) {
  const columns = {};
  const types = {};
  for (const index of indices) {
    columns[index] = Object.keys(FIELDS[index] || {});
    types[index] = FIELDS[index] || {};
  }
  return Promise.resolve({ columns, types });
}

const SCHEMA = { orders: null, "logs-2026.10": null };

function completer(config = esConfig, options = {}) {
  return new JsonDslCompletion(SCHEMA, config, { source: "search", fetchFields, ...options });
}

// The completions at `|`, the fields loaded.
async function complete(marked, config = esConfig) {
  return await completer(config).complete(...at(marked), true);
}

// The text after accepting `label` at `|`, the cursor at `|`.
async function accept(marked, label, config = esConfig) {
  const [text, pos] = at(marked);
  const result = await completer(config).complete(text, pos, true);
  const option = result && result.options.find((o) => o.label === label);
  if (!option) throw new Error(`no ${label} in ${labels(result)}`);

  const view = new EditorView({
    state: EditorState.create({ doc: text, selection: { anchor: pos } }),
    parent: document.body,
  });
  if (typeof option.apply === "function") {
    option.apply(view, option, result.from, result.to);
  } else {
    view.dispatch({
      changes: { from: result.from, to: result.to, insert: option.apply ?? option.label },
      selection: { anchor: result.from + (option.apply ?? option.label).length },
    });
  }
  const out = view.state.doc.toString();
  const cursor = view.state.selection.main.head;
  view.destroy();
  return out.slice(0, cursor) + "|" + out.slice(cursor);
}

beforeEach(() => clearFieldCache());

describe("keys, at every level of the request", () => {
  it("offers the request's keys at the top, not URL parameters", async () => {
    const ls = labels(await complete('{ "| }'));
    expect(ls).toEqual(expect.arrayContaining(["query", "aggs", "size", "from", "sort", "_source"]));
    expect(ls).not.toContain("routing");
    expect(ls).not.toContain("match");
  });

  it("leaves out the keys the object has", async () => {
    const ls = labels(await complete('{ "size": 10, "query": {}, "| }'));
    expect(ls).not.toContain("size");
    expect(ls).not.toContain("query");
    expect(ls).toContain("aggs");
  });

  it("offers query clauses in a query, and a bool's clauses in a bool", async () => {
    expect(labels(await complete('{"query": {"|"}}'))).toEqual(
      expect.arrayContaining(["bool", "term", "range", "match", "exists", "nested"]),
    );
    const bool = labels(await complete('{"query": {"bool": {"|"}}}'));
    expect(bool).toEqual(expect.arrayContaining(["must", "filter", "should", "must_not"]));
    expect(bool).not.toContain("term");
  });

  it("offers clauses in an item of a bool's list", async () => {
    const ls = labels(await complete('{"query": {"bool": {"filter": [{"|"}]}}}'));
    expect(ls).toEqual(expect.arrayContaining(["term", "range", "bool"]));
  });

  it("offers nothing more in a query clause that has its query", async () => {
    expect(await complete('{"query": {"term": {"a": 1}, "|"}}')).toBeNull();
  });

  it("offers fields, with their types, where a clause is keyed by field", async () => {
    const result = await complete('{"query": {"term": {"|"}}}');
    expect(labels(result)).toEqual(expect.arrayContaining(["status", "customer.keyword", "level"]));
    const status = result.options.find((o) => o.label === "status");
    expect(status.detail).toBe("keyword · orders");
  });

  it("offers a range's operators inside a field of a range", async () => {
    const ls = labels(await complete('{"query": {"range": {"total": {"|"}}}}'));
    expect(ls).toEqual(expect.arrayContaining(["gte", "gt", "lte", "lt", "format"]));
  });

  it("tells an aggregation's name from its type, and nests aggregations", async () => {
    expect(labels(await complete('{"aggs": {"by_status": {"|"}}}'))).toEqual(
      expect.arrayContaining(["terms", "date_histogram", "avg", "aggs"]),
    );
    expect(
      labels(await complete('{"aggs": {"a": {"terms": {"field": "status"}, "aggs": {"b": {"|"}}}}}')),
    ).toContain("avg");
    expect(labels(await complete('{"aggs": {"by_status": {"terms": {"|"}}}}'))).toEqual(
      expect.arrayContaining(["field", "size", "order", "min_doc_count"]),
    );
  });

  it("reads `terms` in a query and in an aggregation apart", async () => {
    // In a query, terms is keyed by field; in an aggregation it takes one.
    expect(labels(await complete('{"query": {"terms": {"|"}}}'))).toContain("status");
    expect(labels(await complete('{"aggs": {"x": {"terms": {"|"}}}}'))).toContain("field");
  });

  it("offers sort fields and their options", async () => {
    expect(labels(await complete('{"sort": [{"|"}]}'))).toEqual(
      expect.arrayContaining(["created_at", "_score"]),
    );
    expect(labels(await complete('{"sort": [{"total": {"|"}}]}'))).toEqual(
      expect.arrayContaining(["order", "mode", "missing"]),
    );
  });

  it("offers index names where an object is keyed by index", async () => {
    expect(labels(await complete('{"indices_boost": [{"|"}]}'))).toEqual(["orders", "logs-2026.10"]);
  });
});

describe("values", () => {
  it("offers a parameter's values", async () => {
    expect(labels(await complete('{"sort": [{"total": {"order": "|"}}]}'))).toEqual(["asc", "desc"]);
    expect(
      labels(await complete('{"aggs": {"x": {"date_histogram": {"calendar_interval": "|"}}}}')),
    ).toContain("month");
    expect(labels(await complete('{"query": {"match": {"customer": {"operator": "|"}}}}'))).toEqual([
      "or",
      "and",
    ]);
  });

  it("offers true and false for a boolean", async () => {
    expect(labels(await complete('{"track_total_hits": |}'))).toEqual(
      expect.arrayContaining(["true", "false"]),
    );
    expect(labels(await complete('{"explain": t|}'))).toContain("true");
  });

  it("offers the fields of the types a parameter takes", async () => {
    const date = labels(await complete('{"aggs": {"x": {"date_histogram": {"field": "|"}}}}'));
    expect(date.sort()).toEqual(["@timestamp", "created_at"]);
    const avg = labels(await complete('{"aggs": {"x": {"avg": {"field": "|"}}}}'));
    expect(avg.sort()).toEqual(["latency_ms", "total"]);
    expect(labels(await complete('{"query": {"exists": {"field": "|"}}}'))).toContain("customer");
    expect(labels(await complete('{"query": {"nested": {"path": "|"}}}'))).toEqual(["lines"]);
  });

  it("offers fields in _source and multi_match lists", async () => {
    expect(labels(await complete('{"_source": ["|"]}'))).toContain("status");
    expect(labels(await complete('{"query": {"multi_match": {"fields": ["|"]}}}'))).toContain("customer");
  });

  it("offers index names for _index", async () => {
    expect(labels(await complete('{"query": {"term": {"_index": "|"}}}'))).toEqual([
      "orders",
      "logs-2026.10",
    ]);
  });

  it("offers each clause, as an object, where a query goes", async () => {
    const ls = labels(await complete('{"query": {"bool": {"must": |}}}'));
    expect(ls).toEqual(expect.arrayContaining(["term", "range", "bool", "[ ]"]));
    expect(labels(await complete('{"query": {"bool": {"filter": [|]}}}'))).toContain("term");
  });

  it("offers the template's variables as values", async () => {
    expect(labels(await complete('{"size": {{limit}}, "from": |}'))).toContain("{{limit}}");
  });
});

describe("a template that is not JSON yet", () => {
  it("reads through a bare {{variable}} in value position", async () => {
    expect(labels(await complete('{"size": {{n}}, "query": {"term": {"|"}}}'))).toContain("status");
  });

  it("reads through strings that hold braces and quotes", async () => {
    const ls = labels(await complete('{"query": {"match": {"customer": "a{b\\"}"}}, "|}'));
    expect(ls).toContain("aggs");
    expect(ls).not.toContain("query");
  });

  it("reads through [[ ]] blocks", async () => {
    expect(
      labels(await complete('{"query": {"bool": {"filter": [] [[, "must": {"term": {"|"}}}]]}}}')),
    ).toContain("status");
  });

  it("completes after a trailing comma, with nothing typed", async () => {
    const ls = labels(await complete('{"query": {"match": {"customer": "a{b"}}, |}'));
    expect(ls).toContain("aggs");
    expect(ls).not.toContain("query");
  });

  it("completes a bare word being typed as a key", async () => {
    expect(labels(await complete('{"query": {"bo|}}'))).toContain("bool");
  });

  it("completes in a request missing its closing braces", async () => {
    expect(labels(await complete('{"query": {"bool": {"must": [{"|'))).toContain("term");
  });

  it("offers requests to start from in an empty editor", async () => {
    expect(labels(await complete("|"))).toEqual(["match_all", "bool query", "terms aggregation"]);
  });
});

describe("variables", () => {
  it("offers the template's variables after {{, in code and in strings", async () => {
    const result = await complete('{"size": {{limit}}, "query": {"term": {"status": "{{|"}}}');
    expect(labels(result)).toEqual(["{{limit}}"]);
  });

  it("offers the name being typed as a new variable", async () => {
    expect(labels(await complete('{"size": {{lim|}'))).toEqual(["{{lim}}"]);
  });
});

describe("what accepting a completion inserts", () => {
  it("a key with its value's opening, the cursor inside", async () => {
    expect(await accept('{"query": {"bool": {"|"}}}', "must")).toBe(
      '{"query": {"bool": {"must": [ | ]}}}',
    );
    expect(await accept('{"query": {|}}', "bool")).toBe('{"query": {"bool": { "must": [ | ] }}}');
    expect(await accept('{"|"}', "size")).toBe('{"size": |}');
    expect(await accept('{"aggs": {"x": {"terms": {"|"}}}}', "field")).toBe(
      '{"aggs": {"x": {"terms": {"field": "|"}}}}',
    );
  });

  it("a clause keyed by field, the field to type first", async () => {
    expect(await accept('{"query": {"bo|}}', "bool")).toBe('{"query": {"bool": { "must": [ | ] }}}');
    const term = await accept('{"query": {"|"}}', "term");
    expect(term.replace("|", "")).toBe('{"query": {"term": { "field": "value" }}}');
  });

  it("a key typed further after the list opened, the typing replaced", async () => {
    const [text, pos] = at('{"aggs": {"x": {"|"}}}');
    const result = await completer().complete(text, pos, true);
    const option = result.options.find((o) => o.label === "date_histogram");
    // "date_h" typed since: CodeMirror hands the word as it is now.
    const typed = text.slice(0, pos) + "date_h" + text.slice(pos);
    const view = new EditorView({
      state: EditorState.create({ doc: typed, selection: { anchor: pos + 6 } }),
      parent: document.body,
    });
    option.apply(view, option, result.from, pos + 6);
    expect(view.state.doc.toString()).toBe(
      '{"aggs": {"x": {"date_histogram": { "field": "", "calendar_interval": "day" }}}}',
    );
    view.destroy();
  });

  it("a key alone when its colon is there", async () => {
    expect(await accept('{"qu|": {}}', "query")).toBe('{"query|": {}}');
  });

  it("a value in its quotes, or quoted", async () => {
    expect(await accept('{"sort": [{"total": {"order": "d|"}}]}', "desc")).toBe(
      '{"sort": [{"total": {"order": "desc|"}}]}',
    );
    expect(await accept('{"aggs": {"x": {"terms": {"field": |}}}}', "status")).toBe(
      '{"aggs": {"x": {"terms": {"field": "status"|}}}}',
    );
  });

  it("a clause as an object where a query goes", async () => {
    expect(await accept('{"query": {"bool": {"filter": [|]}}}', "exists")).toBe(
      '{"query": {"bool": {"filter": [{ "exists": { "field": "|" } }]}}}',
    );
  });
});

describe("the flat schema, for an adapter that sends no grammar", () => {
  const { grammar: _grammar, ...flat } = esConfig.context_schema;
  const legacy = { ...esConfig, context_schema: flat };

  it("reads a key's children wherever the key is", async () => {
    expect(labels(await complete('{"query": {"bool": {"|"}}}', legacy))).toContain("must");
    expect(labels(await complete('{"query": {"bool": {"must": [{"|"}]}}}', legacy))).toContain("term");
    expect(labels(await complete('{"query": {"match": {"|"}}}', legacy))).toContain("status");
    expect(labels(await complete('{"sort": [{"x": {"order": "|"}}]}', legacy))).toEqual([
      "asc",
      "desc",
    ]);
  });

  it("offers every keyword and field without a schema", async () => {
    const { context_schema: _schema, ...none } = esConfig;
    const ls = labels(await complete('{"|"}', none));
    expect(ls).toEqual(expect.arrayContaining(["query", "bool", "status"]));
  });
});
