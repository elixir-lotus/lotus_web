// "just now", "2 min ago": a <time datetime> written relative to now, in the
// page's language, and again every 30 seconds.
const UNITS = [
  ["day", 86400],
  ["hour", 3600],
  ["minute", 60],
];

export function relativeTime(date, now = new Date(), locale = undefined) {
  const seconds = Math.round((date.getTime() - now.getTime()) / 1000);
  const format = new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "short" });
  for (const [unit, size] of UNITS) {
    if (Math.abs(seconds) >= size) return format.format(Math.trunc(seconds / size), unit);
  }
  return format.format(0, "second");
}

export default {
  mounted() {
    this.write();
    this.timer = setInterval(() => this.write(), 30000);
  },

  updated() {
    this.write();
  },

  write() {
    const date = new Date(this.el.getAttribute("datetime"));
    if (Number.isNaN(date.getTime())) return;
    this.el.textContent = relativeTime(date, new Date(), document.documentElement.lang || undefined);
    this.el.title = date.toLocaleString();
  },

  destroyed() {
    clearInterval(this.timer);
  },
};
