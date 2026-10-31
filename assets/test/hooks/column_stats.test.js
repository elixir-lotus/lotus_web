import { describe, it, expect } from "vitest";
import ColumnStats from "../../js/hooks/column_stats.js";

function render(stats) {
  const el = document.createElement("div");
  el.setAttribute("data-stats", JSON.stringify(stats));
  ColumnStats.render.call({ el });
  return el;
}

const base = { count: 1, null_count: 0, null_percentage: 0, distinct_count: 1 };

describe("ColumnStats", () => {
  it("shows a top value as text, in the label and its title", () => {
    const value = '"><img id=pwn src=x onerror="window.__x=1">';
    const el = render({
      ...base,
      type: "string",
      min_length: 5,
      max_length: 40,
      top_values: [{ value, count: 1 }],
    });

    expect(el.querySelector("img")).toBeNull();
    const label = el.querySelector(".lotus-stats-hist-label");
    expect(label.getAttribute("title")).toBe(value);
    expect(label.textContent).toBe(value.substring(0, 24) + "…");
  });

  it("shows a short top value as text", () => {
    const el = render({
      ...base,
      type: "string",
      top_values: [{ value: "<svg id=pwn onload=1>", count: 1 }],
    });

    expect(el.querySelector("svg")).toBeNull();
    expect(el.querySelector(".lotus-stats-hist-label").textContent).toBe("<svg id=pwn onload=1>");
  });

  it("shows temporal buckets and bounds as text", () => {
    const el = render({
      ...base,
      type: "temporal",
      earliest: "<b id=early>",
      latest: "<b id=late>",
      distribution: [{ bucket: "<i id=bucket>", count: 1 }],
    });

    expect(el.querySelector("b, i")).toBeNull();
    expect(el.textContent).toContain("<b id=early>");
    expect(el.textContent).toContain("<i id=bucket>");
  });
});
