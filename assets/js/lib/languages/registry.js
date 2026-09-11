import { SqlContextAnalyzer } from "./sql/context_analyzer.js";
import { SqlCompletion } from "./sql/completion.js";
import { JsonDslCompletion } from "./json_dsl/completion.js";

const languages = {
  sql: { Analyzer: SqlContextAnalyzer, Completion: SqlCompletion },
  json: { Completion: JsonDslCompletion },
};

export function getLanguage(name) {
  if (name && name.startsWith("json:")) return languages.json;
  return languages[name] || languages.sql;
}
