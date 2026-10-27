import { describe, it, expect } from "vitest";
import {
  PostgreSQL,
  MySQL,
  SQLite,
  MSSQL,
  MariaSQL,
  Cassandra,
  PLSQL,
} from "@codemirror/lang-sql";
import {
  toDialectSpec,
  resolveCodeMirrorDialect,
  getDialectConfig,
} from "../../js/lib/dialect_config.js";

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

describe("resolveCodeMirrorDialect", () => {
  const emptyCfg = { keywords: [], types: [] };

  it("returns built-in dialects for known aliases", () => {
    expect(resolveCodeMirrorDialect("postgres", emptyCfg)).toBe(PostgreSQL);
    expect(resolveCodeMirrorDialect("postgresql", emptyCfg)).toBe(PostgreSQL);
    expect(resolveCodeMirrorDialect("mysql", emptyCfg)).toBe(MySQL);
    expect(resolveCodeMirrorDialect("mariadb", emptyCfg)).toBe(MariaSQL);
    expect(resolveCodeMirrorDialect("mariasql", emptyCfg)).toBe(MariaSQL);
    expect(resolveCodeMirrorDialect("sqlite", emptyCfg)).toBe(SQLite);
    expect(resolveCodeMirrorDialect("mssql", emptyCfg)).toBe(MSSQL);
    expect(resolveCodeMirrorDialect("sqlserver", emptyCfg)).toBe(MSSQL);
    expect(resolveCodeMirrorDialect("cassandra", emptyCfg)).toBe(Cassandra);
    expect(resolveCodeMirrorDialect("cql", emptyCfg)).toBe(Cassandra);
    expect(resolveCodeMirrorDialect("plsql", emptyCfg)).toBe(PLSQL);
    expect(resolveCodeMirrorDialect("oracle", emptyCfg)).toBe(PLSQL);
  });

  it("synthesizes a SQLDialect for unknown names and carries the spec", () => {
    const config = {
      keywords: ["SELECT", "FROM"],
      types: ["INTEGER"],
      dialect_spec: {
        identifier_quotes: "`",
        hash_comments: true,
        double_quoted_strings: false,
        case_insensitive_identifiers: true,
      },
    };

    const dialect = resolveCodeMirrorDialect("clickhouse", config);

    // SQLDialect.define() returns an object with a `.spec` carrying the
    // merged config (public surface per @codemirror/lang-sql).
    expect(dialect).not.toBe(PostgreSQL);
    expect(dialect.spec.identifierQuotes).toBe("`");
    expect(dialect.spec.hashComments).toBe(true);
    expect(dialect.spec.doubleQuotedStrings).toBe(false);
    expect(dialect.spec.caseInsensitiveIdentifiers).toBe(true);
    // CodeMirror looks words up lowercased, so the lists are lowercased.
    expect(dialect.spec.keywords).toBe("select from");
    expect(dialect.spec.types).toBe("integer");
  });

  it("synthesized dialect works without any dialect_spec", () => {
    const config = { keywords: ["a"], types: ["b"] };
    const dialect = resolveCodeMirrorDialect("myadapter", config);
    expect(dialect.spec.keywords).toBe("a");
    expect(dialect.spec.types).toBe("b");
    expect(dialect.spec.hashComments).toBeUndefined();
  });
});

describe("getDialectConfig", () => {
  // What an external adapter such as lotus_clickhouse sends: its
  // `query_language/0` as the language, uppercase keywords, snake_case keys.
  const clickhouse = {
    language: "sql:clickhouse",
    keywords: ["PREWHERE", "FINAL", "SETTINGS"],
    types: ["UInt64", "LowCardinality"],
    functions: [{ name: "toDate", detail: "Convert to Date", args: "(expr)" }],
    context_boundaries: ["PREWHERE", "SETTINGS"],
    dialect_spec: { identifier_quotes: '"`', hash_comments: true },
    tokenizer: { "backslash_escapes?": true },
  };

  it("merges a sql:<dialect> config with the SQL defaults, as for plain sql", async () => {
    const config = await getDialectConfig("clickhouse-merge", () =>
      Promise.resolve(clickhouse),
    );

    expect(config.language).toBe("sql");
    expect(config.keywords).toContain("select");
    expect(config.keywords).toContain("prewhere");
    expect(config.types).toContain("uint64");
    expect(config.functions.map((f) => f.name)).toContain("COUNT");
    expect(config.functions.map((f) => f.name)).toContain("toDate");
    expect(config.contextBoundaries).toEqual(["PREWHERE", "SETTINGS"]);
    expect(config.dialect_spec).toEqual(clickhouse.dialect_spec);
    expect(config.tokenizer).toEqual(clickhouse.tokenizer);
  });

  it("highlights the SQL defaults and the adapter's keywords in a synthesized dialect", async () => {
    const config = await getDialectConfig("clickhouse-highlight", () =>
      Promise.resolve(clickhouse),
    );
    const words = resolveCodeMirrorDialect("clickhouse", config).spec.keywords.split(" ");

    expect(words).toContain("select");
    expect(words).toContain("prewhere");
  });

  it("passes a json:<dsl> config through unchanged", async () => {
    const json = { language: "json:elasticsearch", keywords: ["query"] };
    const config = await getDialectConfig("json:merge-test", () => Promise.resolve(json));
    expect(config).toBe(json);
  });
});
