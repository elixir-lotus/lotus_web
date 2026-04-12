import { SqlContextAnalyzer } from "./sql/context_analyzer.js";
import { SqlCompletion } from "./sql/completion.js";

const languages = {
  sql: { Analyzer: SqlContextAnalyzer, Completion: SqlCompletion },
};

export function getLanguage(name) {
  return languages[name] || languages.sql;
}
