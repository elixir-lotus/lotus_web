// Side by side, the pinned result's table and the results grid scroll
// together: scrolling one scrolls the other to the same place, down and
// across. Both draw their rows 40px high, so the same scrollTop shows the
// same row numbers.
//
// On the pinned table's scrolling element; it names the grid in
// `data-grid` and follows `data-sync` ("false": each scrolls on its own).
// The grid is Masu's: its rows scroll in its `.masu-grid`, which it may
// build again (a new run), so the hook finds it on each scroll.

const PinScroll = {
  mounted() {
    // The element just scrolled to follow the other: its scroll event, which
    // comes before the next frame, is not sent back.
    this.ignore = null;

    this.onOwn = () => this.follow(this.el, this.grid());
    this.onGrid = (event) => {
      const grid = this.grid();
      if (grid && event.target === grid) this.follow(grid, this.el);
    };

    this.el.addEventListener("scroll", this.onOwn, { passive: true });
    // Captured on the document: the grid's element changes, the listener
    // stays.
    document.addEventListener("scroll", this.onGrid, {
      passive: true,
      capture: true,
    });
  },

  destroyed() {
    cancelAnimationFrame(this.frame);
    this.el.removeEventListener("scroll", this.onOwn);
    document.removeEventListener("scroll", this.onGrid, { capture: true });
  },

  grid() {
    const host = document.getElementById(this.el.dataset.grid);
    if (!host) return null;
    return host.matches(".masu-grid") ? host : host.querySelector(".masu-grid");
  },

  follow(from, to) {
    if (this.el.dataset.sync === "false" || !to || this.ignore === from) return;
    if (to.scrollTop === from.scrollTop && to.scrollLeft === from.scrollLeft)
      return;
    this.ignore = to;
    to.scrollTop = from.scrollTop;
    to.scrollLeft = from.scrollLeft;
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => (this.ignore = null));
  },
};

export default PinScroll;
