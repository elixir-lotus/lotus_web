import { describe, it, expect, vi, beforeAll } from "vitest";

const toolResult = (html) => ({
  jsonrpc: "2.0",
  method: "ui/notifications/tool-result",
  params: { structuredContent: { html, title: "Chart" } },
});

describe("the chart app", () => {
  beforeAll(async () => {
    globalThis.ResizeObserver ??= class {
      observe() {}
    };
    vi.spyOn(window.parent, "postMessage").mockImplementation(() => {});
    document.body.innerHTML = '<h1 id="title"></h1><div id="chart"></div><p id="note"></p>';
    await import("../../js/mcp/chart_app.js");
  });

  it("ignores a result from a frame that is not the host", () => {
    const frame = document.createElement("iframe");
    document.body.appendChild(frame);

    window.dispatchEvent(
      new MessageEvent("message", {
        data: toolResult('<img id="pwn" src="x">'),
        source: frame.contentWindow,
      }),
    );

    expect(document.getElementById("pwn")).toBeNull();
    expect(document.getElementById("chart").innerHTML).toBe("");
  });

  it("draws the host's result", () => {
    window.dispatchEvent(
      new MessageEvent("message", {
        data: toolResult('<div id="drawn"></div>'),
        source: window.parent,
      }),
    );

    expect(document.getElementById("drawn")).not.toBeNull();
  });
});
