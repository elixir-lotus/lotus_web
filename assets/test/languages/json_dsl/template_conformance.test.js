// The editor reads a JSON source's template as Lotus does. The fixture
// (written by test/lotus/web/tokenizer_conformance_test.exs) has, for a
// corpus of templates, the variables Lotus finds and whether the request
// is a JSON object once its blocks are kept or dropped and its variables
// bound: the editor's parser must find the same variables, and an error
// exactly where Lotus would refuse the request.
import { describe, it, expect } from "vitest";
import {
  parseTokens,
  significantTokens,
  tokensFor,
  templateVariables,
} from "../../../js/lib/languages/json_dsl/parser.js";
import fixture from "../../fixtures/tokenizer_conformance.json";

function valid(text, mode) {
  const { root, errors } = parseTokens(text, tokensFor(significantTokens(text), mode, text));
  return !!root && root.kind === "object" && errors.length === 0;
}

describe("the editor reads JSON templates as Lotus does", () => {
  const cases = fixture.json_templates;

  it(`finds the variables Lotus finds (${cases.length} templates)`, () => {
    const differ = cases
      .filter((c) => JSON.stringify(templateVariables(c.text)) !== JSON.stringify(c.variables))
      .map((c) => ({ text: c.text, lotus: c.variables, editor: templateVariables(c.text) }));
    expect(differ.slice(0, 5)).toEqual([]);
  });

  for (const mode of ["kept", "dropped"]) {
    it(`accepts what Lotus accepts, blocks ${mode}`, () => {
      const differ = cases
        .filter((c) => valid(c.text, mode) !== c[mode])
        .map((c) => ({ text: c.text, lotus: c[mode], editor: valid(c.text, mode) }));
      expect(differ.slice(0, 5)).toEqual([]);
    });
  }
});
