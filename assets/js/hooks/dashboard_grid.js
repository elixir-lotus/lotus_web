// The dashboard's grid: it places the cards on 12 columns, with no gaps
// above them, and stacks them in one column on a phone. A card folds to
// its title (its chevron): for the viewer, in this browser; in edit mode,
// how it starts, for everyone. In edit mode, a card moves by its title and
// is resized by its corner, with the pointer or with Alt and the arrow
// keys (Shift to resize): it snaps from slot to slot, its width to a
// quarter, a third, a half, two thirds, three quarters or the row, and the
// cards it covers make room. Tidy up (`lotus:tidy`) packs the cards into
// full rows; a card's Size (`lotus:size`) sets its width.
//
// The server renders the cards with their place (data-x, data-y, data-w,
// data-h) on a CSS grid; this hook takes over their style, which the cards
// keep across renders (JS.ignore_attributes on them).
import { COLUMNS, WIDTHS, changes, compact, place, snapWidth, snapX, stack, tidy } from "../lib/dashboard_layout";

// A row is 84px high with 16px between rows; a folded card, its title.
const PITCH = 100;
const GAP = 16;
const FOLDED = 0.6;
const HEADING = 0.6;
const PHONE = 640;
const PHONE_CHART = 320;

export default {
  mounted() {
    this.store = `lotus:dashboard:${this.el.dataset.dashboardId}:folded`;
    this.el.classList.add("lotus-grid-placed");

    this.onPointerDown = (event) => this.pointerDown(event);
    this.onClick = (event) => this.click(event);
    this.onKey = (event) => this.key(event);
    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("click", this.onClick, true);
    this.el.addEventListener("keydown", this.onKey);
    this.onTidy = () => this.tidy();
    this.onSize = (event) => this.size(event.detail);
    this.el.addEventListener("lotus:tidy", this.onTidy);
    this.el.addEventListener("lotus:size", this.onSize);

    this.resize = new ResizeObserver(() => this.layout());
    this.resize.observe(this.el);
    // A card added, removed or set up again (its place, how it starts).
    this.changes = new MutationObserver(() => this.layout());
    this.changes.observe(this.el, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["data-x", "data-y", "data-w", "data-h", "data-folded-default", "data-editing"],
    });
    this.layout();
  },

  updated() {
    this.layout();
  },

  destroyed() {
    this.resize.disconnect();
    this.changes.disconnect();
  },

  // -- The layout --------------------------------------------------------

  cards() {
    return [...this.el.querySelectorAll(":scope > [data-card-id]")];
  },

  card(id) {
    return this.el.querySelector(`:scope > [data-card-id="${CSS.escape(id)}"]`);
  },

  editing() {
    return this.el.dataset.editing === "true";
  },

  // The cards as the server has them.
  base() {
    return this.cards().map((el) => ({
      id: el.dataset.cardId,
      x: Number(el.dataset.x),
      y: Number(el.dataset.y),
      w: Number(el.dataset.w),
      h: Number(el.dataset.h),
    }));
  },

  folds() {
    try {
      return JSON.parse(localStorage.getItem(this.store) || "{}");
    } catch {
      return {};
    }
  },

  // Folded: in edit mode, never (the cards are set up open); else as the
  // viewer left it, or as the card starts.
  folded(el) {
    if (this.editing() || !el.querySelector("[data-card-fold]")) return false;
    const mine = this.folds()[el.dataset.cardId];
    return mine === undefined ? el.dataset.foldedDefault === "true" : mine;
  },

  layout() {
    if (this.drag) return;
    const folded = new Set(this.cards().filter((el) => this.folded(el)).map((el) => el.dataset.cardId));
    // A heading, out of edit mode, is a line of text over the cards it names.
    const headings = new Set(
      this.editing() ? [] : this.cards().filter((el) => el.dataset.cardType === "heading").map((el) => el.dataset.cardId),
    );
    const cards = this.base().map((card) =>
      folded.has(card.id) ? { ...card, h: FOLDED } : headings.has(card.id) ? { ...card, h: HEADING } : card,
    );
    this.phone = this.el.clientWidth < PHONE;
    this.el.classList.toggle("lotus-grid-stacked", this.phone);
    if (this.phone) this.flow(stack(cards), folded);
    else this.draw(compact(cards), folded);
  },

  // A phone's dashboard: one column, in reading order, each card as high as
  // what it shows, and a chart at a height that reads.
  flow(layout, folded) {
    layout.forEach((card, order) => {
      const el = this.card(card.id);
      if (!el) return;
      const chart = !folded.has(card.id) && el.querySelector(".fude");
      Object.assign(el.style, { order, left: "", top: "", width: "", height: chart ? `${PHONE_CHART}px` : "" });
      el.dataset.folded = String(folded.has(card.id));
      el.querySelector("[data-card-fold]")?.setAttribute("aria-expanded", String(!folded.has(card.id)));
    });
    this.el.style.height = "";
  },

  draw(layout, folded = new Set()) {
    const column = (this.el.clientWidth + GAP) / COLUMNS;
    let bottom = 0;
    for (const card of layout) {
      const el = this.card(card.id);
      if (!el) continue;
      if (this.drag && this.drag.id === card.id) {
        bottom = Math.max(bottom, card.y + card.h);
        continue;
      }
      Object.assign(el.style, box(card, column));
      el.dataset.folded = String(folded.has(card.id));
      el.querySelector("[data-card-fold]")?.setAttribute("aria-expanded", String(!folded.has(card.id)));
      bottom = Math.max(bottom, card.y + card.h);
    }
    this.el.style.height = `${Math.max(0, bottom * PITCH - GAP)}px`;
  },

  // -- Folding -------------------------------------------------------------

  click(event) {
    // The click that ends a drag is not a click on the card.
    if (this.dragged) {
      this.dragged = false;
      event.stopPropagation();
      event.preventDefault();
      return;
    }
    const fold = event.target.closest("[data-card-fold]");
    if (!fold) return;
    event.stopPropagation();
    const el = fold.closest("[data-card-id]");
    const id = el.dataset.cardId;

    if (this.editing()) {
      // How it starts, for everyone: the card's setting.
      const starts = el.dataset.foldedDefault !== "true";
      this.pushEventTo(this.el.dataset.target, "fold_card", { card_id: id, folded: starts });
    } else {
      const folds = this.folds();
      folds[id] = !this.folded(el);
      try {
        localStorage.setItem(this.store, JSON.stringify(folds));
      } catch {
        // No storage (a private window): it folds until the page reloads.
        el.dataset.foldedDefault = String(folds[id]);
      }
      this.layout();
    }
  },

  // -- Moving and resizing (edit mode) ----------------------------------------

  pointerDown(event) {
    if (!this.editing() || this.phone || event.button !== 0) return;
    const resize = event.target.closest("[data-card-resize]");
    const handle = event.target.closest("[data-card-handle]");
    if (!resize && (!handle || event.target.closest("button, a, input, select, textarea"))) return;

    const el = event.target.closest("[data-card-id]");
    const base = this.base();
    const card = base.find((c) => c.id === el.dataset.cardId);
    const column = (this.el.clientWidth + GAP) / COLUMNS;
    this.drag = {
      id: card.id,
      el,
      base,
      card,
      column,
      resize: Boolean(resize),
      start: { x: event.clientX, y: event.clientY },
      box: { left: el.offsetLeft, top: el.offsetTop, width: el.offsetWidth, height: el.offsetHeight },
      to: card,
      moved: false,
    };
    el.setPointerCapture(event.pointerId);
    const move = (e) => this.pointerMove(e);
    const up = (e) => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
      this.pointerUp(e);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
  },

  pointerMove(event) {
    const drag = this.drag;
    const dx = event.clientX - drag.start.x;
    const dy = event.clientY - drag.start.y;
    if (!drag.moved && Math.hypot(dx, dy) < 4) return;
    if (!drag.moved) {
      drag.moved = true;
      drag.el.classList.add("lotus-card-dragging");
    }

    // The slot under the pointer: the card snaps to it, as a magnet.
    let change;
    if (drag.resize) {
      const w = (drag.box.width + dx + GAP) / drag.column;
      const h = (drag.box.height + dy + GAP) / PITCH;
      change = { w: snapWidth(w), h: Math.max(1, Math.round(h)) };
    } else {
      const left = drag.box.left + dx;
      const top = drag.box.top + dy;
      const y = Math.max(0, Math.round(top / PITCH));
      change = { x: snapX(left / drag.column, { ...drag.card, y }, drag.base), y };
    }

    const to = place(drag.base, drag.id, change);
    const card = to.find((c) => c.id === drag.id);
    if (drag.layout && same(card, drag.to)) return;
    drag.to = card;
    drag.layout = to;
    Object.assign(drag.el.style, box(card, drag.column));
    this.draw(to);
  },

  pointerUp() {
    const drag = this.drag;
    this.drag = null;
    drag.el.classList.remove("lotus-card-dragging");
    if (!drag.moved || !drag.layout) return;
    this.dragged = true;
    setTimeout(() => (this.dragged = false), 0);
    this.commit(drag.base, drag.layout);
  },

  key(event) {
    if (!this.editing() || !event.altKey) return;
    const el = event.target.closest("[data-card-id]");
    if (!el || event.target !== el) return;
    const step = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[event.key];
    if (!step) return;
    event.preventDefault();
    const base = this.base();
    const card = base.find((c) => c.id === el.dataset.cardId);
    const change = event.shiftKey
      ? { w: nextWidth(card.w, step[0]), h: Math.max(1, card.h + step[1]) }
      : { x: card.x + step[0], y: Math.max(0, card.y + step[1]) };
    this.commit(base, place(base, card.id, change));
    el.focus();
  },

  // Tidy up: the cards in full rows, a heading on a row of its own.
  tidy() {
    if (!this.editing()) return;
    const base = this.base();
    const headings = new Set(
      this.cards().filter((el) => el.dataset.cardType === "heading").map((el) => el.dataset.cardId),
    );
    this.commit(base, tidy(base, headings));
  },

  // A card's width, from its menu's Size.
  size({ card, w }) {
    if (!this.editing()) return;
    const base = this.base();
    this.commit(base, place(base, String(card), { w }));
  },

  // Draws the new layout at once, and sends the server the cards that moved.
  commit(before, after) {
    this.draw(after);
    for (const card of after) {
      const el = this.card(card.id);
      if (el) Object.assign(el.dataset, { x: card.x, y: card.y, w: card.w, h: card.h });
    }
    const moved = changes(before, after);
    if (Object.keys(moved).length > 0) {
      this.pushEventTo(this.el.dataset.target, "update_layouts", { layouts: moved });
    }
  },
};

const same = (a, b) => b && a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h;

// The next width a card snaps to, wider or narrower.
function nextWidth(w, step) {
  if (step > 0) return WIDTHS.find((width) => width > w) ?? COLUMNS;
  return [...WIDTHS].reverse().find((width) => width < w) ?? WIDTHS[0];
}

// The box of a card, in pixels.
function box(card, column) {
  return {
    left: `${card.x * column}px`,
    top: `${card.y * PITCH}px`,
    width: `${card.w * column - GAP}px`,
    height: `${card.h * PITCH - GAP}px`,
  };
}
