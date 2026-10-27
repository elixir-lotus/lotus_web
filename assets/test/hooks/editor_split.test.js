import { describe, it, expect, beforeEach, afterEach } from "vitest";
import EditorSplit from "../../js/hooks/editor_split.js";

// happy-dom lays nothing out: the page here is 800px for the editor, its
// 60px toolbar, the 10px divider and the results, which leaves 730px to
// share between the editor and the results.
const AREA = 800;
const CHROME = 60;
const DIVIDER = 10;
const SPACE = AREA - CHROME - DIVIDER;

let wide;

function mount() {
  document.body.innerHTML = `
    <div id="area">
      <div id="box"><div id="editor"></div></div>
      <div id="split"></div>
      <div id="results"></div>
    </div>`;

  const area = document.getElementById("area");
  const box = document.getElementById("box");
  const editor = document.getElementById("editor");
  const split = document.getElementById("split");
  const editorHeight = () => parseInt(editor.style.height, 10) || 300;

  Object.defineProperty(area, "clientHeight", { get: () => AREA });
  Object.defineProperty(editor, "offsetHeight", { get: editorHeight });
  Object.defineProperty(box, "offsetHeight", {
    get: () => editorHeight() + CHROME,
  });
  Object.defineProperty(split, "offsetHeight", { get: () => DIVIDER });

  const hook = Object.create(EditorSplit);
  hook.el = split;
  hook.mounted();
  return { hook, editor, split };
}

const key = (el, name) =>
  el.dispatchEvent(new KeyboardEvent("keydown", { key: name, bubbles: true }));

describe("EditorSplit", () => {
  beforeEach(() => {
    localStorage.clear();
    wide = { matches: true, addEventListener() {}, removeEventListener() {} };
    window.matchMedia = () => wide;
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("measures the parent the divider has now, after a patch moves it", () => {
    const { hook, editor, split } = mount();
    const area = document.getElementById("area");
    const moved = area.cloneNode(false);
    Object.defineProperty(moved, "clientHeight", { get: () => AREA });
    moved.append(...area.children);
    area.replaceWith(moved);

    expect(() => hook.updated()).not.toThrow();
    expect(split.parentElement).toBe(moved);
    expect(editor.style.height).toBe(`${Math.round(SPACE * 0.35)}px`);
  });

  it("leaves the editor alone while the divider has no parent", () => {
    const { hook, editor, split } = mount();
    const height = editor.style.height;
    split.remove();

    expect(() => hook.updated()).not.toThrow();
    expect(editor.style.height).toBe(height);
  });

  it("gives the editor its default share", () => {
    const { editor } = mount();

    expect(editor.style.height).toBe(`${Math.round(SPACE * 0.35)}px`);
    expect(editor.hasAttribute("data-split")).toBe(true);
  });

  it("keeps the height the viewer chose", () => {
    localStorage.setItem("lotus:editor_height", "180");

    expect(mount().editor.style.height).toBe("180px");
  });

  it("leaves the results room, and the editor some", () => {
    const { editor, split } = mount();

    key(split, "End");
    expect(editor.style.height).toBe(`${SPACE - 220}px`);

    key(split, "Home");
    expect(editor.style.height).toBe("96px");
    expect(localStorage.getItem("lotus:editor_height")).toBe("96");
  });

  it("steps with the arrow keys and resets on a double-click", () => {
    const { editor, split } = mount();
    const start = parseInt(editor.style.height, 10);

    key(split, "ArrowDown");
    expect(editor.style.height).toBe(`${start + 24}px`);
    key(split, "ArrowUp");
    key(split, "ArrowUp");
    expect(editor.style.height).toBe(`${start - 24}px`);

    split.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }));
    expect(editor.style.height).toBe(`${start}px`);
    expect(localStorage.getItem("lotus:editor_height")).toBe("null");
  });

  it("lets a narrow screen scroll instead", () => {
    wide.matches = false;
    const { editor } = mount();

    expect(editor.style.height).toBe("");
    expect(editor.style.minHeight).toBe("300px");
    expect(editor.hasAttribute("data-split")).toBe(false);
  });
});
