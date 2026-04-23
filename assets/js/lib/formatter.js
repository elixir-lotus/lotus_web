/**
 * Language-aware pretty-printing for the query editor.
 *
 * Structural pretty-print only — expands a minified/compact representation
 * into an indented one without making opinionated choices about casing,
 * keyword alignment, etc. For JSON-shaped languages this is the same
 * transformation Chrome's "Pretty print" applies to a raw response.
 *
 * `supportsFormatting(dialectName)` gates the UI affordance so the button
 * only appears for languages where structural pretty-print makes sense.
 * SQL has no equivalent — it's already whitespace-agnostic, so any
 * prettifier has to invent line breaks (that's a formatter, not a
 * pretty-printer).
 */

export function supportsFormatting(dialectName) {
  return typeof dialectName === "string" && dialectName.startsWith("json:");
}

/**
 * Pretty-print `content` using the formatter for `dialectName`.
 *
 * Returns `{ ok: true, content }` on success, `{ ok: false, error }` on
 * parse failure or when no formatter applies. Callers show `error` in a
 * toast; the editor content is left untouched on failure.
 */
export function format(content, dialectName) {
  if (!supportsFormatting(dialectName)) {
    return { ok: false, error: "formatting not supported for this source" };
  }

  if (dialectName.startsWith("json:")) {
    return formatJson(content);
  }

  return { ok: false, error: "formatting not supported for this source" };
}

function formatJson(content) {
  const trimmed = content.trim();
  if (trimmed === "") return { ok: true, content: "" };

  try {
    const parsed = JSON.parse(trimmed);
    return { ok: true, content: JSON.stringify(parsed, null, 2) };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}
