import { tinykeys } from "tinykeys";

export function initGlobalShortcuts() {
  const unsubscribe = tinykeys(window, {
    "$mod+Slash": (event) => {
      event.preventDefault();
      toggleShortcutsModal();
    },
    // ⌘K opens the command palette (Jumon's own shortcut).
    "$mod+j": (event) => {
      event.preventDefault();
      toggleAIAssistant();
    },
    "$mod+Shift+v": (event) => {
      event.preventDefault();
      toggleVisualization();
    },
    "$mod+1": (event) => {
      event.preventDefault();
      switchViewMode("table");
    },
    "$mod+2": (event) => {
      event.preventDefault();
      switchViewMode("chart");
    },
    // A page's pane that gives way to its results, as the query editor
    // does with its own keys: ⌘↑ minimizes it, ⌘↓ brings it back.
    "$mod+ArrowUp": (event) => pane(event, "minimize"),
    "$mod+ArrowDown": (event) => pane(event, "expand"),
  });

  return unsubscribe;
}

function toggleShortcutsModal() {
  const commandButton = document.querySelector(
    'button[title="Keyboard shortcuts"]',
  );
  if (commandButton) {
    commandButton.click();
  }
}

function toggleAIAssistant() {
  const aiButton = document.getElementById("ai-assistant-btn");
  if (aiButton) {
    aiButton.click();
  }
}

function toggleVisualization() {
  const vizButton = document.getElementById("visualization-btn");
  if (vizButton) {
    vizButton.click();
  }
}

function switchViewMode(mode) {
  const btn = document.getElementById(`view-mode-${mode}-btn`);
  if (btn) {
    btn.click();
  }
}

// Clicks the page's button marked `data-lotus-shortcut` for the shortcut,
// unless the person is typing: a field and the editor keep ⌘↑ and ⌘↓.
export function pane(event, action) {
  const target = event.target;
  if (target instanceof Element && target.closest("input, textarea, select, [contenteditable], .cm-editor")) return;

  const button = document.querySelector(`[data-lotus-shortcut="${action}"]`);
  if (button) {
    event.preventDefault();
    button.click();
  }
}
