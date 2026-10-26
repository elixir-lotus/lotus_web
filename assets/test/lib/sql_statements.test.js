import { describe, it, expect } from "vitest";
import {
  splitStatements,
  statementAt,
  countStatements,
  runTarget,
  dialectOptions,
} from "../../js/lib/sql_statements.js";

const texts = (text, options) =>
  splitStatements(text, options)
    .filter((s) => s.from !== null)
    .map((s) => text.slice(s.from, s.to));

const at = (text, pos, options) => {
  const range = statementAt(text, pos, options);
  return range && text.slice(range.from, range.to);
};

// The cursor where `|` is, in a text without it.
const cursor = (marked) => [marked.replace("|", ""), marked.indexOf("|")];

describe("splitStatements", () => {
  it("splits at each ;", () => {
    expect(texts("SELECT 1; SELECT 2;\nSELECT 3")).toEqual([
      "SELECT 1",
      "SELECT 2",
      "SELECT 3",
    ]);
  });

  it("gives one statement for a text without ;", () => {
    expect(texts("  SELECT *\nFROM users\n")).toEqual(["SELECT *\nFROM users"]);
  });

  it("ignores ; in single- and double-quoted strings", () => {
    expect(texts(`SELECT 'a;b', 'it''s;'; SELECT "c;d"`)).toEqual([
      `SELECT 'a;b', 'it''s;'`,
      `SELECT "c;d"`,
    ]);
  });

  it("ignores ; in backquoted identifiers (MySQL)", () => {
    expect(texts("SELECT `a;b` FROM t; SELECT 2", dialectOptions("mysql"))).toEqual([
      "SELECT `a;b` FROM t",
      "SELECT 2",
    ]);
  });

  it("ignores ; in dollar-quoted strings (Postgres)", () => {
    const text = "SELECT $$a;b$$; SELECT $fn$ x; $$ y; $fn$; SELECT 3";
    expect(texts(text, dialectOptions("postgres"))).toEqual([
      "SELECT $$a;b$$",
      "SELECT $fn$ x; $$ y; $fn$",
      "SELECT 3",
    ]);
  });

  it("does not take a positional parameter or an identifier's $ for a dollar quote", () => {
    expect(texts("SELECT $1; SELECT a$b$c; SELECT 3", dialectOptions("postgres"))).toEqual([
      "SELECT $1",
      "SELECT a$b$c",
      "SELECT 3",
    ]);
  });

  it("ignores ; in line comments and block comments", () => {
    const text = "SELECT 1 -- one; two\n; /* a; b */ SELECT 2";
    // A statement starts at its code, after the comments before it.
    expect(texts(text)).toEqual(["SELECT 1", "SELECT 2"]);
  });

  it("leaves out a part with only comments and whitespace", () => {
    const text = "SELECT 1; -- the end;\n  /* ; */  ";
    expect(texts(text)).toEqual(["SELECT 1"]);
    expect(countStatements(text)).toBe(1);
  });

  it("nests block comments in Postgres, not in MySQL", () => {
    const text = "/* a /* b */ ; */ SELECT 1; SELECT 2";
    expect(texts(text, dialectOptions("postgres"))).toEqual(["SELECT 1", "SELECT 2"]);
    expect(texts(text, dialectOptions("mysql"))).toEqual([
      "*/ SELECT 1",
      "SELECT 2",
    ]);
  });

  it("takes backslash escapes in MySQL strings, and in Postgres E'' strings", () => {
    expect(texts(String.raw`SELECT 'a\';b'; SELECT 2`, dialectOptions("mysql"))).toEqual([
      String.raw`SELECT 'a\';b'`,
      "SELECT 2",
    ]);
    expect(texts(String.raw`SELECT E'a\';b'; SELECT 2`, dialectOptions("postgres"))).toEqual([
      String.raw`SELECT E'a\';b'`,
      "SELECT 2",
    ]);
    // A standard string ends at the quote after the backslash.
    expect(texts(String.raw`SELECT 'a\'; SELECT 2`, dialectOptions("postgres"))).toEqual([
      String.raw`SELECT 'a\'`,
      "SELECT 2",
    ]);
  });

  it("takes # for a comment in MySQL only", () => {
    expect(texts("SELECT 1 # x; y\n; SELECT 2", dialectOptions("mysql"))).toEqual([
      "SELECT 1",
      "SELECT 2",
    ]);
  });

  it("reads MySQL's 5--1 as arithmetic, and its # as a comment", () => {
    expect(texts("SELECT 5--1; SELECT 2 # x; y\n", dialectOptions("mysql"))).toEqual([
      "SELECT 5--1",
      "SELECT 2",
    ]);
  });

  it("ignores ; in SQLite's [bracketed] identifiers", () => {
    expect(texts("SELECT [a;b] FROM t; SELECT 2", dialectOptions("sqlite"))).toEqual([
      "SELECT [a;b] FROM t",
      "SELECT 2",
    ]);
  });

  it("ends an unterminated string or comment at the end of the text", () => {
    expect(texts("SELECT 1; SELECT 'a; b")).toEqual(["SELECT 1", "SELECT 'a; b"]);
    expect(texts("SELECT 1; /* a; b")).toEqual(["SELECT 1"]);
  });

  it("keeps Lotus variables and optional clauses in their statement", () => {
    const text = "SELECT * FROM t WHERE 1 = 1 [[AND a = {{a}}]]; SELECT {{b}}";
    expect(texts(text)).toEqual([
      "SELECT * FROM t WHERE 1 = 1 [[AND a = {{a}}]]",
      "SELECT {{b}}",
    ]);
  });
});

describe("statementAt", () => {
  const scratch = "SELECT 1;\n\nSELECT 2\nFROM t;\n-- done\n";

  it("gives the statement the cursor is in", () => {
    expect(at(...cursor("SELECT 1;\nSEL|ECT 2;\nSELECT 3"))).toBe("SELECT 2");
  });

  it("gives the statement a ; ends for a cursor just after it", () => {
    expect(at(...cursor("SELECT 1;|\nSELECT 2"))).toBe("SELECT 1");
    expect(at(...cursor("SELECT 1;  |\nSELECT 2"))).toBe("SELECT 1");
  });

  it("gives the next statement for a cursor at its start", () => {
    expect(at(...cursor("SELECT 1; |SELECT 2"))).toBe("SELECT 2");
  });

  it("gives the next statement for a cursor on a line above it", () => {
    expect(at(scratch, scratch.indexOf("\n\n") + 1)).toBe("SELECT 2\nFROM t");
  });

  it("gives the last statement for a cursor in a trailing comment", () => {
    expect(at(scratch, scratch.length)).toBe("SELECT 2\nFROM t");
    expect(at(scratch, scratch.indexOf("done"))).toBe("SELECT 2\nFROM t");
  });

  it("gives the first statement for a cursor in a leading comment-only part", () => {
    expect(at(...cursor("-- note|\n; SELECT 1"))).toBe("SELECT 1");
  });

  it("gives null for a text with no statement", () => {
    expect(statementAt("  -- nothing\n", 3)).toBeNull();
  });
});

describe("runTarget", () => {
  const text = "SELECT 1;\nSELECT 2;";

  it("runs the selection, without the whitespace around it", () => {
    const from = text.indexOf("SELECT 2") - 1;
    const target = runTarget(text, { from, to: from + 9, head: from + 9 });
    expect(target.scope).toBe("selection");
    expect(target.text).toBe("SELECT 2");
    expect(text.slice(target.from, target.to)).toBe("SELECT 2");
  });

  it("runs the statement at the cursor when the text has several", () => {
    const pos = text.indexOf("2");
    const target = runTarget(text, { from: pos, to: pos, head: pos });
    expect(target).toEqual({
      scope: "statement",
      from: 10,
      to: 18,
      text: "SELECT 2",
    });
  });

  it("runs everything when the text has one statement", () => {
    const one = "SELECT 1;\n-- the end";
    expect(runTarget(one, { from: 0, to: 0, head: 0 })).toEqual({
      scope: "all",
      from: null,
      to: null,
      text: one,
    });
  });

  it("does not take a blank selection for one", () => {
    expect(runTarget(text, { from: 9, to: 10, head: 10 }).scope).toBe("statement");
  });
});
