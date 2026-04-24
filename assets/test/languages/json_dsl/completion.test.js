import { describe, it, expect, beforeEach } from "vitest";
import { EditorState } from "@codemirror/state";
import { json } from "@codemirror/lang-json";
import { JsonDslCompletion } from "../../../js/lib/languages/json_dsl/completion.js";

// Minimal fake completion context. We only care about state + pos — the
// completion source never consults the `explicit` / `matchBefore` hooks
// in our implementation.
function makeContext(doc, pos) {
  const state = EditorState.create({ doc, extensions: [json()] });
  return { state, pos, explicit: true };
}

function labels(result) {
  if (!result) return [];
  return result.options.map((o) => o.label);
}

describe("JsonDslCompletion with context_schema", () => {
  const schema = {
    users: ["name", "age", "created_at"],
    orders: ["total", "status"],
  };

  const contextSchema = {
    root: ["query", "aggs", "sort", "size"],
    children: {
      query: ["match", "match_all", "term", "terms", "bool", "range"],
      bool: ["must", "should", "must_not", "filter", "minimum_should_match"],
      must: "array_of_query",
      should: "array_of_query",
      must_not: "array_of_query",
      filter: "array_of_query",
      match: "fields",
      term: "fields",
      range: "fields",
      aggs: "named_aggregation",
    },
    value_literals: {
      order: ["asc", "desc"],
      calendar_interval: ["minute", "hour", "day", "week", "month"],
    },
  };

  let completion;
  let source;

  beforeEach(() => {
    completion = new JsonDslCompletion(schema, {
      keywords: ["query", "aggs", "sort", "bool"],
      context_schema: contextSchema,
    });
    source = completion.createCompletionSource();
  });

  describe("key position at root", () => {
    it("suggests context_schema.root when the doc is empty", () => {
      const doc = '{"}';
      //           ^ cursor just inside the open brace / quote
      const ctx = makeContext(doc, 2);
      const result = source(ctx);
      expect(labels(result).sort()).toEqual(
        ["aggs", "query", "size", "sort"].sort(),
      );
    });

    it("suggests root keys inside a non-empty but root-level object", () => {
      const doc = '{"size": 10, ""}';
      //                         ^ pos after opening quote of 2nd key
      const ctx = makeContext(doc, 14);
      const result = source(ctx);
      expect(labels(result)).toContain("query");
      expect(labels(result)).toContain("aggs");
      expect(labels(result)).not.toContain("match");
    });
  });

  describe("nested key positions", () => {
    it('suggests query-type keys inside {"query": {↓}}', () => {
      const doc = '{"query": {""}}';
      //                     ^ pos right after opening quote
      const ctx = makeContext(doc, 12);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("match");
      expect(ls).toContain("bool");
      expect(ls).toContain("range");
      // NOT the root keys
      expect(ls).not.toContain("query");
      expect(ls).not.toContain("aggs");
    });

    it('suggests bool leaves inside {"query": {"bool": {↓}}}', () => {
      const doc = '{"query": {"bool": {""}}}';
      //                              ^ pos right after opening quote
      const ctx = makeContext(doc, 21);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("must");
      expect(ls).toContain("should");
      expect(ls).toContain("filter");
      // not query keywords
      expect(ls).not.toContain("match");
      expect(ls).not.toContain("query");
    });

    it('suggests field names inside {"match": {↓}} (:fields marker)', () => {
      const doc = '{"match": {""}}';
      const ctx = makeContext(doc, 12);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("name");
      expect(ls).toContain("age");
      expect(ls).toContain("total");
      // not keywords
      expect(ls).not.toContain("match");
      expect(ls).not.toContain("bool");
    });

    it('suggests query-type keys inside must array element: {"must": [{↓}]}', () => {
      const doc = '{"must": [{""}]}';
      const ctx = makeContext(doc, 12);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("match");
      expect(ls).toContain("bool");
      expect(ls).toContain("range");
    });

    it("returns no suggestions inside :named_aggregation (free-form bucket name)", () => {
      const doc = '{"aggs": {""}}';
      const ctx = makeContext(doc, 11);
      const result = source(ctx);
      expect(result).toBeNull();
    });
  });

  describe("value position", () => {
    it('suggests value_literals for {"order": "↓"}', () => {
      const doc = '{"order": ""}';
      //                      ^ inside the value string
      const ctx = makeContext(doc, 11);
      const result = source(ctx);
      expect(labels(result).sort()).toEqual(["asc", "desc"]);
    });

    it("suggests value_literals for calendar_interval", () => {
      const doc = '{"calendar_interval": ""}';
      const ctx = makeContext(doc, 23);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("day");
      expect(ls).toContain("month");
    });

    it("returns null for keys without value_literals", () => {
      const doc = '{"name": ""}';
      const ctx = makeContext(doc, 10);
      const result = source(ctx);
      expect(result).toBeNull();
    });
  });

  describe("fallback when context_schema is absent", () => {
    it("falls back to flat keywords + fields at every key position", () => {
      const legacy = new JsonDslCompletion(schema, {
        keywords: ["query", "aggs", "match"],
        // no context_schema
      });
      const src = legacy.createCompletionSource();
      const doc = '{""}';
      const ctx = makeContext(doc, 2);
      const result = src(ctx);
      const ls = labels(result);
      expect(ls).toContain("query");
      expect(ls).toContain("match");
      expect(ls).toContain("name"); // field from schema
    });
  });

  describe("range operator grandparent lookup", () => {
    it('suggests gte/lt/etc. inside {"range": {"created_at": {↓}}}', () => {
      const doc = '{"range": {"created_at": {""}}}';
      //           0         1         2         3
      //           0123456789012345678901234567890
      //                                     ^ pos 26 (inside last "")
      const ctx = makeContext(doc, 26);
      const result = source(ctx);
      const ls = labels(result);
      expect(ls).toContain("gte");
      expect(ls).toContain("lte");
      expect(ls).toContain("gt");
      expect(ls).toContain("lt");
      expect(ls).toContain("format");
    });
  });

  describe("partial string value bounds", () => {
    it('replacement range for {"order": "ma↓"} drops the opening quote only', () => {
      const doc = '{"order": "ma"}';
      //           0         1
      //           0123456789012345
      //                       ^ pos 12 (cursor after "ma")
      const ctx = makeContext(doc, 12);
      const result = source(ctx);
      expect(result).not.toBeNull();
      // wordFrom must be _after_ the opening `"` (position 11), not on it
      expect(result.from).toBe(11);
      // wordTo must stop at the closing `"` (position 13)
      expect(result.to).toBe(13);
    });
  });

  describe("malformed / mid-typing JSON tolerance", () => {
    it("still suggests root keys when the JSON is not yet closed", () => {
      const doc = '{"';
      const ctx = makeContext(doc, 2);
      const result = source(ctx);
      // Should not throw; should return something useful
      expect(result).not.toBeNull();
      expect(labels(result)).toContain("query");
    });

    it("handles partial key prefix correctly", () => {
      const doc = '{"que"}';
      //              ^ cursor at position 5 — after "que
      const ctx = makeContext(doc, 5);
      const result = source(ctx);
      expect(labels(result)).toContain("query");
    });
  });
});
