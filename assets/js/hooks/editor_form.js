import { createEditor } from "../lib/editor.js";
import {
  getCachedDialectConfig,
  isJsonLanguage,
} from "../lib/dialect_config.js";
import { format as formatContent } from "../lib/formatter.js";
import { runTarget, dialectOptions } from "../lib/sql_statements.js";
import { tinykeys } from "tinykeys";

export default {
  mounted() {
    const textarea = this.el;
    const editorContainer = document.getElementById("editor");

    // The texts sent to the server that it has not echoed back yet.
    this.sentContents = [];

    const onContentChange = (content) => {
      this.sentContents.push(content);
      if (this.sentContents.length > 100) this.sentContents.shift();
      this.pushEventTo(
        this.el.closest("[data-phx-component]"),
        "editor_content_changed",
        { statement: content },
      );
    };

    let t = null;
    const onVariableChange = (vars) => {
      if (t) clearTimeout(t);
      t = setTimeout(() => {
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "variables_detected",
          { variables: vars },
        );
      }, 500);
    };

    const onRunQuery = () => {
      const form = this.el.form;
      if (!form) return;
      textarea.value = this.editor.getContent();
      const submit = form.querySelector('button[type="submit"]');
      if (submit && !submit.disabled) submit.click();
    };

    // What a run runs: the selection, the statement at the cursor when the
    // editor has several, or the whole text. The server hears which, for the
    // run buttons' labels.
    let runScope = "all";
    let scopeTimer = null;
    const onSelectionChange = () => {
      clearTimeout(scopeTimer);
      scopeTimer = setTimeout(() => {
        const scope = this.runTarget().scope;
        if (scope === runScope) return;
        runScope = scope;
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "editor_run_scope",
          { scope },
        );
      }, 150);
    };
    this.clearScopeTimer = () => clearTimeout(scopeTimer);

    const initialSchema = this.getSchemaFromDOM();
    const initialDialect = this.getDialectFromDOM();

    this.editor = createEditor({
      textarea,
      parent: editorContainer,
      schema: initialSchema,
      dialectName: initialDialect,
      onChange: onContentChange,
      onRun: onRunQuery,
      onFormat: () => {
        if (this.formattable()) this.formatEditor();
      },
      onSelectionChange,
      onVars: onVariableChange,
      completionOptions: {
        fetchColumns: (tables) => this.fetchColumns(tables),
        fetchFields: (indices) => this.fetchFields(indices),
        source: () => this.getSourceFromDOM(),
        schemas: () => this.getSchemasFromDOM(),
      },
    });

    editorContainer.lotusEditor = this.editor;
    onSelectionChange();

    this.fetchAndApplyDialect(initialDialect);

    this.unbindKeys = tinykeys(window, {
      "Meta+Enter": (event) => {
        event.preventDefault();
        onRunQuery();
      },
      "Control+Enter": (event) => {
        event.preventDefault();
        onRunQuery();
      },
      "Meta+Shift+c": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "copy_query",
          {},
        );
      },
      "Control+Shift+c": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "copy_query",
          {},
        );
      },
      "Meta+Shift+f": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "format_query",
          {},
        );
      },
      "Control+Shift+f": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "format_query",
          {},
        );
      },
      "Meta+x": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "toggle_variable_settings",
          {},
        );
      },
      "Control+x": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "toggle_variable_settings",
          {},
        );
      },
      "Meta+e": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "toggle_schema_explorer",
          {},
        );
      },
      "Control+e": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "toggle_schema_explorer",
          {},
        );
      },
      "Meta+ArrowDown": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "expand_editor",
          {},
        );
      },
      "Control+ArrowDown": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "expand_editor",
          {},
        );
      },
      "Meta+ArrowUp": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "minimize_editor",
          {},
        );
      },
      "Control+ArrowUp": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "minimize_editor",
          {},
        );
      },
      "Meta+g": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "smart_toggle_visualization_drawer",
          {},
        );
      },
      "Control+g": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "smart_toggle_visualization_drawer",
          {},
        );
      },
      "Meta+1": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "set_view_mode",
          { mode: "table" },
        );
      },
      "Control+1": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "set_view_mode",
          { mode: "table" },
        );
      },
      "Meta+2": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "set_view_mode",
          { mode: "chart" },
        );
      },
      "Control+2": (event) => {
        event.preventDefault();
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "set_view_mode",
          { mode: "chart" },
        );
      },
    });

    // The form sends the whole text as the query's statement, and the part
    // to run, when it is not all of it, as `run_statement`. LiveView reads
    // the form after this listener.
    this.el.form?.addEventListener("submit", () => {
      textarea.value = this.editor.getContent();

      const input = this.el.form.querySelector('input[name="run_statement"]');
      const target = this.runTarget();
      if (input) input.value = target.scope === "all" ? "" : target.text;
      if (target.scope !== "all") this.editor.flash(target.from, target.to);
    });

    this.handleEvent("format-editor-content", (payload) => {
      this.formatEditor(payload && payload.dialect);
    });

    this.handleEvent("copy-editor-content", () => {
      const content = this.editor.getContent();
      navigator.clipboard
        .writeText(content)
        .then(() => {
          this.pushEventTo(
            this.el.closest("[data-phx-component]"),
            "copy-to-clipboard-success",
            {},
          );
        })
        .catch((err) => {
          this.pushEventTo(
            this.el.closest("[data-phx-component]"),
            "copy-to-clipboard-error",
            { error: err.message },
          );
        });
    });

    this.requestSchema();
  },

  updated() {
    const newSchema = this.getSchemaFromDOM();
    if (newSchema) this.editor?.updateSchema(newSchema);

    const newDialect = this.getDialectFromDOM();
    if (newDialect && newDialect !== this._lastDialect) {
      this.fetchAndApplyDialect(newDialect);
    }

    if (this.editor) this.syncContent(this.el.value);
  },

  // The statement as the server renders it. An echo of a text the editor
  // sent is behind the editor, which has moved on (a completion taken, more
  // typed): it is dropped, as are the sends before it. Any other text is a
  // change from the server (a generated query, a query loaded) and replaces
  // the editor's.
  syncContent(value) {
    const sent = this.sentContents || [];
    const echoed = sent.lastIndexOf(value);
    if (echoed !== -1) {
      sent.splice(0, echoed + 1);
      return;
    }
    if (value !== this.editor.getContent()) this.editor.setContent(value);
  },

  // The server offers formatting for SQL and JSON sources only.
  formattable() {
    const el = document.querySelector("[data-editor-formattable]");
    return el?.dataset.editorFormattable === "true";
  },

  currentDialect() {
    return this._lastDialect || this.getDialectFromDOM();
  },

  runTarget() {
    const view = this.editor.view;
    const text = view.state.doc.toString();
    const dialect = this.currentDialect();
    if (isJsonLanguage(dialect)) return { scope: "all", text };
    const server = getCachedDialectConfig(dialect)?.tokenizer;
    return runTarget(text, view.state.selection.main, dialectOptions(dialect, server));
  },

  // Formats the text in place, as one change that one undo takes back; a
  // text the formatter cannot read stays as it is.
  formatEditor(dialect) {
    const content = this.editor.getContent();
    const result = formatContent(content, dialect || this.currentDialect());

    if (result.ok) {
      if (result.content !== content) {
        this.editor.replaceContent(result.content, "input.format");
      }
      this.pushEventTo(
        this.el.closest("[data-phx-component]"),
        "format-editor-content-success",
        {},
      );
    } else {
      this.pushEventTo(
        this.el.closest("[data-phx-component]"),
        "format-editor-content-error",
        { error: result.error },
      );
    }
  },

  // The columns of the tables a statement uses, from the server (the editor
  // has tables only, up front).
  fetchColumns(tables) {
    return new Promise((resolve) => {
      this.pushEventTo(
        this.el.closest("[data-phx-component]"),
        "editor_columns",
        { tables },
        (reply) => resolve((reply && reply.columns) || {}),
      );
    });
  },

  // The fields of a JSON source's indices, with their mapping types:
  // `{columns: {index: [name]}, types: {index: {name: type}}}`.
  fetchFields(indices) {
    return new Promise((resolve) => {
      this.pushEventTo(
        this.el.closest("[data-phx-component]"),
        "editor_columns",
        { tables: indices },
        (reply) => resolve(reply || {}),
      );
    });
  },

  getSourceFromDOM() {
    const el = document.querySelector("[data-editor-source]");
    return (el && el.dataset.editorSource) || "";
  },

  getSchemasFromDOM() {
    const el = document.querySelector("[data-editor-schemas]");
    if (!el) return [];
    try {
      return JSON.parse(el.dataset.editorSchemas);
    } catch {
      return [];
    }
  },

  getSchemaFromDOM() {
    const el = document.querySelector("[data-editor-schema]");
    if (!el) return null;
    try {
      return JSON.parse(el.dataset.editorSchema);
    } catch {
      return null;
    }
  },

  getDialectFromDOM() {
    const el = document.querySelector("[data-editor-dialect]");
    if (!el) return "postgres";
    return el.dataset.editorDialect || "postgres";
  },

  fetchAndApplyDialect(dialectName) {
    this._lastDialect = dialectName;

    const fetchFn = (name) => {
      return new Promise((resolve) => {
        this.pushEventTo(
          this.el.closest("[data-phx-component]"),
          "fetch_dialect_config",
          { dialect: name },
          (reply) => {
            resolve(reply.config);
          },
        );
      });
    };

    this.editor.updateDialect(dialectName, fetchFn);
  },

  requestSchema() {
    this.pushEventTo(
      this.el.closest("[data-phx-component]"),
      "request_editor_schema",
      {},
    );
  },

  destroyed() {
    this.clearScopeTimer?.();
    this.editor?.destroy();
    this.unbindKeys?.();
  },
};
