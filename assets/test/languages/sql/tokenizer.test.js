import { describe, it, expect } from "vitest";
import {
  tokenize,
  scan,
  TYPES,
  profileFor,
  identifierName,
  isCode,
} from "../../../js/lib/languages/sql/tokenizer.js";

const PG = profileFor("postgres");
const MY = profileFor("mysql");
const LITE = profileFor("sqlite");
const ANSI = profileFor("sql");

// The tokens as [type, text], without whitespace.
const toks = (text, profile = ANSI) =>
  tokenize(text, profile)
    .filter((t) => t.type !== "whitespace")
    .map((t) => [t.type, text.slice(t.start, t.end)]);

const typeOf = (text, profile, piece) => {
  const found = tokenize(text, profile).find((t) => text.slice(t.start, t.end) === piece);
  return found && found.type;
};

describe("tokenize", () => {
  it("covers the text exactly, token after token", () => {
    const text = "SELECT a.b, 'x''y' -- c\n/* d */ FROM \"t\" WHERE n >= 1.5e-3;";
    for (const profile of [PG, MY, LITE, ANSI]) {
      const tokens = tokenize(text, profile);
      let at = 0;
      for (const t of tokens) {
        expect(t.start).toBe(at);
        expect(t.end).toBeGreaterThan(t.start);
        at = t.end;
      }
      expect(at).toBe(text.length);
    }
  });

  it("gives words, numbers and punctuation", () => {
    expect(toks("SELECT a.b, f(1.5) FROM t;")).toEqual([
      ["word", "SELECT"],
      ["word", "a"],
      ["dot", "."],
      ["word", "b"],
      ["comma", ","],
      ["word", "f"],
      ["lparen", "("],
      ["number", "1.5"],
      ["rparen", ")"],
      ["word", "FROM"],
      ["word", "t"],
      ["semicolon", ";"],
    ]);
    expect(toks("1e-5 0x1F .5")).toEqual([
      ["number", "1e-5"],
      ["number", "0x1F"],
      ["number", ".5"],
    ]);
  });

  describe("strings and quoted identifiers", () => {
    it("takes doubled quotes as part of them", () => {
      expect(toks(`'it''s' "a""b"`)).toEqual([
        ["string", "'it''s'"],
        ["quoted", '"a""b"'],
      ]);
    });

    it("runs an unterminated one to the end", () => {
      expect(toks("SELECT 'abc")).toEqual([
        ["word", "SELECT"],
        ["string", "'abc"],
      ]);
      expect(toks('SELECT "abc')).toEqual([
        ["word", "SELECT"],
        ["quoted", '"abc'],
      ]);
      expect(toks("SELECT 'a\\", MY)).toEqual([
        ["word", "SELECT"],
        ["string", "'a\\"],
      ]);
    });

    it("has MySQL's double-quoted strings, backticks and backslash escapes", () => {
      expect(toks(`"a;b" \`c\`\`d\` 'e\\'f'`, MY)).toEqual([
        ["string", '"a;b"'],
        ["quoted", "`c``d`"],
        ["string", "'e\\'f'"],
      ]);
    });

    it("has no backslash escapes in standard strings", () => {
      expect(toks("'a\\' x", PG)).toEqual([
        ["string", "'a\\'"],
        ["word", "x"],
      ]);
    });

    it("takes Postgres's E'' strings with backslash escapes, only as a prefix", () => {
      expect(toks("E'a\\'b' e'c\\'d'", PG)).toEqual([
        ["string", "E'a\\'b'"],
        ["string", "e'c\\'d'"],
      ]);
      // The E of a name is the name's.
      expect(toks("nameE'a\\' x", PG)).toEqual([
        ["word", "nameE"],
        ["string", "'a\\'"],
        ["word", "x"],
      ]);
    });

    it("takes N'', X'', B'' and U&'' as plain strings", () => {
      expect(toks("N'a\\' X'1F' B'01' U&'d'", PG)).toEqual([
        ["word", "N"],
        ["string", "'a\\'"],
        ["word", "X"],
        ["string", "'1F'"],
        ["word", "B"],
        ["string", "'01'"],
        ["word", "U"],
        ["operator", "&"],
        ["string", "'d'"],
      ]);
    });

    it("has SQLite's [bracketed] and backquoted identifiers", () => {
      expect(toks("SELECT [a b], `c` FROM [t]", LITE)).toEqual([
        ["word", "SELECT"],
        ["quoted", "[a b]"],
        ["comma", ","],
        ["quoted", "`c`"],
        ["word", "FROM"],
        ["quoted", "[t]"],
      ]);
      expect(toks("[open", LITE)).toEqual([["quoted", "[open"]]);
    });

    it("names a quoted identifier without its quotes", () => {
      const text = `"a""b" \`c\` [d e] plain`;
      const names = tokenize(text, { ...ANSI, identifierQuotes: ['"', "`", "["] })
        .filter(isCode)
        .map((t) => identifierName(text, t));
      expect(names).toEqual(['a"b', "c", "d e", "plain"]);
    });
  });

  describe("dollar quotes (Postgres)", () => {
    it("are strings, with or without a tag", () => {
      expect(toks("$$a;'b$$ $fn$ x $$ y $fn$", PG)).toEqual([
        ["string", "$$a;'b$$"],
        ["string", "$fn$ x $$ y $fn$"],
      ]);
    });

    it("open only where an identifier does not go on", () => {
      expect(toks("foo$bar$ x", PG)).toEqual([
        ["word", "foo$bar$"],
        ["word", "x"],
      ]);
      expect(toks("$1 + $2", PG)).toEqual([
        ["word", "$1"],
        ["operator", "+"],
        ["word", "$2"],
      ]);
    });

    it("run an unterminated one to the end", () => {
      expect(toks("SELECT $$abc; d", PG)).toEqual([
        ["word", "SELECT"],
        ["string", "$$abc; d"],
      ]);
    });

    it("are not in MySQL", () => {
      expect(typeOf("SELECT $$a$$", MY, "$$a$$")).toBe("word");
    });
  });

  describe("comments", () => {
    it("has -- and /* */ comments", () => {
      expect(toks("a -- b; c\nd /* e; */ f")).toEqual([
        ["word", "a"],
        ["comment", "-- b; c"],
        ["word", "d"],
        ["comment", "/* e; */"],
        ["word", "f"],
      ]);
    });

    it("nests block comments in Postgres only", () => {
      expect(toks("/* a /* b */ c */ d", PG)).toEqual([
        ["comment", "/* a /* b */ c */"],
        ["word", "d"],
      ]);
      expect(toks("/* a /* b */ c", MY)[0]).toEqual(["comment", "/* a /* b */"]);
      expect(toks("/* a /* b */ c", LITE)[0]).toEqual(["comment", "/* a /* b */"]);
    });

    it("runs an unterminated comment to the end", () => {
      expect(toks("a /* b; c")).toEqual([
        ["word", "a"],
        ["comment", "/* b; c"],
      ]);
    });

    it("has MySQL's # comments, and its -- only before a space", () => {
      expect(toks("a # b\nc", MY)).toEqual([
        ["word", "a"],
        ["comment", "# b"],
        ["word", "c"],
      ]);
      expect(toks("5--1", MY)).toEqual([
        ["number", "5"],
        ["operator", "-"],
        ["operator", "-"],
        ["number", "1"],
      ]);
      expect(toks("5 -- 1", MY)).toEqual([
        ["number", "5"],
        ["comment", "-- 1"],
      ]);
      expect(toks("5 --\tx", MY)[1]).toEqual(["comment", "--\tx"]);
      expect(toks("5 --", MY)[1]).toEqual(["comment", "--"]);
      // Elsewhere -- is always a comment, and # is an operator.
      expect(toks("5--1", PG)).toEqual([
        ["number", "5"],
        ["comment", "--1"],
      ]);
      expect(typeOf("a # b", PG, "#")).toBe("operator");
    });

    it("reads MySQL's /*! … */ as code, and keeps /*+ … */ hints as comments", () => {
      expect(toks("SELECT /*!40001 SQL_NO_CACHE */ a; b", MY)).toEqual([
        ["word", "SELECT"],
        ["operator", "/*!"],
        ["number", "40001"],
        ["word", "SQL_NO_CACHE"],
        ["operator", "*/"],
        ["word", "a"],
        ["semicolon", ";"],
        ["word", "b"],
      ]);
      expect(toks("SELECT /*+ BKA(t) */ a", MY)[1]).toEqual(["comment", "/*+ BKA(t) */"]);
      expect(toks("/*! a */", PG)).toEqual([["comment", "/*! a */"]]);
    });
  });

  describe("Lotus syntax", () => {
    it("has {{variables}}", () => {
      expect(toks("x = {{user_id}} AND y = {{ bad }} {{1x}}")).toEqual([
        ["word", "x"],
        ["operator", "="],
        ["variable", "{{user_id}}"],
        ["word", "AND"],
        ["word", "y"],
        ["operator", "="],
        ["operator", "{"],
        ["operator", "{"],
        ["word", "bad"],
        ["operator", "}"],
        ["operator", "}"],
        ["operator", "{"],
        ["operator", "{"],
        ["number", "1x"],
        ["operator", "}"],
        ["operator", "}"],
      ]);
    });

    it("does not read a variable in a string or a comment", () => {
      expect(toks("'{{a}}' -- {{b}}")).toEqual([
        ["string", "'{{a}}'"],
        ["comment", "-- {{b}}"],
      ]);
    });

    it("opens [[ blocks, and closes only an open one", () => {
      expect(toks("WHERE 1=1 [[AND a = {{a}}]] x]]")).toEqual([
        ["word", "WHERE"],
        ["number", "1"],
        ["operator", "="],
        ["number", "1"],
        ["block_open", "[["],
        ["word", "AND"],
        ["word", "a"],
        ["operator", "="],
        ["variable", "{{a}}"],
        ["block_close", "]]"],
        ["word", "x"],
        ["operator", "]"],
        ["operator", "]"],
      ]);
    });

    it("leaves array syntax alone", () => {
      const types = (text) =>
        tokenize(text, PG)
          .map((t) => t.type)
          .filter((t) => t === "block_open" || t === "block_close");
      expect(types("SELECT ARRAY[[1,2],[3,4]]")).toEqual([]);
      expect(types("SELECT arr[1][2]")).toEqual([]);
      expect(types("SELECT f(x)[[1]]")).toEqual([]);
      expect(types("SELECT 1 [[AND x]]")).toEqual(["block_open", "block_close"]);
    });

    it("opens [[ in SQLite too", () => {
      expect(toks("WHERE [[AND [a] = 1]]", LITE)).toEqual([
        ["word", "WHERE"],
        ["block_open", "[["],
        ["word", "AND"],
        ["quoted", "[a]"],
        ["operator", "="],
        ["number", "1"],
        ["block_close", "]]"],
      ]);
    });
  });

  it("reads non-ASCII names as words, and keeps surrogate pairs whole", () => {
    expect(toks("SELECT prénom, 名前 FROM café 😀")).toEqual([
      ["word", "SELECT"],
      ["word", "prénom"],
      ["comma", ","],
      ["word", "名前"],
      ["word", "FROM"],
      ["word", "café"],
      ["word", "😀"],
    ]);
  });

  it("scans a megabyte well under 50 ms", () => {
    const unit =
      "SELECT o.id, 'a;b''c' AS s, \"Q\" FROM orders o -- note\nWHERE x = {{x}} /* c */ [[AND y > 1.5]];\n";
    const text = unit.repeat(Math.ceil(1_000_000 / unit.length));

    // Once the JIT has compiled it, the middle of five runs.
    for (let k = 0; k < 4; k++) scan(text, PG);
    const times = [];
    let count = 0;
    for (let k = 0; k < 5; k++) {
      const started = performance.now();
      count = scan(text, PG).count;
      times.push(performance.now() - started);
    }
    times.sort((a, b) => a - b);

    expect(count).toBeGreaterThan(400_000);
    expect(times[2]).toBeLessThan(50);
  });

  it("scans to the same tokens it gives as objects", () => {
    const text = "SELECT 'a' -- b\n, \"c\" FROM t [[AND {{x}}]];";
    const { types, starts, count } = scan(text, PG);
    const tokens = tokenize(text, PG);
    expect(count).toBe(tokens.length);
    tokens.forEach((t, k) => {
      expect(TYPES[types[k]]).toBe(t.type);
      expect(starts[k]).toBe(t.start);
      expect(starts[k + 1]).toBe(t.end);
    });
  });
});

describe("profileFor", () => {
  it("takes the server's profile over the dialect's", () => {
    const profile = profileFor("sql", {
      string_quotes: ["'"],
      identifier_quotes: ["`"],
      line_comments: ["--", "#"],
      "block_comments?": true,
      "nested_block_comments?": false,
      "dollar_quotes?": false,
      "backslash_escapes?": true,
    });
    expect(profile.identifierQuotes).toEqual(["`"]);
    expect(profile.lineComments).toEqual(["--", "#"]);
    expect(profile.backslashEscapes).toBe(true);
  });

  it("keeps SQLite's [bracketed] identifiers under the server's profile", () => {
    const profile = profileFor("sqlite", { identifier_quotes: ['"', "`"] });
    expect(profile.identifierQuotes).toEqual(['"', "`", "["]);
  });

  it("is ANSI SQL for a dialect it does not know", () => {
    const profile = profileFor("unknown");
    expect(profile.stringQuotes).toEqual(["'"]);
    expect(profile.identifierQuotes).toEqual(['"']);
    expect(profile.dollarQuotes).toBe(false);
  });
});
