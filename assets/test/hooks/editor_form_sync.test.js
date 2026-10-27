import { describe, it, expect } from "vitest";
import EditorForm from "../../js/hooks/editor_form.js";

// The editor hook's view of the statement the server renders.
function hook(content, sent) {
  const editor = {
    content,
    getContent() {
      return this.content;
    },
    setContent(text) {
      this.content = text;
    },
  };
  return { ...EditorForm, editor, sentContents: [...sent] };
}

describe("EditorForm.syncContent", () => {
  it("drops an echo of a text the editor sent, the editor having moved on", () => {
    // "date_h" typed, then a completion taken before its echo came back.
    const h = hook('{"date_histogram": {}}', ['{"date_h"}', '{"date_histogram": {}}']);
    h.syncContent('{"date_h"}');
    expect(h.editor.content).toBe('{"date_histogram": {}}');
    expect(h.sentContents).toEqual(['{"date_histogram": {}}']);

    h.syncContent('{"date_histogram": {}}');
    expect(h.editor.content).toBe('{"date_histogram": {}}');
    expect(h.sentContents).toEqual([]);
  });

  it("takes a text the server changed", () => {
    const h = hook("SELECT 1", ["SELECT 1"]);
    h.syncContent("SELECT 2 -- generated");
    expect(h.editor.content).toBe("SELECT 2 -- generated");
  });
});
