import { describe, it, expect } from "vitest";
import { changes, clamp, compact, place, stack } from "../../js/lib/dashboard_layout.js";

const card = (id, x, y, w, h) => ({ id, x, y, w, h });
const at = (layout, id) => {
  const { x, y, w, h } = layout.find((c) => c.id === id);
  return [x, y, w, h];
};

describe("clamp", () => {
  it("keeps a card on the 12 columns, at least one by one", () => {
    expect(clamp(card("a", 10, -2, 6, 0))).toEqual(card("a", 6, 0, 6, 1));
    expect(clamp(card("a", 2.4, 1.6, 0, 3))).toEqual(card("a", 2, 2, 1, 3));
  });
});

describe("compact", () => {
  it("closes the gaps above the cards, in the order of their rows", () => {
    const layout = compact([card("a", 0, 3, 6, 2), card("b", 6, 5, 6, 2), card("c", 0, 9, 12, 1)]);
    expect(at(layout, "a")).toEqual([0, 0, 6, 2]);
    expect(at(layout, "b")).toEqual([6, 0, 6, 2]);
    expect(at(layout, "c")).toEqual([0, 2, 12, 1]);
  });

  it("keeps a card under the one above it in its columns", () => {
    const layout = compact([card("a", 0, 0, 8, 4), card("b", 4, 4, 8, 2)]);
    expect(at(layout, "b")).toEqual([4, 4, 8, 2]);
  });
});

describe("place", () => {
  const layout = [card("a", 0, 0, 6, 4), card("b", 6, 0, 6, 4), card("c", 0, 4, 12, 2)];

  it("moves a card and pushes down what it covers", () => {
    const moved = place(layout, "c", { x: 0, y: 0 });
    expect(at(moved, "c")).toEqual([0, 0, 12, 2]);
    expect(at(moved, "a")).toEqual([0, 2, 6, 4]);
    expect(at(moved, "b")).toEqual([6, 2, 6, 4]);
  });

  it("swaps two cards side by side", () => {
    const moved = place(layout, "a", { x: 6, y: 0 });
    expect(at(moved, "a")).toEqual([6, 0, 6, 4]);
    expect(at(moved, "b")).toEqual([0, 0, 6, 4]);
  });

  it("resizes a card, and the cards below follow its new height", () => {
    const resized = place(layout, "a", { h: 6 });
    expect(at(resized, "a")).toEqual([0, 0, 6, 6]);
    expect(at(resized, "c")).toEqual([0, 6, 12, 2]);
  });

  it("does not let a card leave the columns", () => {
    expect(at(place(layout, "a", { x: 9 }), "a")).toEqual([6, 0, 6, 4]);
  });
});

describe("stack", () => {
  it("puts the cards in one column, in reading order", () => {
    const stacked = stack([card("b", 6, 0, 6, 4), card("a", 0, 0, 6, 4), card("c", 0, 4, 12, 2)]);
    expect(stacked.map((c) => [c.id, c.y])).toEqual([
      ["a", 0],
      ["b", 4],
      ["c", 8],
    ]);
    expect(stacked.every((c) => c.x === 0 && c.w === 12)).toBe(true);
  });
});

describe("changes", () => {
  it("lists the cards whose place or size changed", () => {
    const before = [card("a", 0, 0, 6, 4), card("b", 6, 0, 6, 4)];
    const after = [card("a", 0, 0, 6, 4), card("b", 0, 4, 6, 4)];
    expect(changes(before, after)).toEqual({ b: { x: 0, y: 4, w: 6, h: 4 } });
  });
});

import { snapWidth, tidy } from "../../js/lib/dashboard_layout.js";

describe("snapWidth", () => {
  it("snaps to a quarter, a third, a half, two thirds, three quarters or the row", () => {
    expect([1, 2, 5, 7, 10, 11, 12].map(snapWidth)).toEqual([3, 3, 4, 6, 9, 12, 12]);
  });
});

describe("tidy", () => {
  it("fills each row and gives its cards one height, in reading order", () => {
    const layout = [card("a", 0, 0, 6, 4), card("b", 0, 4, 4, 3), card("c", 6, 4, 4, 5), card("d", 0, 9, 8, 2)];
    const tidied = tidy(layout);
    expect(at(tidied, "a")).toEqual([0, 0, 6, 4]);
    expect(at(tidied, "b")).toEqual([6, 0, 6, 4]);
    expect(at(tidied, "c")).toEqual([0, 4, 6, 5]);
    expect(at(tidied, "d")).toEqual([6, 4, 6, 5]);
  });

  it("widens a lone card to the row, and keeps a heading on a row of its own", () => {
    const layout = [card("h", 0, 0, 12, 1), card("a", 0, 1, 4, 4), card("b", 4, 1, 4, 4), card("c", 0, 5, 5, 3)];
    const tidied = tidy(layout, new Set(["h"]));
    expect(at(tidied, "h")).toEqual([0, 0, 12, 1]);
    expect(at(tidied, "a")).toEqual([0, 1, 6, 4]);
    expect(at(tidied, "b")).toEqual([6, 1, 6, 4]);
    expect(at(tidied, "c")).toEqual([0, 5, 12, 3]);
  });

  it("splits three or four cards evenly", () => {
    const tidied = tidy([card("a", 0, 0, 3, 2), card("b", 3, 0, 3, 2), card("c", 6, 0, 2, 3), card("d", 8, 0, 3, 2)]);
    expect(tidied.map((c) => [c.x, c.w, c.h])).toEqual([
      [0, 3, 3],
      [3, 3, 3],
      [6, 3, 3],
      [9, 3, 3],
    ]);
  });
});

import { snapX } from "../../js/lib/dashboard_layout.js";

describe("snapX", () => {
  const layout = [card("a", 0, 0, 6, 4), card("b", 6, 0, 6, 4), card("c", 0, 4, 4, 3)];

  it("pulls a half to the slots of its width", () => {
    expect(snapX(1.8, card("b", 6, 0, 6, 4), layout)).toBe(0);
    expect(snapX(4.4, card("b", 6, 0, 6, 4), layout)).toBe(6);
  });

  it("pulls a card beside the cards of its rows, not of others", () => {
    expect(snapX(3.1, card("x", 0, 4, 4, 3), layout)).toBe(4);
    // Beside "c" in its rows; below them, to the slots of its width.
    expect(snapX(3.2, card("x", 0, 4, 5, 3), layout)).toBe(4);
    expect(snapX(3.2, card("x", 0, 9, 5, 3), layout)).toBe(5);
  });
});
