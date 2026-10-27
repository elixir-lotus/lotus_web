/**
 * The editor's language for JSON query templates: highlighting, indentation,
 * folding, bracket matching and error markers that read `{{variables}}` and
 * `[[ ]]` blocks as Lotus does, where CodeMirror's JSON grammar stops at the
 * first `{{` and marks the rest of the request as broken.
 *
 * The syntax tree comes from the editor's copy of Lotus's tokenizer
 * (parser.js): a `{{name}}` is a variable, `[[` opens a block only where no
 * single `[` is open and the block closes (so `[[1, 2], [3, 4]]` stays an
 * array), and a string is a property name where the request has a key.
 */
import {
  Language,
  LanguageSupport,
  defineLanguageFacet,
  languageDataProp,
  foldNodeProp,
  foldInside,
  indentNodeProp,
  delimitedIndent,
  indentUnit,
} from "@codemirror/language";
import { NodeSet, NodeType, NodeProp, Parser, Tree } from "@lezer/common";
import { styleTags, tags as t } from "@lezer/highlight";
import { linter } from "@codemirror/lint";
import { parseTemplate, parseTokens, significantTokens, tokensFor, jsonProfile } from "./parser.js";
import { Grammar } from "./grammar.js";

const data = defineLanguageFacet({
  closeBrackets: { brackets: ["[", "{", '"'] },
  indentOnInput: /^\s*[}\]]$/,
});

const NAMES = [
  "Document",
  "Object",
  "Array",
  "Block",
  "PropertyName",
  "String",
  "Number",
  "True",
  "False",
  "Null",
  "Variable",
  "{",
  "}",
  "[",
  "]",
  "BlockOpen",
  "BlockClose",
  ":",
  ",",
  "Invalid",
];
const ID = Object.fromEntries(NAMES.map((name, id) => [name, id]));

const nodeSet = new NodeSet(
  NAMES.map((name, id) => {
    const props = [];
    if (id === 0) props.push([languageDataProp, data]);
    if (name === "{") props.push([NodeProp.closedBy, ["}"]]);
    if (name === "}") props.push([NodeProp.openedBy, ["{"]]);
    if (name === "[") props.push([NodeProp.closedBy, ["]"]]);
    if (name === "]") props.push([NodeProp.openedBy, ["["]]);
    if (name === "Object" || name === "Array") props.push([NodeProp.group, ["Value"]]);
    return NodeType.define({ id, name, props, top: id === 0, error: name === "Invalid" });
  }),
).extend(
  styleTags({
    PropertyName: t.propertyName,
    String: t.string,
    Number: t.number,
    "True False": t.bool,
    Null: t.null,
    Variable: t.special(t.variableName),
    "BlockOpen BlockClose": t.meta,
    "{ }": t.brace,
    "[ ]": t.squareBracket,
    ": ,": t.separator,
    Invalid: t.invalid,
  }),
  foldNodeProp.add({ "Object Array": foldInside }),
  indentNodeProp.add({
    Object: delimitedIndent({ closing: "}" }),
    Array: delimitedIndent({ closing: "]" }),
  }),
);

/** The syntax tree of a template: its tokens, in objects, arrays and blocks. */
export function templateTree(text, profile = jsonProfile()) {
  const tokens = significantTokens(text, profile);
  const keys = new Set();
  collectKeys(parseTokens(text, tokensFor(tokens, "kept")).root, keys);

  const buffer = [];
  const open = [];
  const leaf = (name, from, to) => buffer.push(ID[name], from, to, 4);
  const close = (to) => {
    const node = open.pop();
    buffer.push(ID[node.name], node.from, to, buffer.length - node.at + 4);
  };
  const top = () => open[open.length - 1];

  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    const raw = text.slice(tok.start, tok.end);

    if (tok.type === "block_open") {
      open.push({ name: "Block", from: tok.start, at: buffer.length });
      leaf("BlockOpen", tok.start, tok.end);
    } else if (tok.type === "block_close") {
      leaf("BlockClose", tok.start, tok.end);
      if (top() && top().name === "Block") close(tok.end);
    } else if (tok.type === "operator" && (raw === "{" || raw === "[")) {
      open.push({ name: raw === "{" ? "Object" : "Array", from: tok.start, at: buffer.length });
      leaf(raw, tok.start, tok.end);
    } else if (tok.type === "operator" && (raw === "}" || raw === "]")) {
      const want = raw === "}" ? "Object" : "Array";
      if (top() && top().name === want) {
        leaf(raw, tok.start, tok.end);
        close(tok.end);
      } else {
        leaf("Invalid", tok.start, tok.end);
      }
    } else if (tok.type === "string") {
      leaf(keys.has(tok.start) ? "PropertyName" : "String", tok.start, tok.end);
    } else if (tok.type === "number") {
      leaf("Number", tok.start, tok.end);
    } else if (tok.type === "variable") {
      leaf("Variable", tok.start, tok.end);
    } else if (tok.type === "word") {
      const name = raw === "true" ? "True" : raw === "false" ? "False" : raw === "null" ? "Null" : "Invalid";
      leaf(name, tok.start, tok.end);
    } else if (tok.type === "comma") {
      leaf(",", tok.start, tok.end);
    } else if (raw === ":") {
      leaf(":", tok.start, tok.end);
    } else if (raw === "-" && tokens[i + 1] && tokens[i + 1].type === "number" && tokens[i + 1].start === tok.end) {
      leaf("Number", tok.start, tokens[i + 1].end);
      i += 1;
    } else {
      leaf("Invalid", tok.start, tok.end);
    }
  }
  while (open.length) close(text.length);

  return Tree.build({ buffer, nodeSet, topID: ID.Document, length: text.length });
}

function collectKeys(node, keys) {
  if (!node) return;
  if (node.kind === "object") {
    for (const m of node.members) {
      if (m.key && m.key.quoted) keys.add(m.key.from);
      collectKeys(m.value, keys);
    }
  } else if (node.kind === "array") {
    for (const item of node.items) collectKeys(item, keys);
  }
}

class TemplateParser extends Parser {
  constructor(profile) {
    super();
    this.profile = profile;
  }

  createParse(input) {
    const text = input.read(0, input.length);
    const profile = this.profile;
    return {
      parsedPos: input.length,
      stoppedAt: null,
      stopAt() {},
      advance: () => templateTree(text, profile),
    };
  }
}

function templateLanguage(profile) {
  return new Language(data, new TemplateParser(profile), [], "json-template");
}

/** The language with the JSON profile, for tests and an editor without config. */
export const jsonTemplateLanguage = templateLanguage(jsonProfile());

/**
 * Error markers: what makes Lotus refuse the request (not JSON once blocks
 * are kept or dropped and variables bound, not an object), and warnings
 * for what the cluster would refuse or drop: a duplicate key, a key the
 * grammar says the object does not take, a second clause in a query.
 */
export function templateDiagnostics(text, { contextSchema = null, profile = null } = {}) {
  if (text.trim() === "") return [];
  const parsed = parseTemplate(text, profile || jsonProfile());
  const diagnostics = [];

  for (const e of parsed.errors) {
    diagnostics.push({ from: e.from, to: Math.min(e.to, text.length), severity: "error", message: e.message });
  }
  for (const w of parsed.warnings) {
    diagnostics.push({ from: w.from, to: w.to, severity: "warning", message: w.message });
  }

  if (contextSchema && contextSchema.grammar && parsed.root && parsed.root.kind === "object") {
    diagnostics.push(...grammarWarnings(new Grammar(contextSchema), parsed.root));
  }

  return diagnostics
    .filter((d) => d.from <= text.length)
    .map((d) => ({ ...d, to: Math.max(d.to, Math.min(d.from + 1, text.length)) }));
}

// The keys an object does not take, by the grammar, along every path.
function grammarWarnings(grammar, root) {
  const out = [];

  const walk = (node, spec) => {
    if (!node || spec === null) return;
    if (node.kind === "object") {
      const keys = grammar.keysOf(spec);
      const known = new Set(keys.members.map((m) => m.key));
      const clauses = node.members.filter((m) => m.key && known.has(m.key.name));
      if (keys.oneKey && clauses.length > 1) {
        const extra = clauses[1].key;
        out.push({
          from: extra.from,
          to: extra.to,
          severity: "warning",
          message: "A query clause holds one query: combine them in a bool",
        });
      }
      for (const member of node.members) {
        const key = member.key;
        if (!key || key.variable || key.name === undefined) continue;
        if (keys.closed && !known.has(key.name) && grammar.takesObject(spec)) {
          out.push({
            from: key.from,
            to: key.to,
            severity: "warning",
            message: `Unknown key "${key.name}" here`,
          });
          continue;
        }
        walk(member.value, grammar.child(spec, { key: key.name, node: member.value }));
      }
    } else if (node.kind === "array") {
      node.items.forEach((item, index) => walk(item, grammar.child(spec, { index, node: item })));
    }
  };

  walk(root, grammar.root());
  return out;
}

/**
 * The language for a JSON source: highlighting, folding, two-space
 * indentation, autocomplete from `completion`, and error markers.
 * `config` is the adapter's editor config.
 */
export function jsonTemplate({ completion = null, config = {} } = {}) {
  const profile = jsonProfile(config.tokenizer || null);
  const language = config.tokenizer ? templateLanguage(profile) : jsonTemplateLanguage;
  const extensions = [
    indentUnit.of("  "),
    linter((view) =>
      templateDiagnostics(view.state.doc.toString(), {
        contextSchema: config.context_schema || null,
        profile,
      }),
    ),
  ];
  if (completion) {
    extensions.push(language.data.of({ autocomplete: completion.createCompletionSource() }));
  }
  return new LanguageSupport(language, extensions);
}
