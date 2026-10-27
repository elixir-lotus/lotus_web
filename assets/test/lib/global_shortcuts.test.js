import { describe, it, expect, afterEach } from "vitest";
import { pane } from "../../js/lib/global_shortcuts.js";

const shortcut = (target) => {
  const event = new KeyboardEvent("keydown", { key: "ArrowUp", metaKey: true, cancelable: true });
  Object.defineProperty(event, "target", { get: () => target });
  return event;
};

describe("the pane shortcuts", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("click the page's button for the shortcut", () => {
    document.body.innerHTML = `<button data-lotus-shortcut="minimize"></button><div id="page"></div>`;
    let clicks = 0;
    document.querySelector("button").addEventListener("click", () => clicks++);

    const event = shortcut(document.getElementById("page"));
    pane(event, "minimize");
    pane(shortcut(document.getElementById("page")), "expand");

    expect(clicks).toBe(1);
    expect(event.defaultPrevented).toBe(true);
  });

  it("leave a field and the editor their keys", () => {
    document.body.innerHTML = `
      <button data-lotus-shortcut="minimize"></button>
      <textarea></textarea>
      <div class="cm-editor"><div id="line"></div></div>`;
    let clicks = 0;
    document.querySelector("button").addEventListener("click", () => clicks++);

    pane(shortcut(document.querySelector("textarea")), "minimize");
    pane(shortcut(document.getElementById("line")), "minimize");

    expect(clicks).toBe(0);
  });
});
