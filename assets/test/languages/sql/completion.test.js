import { describe, it, expect, beforeEach } from "vitest";
import { SqlContextAnalyzer } from "../../../js/lib/languages/sql/context_analyzer.js";
import {
  SqlCompletion,
  clearColumnCache,
  MAX_TABLES,
} from "../../../js/lib/languages/sql/completion.js";
import { profileFor } from "../../../js/lib/languages/sql/tokenizer.js";

// The text with the cursor where `|` is.
const at = (marked) => [marked.replace("|", ""), marked.indexOf("|")];

const analyze = (marked, dialect = "postgres") =>
  new SqlContextAnalyzer({}, profileFor(dialect)).analyzeContext(...at(marked));

const SCHEMA = {
  customers: ["id", "name", "email"],
  orders: ["id", "customer_id", "total", "status"],
  "order items": ["order_id", "sku"],
};

const labels = (result) => (result ? result.options.map((o) => o.label) : []);

const complete = (marked, schema = SCHEMA, options = {}) =>
  new SqlCompletion(schema, {}, { dialect: "postgres", source: "main", ...options }).complete(
    ...at(marked),
  );

describe("SqlContextAnalyzer", () => {
  it("reads the whole table name after FROM", () => {
    const a = analyze("select | from customers");
    expect(a.contextType).toBe("select_columns");
    expect(a.sources).toEqual([{ name: "customers", parts: ["customers"], kind: "table" }]);
  });

  it("knows an alias defined after the cursor", () => {
    const a = analyze("select c.| from customers c");
    expect(a.qualifier).toEqual(["c"]);
    expect(a.sources).toEqual([{ name: "c", parts: ["customers"], kind: "table" }]);
  });

  it("keeps every alias of comma joins", () => {
    const a = analyze("select | from orders o, customers c, reporting.items AS i");
    expect(a.sources.map((s) => [s.name, s.parts.join(".")])).toEqual([
      ["o", "orders"],
      ["c", "customers"],
      ["i", "reporting.items"],
    ]);
  });

  it("reads JOINs and their aliases", () => {
    const a = analyze("select * from orders o left join customers as c on c.id = o.| where 1=1");
    expect(a.contextType).toBe("after_on");
    expect(a.qualifier).toEqual(["o"]);
    expect(a.sources.map((s) => s.name)).toEqual(["o", "c"]);
  });

  it("knows WITH queries as tables, with their plain columns", () => {
    const a = analyze(
      "with recent as (select id, total as amount, o.status from orders o), " +
        "odd as (select count(*) from orders), named (x, y) as (select 1, 2) " +
        "select r.| from recent r",
    );
    expect(a.ctes).toEqual({
      recent: ["id", "amount", "status"],
      odd: null,
      named: ["x", "y"],
    });
    expect(a.sources).toEqual([{ name: "r", parts: ["recent"], kind: "cte" }]);
  });

  it("takes a subquery or a function in FROM for a source with unknown columns", () => {
    const a = analyze("select | from (select 1) sub, generate_series(1, 3) g");
    expect(a.sources).toEqual([
      { name: "sub", parts: null, kind: "subquery" },
      { name: "g", parts: ["generate_series"], kind: "subquery" },
    ]);
  });

  it("reads the sources of the query the cursor is in", () => {
    const inner = analyze("select * from orders o where o.id in (select | from customers c)");
    expect(inner.sources.map((s) => s.name)).toEqual(["c"]);

    const outer = analyze("select | from orders o where o.id in (select id from customers c)");
    expect(outer.sources.map((s) => s.name)).toEqual(["o"]);

    const cte = analyze("with r as (select | from orders o) select * from r");
    expect(cte.sources.map((s) => s.name)).toEqual(["o"]);
  });

  it("reads quoted and schema-qualified names", () => {
    const a = analyze('select | from "Order Items" oi join reporting."Customers" rc on true');
    expect(a.sources).toEqual([
      { name: "oi", parts: ["Order Items"], kind: "table" },
      { name: "rc", parts: ["reporting", "Customers"], kind: "table" },
    ]);
  });

  it("gives a schema qualifier", () => {
    expect(analyze("select * from reporting.|").qualifier).toEqual(["reporting"]);
    expect(analyze("select * from reporting.|").contextType).toBe("after_from");
    expect(analyze("select public.orders.| from public.orders").qualifier).toEqual([
      "public",
      "orders",
    ]);
  });

  it("finds the clause from tokens", () => {
    const cases = {
      "select |": "select_columns",
      "select a, | from t": "select_columns",
      "select count(|) from t": "select_columns",
      "select * from |": "after_from",
      "select * from a, |": "after_from",
      "select * from a join |": "after_from",
      "select * from a |": "alias",
      "select * from a as |": "alias",
      "select * from t where |": "where_condition",
      "select * from t where a = 1 and |": "where_condition",
      "select * from t where a in (select b from u) and |": "where_condition",
      "select * from t where a in (select | from u)": "select_columns",
      "select * from t group by |": "after_group_by",
      "select * from t order by |": "after_order_by",
      "select a from t group by a having |": "after_having",
      "select * from t limit |": "unknown",
      "update t set |": "where_condition",
      "insert into |": "after_from",
    };
    for (const [marked, type] of Object.entries(cases)) {
      expect([marked, analyze(marked).contextType]).toEqual([marked, type]);
    }
  });

  it("splits statements only at semicolons in code", () => {
    const a = analyze("select ';' from orders o -- ; \n where o.| ; select * from customers c");
    expect(a.qualifier).toEqual(["o"]);
    expect(a.sources.map((s) => s.name)).toEqual(["o"]);

    const b = analyze("select 1; select c.| from customers c");
    expect(b.sources.map((s) => s.name)).toEqual(["c"]);
  });

  it("offers nothing in a string or a comment", () => {
    expect(analyze("select 'abc|' from t").contextType).toBe("none");
    expect(analyze("select * from t -- where |").contextType).toBe("none");
    expect(analyze("select /* | */ 1").contextType).toBe("none");
    expect(analyze("select * from t where a = 'open|").contextType).toBe("none");
    expect(analyze("select 'x' |from t").contextType).toBe("select_columns");
  });

  it("knows the word under the cursor", () => {
    expect(analyze("select na| from t").word).toEqual({ from: 7, to: 9 });
    expect(analyze("select c.na|me from customers c").word).toEqual({ from: 9, to: 13 });
  });

  it("reads the dialect's quotes", () => {
    const a = analyze("select `o`.| from `orders` `o`", "mysql");
    expect(a.qualifier).toEqual(["o"]);
    expect(a.sources).toEqual([{ name: "o", parts: ["orders"], kind: "table" }]);

    const b = analyze("select [o].| from [orders] [o]", "sqlite");
    expect(b.sources).toEqual([{ name: "o", parts: ["orders"], kind: "table" }]);
  });

  it("takes adapter context boundaries", () => {
    const analyzer = new SqlContextAnalyzer(
      { contextBoundaries: ["prewhere", "sample"] },
      profileFor("clickhouse"),
    );
    expect(analyzer.analyzeContext("select * from t prewhere ", 25).contextType).toBe(
      "where_condition",
    );
    expect(analyzer.analyzeContext("select * from t sample ", 23).contextType).toBe(
      "after_sample",
    );
  });
});

describe("SqlCompletion", () => {
  beforeEach(() => clearColumnCache());

  it("offers the columns of the FROM table in the select list", () => {
    const result = complete("select | from customers");
    expect(labels(result)).toEqual(expect.arrayContaining(["*", "id", "name", "email", "COUNT"]));
    expect(labels(result)).not.toContain("customer_id");
  });

  it("offers an alias's columns after its dot, the alias defined after the cursor", () => {
    expect(labels(complete("select c.| from customers c"))).toEqual(["id", "name", "email"]);
  });

  it("replaces the word after the dot only", () => {
    const result = complete("select c.na| from customers c");
    expect(result.from).toBe(9);
  });

  it("qualifies columns when the statement reads several tables", () => {
    const result = labels(complete("select | from orders o, customers c"));
    expect(result).toEqual(expect.arrayContaining(["o.total", "c.email", "total", "email"]));
  });

  it("offers a WITH query's plain columns, and none of another", () => {
    expect(
      labels(complete("with r as (select id, total as amount from orders) select r.| from r")),
    ).toEqual(["id", "amount"]);
    expect(labels(complete("with r as (select * from orders) select r.| from r"))).toEqual([]);
  });

  it("offers tables, and WITH queries, after FROM", () => {
    const result = labels(complete("with r as (select 1 as a) select * from |"));
    expect(result).toEqual(["customers", "orders", "order items", "r"]);
  });

  it("offers a schema's tables after its name", () => {
    const schema = { "reporting.orders": null, "reporting.customers": null, "public.users": null };
    expect(labels(complete("select * from reporting.|", schema))).toEqual([
      "orders",
      "customers",
    ]);
  });

  it("offers every table for the one schema selected", () => {
    const options = { schemas: ["public"] };
    expect(labels(complete("select * from public.|", SCHEMA, options))).toEqual([
      "customers",
      "orders",
      "order items",
    ]);
  });

  it("resolves a quoted table name", () => {
    expect(labels(complete('select oi.| from "order items" oi'))).toEqual(["order_id", "sku"]);
  });

  it("offers nothing for a subquery's alias, or in a string", () => {
    expect(complete("select s.| from (select 1 as a) s")).toBeNull();
    expect(complete("select 'c.|' from customers c")).toBeNull();
  });

  it("does not offer columns while a keyword is being typed", () => {
    expect(complete("select * fro|")).toBeNull();
  });

  describe("columns loaded when a statement uses a table", () => {
    const lazy = { customers: null, orders: null, "reporting.items": null };

    it("asks the server for the statement's tables, once", async () => {
      const asked = [];
      const fetchColumns = (tables) => {
        asked.push(tables);
        return Promise.resolve({ customers: ["id", "name"], orders: ["id", "total"] });
      };

      const result = await complete("select | from customers c join orders o on true", lazy, {
        fetchColumns,
      });
      expect(asked).toEqual([["customers", "orders"]]);
      expect(labels(result)).toEqual(expect.arrayContaining(["c.name", "o.total"]));

      // Known now, for this source: no second request.
      const again = complete("select c.| from customers c", lazy, { fetchColumns });
      expect(labels(again)).toEqual(["id", "name"]);
      expect(asked.length).toBe(1);
    });

    it("keeps each source's columns apart", async () => {
      const fetchColumns = (tables) => Promise.resolve({ [tables[0]]: ["a"] });
      await complete("select c.| from customers c", lazy, { fetchColumns, source: "one" });

      const asked = [];
      await complete("select c.| from customers c", lazy, {
        source: "two",
        fetchColumns: (tables) => {
          asked.push(tables);
          return Promise.resolve({});
        },
      });
      expect(asked).toEqual([["customers"]]);
    });

    it("asks for at most a few tables at a time", async () => {
      const many = Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`t${i}`, null]));
      const from = Object.keys(many).join(", ");
      const asked = [];
      await complete(`select | from ${from}`, many, {
        fetchColumns: (tables) => {
          asked.push(tables);
          return Promise.resolve({});
        },
      });
      expect(asked[0].length).toBe(MAX_TABLES);
    });

    it("does not ask for tables when only tables are offered", () => {
      const asked = [];
      const result = complete("select * from |", lazy, {
        fetchColumns: (tables) => asked.push(tables),
      });
      expect(asked).toEqual([]);
      expect(labels(result)).toEqual(["customers", "orders", "reporting.items"]);
    });

    it("asks for a schema-qualified table's columns", async () => {
      const asked = [];
      const result = await complete("select i.| from reporting.items i", lazy, {
        fetchColumns: (tables) => {
          asked.push(tables);
          return Promise.resolve({ "reporting.items": ["sku"] });
        },
      });
      expect(asked).toEqual([["reporting.items"]]);
      expect(labels(result)).toEqual(["sku"]);
    });
  });
});
