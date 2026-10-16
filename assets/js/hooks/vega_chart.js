import vegaEmbed from "vega-embed";

// Sumi: blade orange first, then ink (paper on dark) and quiet hues, in
// Outfit, with hairline axes.
function sumiEmbedOptions(isDark) {
  const ink = isDark ? "#f5f0e8" : "#0a0a0b";
  const muted = isDark ? "#a8a49e" : "#5c5a58";
  const line = isDark ? "#2a2a2e" : "#e0dad1";
  const font = "Outfit, system-ui, sans-serif";

  return {
    actions: false,
    renderer: "svg",
    config: {
      background: "transparent",
      font,
      range: {
        category: [
          "#e84a1c",
          isDark ? "#e0dad1" : "#2a2a2e",
          "#7f7c78",
          "#3f78a8",
          "#4f8a63",
          "#c08a2b",
          "#ff8f6a",
          "#7a5c99",
        ],
      },
      mark: { color: "#e84a1c" },
      arc: { stroke: isDark ? "#141416" : "#f5f0e8" },
      axis: {
        labelColor: muted,
        titleColor: ink,
        gridColor: line,
        domainColor: line,
        tickColor: line,
        labelFont: font,
        titleFont: font,
      },
      legend: { labelColor: muted, titleColor: ink },
      title: { color: ink },
      view: { stroke: "transparent" },
    },
  };
}

export default {
  mounted() {
    this.renderChart();

    this.handleEvent("update-chart", ({ spec }) => {
      this.renderChart(spec);
    });

    this.themeObserver = new MutationObserver(() => {
      this.renderChart();
    });
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "data-lotus-theme"],
    });

    this.resizeObserver = new ResizeObserver(() => {
      if (this.resizeTimeout) clearTimeout(this.resizeTimeout);
      this.resizeTimeout = setTimeout(() => this.renderChart(), 100);
    });
    this.resizeObserver.observe(this.el);
  },

  updated() {
    // phx-update="ignore" prevents updates, but if we need to handle them:
    // this.renderChart();
  },

  renderChart(spec) {
    const specData = spec || this.getSpecFromDOM();
    if (!specData || Object.keys(specData).length === 0) {
      this.el.innerHTML =
        '<div class="flex items-center justify-center h-full text-gray-400">No visualization configured</div>';
      return;
    }

    const containerHeight = this.el.clientHeight || 400;

    const fullSpec = {
      ...specData,
      width: "container",
      height: Math.max(containerHeight - 40, 300),
      autosize: { type: "fit", contains: "padding", resize: true },
    };

    const isDark = document.documentElement.classList.contains("dark");
    const isSumi = document.documentElement.dataset.lotusTheme === "sumi";

    const embedOptions = isSumi ? sumiEmbedOptions(isDark) : {
      actions: false,
      renderer: "svg",
      theme: isDark ? "dark" : undefined,
      config: isDark
        ? {
            background: "transparent",
            axis: {
              labelColor: "#9ca3af",
              titleColor: "#d1d5db",
              gridColor: "#374151",
              domainColor: "#4b5563",
            },
            legend: {
              labelColor: "#9ca3af",
              titleColor: "#d1d5db",
            },
            title: {
              color: "#d1d5db",
            },
            view: {
              stroke: "transparent",
            },
          }
        : {
            background: "transparent",
            view: {
              stroke: "transparent",
            },
          },
    };

    vegaEmbed(this.el, fullSpec, embedOptions)
      .then((result) => {
        this.vegaView = result.view;
        // Dispatch resize to ensure Vega picks up container dimensions
        window.dispatchEvent(new Event("resize"));
      })
      .catch((err) => {
        console.error("Vega-Lite rendering error:", err);
        this.el.innerHTML = `<div class="flex items-center justify-center h-full text-red-500">
          <div class="text-center">
            <p class="font-medium">Chart Error</p>
            <p class="text-sm mt-1">${err.message}</p>
          </div>
        </div>`;

        const component = this.el.closest("[data-phx-component]");
        if (component) {
          this.pushEventTo(component, "chart_render_error", {
            error: err.message,
          });
        }
      });
  },

  getSpecFromDOM() {
    const specAttr = this.el.dataset.spec;
    if (!specAttr) return null;
    try {
      return JSON.parse(specAttr);
    } catch (e) {
      console.error("Failed to parse Vega spec:", e);
      return null;
    }
  },

  destroyed() {
    if (this.vegaView) {
      this.vegaView.finalize();
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
    if (this.themeObserver) {
      this.themeObserver.disconnect();
    }
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout);
    }
  },
};
