import { EditorView, basicSetup } from "codemirror";
import { placeholder, keymap } from "@codemirror/view";
import { EditorState, Compartment, Prec } from "@codemirror/state";
import { sql } from "@codemirror/lang-sql";
import { json } from "@codemirror/lang-json";
import { editorStyles, getCompletionStyles } from "./styles";
import { lotusVariablesPlugin } from "./plugins/lotus_variables";
import {
  getDialectConfig,
  getCachedDialectConfig,
  buildSqlExtension,
  isJsonLanguage,
} from "./dialect_config";
import { SqlCompletion } from "./languages/sql/completion";
import { JsonDslCompletion } from "./languages/json_dsl/completion";
import { load } from "./settings";

const editorTheme = EditorView.theme(editorStyles);
const languageCompartment = new Compartment();
const completionThemeCompartment = new Compartment();

function isDarkMode() {
  const theme = load("theme") || "system";

  if (theme === "dark") {
    return true;
  } else if (theme === "light") {
    return false;
  } else {
    const wantsDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    return wantsDark;
  }
}

function initialSqlExt(schema) {
  const cfg = { upperCaseKeywords: true };
  if (schema) cfg.schema = schema;
  return sql(cfg);
}

export function createEditor({
  textarea,
  parent,
  schema = null,
  dialectName = "postgres",
  onChange,
  onRun,
  onVars,
}) {
  let currentSchema = schema;
  let currentDialect = dialectName;
  let currentConfig = null;
  let contextCompletion = null;

  const initialLang = isJsonLanguage(dialectName)
    ? json()
    : initialSqlExt(currentSchema);

  const extensions = [
    basicSetup,
    languageCompartment.of(initialLang),
    completionThemeCompartment.of(
      EditorView.theme(getCompletionStyles(isDarkMode())),
    ),
    editorTheme,
    EditorView.lineWrapping,
    placeholder("SELECT * FROM table_name"),
  ];

  if (onRun) {
    extensions.push(
      Prec.highest(
        keymap.of([
          {
            key: "Mod-Enter",
            run: () => {
              onRun();
              return true;
            },
          },
          {
            key: "Ctrl-Enter",
            run: () => {
              onRun();
              return true;
            },
          },
        ]),
      ),
    );
  }

  if (onVars) {
    extensions.push(lotusVariablesPlugin(onVars));
  }

  const view = new EditorView({
    state: EditorState.create({ doc: textarea.value, extensions }),
    parent,
    dispatch: (tr) => {
      view.update([tr]);
      if (tr.docChanged && onChange) onChange(view.state.doc.toString());
    },
  });

  let themeObserver = null;

  const updateCompletionTheme = () => {
    view.dispatch({
      effects: completionThemeCompartment.reconfigure(
        EditorView.theme(getCompletionStyles(isDarkMode())),
      ),
    });
  };

  if (typeof MutationObserver !== "undefined") {
    themeObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (
          mutation.type === "attributes" &&
          (mutation.attributeName === "class" ||
            mutation.attributeName === "data-theme")
        ) {
          updateCompletionTheme();
        }
      });
    });

    themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "data-theme"],
    });
    themeObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ["class", "data-theme"],
    });
  }

  const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
  const mediaQueryListener = () => updateCompletionTheme();
  mediaQuery.addEventListener("change", mediaQueryListener);

  function reconfigureLanguage() {
    if (!currentConfig) return;

    if (isJsonLanguage(currentDialect)) {
      contextCompletion = new JsonDslCompletion(currentSchema, currentConfig);
      const jsonLang = json();

      view.dispatch({
        effects: languageCompartment.reconfigure([
          jsonLang,
          jsonLang.language.data.of({
            autocomplete: contextCompletion.createCompletionSource(),
          }),
        ]),
      });
    } else {
      contextCompletion = new SqlCompletion(currentSchema, currentConfig);

      view.dispatch({
        effects: languageCompartment.reconfigure(
          buildSqlExtension(
            currentConfig,
            currentSchema,
            contextCompletion,
            currentDialect,
          ),
        ),
      });
    }
  }

  return {
    view,
    getContent() {
      return view.state.doc.toString();
    },
    setContent(content) {
      view.dispatch({
        changes: {
          from: 0,
          to: view.state.doc.length,
          insert: content ?? "",
        },
      });
    },
    updateSchema(newSchema) {
      currentSchema = newSchema;
      if (contextCompletion) {
        contextCompletion.updateSchema(currentSchema);
      }
      reconfigureLanguage();
    },
    applyDialectConfig(config) {
      currentConfig = config;
      reconfigureLanguage();
    },
    updateDialect(newDialectName, fetchFn) {
      currentDialect = newDialectName || "postgres";

      const cached = getCachedDialectConfig(currentDialect);
      if (cached) {
        currentConfig = cached;
        reconfigureLanguage();
        return Promise.resolve();
      }

      return getDialectConfig(currentDialect, fetchFn).then((config) => {
        currentConfig = config;
        reconfigureLanguage();
      });
    },
    updateTheme() {
      updateCompletionTheme();
    },
    destroy() {
      if (themeObserver) {
        themeObserver.disconnect();
      }
      mediaQuery.removeEventListener("change", mediaQueryListener);
      view.destroy();
    },
  };
}
