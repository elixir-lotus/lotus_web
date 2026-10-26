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
});
