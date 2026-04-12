import { SQL_DEFAULTS } from "./defaults.js";

export class SqlContextAnalyzer {
  constructor(config = {}) {
    const allKeywords = [
      ...SQL_DEFAULTS.keywords,
      ...(config.keywords || []).map((k) => k.toLowerCase()),
    ];
    this.keywords = new Set(allKeywords);
    this.contextBoundaries = (config.contextBoundaries || []).map((b) =>
      b.toLowerCase(),
    );
  }

  analyzeContext(query, cursorPos) {
    const beforeCursor = query.substring(0, cursorPos).toLowerCase();
    const afterCursor = query.substring(cursorPos).toLowerCase();

    const currentStatement = this.getCurrentStatement(
      beforeCursor,
      afterCursor,
    );

    return {
      tables: this.extractTables(currentStatement.full),
      aliases: this.extractAliases(currentStatement.full),
      contextType: this.determineContextType(currentStatement.beforeCursor),
      currentTable: this.getCurrentTableContext(currentStatement.beforeCursor),
      isAfterDot: this.isAfterTableDot(currentStatement.beforeCursor),
    };
  }

  getCurrentStatement(beforeCursor, afterCursor) {
    const lastSemicolon = beforeCursor.lastIndexOf(";");
    const nextSemicolon = afterCursor.indexOf(";");

    const statementStart = lastSemicolon === -1 ? 0 : lastSemicolon + 1;
    const beforeInStatement = beforeCursor.substring(statementStart);
    const afterInStatement =
      nextSemicolon === -1
        ? afterCursor
        : afterCursor.substring(0, nextSemicolon);

    return {
      beforeCursor: beforeInStatement.trim(),
      afterCursor: afterInStatement.trim(),
      full: (beforeInStatement + afterInStatement).trim(),
    };
  }

  extractTables(statement) {
    const tables = [];
    const fromRegex = /\bfrom\s+([^where^group^order^limit^having^union^;]+)/gi;
    const joinRegex =
      /\b(?:inner\s+|left\s+|right\s+|outer\s+|cross\s+)?join\s+([^\s]+)/gi;

    let match;

    // Extract FROM tables
    while ((match = fromRegex.exec(statement)) !== null) {
      const tablesPart = match[1].trim();
      const tableNames = this.parseTableReferences(tablesPart);
      tables.push(...tableNames);
    }

    // Extract JOIN tables
    while ((match = joinRegex.exec(statement)) !== null) {
      const tableName = match[1].trim();
      const cleanName = this.cleanTableName(tableName);
      if (cleanName) {
        tables.push(cleanName);
      }
    }

    return [...new Set(tables)];
  }

  parseTableReferences(tablesPart) {
    const tables = [];
    const parts = tablesPart.split(",").map((p) => p.trim());

    for (const part of parts) {
      const tableName = this.cleanTableName(part.split(/\s+/)[0]);
      if (tableName) {
        tables.push(tableName);
      }
    }

    return tables;
  }

  cleanTableName(name) {
    if (!name) return null;

    const parts = name.split(".");
    const tableName = parts[parts.length - 1];

    return tableName.replace(/["`\[\]]/g, "");
  }

  extractAliases(statement) {
    const aliases = {};

    // Pattern: table_name AS alias or table_name alias
    const aliasRegex =
      /(?:from|join)\s+([^\s,]+)(?:\s+as\s+|\s+)([a-zA-Z_][a-zA-Z0-9_]*)\b/gi;

    let match;
    while ((match = aliasRegex.exec(statement)) !== null) {
      const tableName = this.cleanTableName(match[1]);
      const alias = match[2].toLowerCase();

      if (tableName && alias && !this.keywords.has(alias)) {
        aliases[alias] = tableName;
      }
    }

    return aliases;
  }

  determineContextType(beforeCursor) {
    const trimmed = beforeCursor.trim();

    // Check adapter-specific context boundaries first
    for (const boundary of this.contextBoundaries) {
      const pattern = new RegExp(`\\b${boundary}\\s*$`, "i");
      if (pattern.test(trimmed)) {
        if (boundary === "prewhere") return "after_where";
        return `after_${boundary}`;
      }
    }

    if (/\bselect\s*$/i.test(trimmed)) {
      return "after_select";
    }

    if (/\bfrom\s*$/i.test(trimmed)) {
      return "after_from";
    }

    if (
      /\bwhere\s*$/i.test(trimmed) ||
      /\bwhere\b.*\b(?:and|or)\s*$/i.test(trimmed)
    ) {
      return "after_where";
    }

    if (/\border\s+by\s*$/i.test(trimmed)) {
      return "after_order_by";
    }

    if (/\bgroup\s+by\s*$/i.test(trimmed)) {
      return "after_group_by";
    }

    if (
      /\bhaving\s*$/i.test(trimmed) ||
      /\bhaving\b.*\b(?:and|or)\s*$/i.test(trimmed)
    ) {
      return "after_having";
    }

    if (/\bon\s*$/i.test(trimmed)) {
      return "after_on";
    }

    // Check if we're in a SELECT column list
    if (/\bselect\b/i.test(trimmed) && !/\bfrom\b/i.test(trimmed)) {
      return "select_columns";
    }

    // Check if we're in a WHERE condition
    if (
      /\bwhere\b/i.test(trimmed) &&
      !/\b(?:group|order|having|limit)\b/i.test(trimmed)
    ) {
      return "where_condition";
    }

    return "unknown";
  }

  getCurrentTableContext(beforeCursor) {
    const tables = this.extractTables(beforeCursor);
    const aliases = this.extractAliases(beforeCursor);

    // Look for table alias before the cursor (e.g., "u." in "WHERE u.")
    const aliasMatch = beforeCursor.match(/(\w+)\.\s*$/);
    if (aliasMatch) {
      const alias = aliasMatch[1].toLowerCase();
      return aliases[alias] || null;
    }

    // For simple queries with one table, return that table
    if (tables.length === 1) {
      return tables[0];
    }

    return null;
  }

  isAfterTableDot(beforeCursor) {
    return /\w+\.\s*$/.test(beforeCursor);
  }

  getTablesForContext(context) {
    switch (context.contextType) {
      case "after_from":
        return [];

      case "after_select":
      case "select_columns":
      case "after_where":
      case "where_condition":
      case "after_order_by":
      case "after_group_by":
      case "after_having":
      case "after_on":
        if (context.isAfterDot && context.currentTable) {
          return [context.currentTable];
        }
        return context.tables;

      default:
        return [];
    }
  }
}
