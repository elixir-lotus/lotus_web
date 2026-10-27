// The results grid's filter bar (Masu's chips and its Add filter), in the
// Results header row instead of on a line of its own above the grid: the
// rows get that line back.
//
// Masu builds its filter bar in the browser and keeps it, with its own
// listeners, in the grid's `.masu-ui`; it adds it there once, when the grid
// starts. This hook, on an element of the header row, takes that element
// in: Masu still draws it, and its clicks, keys and menus are Masu's. It
// takes it in again if the grid starts again (a LiveView reconnects).
//
// The element is phx-update="ignore", so LiveView leaves what it holds; it
// names the grid in `data-grid`, and is a new element for each grid.
//
// The menus of the bar (Add filter's columns, and the filter of a column
// or a chip) open under their button, from its left edge. The bar is at
// the end of the row now, so they would hang past the results: the hook
// puts each one's right edge at its button's, inside the window, each time
// Masu places it (it opens, its size changes, the page scrolls or resizes).

// Masu's room between a menu and the window's edge, and under its button.
const EDGE = 4;
const GAP = 4;

const ResultsFilters = {
  mounted() {
    // The bar's open menus and the button each opened from.
    this.menus = new Map();
    this.observer = new MutationObserver(() => {
      this.adopt();
      this.track();
    });
    this.placed = new MutationObserver((records) => {
      for (const record of records) this.align(record.target);
    });
    this.resized = new ResizeObserver((entries) => {
      for (const entry of entries) this.align(entry.target);
    });
    this.onViewport = () => {
      cancelAnimationFrame(this.frame);
      this.frame = requestAnimationFrame(() => {
        for (const menu of this.menus.keys()) this.align(menu);
      });
    };
    window.addEventListener("scroll", this.onViewport, true);
    window.addEventListener("resize", this.onViewport);

    this.watch();
    this.adopt();
  },

  updated() {
    this.watch();
    this.adopt();
  },

  destroyed() {
    this.observer.disconnect();
    this.placed.disconnect();
    this.resized.disconnect();
    cancelAnimationFrame(this.frame);
    window.removeEventListener("scroll", this.onViewport, true);
    window.removeEventListener("resize", this.onViewport);
  },

  grid() {
    return document.getElementById(this.el.dataset.grid);
  },

  // Masu adds its bar, and the menus it opens, to the grid's `.masu-ui`,
  // which LiveView renders.
  watch() {
    const ui = this.grid()?.querySelector(":scope > .masu-ui");
    if (!ui || ui === this.watched) return;

    this.observer.disconnect();
    this.observer.observe(ui, { childList: true });
    this.watched = ui;
  },

  adopt() {
    const bar = this.watched?.querySelector(":scope > .masu-chips");
    if (bar && bar.parentElement !== this.el) this.el.replaceChildren(bar);
  },

  // A menu that opens: the bar's, if Masu placed it under one of the bar's
  // buttons (the menus of the headers and the cells are under those).
  track() {
    for (const menu of this.menus.keys()) {
      if (!menu.isConnected) this.menus.delete(menu);
    }
    if (!this.watched) return;

    for (const menu of this.watched.querySelectorAll(":scope > .masu-menu")) {
      if (this.menus.has(menu)) continue;
      const button = this.buttonOf(menu);
      if (!button) continue;

      this.menus.set(menu, button);
      this.placed.observe(menu, { attributes: true, attributeFilter: ["style"] });
      this.resized.observe(menu);
      this.align(menu);
    }
  },

  // The bar's button a menu is under (or over, when it opened upwards),
  // the nearest to where Masu put its left edge; none for another menu.
  buttonOf(menu) {
    const top = parseFloat(menu.style.top);
    const left = parseFloat(menu.style.left);
    if (Number.isNaN(top) || Number.isNaN(left)) return null;

    const width = menu.offsetWidth;
    const height = menu.offsetHeight;
    const room = document.documentElement.clientWidth - width - EDGE;
    let best = null;
    let distance = Infinity;

    for (const button of this.el.querySelectorAll(".masu-add-filter, .masu-chip-text")) {
      const box = button.getBoundingClientRect();
      const below = Math.abs(top - (box.bottom + GAP)) < 2;
      const above = Math.abs(top + height - (box.top - GAP)) < 2;
      if (!below && !above) continue;

      const d = Math.abs(left - Math.max(EDGE, Math.min(box.left, room)));
      if (d < distance) [best, distance] = [button, d];
    }

    return best;
  },

  // The menu's right edge at its button's, inside the window.
  align(menu) {
    const button = this.menus.get(menu);
    if (!button?.isConnected || !menu.isConnected) return;

    const width = menu.offsetWidth;
    const room = document.documentElement.clientWidth - width - EDGE;
    const right = button.getBoundingClientRect().right;
    const left = `${Math.max(EDGE, Math.min(right - width, room))}px`;
    if (menu.style.left !== left) menu.style.left = left;
  },
};

export default ResultsFilters;
