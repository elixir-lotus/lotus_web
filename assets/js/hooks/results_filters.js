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
const ResultsFilters = {
  mounted() {
    this.observer = new MutationObserver(() => this.adopt());
    this.watch();
    this.adopt();
  },

  updated() {
    this.watch();
    this.adopt();
  },

  destroyed() {
    this.observer?.disconnect();
  },

  grid() {
    return document.getElementById(this.el.dataset.grid);
  },

  // Masu adds its bar to the grid's `.masu-ui`, which LiveView renders.
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
};

export default ResultsFilters;
