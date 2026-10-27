/**
 * OptionsSqlEditor Hook
 *
 * The SQL of a dropdown's options, in the editor the query has: its dialect's
 * highlighting, and completion from the query source's tables and columns.
 * The page (data-page) answers the dialect and the columns, as it does for
 * the query's own editor; the modal hears the text and the runs.
 */
import { createEditor } from "../lib/editor.js";

function readDataset(selector, key) {
  return document.querySelector(selector)?.dataset[key];
}

function readJSON(selector, key, fallback) {
  try {
    return JSON.parse(readDataset(selector, key)) ?? fallback;
  } catch {
    return fallback;
  }
}

export default {
  mounted() {
    const page = this.el.dataset.page;
    const container = this.el.querySelector("[data-options-editor]");
    const dialect = readDataset("[data-editor-dialect]", "editorDialect") || "postgres";

    let timer = null;
    const send = (content) => {
      clearTimeout(timer);
      this.pushEventTo(this.el, "update_sql_query", { value: content });
    };

    this.editor = createEditor({
      textarea: { value: this.el.dataset.value || "" },
      parent: container,
      schema: readJSON("[data-editor-schema]", "editorSchema", null),
      dialectName: dialect,
      onChange: (content) => {
        clearTimeout(timer);
        timer = setTimeout(() => send(content), 250);
      },
      onRun: () => {
        send(this.editor.getContent());
        this.pushEventTo(this.el, "test_sql_query", {});
      },
      completionOptions: {
        fetchColumns: (tables) =>
          new Promise((resolve) => {
            this.pushEventTo(page, "editor_columns", { tables }, (reply) =>
              resolve((reply && reply.columns) || {}),
            );
          }),
        source: () => readDataset("[data-editor-source]", "editorSource") || "",
        schemas: () => readJSON("[data-editor-schemas]", "editorSchemas", []),
      },
    });

    this.editor.updateDialect(
      dialect,
      (name) =>
        new Promise((resolve) => {
          this.pushEventTo(page, "fetch_dialect_config", { dialect: name }, (reply) =>
            resolve(reply.config),
          );
        }),
    );

    // Escape closes an open completion list, not the modal around the editor.
    this.onEscapeCapture = (event) => {
      this.completionOpen =
        event.key === "Escape" && !!container.querySelector(".cm-tooltip-autocomplete");
    };
    this.onEscape = (event) => {
      if (event.key === "Escape" && this.completionOpen) event.stopPropagation();
    };
    this.el.addEventListener("keydown", this.onEscapeCapture, true);
    this.el.addEventListener("keydown", this.onEscape);

    this.editor.view.focus();
    this.clearTimer = () => clearTimeout(timer);
  },

  destroyed() {
    this.clearTimer?.();
    this.el.removeEventListener("keydown", this.onEscapeCapture, true);
    this.el.removeEventListener("keydown", this.onEscape);
    this.editor?.destroy();
  },
};
