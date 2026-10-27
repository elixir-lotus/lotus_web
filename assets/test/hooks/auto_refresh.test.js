import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import AutoRefresh from "../../js/hooks/auto_refresh.js";

function mount(attrs) {
  const el = document.createElement("div");
  for (const [name, value] of Object.entries(attrs))
    el.setAttribute(name, value);
  document.body.appendChild(el);

  const hook = Object.create(AutoRefresh);
  hook.el = el;
  hook.pushEvent = vi.fn();
  hook.pushEventTo = vi.fn();
  hook.mounted();
  return hook;
}

describe("AutoRefresh", () => {
  let hidden = false;

  beforeEach(() => {
    vi.useFakeTimers();
    hidden = false;
    Object.defineProperty(document, "hidden", {
      configurable: true,
      get: () => hidden,
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  it("sends its tick to the component it is in, every so many seconds", () => {
    const hook = mount({ "data-seconds": "10", "phx-target": "1" });

    vi.advanceTimersByTime(25_000);

    expect(hook.pushEventTo).toHaveBeenCalledTimes(2);
    expect(hook.pushEventTo).toHaveBeenCalledWith(
      hook.el,
      "auto_refresh_tick",
      {},
    );
    expect(hook.pushEvent).not.toHaveBeenCalled();
    hook.destroyed();
  });

  it("sends the event it names, to the view when it has no target", () => {
    const hook = mount({ "data-seconds": "5", "data-event": "live_tick" });

    vi.advanceTimersByTime(5_000);

    expect(hook.pushEvent).toHaveBeenCalledWith("live_tick", {});
    hook.destroyed();
  });

  it("skips its ticks while the page is not on screen, when asked to", () => {
    const hook = mount({
      "data-seconds": "10",
      "data-event": "live_tick",
      "data-when-visible": "",
      "phx-target": "1",
    });

    hidden = true;
    vi.advanceTimersByTime(30_000);
    expect(hook.pushEventTo).not.toHaveBeenCalled();

    hidden = false;
    vi.advanceTimersByTime(10_000);
    expect(hook.pushEventTo).toHaveBeenCalledTimes(1);
    hook.destroyed();
  });

  it("stops when removed", () => {
    const hook = mount({ "data-seconds": "10", "phx-target": "1" });
    hook.destroyed();

    vi.advanceTimersByTime(30_000);
    expect(hook.pushEventTo).not.toHaveBeenCalled();
  });
});
