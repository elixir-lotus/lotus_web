// The layout of a dashboard's cards on 12 columns, as plain functions.
//
// A card is { id, x, y, w, h }: its column (0–11), its row, its width in
// columns and its height in rows. A layout is a list of cards. Cards fall
// up to the first row where they fit (no gaps above them, in the order of
// their rows), and a card that is moved or resized pushes the cards it
// covers down. The hook (hooks/dashboard_grid.js) measures and draws; these
// functions only place.

export const COLUMNS = 12;

const overlaps = (a, b) =>
  a.id !== b.id && a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

const byPlace = (a, b) => a.y - b.y || a.x - b.x;

// Keeps a card on the columns, with at least one column and one row.
export function clamp(card) {
  const w = Math.max(1, Math.min(COLUMNS, Math.round(card.w)));
  const x = Math.max(0, Math.min(COLUMNS - w, Math.round(card.x)));
  return { ...card, x, w, y: Math.max(0, Math.round(card.y)), h: Math.max(1, Math.round(card.h)) };
}

// Each card falls up to the first row where it covers no card above it.
// `fixed` (an id) stays where it is: the card being moved.
export function compact(layout, fixed = null) {
  const placed = [];
  const still = layout.find((card) => card.id === fixed);
  if (still) placed.push(still);

  for (const card of [...layout].filter((c) => c.id !== fixed).sort(byPlace)) {
    let y = 0;
    // The lowest row above which it would cover something.
    for (;;) {
      const at = { ...card, y };
      const hit = placed.find((other) => overlaps(at, other));
      if (!hit) break;
      y = hit.y + hit.h;
    }
    placed.push({ ...card, y });
  }

  return layout.map((card) => placed.find((p) => p.id === card.id));
}

// Puts a card at a new place or size, pushes down what it covers, and
// closes the gaps.
export function place(layout, id, change) {
  const swapped = swap(layout, id, change);
  if (swapped) return compact(swapped);

  const moved = layout.map((card) => (card.id === id ? clamp({ ...card, ...change }) : card));
  const target = moved.find((card) => card.id === id);

  // What it covers goes below it, and what that covers below that.
  const pushed = moved.map((card) => ({ ...card }));
  const queue = [target];
  while (queue.length > 0) {
    const top = queue.shift();
    for (const card of pushed) {
      if (card.id !== target.id && overlaps(top, card)) {
        card.y = top.y + top.h;
        queue.push(card);
      }
    }
  }

  return compact(pushed, id);
}

// A card dropped on the place of a card of its size takes it, and that
// card takes its own: two charts side by side change sides.
function swap(layout, id, change) {
  const card = layout.find((c) => c.id === id);
  const target = clamp({ ...card, ...change });
  if (target.w !== card.w || target.h !== card.h) return null;
  const other = layout.find(
    (c) => c.id !== id && c.x === target.x && c.y === target.y && c.w === card.w && c.h === card.h,
  );
  if (!other) return null;
  return layout.map((c) =>
    c.id === id ? target : c.id === other.id ? { ...other, x: card.x, y: card.y } : c,
  );
}

// One column, in reading order: a phone's layout.
export function stack(layout) {
  let y = 0;
  return [...layout].sort(byPlace).map((card) => {
    const stacked = { ...card, x: 0, w: COLUMNS, y };
    y += card.h;
    return stacked;
  });
}

// The changes from one layout to another, for the server: { id: {x,y,w,h} }.
export function changes(before, after) {
  const was = new Map(before.map((card) => [card.id, card]));
  const changed = {};
  for (const card of after) {
    const old = was.get(card.id);
    if (!old || old.x !== card.x || old.y !== card.y || old.w !== card.w || old.h !== card.h) {
      changed[card.id] = { x: card.x, y: card.y, w: card.w, h: card.h };
    }
  }
  return changed;
}

// The widths a card snaps to: a quarter, a third, a half, two thirds,
// three quarters, the whole row.
export const WIDTHS = [3, 4, 6, 8, 9, 12];

export function snapWidth(w) {
  return WIDTHS.reduce((best, width) => (Math.abs(width - w) < Math.abs(best - w) ? width : best));
}

// Tidy up: the cards in reading order, in rows that fill the 12 columns.
// A row takes cards while they fit; it is then split evenly (halves,
// thirds, quarters; in proportion for five), and its cards take the height
// of its tallest. A heading (`wide`) has a row of its own.
export function tidy(layout, wide = new Set()) {
  const rows = [];
  let row = [];
  let used = 0;
  for (const card of [...layout].sort(byPlace)) {
    const w = wide.has(card.id) ? COLUMNS : Math.min(COLUMNS, card.w);
    if (row.length > 0 && (used + w > COLUMNS || wide.has(card.id) || wide.has(row[0].id))) {
      rows.push(row);
      row = [];
      used = 0;
    }
    row.push({ ...card, w });
    used += w;
  }
  if (row.length > 0) rows.push(row);

  const tidied = [];
  let y = 0;
  for (const cards of rows) {
    const total = cards.reduce((sum, card) => sum + card.w, 0);
    const h = Math.max(...cards.map((card) => card.h));
    const even = COLUMNS % cards.length === 0;
    // Rounded so that the row is 12 columns exactly.
    let x = 0;
    cards.forEach((card, i) => {
      const share = even ? COLUMNS / cards.length : Math.round((card.w * COLUMNS) / total);
      const w = i === cards.length - 1 ? COLUMNS - x : Math.max(1, share);
      tidied.push({ ...card, x, y, w, h: wide.has(card.id) ? card.h : h });
      x += w;
    });
    y += h;
  }
  return layout.map((card) => tidied.find((t) => t.id === card.id));
}

// The column a moved card snaps to, as to a magnet: the slots of its own
// width (a half at 0 or 6), the row's two edges, and the edges of the cards
// in the rows it would cover (beside them, or in line with them). `raw` is
// where the pointer put it, in columns; `card` its width, row and height.
export function snapX(raw, card, layout) {
  const { w, y, h } = card;
  const marks = new Set([0, COLUMNS - w]);
  for (let x = 0; x + w <= COLUMNS; x += w) marks.add(x);
  for (const other of layout) {
    if (other.id === card.id || other.y >= y + h || y >= other.y + other.h) continue;
    for (const x of [other.x, other.x + other.w, other.x + other.w - w, other.x - w]) {
      if (x >= 0 && x + w <= COLUMNS) marks.add(x);
    }
  }
  return [...marks].reduce((best, x) => (Math.abs(x - raw) < Math.abs(best - raw) ? x : best));
}
