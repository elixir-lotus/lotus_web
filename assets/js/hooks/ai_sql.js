/**
 * AiSql Hook
 *
 * Highlights a query in the AI assistant as the editor highlights it: each
 * line ([data-line]) is parsed on its own, so the lines a diff marks keep
 * their own element. The tokens take the editor's colours (.tok-* in
 * app.css, from the --lotus-syntax-* properties).
 */
import { sql } from "@codemirror/lang-sql";
import { highlightCode, classHighlighter } from "@lezer/highlight";

const parser = sql().language.parser;

function highlight(el) {
  const text = el.textContent;
  if (!text.trim()) return;

  const fragment = document.createDocumentFragment();

  highlightCode(
    text,
    parser.parse(text),
    classHighlighter,
    (token, classes) => {
      if (classes) {
        const span = document.createElement("span");
        span.className = classes;
        span.textContent = token;
        fragment.appendChild(span);
      } else {
        fragment.appendChild(document.createTextNode(token));
      }
    },
    () => fragment.appendChild(document.createTextNode("\n")),
  );

  el.replaceChildren(fragment);
}

export const AiSql = {
  mounted() {
    this.el.querySelectorAll("[data-line]").forEach(highlight);
  },
};

/**
 * AiCopy Hook
 *
 * Copies data-clipboard-text, and shows a tick for a moment.
 */
export const AiCopy = {
  mounted() {
    this.el.addEventListener("click", () => {
      navigator.clipboard?.writeText(this.el.dataset.clipboardText || "").then(() => {
        this.el.dataset.copied = "true";
        setTimeout(() => delete this.el.dataset.copied, 1200);
      });
    });
  },
};
