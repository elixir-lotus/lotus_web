import { describe, it, expect, afterEach, vi } from "vitest";
import PinScroll from "../../js/hooks/pin_scroll.js";

function scrollable(el) {
  // jsdom does not scroll: a settable position, and its scroll event.
  for (const prop of ["scrollTop", "scrollLeft"]) {
    let value = 0;
    Object.defineProperty(el, prop, {
      configurable: true,
      get: () => value,
      set: (v) => {
        value = v;
        el.dispatchEvent(new Event("scroll"));
      },
    });
  }
  return el;
}

function mount(sync = "true") {
  document.body.innerHTML = `
    <div id="results-grid-1"><div class="masu-grid"></div></div>
    <div id="pinned" data-grid="results-grid-1" data-sync="${sync}"></div>`;
  const grid = scrollable(document.querySelector(".masu-grid"));
  const el = scrollable(document.getElementById("pinned"));
  const hook = Object.create(PinScroll);
  hook.el = el;
  hook.mounted();
  return { hook, el, grid };
}

describe("PinScroll", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  it("scrolls the grid with the pinned table, and the table with the grid", () => {
    vi.spyOn(window, "requestAnimationFrame").mockImplementation(() => 1);
    const { hook, el, grid } = mount();

    el.scrollTop = 120;
    expect(grid.scrollTop).toBe(120);

    hook.ignore = null;
    grid.scrollLeft = 30;
    expect(el.scrollLeft).toBe(30);
    hook.destroyed();
  });

  it("each scrolls on its own when not in sync", () => {
    const { hook, el, grid } = mount("false");
    el.scrollTop = 80;
    expect(grid.scrollTop).toBe(0);
    hook.destroyed();
  });
});
