import {
  EditorView,
  ViewPlugin,
  Decoration,
  MatchDecorator,
} from "@codemirror/view";
import { RangeSetBuilder } from "@codemirror/state";
import { scan, tokenize, profileFor, TYPES } from "../languages/sql/tokenizer.js";
import { jsonProfile } from "../languages/json_dsl/parser.js";

const VARIABLE = TYPES.indexOf("variable");
const STRING = TYPES.indexOf("string");

/**
 * The lexical rules to find variables with, for an editor dialect name and
 * the server's profile of the source (`tokenizer` in its editor config),
 * when it sent one.
 */
export function variableProfile(dialectName, serverProfile = null) {
  if (dialectName && dialectName.startsWith("json:")) {
    return jsonProfile(serverProfile);
  }
  return profileFor(dialectName, serverProfile);
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
 * The `{{name}}` placeholders Lotus binds, as `{from, to, name}`, in order:
 * those in code and in string literals (the dialect rewrites `'%{{q}}%'`),
 * not those in a comment or a quoted identifier. The grammar is the
 * server's (`Lotus.Query.Tokenizer`): a name is a letter or `_`, then
 * letters, digits or `_`, with no spaces.
 */
export function variableRanges(content, profile = undefined) {
  const ranges = [];
  const { types, starts, count } = scan(content, profile);

  for (let k = 0; k < count; k++) {
    const from = starts[k];
    const to = starts[k + 1];

    if (types[k] === VARIABLE) {
      ranges.push({ from, to, name: content.slice(from + 2, to - 2) });
    } else if (types[k] === STRING) {
      stringPlaceholders(content, from, to, ranges);
    }
  }

  return ranges;
}

// The placeholders inside a string literal: the leftmost `{{name}}` wins,
// and after a `{{` that does not start one the search goes on from the next
// character, as on the server (`{{{a}}}` holds `{{a}}`).
function stringPlaceholders(text, from, to, ranges) {
  let i = text.indexOf("{{", from);
  while (i !== -1 && i + 4 <= to) {
    const end = placeholderEnd(text, i + 2, to);
    if (end) {
      ranges.push({ from: i, to: end, name: text.slice(i + 2, end - 2) });
      i = text.indexOf("{{", end);
    } else {
      i = text.indexOf("{{", i + 1);
    }
  }
}

function placeholderEnd(text, i, limit) {
  if (!/[A-Za-z_]/.test(text[i] || "")) return 0;
  let j = i + 1;
  while (j < limit && /[A-Za-z0-9_]/.test(text[j])) j += 1;
  return j + 2 <= limit && text[j] === "}" && text[j + 1] === "}" ? j + 2 : 0;
}

/** The names of the variables in `content`, in order, once each. */
export function extractVariables(content, profile = undefined) {
  const seen = new Set();
  for (const { name } of variableRanges(content, profile)) seen.add(name);
  return [...seen];
}

function createVariableDecorations(view, profile) {
  const decorations = [];
  const text = view.state.doc.toString();

  // Optional blocks, where Lotus reads them: not inside a string or a
  // comment, and in a JSON array `[[1, 2]]` is an array.
  const open = [];
  for (const t of tokenize(text, profile)) {
    if (t.type === "block_open") {
      open.push(t.start);
    } else if (t.type === "block_close" && open.length) {
      const start = open.pop();
      decorations.push(optionalBracketDecoration.range(start, start + 2));
      decorations.push(optionalBracketDecoration.range(t.start, t.end));
      if (start + 2 < t.start) {
        decorations.push(optionalClauseDecoration.range(start + 2, t.start));
      }
    }
  }

  // Add variable decorations: the placeholders Lotus binds
  for (const { from, to } of variableRanges(text, profile)) {
    decorations.push(variableContainerDecoration.range(from, to));
  }

  // Sort by start position (required by RangeSetBuilder)
  decorations.sort((a, b) => a.from - b.from || a.to - b.to);

  const builder = new RangeSetBuilder();
  for (const deco of decorations) {
    builder.add(deco.from, deco.to, deco.value);
  }

  return builder.finish();
}

/**
 * Marks the variables and optional clauses, and calls `onVariableChange`
 * with the variables' names when they change. `getProfile()` gives the
 * lexical rules of the current source (see `variableProfile/2`); they are
 * read again on every update, so a change of source re-reads the text.
 */
export function lotusVariablesPlugin(onVariableChange, getProfile = () => undefined) {
  return ViewPlugin.define(
    (view) => {
      let profile = getProfile();
      let profileKey = JSON.stringify(profile);
      let lastVariables = extractVariables(view.state.doc.toString(), profile);

      return {
        decorations: createVariableDecorations(view, profile),

        update(update) {
          const nextProfile = getProfile();
          const nextKey = JSON.stringify(nextProfile);
          const profileChanged = nextKey !== profileKey;
          profile = nextProfile;
          profileKey = nextKey;

          if (update.docChanged || update.viewportChanged || profileChanged) {
            this.decorations = createVariableDecorations(update.view, profile);
          }

          if ((update.docChanged || profileChanged) && onVariableChange) {
            const currentVariables = extractVariables(
              update.state.doc.toString(),
              profile,
            );

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
