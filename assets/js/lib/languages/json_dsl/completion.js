/**
 * JSON DSL completion for non-SQL query languages (Elasticsearch, etc.).
 * All keywords, types, and functions come from the adapter's editor_config —
 * there are no shared defaults across JSON-based query languages.
 */
export class JsonDslCompletion {
  constructor(schema, config = {}) {
    this.schema = schema || {};
    this.keywords = config.keywords || [];
    this.functions = config.functions || [];
    this.types = config.types || [];
  }

  updateSchema(newSchema) {
    this.schema = newSchema || {};
  }

  createCompletionSource() {
    return (context) => {
      const pos = context.pos;
      const doc = context.state.doc.toString();

      const ctx = this.analyzeJsonContext(doc, pos);

      if (!ctx.inKey && !ctx.inValue) {
        return null;
      }

      const completions = this.getCompletions(ctx);
      if (completions.length === 0) return null;

      return {
        from: ctx.wordFrom,
        to: ctx.wordTo,
        options: completions.map((c) => ({
          label: c.label,
          type: c.type || "property",
          detail: c.detail,
          boost: c.boost || 0,
        })),
      };
    };
  }

  analyzeJsonContext(doc, pos) {
    let i = pos - 1;
    let wordFrom = pos;

    // Find the start of the current word
    while (i >= 0) {
      const ch = doc[i];
      if (ch === '"') {
        wordFrom = i + 1;
        break;
      }
      if (ch === ":" || ch === "," || ch === "{" || ch === "[") {
        wordFrom = i + 1;
        break;
      }
      if (/\s/.test(ch)) {
        wordFrom = i + 1;
        break;
      }
      i--;
    }

    // Check if there's a colon before us (value position) or not (key position)
    const beforeWord = doc.substring(Math.max(0, wordFrom - 20), wordFrom);
    const colonSeen = /:\s*"?\s*$/.test(beforeWord);

    // Find end of current word
    let wordTo = pos;
    while (wordTo < doc.length) {
      const ch = doc[wordTo];
      if (ch === '"' || ch === ":" || ch === "," || ch === "}" || ch === "]") {
        break;
      }
      if (/\s/.test(ch)) break;
      wordTo++;
    }

    const currentWord = doc.substring(wordFrom, pos).toLowerCase();

    return {
      inKey: !colonSeen,
      inValue: colonSeen,
      currentWord,
      wordFrom,
      wordTo,
    };
  }

  getCompletions(ctx) {
    if (ctx.inKey) {
      return this.getKeyCompletions(ctx.currentWord);
    }
    return this.getFieldCompletions(ctx.currentWord);
  }

  getKeyCompletions(prefix) {
    const completions = [];

    // Query keywords from adapter config
    for (const kw of this.keywords) {
      if (!prefix || kw.startsWith(prefix)) {
        completions.push({
          label: kw,
          type: "keyword",
          detail: "Query keyword",
          boost: 10,
        });
      }
    }

    // Field names from schema (index mappings)
    for (const indexName of Object.keys(this.schema)) {
      const fields = this.schema[indexName] || [];
      for (const field of fields) {
        if (!prefix || field.startsWith(prefix)) {
          completions.push({
            label: field,
            type: "property",
            detail: `Field in ${indexName}`,
            boost: 5,
          });
        }
      }
    }

    return completions;
  }

  getFieldCompletions(prefix) {
    const completions = [];

    for (const indexName of Object.keys(this.schema)) {
      const fields = this.schema[indexName] || [];
      for (const field of fields) {
        if (!prefix || field.startsWith(prefix)) {
          completions.push({
            label: field,
            type: "property",
            detail: `Field in ${indexName}`,
            boost: 5,
          });
        }
      }
    }

    return completions;
  }
}
