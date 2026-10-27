import {
  EditorView,
  ViewPlugin,
  Decoration,
  MatchDecorator,
} from "@codemirror/view";
import { RangeSetBuilder } from "@codemirror/state";
import { tokenize, JSON_PROFILE } from "../languages/sql/tokenizer.js";
import { templateVariables, stringPlaceholders } from "../languages/json_dsl/parser.js";

function isJson(dialect) {
  return typeof dialect === "string" && dialect.startsWith("json:");
}

const variableContainerDecoration = Decoration.mark({
  class: "cm-lotus-variable-container",
  attributes: { "data-variable": "true" },
});

const bracketDecoration = Decoration.mark({
  class: "cm-lotus-variable-bracket",
});

const variableNameDecoration = Decoration.mark({
  class: "cm-lotus-variable-name",
});

const optionalClauseDecoration = Decoration.mark({
  class: "cm-lotus-optional-clause",
});

const optionalBracketDecoration = Decoration.mark({
  class: "cm-lotus-optional-bracket",
});

/**
 * The statement's variables, in order, once each. A JSON source's are found
 * as Lotus finds them (`{{name}}` in code and in strings, through blocks);
 * a SQL source's by their `{{ name }}` shape.
 */
export function extractVariables(content, dialect = null) {
  if (isJson(dialect)) return [...new Set(templateVariables(content))];

  const variables = [];
  const seen = new Set();
  const regex = /\{\{\s*(\w+)\s*\}\}/g;
  let match;

  while ((match = regex.exec(content)) !== null) {
    const varName = match[1];
    if (!seen.has(varName)) {
      seen.add(varName);
      variables.push(varName);
    }
  }

  return variables;
}

// A JSON source's variables and blocks, where Lotus reads them: `[[1, 2]]`
// in an array is an array.
function jsonDecorations(text) {
  const decorations = [];
  const open = [];
  for (const t of tokenize(text, JSON_PROFILE)) {
    if (t.type === "variable") {
      decorations.push(variableContainerDecoration.range(t.start, t.end));
    } else if (t.type === "string") {
      for (const p of stringPlaceholders(text.slice(t.start, t.end))) {
        decorations.push(variableContainerDecoration.range(t.start + p.start, t.start + p.end));
      }
    } else if (t.type === "block_open") {
      open.push(t.start);
    } else if (t.type === "block_close" && open.length) {
      const start = open.pop();
      decorations.push(optionalBracketDecoration.range(start, start + 2));
      decorations.push(optionalBracketDecoration.range(t.start, t.end));
      if (start + 2 < t.start) decorations.push(optionalClauseDecoration.range(start + 2, t.start));
    }
  }
  return decorations;
}

function createVariableDecorations(view, dialect = null) {
  const text = view.state.doc.toString();
  const decorations = isJson(dialect) ? jsonDecorations(text) : sqlDecorations(text);

  // Sort by start position (required by RangeSetBuilder)
  decorations.sort((a, b) => a.from - b.from || a.to - b.to);

  const builder = new RangeSetBuilder();
  for (const deco of decorations) {
    builder.add(deco.from, deco.to, deco.value);
  }

  return builder.finish();
}

function sqlDecorations(text) {
  const decorations = [];

  // Add optional clause decorations
  const optionalRegex = /\[\[(.*?)\]\]/gs;
  let optMatch;

  while ((optMatch = optionalRegex.exec(text)) !== null) {
    const start = optMatch.index;
    const end = start + optMatch[0].length;

    // Bracket decorations for [[ and ]]
    decorations.push(optionalBracketDecoration.range(start, start + 2));
    decorations.push(optionalBracketDecoration.range(end - 2, end));

    // Content decoration (between brackets)
    if (start + 2 < end - 2) {
      decorations.push(optionalClauseDecoration.range(start + 2, end - 2));
    }
  }

  // Add variable decorations
  const regex = /\{\{\s*(\w+)\s*\}\}/g;
  let match;

  while ((match = regex.exec(text)) !== null) {
    const start = match.index;
    const end = match.index + match[0].length;

    decorations.push(variableContainerDecoration.range(start, end));
  }

  return decorations;
}

/**
 * Marks the statement's variables and optional blocks, and calls
 * `onVariableChange` with its variables when they change. `getDialect`
 * names the source's language, which says how to find them.
 */
export function lotusVariablesPlugin(onVariableChange, getDialect = () => null) {
  return ViewPlugin.define(
    (view) => {
      let lastVariables = extractVariables(view.state.doc.toString(), getDialect());
      let lastDialect = getDialect();

      return {
        decorations: createVariableDecorations(view, lastDialect),

        update(update) {
          const dialect = getDialect();
          if (update.docChanged || update.viewportChanged || dialect !== lastDialect) {
            this.decorations = createVariableDecorations(update.view, dialect);
          }

          if ((update.docChanged || dialect !== lastDialect) && onVariableChange) {
            lastDialect = dialect;
            const currentVariables = extractVariables(update.state.doc.toString(), dialect);

            if (
              JSON.stringify(currentVariables) !== JSON.stringify(lastVariables)
            ) {
              lastVariables = currentVariables;
              onVariableChange(currentVariables);
            }
          }
        },
      };
    },
    {
      decorations: (v) => v.decorations,
    },
  );
}

export const lotusVariableStyles = EditorView.theme({
  ".cm-lotus-variable-container": {
    backgroundColor: "rgba(139, 92, 246, 0.15)",
    borderRadius: "3px",
    padding: "0 2px",
    border: "1px solid rgba(139, 92, 246, 0.3)",
    color: "#7c3aed",
  },
  ".cm-lotus-optional-bracket": {
    color: "#2563eb",
    fontWeight: "bold",
  },
  ".cm-lotus-optional-clause": {
    backgroundColor: "rgba(37, 99, 235, 0.06)",
  },
});
