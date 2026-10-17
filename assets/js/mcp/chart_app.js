// The Lotus chart app (an MCP App): the host renders this document in a
// sandboxed frame next to a show_chart call, hands it the tool's result,
// and the app draws result.structuredContent.spec, a Vega-Lite spec built
// on the server by Lotus.Web.VegaSpecBuilder.
//
// It talks to the host with JSON-RPC over postMessage (the
// io.modelcontextprotocol/ui extension, 2026-01-26): ui/initialize, then
// the tool's result as a notification. It follows the host's light or dark
// theme and reports its height so the host can size the frame.
import vegaEmbed from "vega-embed";

const PROTOCOL_VERSION = "2026-01-26";

const root = document.getElementById("chart");
const title = document.getElementById("title");
const note = document.getElementById("note");

let nextId = 1;
let theme = "light";
let lastResult = null;
const pending = new Map();

const send = (message) => window.parent.postMessage({ jsonrpc: "2.0", ...message }, "*");

const request = (method, params) =>
  new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    send({ id, method, params });
  });

function reportSize() {
  const height = Math.ceil(document.documentElement.getBoundingClientRect().height);
  send({ method: "ui/notifications/size-changed", params: { height } });
}

function embedOptions() {
  const dark = theme === "dark";

  return {
    actions: false,
    renderer: "svg",
    theme: dark ? "dark" : undefined,
    config: {
      background: "transparent",
      view: { stroke: "transparent" },
      ...(dark
        ? {
            axis: {
              labelColor: "#9ca3af",
              titleColor: "#d1d5db",
              gridColor: "#374151",
              domainColor: "#4b5563",
            },
            legend: { labelColor: "#9ca3af", titleColor: "#d1d5db" },
            title: { color: "#d1d5db" },
          }
        : {}),
    },
  };
}

function showMessage(text) {
  root.textContent = "";
  note.textContent = text;
  reportSize();
}

function render(result) {
  lastResult = result;
  document.documentElement.dataset.theme = theme;

  if (!result || !result.spec) {
    showMessage("Nothing to chart.");
    return;
  }

  title.textContent = result.title || "";
  note.textContent = result.has_more
    ? `Showing the first ${result.num_rows} rows.`
    : "";

  const spec = {
    ...result.spec,
    width: "container",
    height: 320,
    autosize: { type: "fit", contains: "padding", resize: true },
  };

  vegaEmbed(root, spec, embedOptions())
    .then(() => reportSize())
    .catch((error) => showMessage(`The chart could not be drawn: ${error.message}`));
}

function applyHostContext(context) {
  if (context && (context.theme === "dark" || context.theme === "light")) {
    theme = context.theme;
    if (lastResult) render(lastResult);
  }
}

window.addEventListener("message", (event) => {
  const message = event.data;
  if (!message || message.jsonrpc !== "2.0") return;

  if (message.method === undefined) {
    const waiting = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) waiting?.reject(new Error(message.error.message));
    else waiting?.resolve(message.result);
    return;
  }

  switch (message.method) {
    case "ui/notifications/tool-result":
      if (message.params?.isError) {
        const text = (message.params.content || []).map((c) => c.text).join(" ");
        showMessage(text || "The chart could not be made.");
      } else {
        render(message.params?.structuredContent);
      }
      break;

    case "ui/notifications/host-context-changed":
      applyHostContext(message.params);
      break;

    case "ui/resource-teardown":
      send({ id: message.id, result: {} });
      break;
  }
});

new ResizeObserver(() => reportSize()).observe(document.body);

request("ui/initialize", {
  protocolVersion: PROTOCOL_VERSION,
  appInfo: { name: "Lotus chart", version: "1.0.0" },
  appCapabilities: { availableDisplayModes: ["inline"] },
})
  .then((result) => {
    applyHostContext(result?.hostContext);
    send({ method: "ui/notifications/initialized", params: {} });
  })
  .catch(() => showMessage("This host could not start the chart."));
