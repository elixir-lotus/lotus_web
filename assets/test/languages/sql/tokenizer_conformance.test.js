// The editor's tokenizer reads SQL as Lotus does. The fixture is what
// Lotus's own tokenizer (`Lotus.Query.Tokenizer`) makes of a corpus, per
// dialect, written by test/lotus/web/tokenizer_conformance_test.exs; each
// case here must give the same strings, identifiers, comments, variables
// and `[[ ]]` blocks, with the same text.
import { describe, it, expect } from "vitest";
import {
  tokenize,
  profileFor,
} from "../../../js/lib/languages/sql/tokenizer.js";
import fixture from "../../fixtures/tokenizer_conformance.json";

const KINDS = {
  string: "string",
  quoted: "identifier",
  comment: "comment",
  variable: "variable",
  block_open: "block_open",
  block_close: "block_close",
};

// The tokens as [kind, text], code runs merged, as the fixture has them.
function regions(text, profile) {
  const out = [];
  for (const token of tokenize(text, profile)) {
    const kind = KINDS[token.type] || "code";
    const raw = text.slice(token.start, token.end);
    const last = out[out.length - 1];
    if (kind === "code" && last && last[0] === "code") last[1] += raw;
    else out.push([kind, raw]);
  }
  return out;
}

describe("the editor's tokenizer reads SQL as Lotus does", () => {
  for (const [dialect, serverProfile] of Object.entries(fixture.profiles)) {
    const profile = profileFor(dialect, serverProfile);
    const cases = fixture.cases.filter((c) => c.dialect === dialect);

    it(`${dialect}: ${cases.length} statements`, () => {
      const differ = cases
        .filter(
          (c) =>
            JSON.stringify(regions(c.text, profile)) !==
            JSON.stringify(c.regions),
        )
        .map((c) => ({
          text: c.text,
          lotus: c.regions,
          editor: regions(c.text, profile),
        }));

      expect(differ.slice(0, 5)).toEqual([]);
    });
  }
});
