import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

const editorStyles = {
  "&": { fontSize: "14px", height: "100%" },
  ".cm-editor": { height: "100%" },
  ".cm-content": {
    padding: "12px",
    fontFamily: "'Monaco','Menlo','Ubuntu Mono',monospace",
  },
  ".cm-scroller": {
    fontFamily: "'Monaco','Menlo','Ubuntu Mono',monospace",
    lineHeight: "1.5",
    scrollPaddingTop: "80px",
    scrollPaddingBottom: "64px",
  },
  ".cm-focused": { outline: "none" },
  ".cm-editor.cm-focused": {
    outline: "2px solid var(--lotus-editor-focus, #3b82f6)",
    outlineOffset: "-1px",
  },
  ".cm-gutters": {
    backgroundColor: "rgb(var(--lotus-editor-light))",
    borderRight: "1px solid rgb(var(--lotus-gray-200))",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    color: "rgb(var(--lotus-gray-500))",
  },
  ".dark .cm-gutters": {
    backgroundColor: "rgb(var(--lotus-editor-dark)) !important",
    borderRight: "1px solid var(--lotus-editor-gutter-line-dark, #404040) !important",
  },
  ".dark .cm-lineNumbers .cm-gutterElement": {
    color: "rgb(var(--lotus-gray-500)) !important",
  },
};

const lightCompletionStyles = {
  ".cm-tooltip.cm-tooltip-autocomplete": {
    fontSize: "13px",
    borderRadius: "6px",
    border: "1px solid rgb(var(--lotus-gray-200))",
    backgroundColor: "rgb(var(--lotus-white))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul": {
    fontFamily: "'Monaco','Menlo','Ubuntu Mono',monospace",
    backgroundColor: "rgb(var(--lotus-white))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul li": {
    color: "rgb(var(--lotus-gray-700))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul li[aria-selected]": {
    background: "rgb(var(--lotus-pink-500) / .12)",
    color: "rgb(var(--lotus-pink-700))",
  },
};

const darkCompletionStyles = {
  ".cm-tooltip.cm-tooltip-autocomplete": {
    fontSize: "13px",
    borderRadius: "6px",
    border: "1px solid rgb(var(--lotus-gray-700))",
    backgroundColor: "rgb(var(--lotus-gray-800))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul": {
    fontFamily: "'Monaco','Menlo','Ubuntu Mono',monospace",
    backgroundColor: "rgb(var(--lotus-gray-800))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul li": {
    color: "rgb(var(--lotus-gray-300))",
  },
  ".cm-tooltip.cm-tooltip-autocomplete ul li[aria-selected]": {
    background: "rgb(var(--lotus-pink-500) / .2)",
    color: "rgb(var(--lotus-pink-300))",
  },
  ".cm-completionDetail": {
    color: "rgb(var(--lotus-gray-400))",
  },
};

// Syntax colours a theme may set (--lotus-syntax-*). Each falls back to the
// colour of CodeMirror's default style, so the default theme is unchanged.
const themeHighlight = syntaxHighlighting(
  HighlightStyle.define([
    { tag: t.keyword, color: "var(--lotus-syntax-keyword, #708)" },
    { tag: [t.string, t.deleted], color: "var(--lotus-syntax-string, #a11)" },
    { tag: [t.literal, t.inserted], color: "var(--lotus-syntax-number, #164)" },
    { tag: [t.atom, t.bool], color: "var(--lotus-syntax-number, #219)" },
    { tag: [t.typeName, t.namespace], color: "var(--lotus-syntax-type, #085)" },
    { tag: t.standard(t.name), color: "var(--lotus-syntax-function, inherit)" },
    { tag: t.comment, color: "var(--lotus-syntax-comment, #940)" },
    { tag: [t.punctuation, t.operator], color: "var(--lotus-syntax-punctuation, inherit)" },
  ]),
);

function getCompletionStyles(isDark = false) {
  return isDark ? darkCompletionStyles : lightCompletionStyles;
}

export {
  editorStyles,
  lightCompletionStyles as completionStyles,
  getCompletionStyles,
  themeHighlight,
};
