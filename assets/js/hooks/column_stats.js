import tippy from "tippy.js";

function formatNumber(n) {
  if (n == null) return "—";
  return Number(n).toLocaleString(undefined, { maximumFractionDigits: 4 });
}

function formatPercentage(n) {
  if (n == null) return "—";
  return Number(n).toFixed(1) + "%";
}

function buildHistogramHTML(histogram) {
  if (!histogram || histogram.length === 0) return "";
  const maxCount = Math.max(...histogram.map((b) => b.count));
  if (maxCount === 0) return "";

  const bars = histogram
    .map((bin) => {
      const pct = maxCount > 0 ? (bin.count / maxCount) * 100 : 0;
      const label =
        bin.bin_start === bin.bin_end
          ? formatNumber(bin.bin_start)
          : `${formatNumber(bin.bin_start)}–${formatNumber(bin.bin_end)}`;
      return `
      <div class="lotus-stats-hist-row">
        <span class="lotus-stats-hist-label" title="${label}">${label}</span>
        <div class="lotus-stats-hist-bar-bg">
          <div class="lotus-stats-hist-bar" style="width:${pct}%"></div>
        </div>
        <span class="lotus-stats-hist-count">${bin.count}</span>
      </div>`;
    })
    .join("");

  return `
    <div class="lotus-stats-section-title">Distribution</div>
    <div class="lotus-stats-histogram">${bars}</div>`;
}

function buildTopValuesHTML(topValues) {
  if (!topValues || topValues.length === 0) return "";

  const maxCount = Math.max(...topValues.map((v) => v.count));
  const rows = topValues
    .slice(0, 8)
    .map((v) => {
      const pct = maxCount > 0 ? (v.count / maxCount) * 100 : 0;
      const val =
        v.value.length > 24 ? v.value.substring(0, 24) + "…" : v.value;
      return `
      <div class="lotus-stats-hist-row">
        <span class="lotus-stats-hist-label" title="${v.value}">${val}</span>
        <div class="lotus-stats-hist-bar-bg">
          <div class="lotus-stats-hist-bar lotus-stats-hist-bar--string" style="width:${pct}%"></div>
        </div>
        <span class="lotus-stats-hist-count">${v.count}</span>
      </div>`;
    })
    .join("");

  return `
    <div class="lotus-stats-section-title">Top values</div>
    <div class="lotus-stats-histogram">${rows}</div>`;
}

function buildDistributionHTML(distribution) {
  if (!distribution || distribution.length === 0) return "";

  const maxCount = Math.max(...distribution.map((d) => d.count));
  const rows = distribution
    .slice(0, 10)
    .map((d) => {
      const pct = maxCount > 0 ? (d.count / maxCount) * 100 : 0;
      return `
      <div class="lotus-stats-hist-row">
        <span class="lotus-stats-hist-label">${d.bucket}</span>
        <div class="lotus-stats-hist-bar-bg">
          <div class="lotus-stats-hist-bar lotus-stats-hist-bar--temporal" style="width:${pct}%"></div>
        </div>
        <span class="lotus-stats-hist-count">${d.count}</span>
      </div>`;
    })
    .join("");

  return `
    <div class="lotus-stats-section-title">Distribution</div>
    <div class="lotus-stats-histogram">${rows}</div>`;
}

function statRow(label, value) {
  return `<div class="lotus-stats-row"><span class="lotus-stats-label">${label}</span><span class="lotus-stats-value">${value}</span></div>`;
}

function buildContent(stats) {
  const type = stats.type;
  const typeBadge = `<span class="lotus-stats-type-badge lotus-stats-type-badge--${type}">${type}</span>`;

  let html = `<div class="lotus-stats-popover">`;
  html += `<div class="lotus-stats-header">${typeBadge}</div>`;

  // Common stats
  html += statRow("Count", formatNumber(stats.count));
  html += statRow("Null", `${stats.null_count} (${formatPercentage(stats.null_percentage)})`);
  html += statRow("Distinct", formatNumber(stats.distinct_count));

  if (type === "numeric") {
    html += `<div class="lotus-stats-divider"></div>`;
    html += statRow("Min", formatNumber(stats.min));
    html += statRow("Max", formatNumber(stats.max));
    html += statRow("Avg", formatNumber(stats.avg));
    html += statRow("Median", formatNumber(stats.median));
    html += statRow("Sum", formatNumber(stats.sum));
    html += buildHistogramHTML(stats.histogram);
  } else if (type === "string") {
    html += `<div class="lotus-stats-divider"></div>`;
    html += statRow("Min length", formatNumber(stats.min_length));
    html += statRow("Max length", formatNumber(stats.max_length));
    html += buildTopValuesHTML(stats.top_values);
  } else if (type === "temporal") {
    html += `<div class="lotus-stats-divider"></div>`;
    html += statRow("Earliest", stats.earliest || "—");
    html += statRow("Latest", stats.latest || "—");
    html += buildDistributionHTML(stats.distribution);
  }

  html += `</div>`;
  return html;
}

const ColumnStats = {
  mounted() {
    const raw = this.el.getAttribute("data-stats");
    if (!raw) return;

    let stats;
    try {
      stats = JSON.parse(raw);
    } catch {
      return;
    }

    this.tippy = tippy(this.el, {
      content: buildContent(stats),
      theme: "lotus-stats",
      arrow: true,
      offset: [0, 8],
      placement: "bottom-start",
      trigger: "click",
      interactive: true,
      allowHTML: true,
      animation: "fade",
      maxWidth: 320,
      appendTo: () => document.body,
    });
  },

  updated() {
    const raw = this.el.getAttribute("data-stats");
    if (!raw || !this.tippy) return;

    try {
      const stats = JSON.parse(raw);
      this.tippy.setContent(buildContent(stats));
    } catch {
      // ignore parse errors
    }
  },

  destroyed() {
    if (this.tippy) this.tippy.destroy();
  },
};

// The stats of a column in a panel of Masu's results grid (its "Column
// stats" header item): the same content, in the panel the grid opens.
export const MasuColumnStats = {
  mounted() {
    this.render();
  },

  updated() {
    this.render();
  },

  render() {
    try {
      const stats = JSON.parse(this.el.getAttribute("data-stats") || "{}");
      this.el.innerHTML = Object.keys(stats).length ? buildContent(stats) : "";
    } catch {
      this.el.innerHTML = "";
    }
  },
};

export default ColumnStats;
