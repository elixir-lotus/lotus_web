import { describe, it, expect } from "vitest";
import { relativeTime } from "../../js/hooks/relative_time.js";

// What Intl writes, so that the test does not depend on the ICU of Node.
const intl = (locale, value, unit) =>
  new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "short" }).format(value, unit);

describe("relativeTime", () => {
  const now = new Date("2026-10-24T12:00:00Z");
  const ago = (seconds) => new Date(now.getTime() - seconds * 1000);

  it("says now under a minute", () => {
    expect(relativeTime(ago(20), now, "en")).toBe(intl("en", 0, "second"));
  });

  it("counts minutes, hours and days", () => {
    expect(relativeTime(ago(150), now, "en")).toBe(intl("en", -2, "minute"));
    expect(relativeTime(ago(3 * 3600), now, "en")).toBe(intl("en", -3, "hour"));
    expect(relativeTime(ago(86400), now, "en")).toBe(intl("en", -1, "day"));
  });

  it("writes the page's language", () => {
    expect(relativeTime(ago(120), now, "fr")).toBe(intl("fr", -2, "minute"));
  });
});
