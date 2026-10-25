// A list's view (a gallery or a table), as the viewer last chose it: kept
// in this browser. The server renders it from the first frame (the
// socket's `views` param); should the two differ, the list asks for it.
import { load, store } from "../lib/settings";

export default {
  mounted() {
    const key = this.el.dataset.store;
    const chosen = load(key);
    if (chosen && chosen !== this.el.dataset.view) {
      this.pushEventTo(this.el, "set_view", { view: chosen, list: this.el.dataset.list });
    }
    this.el.addEventListener("click", (event) => {
      const choice = event.target.closest("[data-view-choice]");
      if (choice) store(key, choice.dataset.viewChoice);
    });
  },
};
