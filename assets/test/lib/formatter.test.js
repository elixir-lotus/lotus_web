import { describe, it, expect } from "vitest";
import { format, supportsFormatting } from "../../js/lib/formatter.js";

const QUERY =
  "select id, name from users where 1=1 [[AND status = {{order_status}}]] " +
  "[[AND email LIKE '%' || {{ user_email }} || '%']] and created_at >= {{since}} " +
  "order by id limit {{limit}}";

const DIALECTS = ["postgres", "mysql", "sqlite", "clickhouse", "mssql", "sql", "unknown"];

describe("format SQL", () => {
  it("lays the statement out on lines", () => {
    const result = format("select id, name from users where id = 1", "postgres");
    expect(result).toEqual({
      ok: true,
      content: "select\n  id,\n  name\nfrom\n  users\nwhere\n  id = 1",
    });
  });

  it("keeps the keywords' case", () => {
    const result = format("SELECT id FROM users", "postgres");
    expect(result.content).toBe("SELECT\n  id\nFROM\n  users");
  });

  for (const dialect of DIALECTS) {
    it(`keeps Lotus variables and optional clauses as written (${dialect})`, () => {
      const result = format(QUERY, dialect);

      expect(result.ok).toBe(true);
      expect(result.content).toContain("[[AND status = {{order_status}}]]");
      expect(result.content).toContain("[[AND email LIKE '%' || {{ user_email }} || '%']]");
      expect(result.content).toContain(">= {{since}}");
      expect(result.content).toContain("{{limit}}");
    });
  }

  it("keeps an optional clause over several lines as written", () => {
    const query = "select * from t where 1 = 1\n[[\n  AND a = {{a}}\n]]";
    const result = format(query, "postgres");
    expect(result.ok).toBe(true);
    expect(result.content).toContain("[[\n  AND a = {{a}}\n]]");
  });

  it("is the same the second time", () => {
    const once = format(QUERY, "postgres").content;
    expect(format(once, "postgres").content).toBe(once);
  });

  it("formats each statement of several", () => {
    const result = format("select 1; select 2;", "postgres");
    expect(result.content).toBe("select\n  1;\n\nselect\n  2;");
  });

  it("fails with a short message on SQL it cannot read", () => {
    const result = format("select (1", "postgres");
    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/^Parse error/);
    expect(result.error).not.toContain("\n");
  });

  it("leaves blank text as it is", () => {
    expect(format("  \n", "postgres")).toEqual({ ok: true, content: "  \n" });
  });
});

describe("format JSON", () => {
  it("pretty-prints JSON languages", () => {
    expect(format('{"query":{"match_all":{}}}', "json:elasticsearch")).toEqual({
      ok: true,
      content: '{\n  "query": {\n    "match_all": {}\n  }\n}',
    });
  });

  it("fails on JSON it cannot parse", () => {
    expect(format("{", "json:elasticsearch").ok).toBe(false);
  });
});

describe("supportsFormatting", () => {
  it("is for a known language only", () => {
    expect(supportsFormatting("postgres")).toBe(true);
    expect(supportsFormatting("json:elasticsearch")).toBe(true);
    expect(supportsFormatting("")).toBe(false);
    expect(supportsFormatting(null)).toBe(false);
  });
});
