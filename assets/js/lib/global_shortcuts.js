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
