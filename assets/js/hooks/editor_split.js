// The divider between the query editor and its results: drag it, or focus
// it and use the arrow keys, to give the editor more or less of the page.
// The editor's height is the viewer's, kept in this browser; double-click
// the divider to go back to the default. The results take the rest.
//
// The editor (#editor) is phx-update="ignore", so the height set here stays
// across LiveView updates. Off on narrow screens, where the page scrolls.
//
// Another page splits its own two panes with the divider's data: the pane
// it sizes (`data-target`, the id of the first of the two, whose style the
// page leaves to the hook, as with JS.ignore_attributes), where the height
// is kept (`data-key`) and the pane's default share (`data-share`).
import { load, store } from "../lib/settings";

const KEY = "editor_height";
// The default: this share of the space the editor and the results share.
const DEFAULT_SHARE = 0.35;
const TARGET = "editor";
const MIN_EDITOR = 96;
const MIN_RESULTS = 220;
const STEP = 24;
const WIDE = "(min-width: 640px)";

const EditorSplit = {
  mounted() {
    const { target, key, share } = this.el.dataset;
    this.editor = document.getElementById(target || TARGET);
    this.storeKey = key || KEY;
    this.share = Number.parseFloat(share) || DEFAULT_SHARE;
    this.area = this.el.parentElement;
    this.wide = window.matchMedia(WIDE);

    this.onPointerDown = (e) => this.startDrag(e);
    this.onKeyDown = (e) => this.key(e);
    this.onDoubleClick = () => this.reset();
    this.onResize = () => this.apply(this.height);
    this.onWide = () => this.apply(this.height);

    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("keydown", this.onKeyDown);
    this.el.addEventListener("dblclick", this.onDoubleClick);
    window.addEventListener("resize", this.onResize);
    this.wide.addEventListener("change", this.onWide);

    this.height = this.stored();
    this.apply(this.height);
  },

  updated() {
    this.apply(this.height);
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize);
    this.wide.removeEventListener("change", this.onWide);
    this.endDrag();
  },

  stored() {
    try {
      const height = load(this.storeKey);
      return Number.isFinite(height) ? height : null;
    } catch (_error) {
      return null;
    }
  },

  // The space the editor and the results share, without the editor's own
  // toolbar and the divider.
  space() {
    const chrome = this.editorBox().offsetHeight - this.editor.offsetHeight;
    return this.area.clientHeight - chrome - this.el.offsetHeight;
  },

  editorBox() {
    return this.area.firstElementChild;
  },

  clamp(height) {
    const max = Math.max(MIN_EDITOR, this.space() - MIN_RESULTS);
    return Math.round(Math.min(Math.max(height, MIN_EDITOR), max));
  },

  // `height` null is the default share.
  apply(height) {
    if (!this.editor) return;

    if (!this.wide.matches) {
      this.editor.style.height = "";
      this.editor.style.minHeight = "300px";
      this.editor.removeAttribute("data-split");
      return;
    }

    const px = this.clamp(height ?? this.space() * this.share);
    this.editor.style.minHeight = "0";
    this.editor.style.height = `${px}px`;
    this.editor.setAttribute("data-split", "");
    this.el.setAttribute("aria-valuenow", String(px));
  },

  set(height, { save = true } = {}) {
    this.height = this.clamp(height);
    this.apply(this.height);
    if (save) {
      try {
        store(this.storeKey, this.height);
      } catch (_error) {
        // A browser that keeps nothing still drags.
      }
    }
  },

  reset() {
    this.height = null;
    try {
      store(this.storeKey, null);
    } catch (_error) {
      // Nothing kept to forget.
    }
    this.apply(null);
  },

  startDrag(e) {
    if (!this.wide.matches || e.button !== 0) return;
    e.preventDefault();

    const startY = e.clientY;
    const startHeight = this.editor.offsetHeight;
    this.el.setPointerCapture(e.pointerId);
    this.el.dataset.dragging = "";
    document.body.style.userSelect = "none";

    this.onPointerMove = (move) => {
      this.set(startHeight + move.clientY - startY, { save: false });
    };
    this.onPointerUp = () => {
      this.set(this.editor.offsetHeight);
      this.endDrag();
    };

    this.el.addEventListener("pointermove", this.onPointerMove);
    this.el.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("pointercancel", this.onPointerUp);
  },

  endDrag() {
    if (this.onPointerMove) {
      this.el.removeEventListener("pointermove", this.onPointerMove);
      this.el.removeEventListener("pointerup", this.onPointerUp);
      this.el.removeEventListener("pointercancel", this.onPointerUp);
      this.onPointerMove = null;
    }
    delete this.el.dataset.dragging;
    document.body.style.userSelect = "";
  },

  key(e) {
    const height = this.editor.offsetHeight;
    if (e.key === "ArrowUp") this.set(height - STEP);
    else if (e.key === "ArrowDown") this.set(height + STEP);
    else if (e.key === "Home") this.set(MIN_EDITOR);
    else if (e.key === "End") this.set(Infinity);
    else if (e.key === "Enter") this.reset();
    else return;
    e.preventDefault();
  },
};

export default EditorSplit;
