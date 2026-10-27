import { describe, it, expect, afterEach } from "vitest";
import ResultsFilters from "../../js/hooks/results_filters.js";

// The grid as Masu leaves it: its filter bar in its `.masu-ui`.
function page({ bar = true } = {}) {
  document.body.innerHTML = `
    <div id="header"><div id="slot" data-grid="grid"></div></div>
    <div id="grid" class="masu"><div class="masu-ui"></div><div class="masu-grid"></div></div>`;

  if (bar) addBar();
  return document.getElementById("slot");
}

function addBar() {
  const bar = document.createElement("div");
  bar.className = "masu-chips";
  bar.innerHTML = `<button type="button" class="masu-add-filter">Add filter</button>`;
  document.querySelector("#grid > .masu-ui").appendChild(bar);
  return bar;
}

function mount(el) {
  const hook = Object.create(ResultsFilters);
  hook.el = el;
  hook.mounted();
  return hook;
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const frame = () => new Promise((resolve) => requestAnimationFrame(() => resolve()));

// happy-dom lays nothing out: the window's width, a box for an element, and
// a menu's width, as the browser would give them.
function windowWidth(width) {
  Object.defineProperty(document.documentElement, "clientWidth", {
    configurable: true,
    get: () => width,
  });
}

function box(el, { left, top, width, height }) {
  el.getBoundingClientRect = () => ({
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
  });
}

// A menu as Masu opens one: in the grid's `.masu-ui`, a popover placed from
// its button's left edge, under it (`below`), inside the window.
function openMenu({ left, top, width = 224, height = 120 }) {
  const menu = document.createElement("div");
  menu.className = "masu-menu masu-panel masu-filters-panel";
  Object.defineProperty(menu, "offsetWidth", { get: () => width });
  Object.defineProperty(menu, "offsetHeight", { get: () => height });
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  document.querySelector("#grid > .masu-ui").appendChild(menu);
  return menu;
}

// The bar's Add filter at the end of the header row: 1248 to 1344, its
// bottom at 512.
function barAtTheEnd(vw = 1400) {
  windowWidth(vw);
  const slot = page();
  mount(slot);
  const button = slot.querySelector(".masu-add-filter");
  box(button, { left: 1248, top: 488, width: 96, height: 24 });
  return { slot, button };
}

describe("ResultsFilters", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("moves the grid's filter bar into the header row", () => {
    const slot = page();
    const bar = document.querySelector(".masu-chips");
    mount(slot);

    expect(bar.parentElement).toBe(slot);
    expect(document.querySelector("#grid .masu-chips")).toBeNull();
  });

  it("takes the bar when the grid adds it after the hook mounts", async () => {
    const slot = page({ bar: false });
    mount(slot);

    const bar = addBar();
    await flush();

    expect(bar.parentElement).toBe(slot);
  });

  it("takes the new bar of a grid that starts again, and drops the old", async () => {
    const slot = page();
    mount(slot);
    const old = slot.firstElementChild;

    const bar = addBar();
    await flush();

    expect(bar.parentElement).toBe(slot);
    expect(old.isConnected).toBe(false);
    expect(slot.children).toHaveLength(1);
  });

  it("keeps the bar's own listeners: it moves the element, not a copy", () => {
    const slot = page();
    const bar = document.querySelector(".masu-chips");
    let clicks = 0;
    bar.addEventListener("click", () => clicks++);
    mount(slot);

    slot.querySelector(".masu-add-filter").click();
    expect(clicks).toBe(1);
  });

  it("stops watching when it goes", async () => {
    const slot = page({ bar: false });
    const hook = mount(slot);
    hook.destroyed();

    addBar();
    await flush();

    expect(slot.children).toHaveLength(0);
  });

  describe("the bar's menus", () => {
    afterEach(() => windowWidth(1024));

    it("opens Add filter's menu right-aligned to the button, not past it", async () => {
      barAtTheEnd();
      // Masu: from the button's left (1248), kept inside the window.
      const menu = openMenu({ left: 1400 - 224 - 4, top: 516 });
      await flush();

      expect(menu.style.left).toBe(`${1344 - 224}px`);
    });

    it("aligns the filter that opens next, and again when Masu places it again", async () => {
      barAtTheEnd();
      const menu = openMenu({ left: 1124, top: 516, width: 272 });
      await flush();
      expect(menu.style.left).toBe(`${1344 - 272}px`);

      // Masu places its menus again as the page scrolls or resizes.
      menu.style.left = "1124px";
      await flush();
      expect(menu.style.left).toBe(`${1344 - 272}px`);
    });

    it("keeps a menu inside a narrow window", async () => {
      windowWidth(700);
      const slot = page();
      mount(slot);
      const button = slot.querySelector(".masu-add-filter");
      // The button wider than what is left of the window to its left.
      box(button, { left: 104, top: 488, width: 96, height: 24 });

      const menu = openMenu({ left: 104, top: 516, width: 272 });
      await flush();
      expect(menu.style.left).toBe("4px");

      box(button, { left: 580, top: 471, width: 96, height: 24 });
      window.dispatchEvent(new Event("resize"));
      await frame();
      expect(menu.style.left).toBe(`${676 - 272}px`);
    });

    it("leaves the menus of the headers and the cells where Masu puts them", async () => {
      barAtTheEnd();
      // A header's menu: under the grid's header, below the row.
      const menu = openMenu({ left: 1100, top: 560 });
      await flush();

      expect(menu.style.left).toBe("1100px");
    });
  });
});
