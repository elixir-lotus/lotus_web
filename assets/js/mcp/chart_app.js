// The Lotus chart app (an MCP App): the host renders this document in a
// sandboxed frame next to a show_chart call, hands it the tool's result,
// and the app draws result.structuredContent.html, the chart as the server
// made it with Lotus.Web.Charts and Fude, which mountFude brings to life.
//
// It talks to the host with JSON-RPC over postMessage (the
// io.modelcontextprotocol/ui extension, 2026-01-26): ui/initialize, then
// the tool's result as a notification. It follows the host's light or dark
// theme (data-theme, which Fude's dark colors follow) and reports its
// height so the host can size the frame.
import { mountFude } from "fude";

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

function showMessage(text) {
  root.textContent = "";
  note.textContent = text;
  reportSize();
}

function render(result) {
  lastResult = result;
  document.documentElement.dataset.theme = theme;

  if (!result || !result.html) {
    showMessage("Nothing to chart.");
    return;
  }

  title.textContent = result.title || "";
  note.textContent = result.has_more
    ? `Showing the first ${result.num_rows} rows.`
    : "";

  // The server's HTML of the chart, escaped by HEEx; drawn once, then
  // again in the host's theme, which only the colors follow.
  if (root.dataset.drawn !== "true") {
    root.innerHTML = result.html;
    root.dataset.drawn = "true";
    mountFude(root);
  }

  reportSize();
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
