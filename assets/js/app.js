import topbar from "topbar";
import { applyPalette, tokenColor } from "./lib/palette";
import { Jumon } from "jumon";
import { Koyomi } from "koyomi";
import { Kotoba } from "kotoba";
import { Masu } from "masu";
import { Fude, registerMap } from "fude";

// Fude's maps, served by Lotus.Web.Assets: fetched when a map chart first draws.
for (const name of ["world", "us-states"]) {
  const url = document.querySelector(`meta[name="lotus-map-${name}"]`)?.content;
  if (url) registerMap(name, url);
}

import AIMessageInput from "./hooks/ai_message_input";
import AIPromptInput from "./hooks/ai_prompt_input";
import AutoRefresh from "./hooks/auto_refresh";
import AutoScrollAI from "./hooks/auto_scroll_ai";
import Clipboard from "./hooks/clipboard";
import ColumnStats from "./hooks/column_stats";
import DispatchChangeOnUpdate from "./hooks/dispatch_change_on_update";
import EditorContextMenu from "./hooks/editor_context_menu";
import EditorForm from "./hooks/editor_form";
import Flash from "./hooks/flash";
import MultiSelectSearch from "./hooks/multi_select_search";
import PlatformScout from "./hooks/platform_scout";
import ResultsVisibility from "./hooks/results_visibility";
import TagInput from "./hooks/tag_input";
import TagRemove from "./hooks/tag_remove";
import ThemeSelector from "./hooks/theme_selector";
import Tippy from "./hooks/tippy";
import Toast from "./hooks/toast";
import { load } from "./lib/settings";
import { initGlobalShortcuts } from "./lib/global_shortcuts";

function initializeTheme() {
  const wantsDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const theme = load("theme") || "system";

  if (
    theme === "dark" ||
    (theme === "system" && wantsDark)
  ) {
    document.documentElement.classList.add("dark");
  } else {
    document.documentElement.classList.remove("dark");
  }
}

applyPalette();
initializeTheme();
initGlobalShortcuts();

let topBarScheduled = undefined;

window.addEventListener("phx:page-loading-start", (info) => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 500);
  }
});

window.addEventListener("phx:page-loading-stop", (info) => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

window.addEventListener("phx:open-blank", (event) => {
  window.open(event.detail.location, '_blank');
});

window.addEventListener("phx:scroll-to-element", (event) => {
  const el = document.getElementById(event.detail.id);
  if (el) {
    el.scrollIntoView({ behavior: "smooth", block: "start" });
  }
});

window.addEventListener("phx:update-query-params", (event) => {
  const url = new URL(window.location);
  url.search = "";
  for (const [key, value] of Object.entries(event.detail.params || {})) {
    if (value !== "" && value != null) {
      url.searchParams.set(key, value);
    }
  }
  history.replaceState(history.state, "", url.toString());
});

function configureTopbar() {
  topbar.config({
    barColors: { 0: tokenColor("logo-petal") || "#FF8086" },
    shadowColor: "rgba(0, 0, 0, .3)",
  });
}

configureTopbar();
window.addEventListener("lotus:theme-changed", configureTopbar);

// The command palette's actions that drive the page click its own buttons
// (Lotus.Web.Commands): the action does what the button does, and nothing
// when the page has no such button.
window.addEventListener("lotus:click", (event) => {
  const selector = event.detail && event.detail.to;
  if (selector) document.querySelector(selector)?.click();
});

const hooks = {
  AIMessageInput,
  AIPromptInput,
  AutoRefresh,
  AutoScrollAI,
  Clipboard,
  DispatchChangeOnUpdate,
  EditorContextMenu,
  EditorForm,
  Flash,
  MultiSelectSearch,
  PlatformScout,
  ResultsVisibility,
  TagInput,
  TagRemove,
  ThemeSelector,
  Jumon,
  Koyomi,
  Kotoba,
  Masu,
  Fude,
  ColumnStats,
  Tippy,
  Toast,
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveTran = document
  .querySelector("meta[name='live-transport']")
  .getAttribute("content");
const livePath = document
  .querySelector("meta[name='live-path']")
  .getAttribute("content");

const liveSocket = new LiveView.LiveSocket(livePath, Phoenix.Socket, {
  transport: liveTran === "longpoll" ? Phoenix.LongPoll : WebSocket,
  params: { _csrf_token: csrfToken },
  hooks: hooks,
});

liveSocket.connect();
