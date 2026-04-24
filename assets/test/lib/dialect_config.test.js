import { describe, it, expect } from "vitest";
import { toDialectSpec } from "../../js/lib/dialect_config.js";

describe("toDialectSpec", () => {
  it("returns empty object for null / undefined / non-object input", () => {
    expect(toDialectSpec(null)).toEqual({});
    expect(toDialectSpec(undefined)).toEqual({});
    expect(toDialectSpec("not a spec")).toEqual({});
  });

  it("maps snake_case keys to the exact camelCase names SQLDialect.define expects", () => {
    const spec = {
      identifier_quotes: "`",
      operator_chars: "*+-<>!=",
      hash_comments: true,
      slash_comments: false,
      double_quoted_strings: false,
      double_dollar_quoted_strings: true,
      backslash_escapes: true,
      space_after_dashes: false,
      case_insensitive_identifiers: true,
      char_set_casts: false,
      plsql_quoting_mechanism: false,
      unquoted_bit_literals: true,
      treat_bits_as_bytes: false,
      special_var: "@",
      builtin: "true false null",
    };

    expect(toDialectSpec(spec)).toEqual({
      identifierQuotes: "`",
      operatorChars: "*+-<>!=",
      hashComments: true,
      slashComments: false,
      doubleQuotedStrings: false,
      doubleDollarQuotedStrings: true,
      backslashEscapes: true,
      spaceAfterDashes: false,
      caseInsensitiveIdentifiers: true,
      charSetCasts: false,
      plsqlQuotingMechanism: false,
      unquotedBitLiterals: true,
      treatBitsAsBytes: false,
      specialVar: "@",
      builtin: "true false null",
    });
  });

  it("passes unknown keys through unchanged (forward-compat with future SQLDialectSpec fields)", () => {
    const spec = { hash_comments: true, futureField: "hello" };
    expect(toDialectSpec(spec)).toEqual({
      hashComments: true,
      futureField: "hello",
    });
  });

  it("preserves falsy values", () => {
    expect(toDialectSpec({ hash_comments: false })).toEqual({
      hashComments: false,
    });
  });
});
