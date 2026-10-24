/**
 * AiPicker Hook
 *
 * Point at the page to give the AI assistant context: with the picker on,
 * what is under the pointer is outlined and named (a column or a row of the
 * results, a line or the selection in the editor, a table or a column of the
 * schema explorer), and a click adds it to the message as a chip. Shift and
 * click adds several. The chips go with the message as JSON, in the form's
 * `context` field, and are cleared when it is sent.
 *
 * On the form of the assistant's composer. Its toggle is [data-ai-pick-toggle],
 * its chips [data-ai-chips] (phx-update="ignore", so a patch keeps them).
 */

const MAX_CHIPS = 8;
const MAX_TEXT = 400;

const clip = (text, n = MAX_TEXT) => {
  const t = (text || "").replace(/\s+/g, " ").trim();
  return t.length > n ? t.slice(0, n - 1) + "…" : t;
};

// What a node of the page stands for, or null.
function describe(target, event) {
  const header = target.closest(".masu [role=columnheader]");
  if (header) {
    const grid = header.closest(".masu");
    const key = header.dataset.key || clip(header.textContent, 60);
    const index = header.getAttribute("aria-colindex");
    const values = [
      ...new Set(
        [...grid.querySelectorAll(`[role=gridcell][aria-colindex="${index}"]`)]
          .slice(0, 6)
          .map((cell) => clip(cell.textContent, 40)),
      ),
    ];
    return {
      el: header,
      kind: "column",
      label: key,
      detail: `the results column "${key}"${values.length ? `, with values like ${values.join(", ")}` : ""}`,
    };
  }

  const cell = target.closest(".masu [role=gridcell]");
  if (cell) {
    const grid = cell.closest(".masu");
    const row = cell.closest("[role=row]");
    const n = Number(row?.dataset.index ?? 0) + 1;
    const names = {};
    grid.querySelectorAll("[role=columnheader]").forEach((h) => {
      names[h.getAttribute("aria-colindex")] = h.dataset.key || clip(h.textContent, 40);
    });
    const column = names[cell.getAttribute("aria-colindex")] || "?";
    const value = clip(cell.textContent, 60);
    const fields = [...(row?.querySelectorAll("[role=gridcell]") || [])]
      .map((c) => `${names[c.getAttribute("aria-colindex")] || "?"} = ${clip(c.textContent, 60)}`)
      .join(", ");
    return {
      el: cell,
      kind: "row",
      label: `row ${n} · ${column} = ${value}`,
      detail: `row ${n} of the results (${fields}), its ${column}`,
    };
  }

  const pick = target.closest("[data-ai-pick]");
  if (pick) {
    const kind = pick.dataset.aiPick;
    const label = pick.dataset.aiPickLabel || clip(pick.textContent, 60);
    return { el: pick, kind, label, detail: `the ${kind} ${label} in the schema` };
  }

  const editorEl = target.closest("#editor");
  const view = editorEl?.lotusEditor?.view;
  if (view) {
    const sel = view.state.selection.main;
    if (!sel.empty) {
      const text = view.state.sliceDoc(sel.from, sel.to);
      return {
        el: view.contentDOM,
        kind: "sql",
        label: `selection · ${clip(text, 32)}`,
        detail: `this part of the query in the editor: ${clip(text)}`,
      };
    }
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
    if (pos != null) {
      const line = view.state.doc.lineAt(pos);
      if (line.text.trim()) {
        const lineEl = view.domAtPos(line.from).node;
        const el = (lineEl.nodeType === 1 ? lineEl : lineEl.parentElement)?.closest(".cm-line") || view.contentDOM;
        return {
          el,
          kind: "sql",
          label: `line ${line.number} · ${clip(line.text, 32)}`,
          detail: `line ${line.number} of the query in the editor: ${clip(line.text)}`,
        };
      }
    }
  }

  return null;
}

export default {
  mounted() {
    this.chips = [];
    this.toggle = this.el.querySelector("[data-ai-pick-toggle]");
    this.list = this.el.querySelector("[data-ai-chips]");
    this.input = this.el.querySelector("input[name=context]");

    this.outline = document.createElement("div");
    this.outline.className = "lotus-ai-pick-outline";
    this.outline.innerHTML = '<span class="lotus-ai-pick-label"></span>';
    this.outline.hidden = true;
    document.body.appendChild(this.outline);

    this.onMove = (e) => {
      if (this.el.contains(e.target)) return this.hide();
      const found = describe(e.target, e);
      found ? this.show(found) : this.hide();
    };

    this.onDown = (e) => {
      if (this.el.contains(e.target) || e.target.closest(".lotus-ai-panel")) return;
      const found = describe(e.target, e);
      if (!found) return;
      e.preventDefault();
      e.stopPropagation();
      this.add(found);
      if (!e.shiftKey) this.stop();
    };

    // The click that follows a picking mousedown would open a menu or sort.
    this.onClick = (e) => {
      if (this.swallowClick) {
        e.preventDefault();
        e.stopPropagation();
        this.swallowClick = false;
      }
    };

    this.onKey = (e) => {
      if (e.key === "Escape") this.stop();
    };

    this.toggle?.addEventListener("click", (e) => {
      e.preventDefault();
      this.picking ? this.stop() : this.start();
    });

    this.list.addEventListener("click", (e) => {
      const remove = e.target.closest("[data-remove]");
      if (remove) {
        this.chips.splice(Number(remove.dataset.remove), 1);
        this.render();
      }
    });

    this.el.addEventListener("submit", () => {
      setTimeout(() => {
        this.chips = [];
        this.render();
      }, 50);
    });

  },

  start() {
    this.picking = true;
    document.documentElement.classList.add("lotus-ai-picking");
    this.toggle?.setAttribute("aria-pressed", "true");
    document.addEventListener("mousemove", this.onMove, true);
    document.addEventListener("mousedown", this.onDown, true);
    document.addEventListener("click", this.onClick, true);
    document.addEventListener("keydown", this.onKey, true);
  },

  stop() {
    this.picking = false;
    document.documentElement.classList.remove("lotus-ai-picking");
    this.toggle?.setAttribute("aria-pressed", "false");
    document.removeEventListener("mousemove", this.onMove, true);
    document.removeEventListener("mousedown", this.onDown, true);
    document.removeEventListener("keydown", this.onKey, true);
    // Leave the click listener until the click of this mousedown has passed.
    setTimeout(() => document.removeEventListener("click", this.onClick, true), 0);
    this.hide();
  },

  show({ el, label }) {
    const r = el.getBoundingClientRect();
    Object.assign(this.outline.style, {
      top: `${r.top - 3}px`,
      left: `${r.left - 3}px`,
      width: `${r.width + 6}px`,
      height: `${r.height + 6}px`,
    });
    this.outline.firstChild.textContent = label;
    this.outline.hidden = false;
  },

  hide() {
    this.outline.hidden = true;
  },

  add({ kind, label, detail }) {
    this.swallowClick = true;
    if (this.chips.some((c) => c.label === label)) return;
    this.chips = [...this.chips, { kind, label, detail }].slice(-MAX_CHIPS);
    this.render();
    this.el.querySelector("textarea")?.focus();
  },

  render() {
    this.input.value = this.chips.length ? JSON.stringify(this.chips) : "";
    this.list.hidden = this.chips.length === 0;
    this.list.replaceChildren(
      ...this.chips.map((chip, i) => {
        const el = document.createElement("span");
        el.className = "lotus-ai-context-chip lotus-ai-in";
        el.dataset.kind = chip.kind;
        const text = document.createElement("span");
        text.className = "truncate";
        text.textContent = chip.label;
        const remove = document.createElement("button");
        remove.type = "button";
        remove.dataset.remove = i;
        remove.setAttribute("aria-label", this.list.dataset.removeLabel || "Remove");
        remove.textContent = "×";
        el.append(text, remove);
        return el;
      }),
    );
  },

  destroyed() {
    this.stop();
    this.outline.remove();
  },
};
