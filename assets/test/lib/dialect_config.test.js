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
    expect(dialect.spec.keywords).toBe("SELECT FROM");
    expect(dialect.spec.types).toBe("INTEGER");
  });

  it("synthesized dialect works without any dialect_spec", () => {
    const config = { keywords: ["a"], types: ["b"] };
    const dialect = resolveCodeMirrorDialect("myadapter", config);
    expect(dialect.spec.keywords).toBe("a");
    expect(dialect.spec.types).toBe("b");
    expect(dialect.spec.hashComments).toBeUndefined();
  });
});
