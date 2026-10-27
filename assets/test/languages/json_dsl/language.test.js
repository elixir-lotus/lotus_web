import { describe, it, expect } from "vitest";
import { EditorState } from "@codemirror/state";
import { foldable, getIndentation, ensureSyntaxTree, syntaxTree } from "@codemirror/language";
import { highlightTree, classHighlighter } from "@lezer/highlight";
import {
  jsonTemplate,
  templateDiagnostics,
} from "../../../js/lib/languages/json_dsl/language.js";
import esConfig from "../../fixtures/elasticsearch_editor_config.json";

const messages = (text, opts) => templateDiagnostics(text, opts).map((d) => `${d.severity}: ${d.message}`);

// The highlighted pieces of `text`: [text, classes].
function highlights(text) {
  const state = EditorState.create({ doc: text, extensions: [jsonTemplate()] });
  ensureSyntaxTree(state, state.doc.length, 5000);
  const out = [];
  highlightTree(syntaxTree(state), classHighlighter, (from, to, classes) => {
    out.push([text.slice(from, to), classes]);
  });
  return out;
}

describe("highlighting", () => {
  it("reads keys and values, through a bare variable", () => {
    const h = highlights('{"size": {{n}}, "query": {"term": {"status": "paid"}}, "x": [1, true, null]}');
    const of = (piece) => h.filter(([t]) => t === piece).map(([, c]) => c);
    expect(of('"query"')).toEqual(["tok-propertyName"]);
    expect(of('"status"')).toEqual(["tok-propertyName"]);
    expect(of('"paid"')).toEqual(["tok-string"]);
    expect(of("{{n}}")[0]).toContain("tok-variableName");
    expect(of("1")).toEqual(["tok-number"]);
    expect(of("true")).toEqual(["tok-bool"]);
  });

  it("reads [[ ]] as a block only outside an array, as Lotus does", () => {
    const h = highlights('{"a": 1 [[, "b": 2]], "c": [[1, 2], [3, 4]]}');
    const meta = h.filter(([, c]) => c.includes("tok-meta")).map(([t]) => t);
    expect(meta).toEqual(["[[", "]]"]);
  });
});

describe("indentation and folding", () => {
  it("indents by the open braces", () => {
    const text = '{\n  "query": {\n    "bool": {\n    }\n  }\n}';
    const state = EditorState.create({ doc: text, extensions: [jsonTemplate()] });
    ensureSyntaxTree(state, state.doc.length, 5000);
    const lineIndent = (n) => getIndentation(state, state.doc.line(n).from);
    expect([2, 3, 4, 5, 6].map(lineIndent)).toEqual([2, 4, 4, 2, 0]);
  });

  it("folds an object, a brace in a string aside", () => {
    const text = '{\n  "q": "{",\n  "a": {\n    "b": 1\n  }\n}';
    const state = EditorState.create({ doc: text, extensions: [jsonTemplate()] });
    const line = state.doc.line(3);
    expect(foldable(state, line.from, line.to)).toEqual({ from: line.to, to: text.lastIndexOf("  }") + 2 });
  });
});

describe("error markers", () => {
  it("marks nothing in a valid template", () => {
    expect(messages('{"size": {{n}}, "q": "*{{q}}*" [[, "from": {{f}}]]}')).toEqual([]);
    expect(messages("")).toEqual([]);
  });

  it("marks what Lotus refuses, where", () => {
    const d = templateDiagnostics('{"a": 1,}');
    expect(d).toEqual([
      { from: 7, to: 8, severity: "error", message: "Trailing comma: JSON takes none after the last property" },
    ]);
    expect(messages('{"a": "x" // note\n}')).toContain("error: Comments are not allowed in JSON");
    expect(messages("{a: 1}")).toContain("error: A property name takes double quotes");
    expect(messages('[{"a": 1}]')).toContain("error: The request must be a JSON object, in { }");
    expect(messages('{"a": {{ x }}}')[0]).toMatch(/A variable is \{\{name\}\}/);
  });

  it("marks a block that breaks the request when it is left out", () => {
    expect(messages('{"a": 1 [[, "b": {{b}},]]}')).toEqual([
      "error: Trailing comma: JSON takes none after the last property",
    ]);
    expect(messages('{"a": [[{{x}}]]}')).toEqual([
      "error: Expected a value (with the optional blocks left out)",
    ]);
  });

  it("takes a block after an item of an array, as Lotus does", () => {
    expect(messages('{"filter": [{"match_all": {}} [[, {"term": {"a": "{{a}}"}}]]]}')).toEqual([]);
  });

  it("explains a block at the start of an array's items, which Lotus reads as brackets", () => {
    const m = messages('{"filter": [ [[ {"term": {"a": "{{a}}"}}, ]] {"match_all": {}}]}');
    expect(m.some((x) => /warning: In an array, Lotus reads \[\[ as an optional block only after an item/.test(x))).toBe(true);
    // A nested array that parses gets no such word.
    expect(messages('{"c": [[1, 2], [3, 4]]}')).toEqual([]);
  });

  it("warns about a duplicate key, an unknown key and a second query clause", () => {
    const opts = { contextSchema: esConfig.context_schema };
    expect(messages('{"size": 1, "size": 2}', opts)).toEqual([
      'warning: Duplicate key "size": only one of them is sent',
    ]);
    expect(messages('{"query": {"bool": {"must": [], "musts": []}}}', opts)).toEqual([
      'warning: Unknown key "musts" here',
    ]);
    expect(messages('{"query": {"term": {"a": 1}, "match": {"b": 2}}}', opts)).toEqual([
      "warning: A query clause holds one query: combine them in a bool",
    ]);
    // Fields, aggregation names and open objects take any key.
    expect(
      messages(
        '{"query": {"term": {"anything.at.all": 1}}, "aggs": {"mine": {"terms": {"field": "x"}, "meta": {"y": 1}}}}',
        opts,
      ),
    ).toEqual([]);
  });
});
