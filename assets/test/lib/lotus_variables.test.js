import { describe, it, expect } from "vitest";
import {
  extractVariables,
  variableRanges,
  variableProfile,
} from "../../js/lib/plugins/lotus_variables.js";

// The server's lexical profile for ClickHouse (Lotus.Source.Adapter.lexical_profile/1
// with lotus_clickhouse's dialect_spec), as fetch_dialect_config sends it.
const CLICKHOUSE = {
  string_quotes: ["'"],
  identifier_quotes: ['"', "`"],
  line_comments: ["--", "#"],
  "block_comments?": true,
  "backslash_escapes?": true,
  "dollar_quotes?": true,
};

const ELASTICSEARCH = {
  string_quotes: ['"'],
  identifier_quotes: [],
  line_comments: [],
  "block_comments?": false,
  "backslash_escapes?": true,
};

describe("extractVariables", () => {
  it("finds variables in code and in string literals, in order, once each", () => {
    const sql = "SELECT * FROM t WHERE a = {{a}} AND b LIKE '%{{b}}%' AND c = {{a}}";
    expect(extractVariables(sql)).toEqual(["a", "b"]);
  });

  it("does not count a variable in a comment or a quoted identifier", () => {
    const sql = [
      "SELECT {{id}} AS x -- {{in_dash_comment}}",
      "/* {{in_block_comment}} */",
      'FROM t WHERE "{{quoted_ident}}" = 1',
    ].join("\n");
    expect(extractVariables(sql)).toEqual(["id"]);
  });

  it("follows the server's placeholder grammar: no spaces, no leading digit", () => {
    expect(extractVariables("SELECT {{ spaced }}, {{1x}}, {{ok_1}}")).toEqual(["ok_1"]);
    expect(extractVariables("SELECT '{{{a}}}'")).toEqual(["a"]);
  });

  it("finds variables inside [[optional]] clauses", () => {
    expect(extractVariables("SELECT 1 [[WHERE a = {{a}}]]")).toEqual(["a"]);
  });

  it("uses the source's lexical rules: ClickHouse # comments, backticks and \\' escapes", () => {
    const profile = variableProfile("clickhouse", CLICKHOUSE);
    const sql = [
      "SELECT {{a}} # {{hash_comment}}",
      ", `{{backtick}}`",
      ", 'it\\'s {{b}}'",
    ].join("\n");

    expect(extractVariables(sql, profile)).toEqual(["a", "b"]);
    // Read as ANSI SQL, the # comment and the backticks are code.
    expect(extractVariables(sql)).toContain("hash_comment");
  });

  it("uses MySQL's built-in rules without a server profile", () => {
    const profile = variableProfile("mysql");
    expect(extractVariables("SELECT {{a}} # {{b}}", profile)).toEqual(["a"]);
  });

  it("reads a JSON DSL's double-quoted strings as strings, with or without the server's profile", () => {
    const body = '{"query": {"term": {"user": "{{user}}"}}, "size": {{size}}}';
    expect(extractVariables(body, variableProfile("json:elasticsearch"))).toEqual([
      "user",
      "size",
    ]);
    expect(
      extractVariables(body, variableProfile("json:elasticsearch", ELASTICSEARCH)),
    ).toEqual(["user", "size"]);
  });
});

describe("variableRanges", () => {
  it("gives the range of each variable the server sees", () => {
    const sql = "SELECT {{a}} -- {{b}}\n, '%{{c}}%'";
    const ranges = variableRanges(sql).map(({ from, to }) => sql.slice(from, to));
    expect(ranges).toEqual(["{{a}}", "{{c}}"]);
  });
});
