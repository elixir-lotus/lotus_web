import { beforeEach, describe, expect, it } from "vitest";
import { listViews, store } from "../../js/lib/settings.js";

describe("listViews", () => {
  beforeEach(() => localStorage.clear());

  it("gives each list's view as the viewer last chose it", () => {
    store("queries_view", "list");
    store("dashboards_view", "grid");

    expect(listViews()).toEqual({ queries: "list", dashboards: "grid", schedules: undefined });
  });

  it("reads the browser again each time, so a choice made since counts", () => {
    expect(listViews().queries).toBeUndefined();

    store("queries_view", "list");

    expect(listViews().queries).toBe("list");
  });
});
