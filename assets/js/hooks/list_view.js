// A list's view (a gallery or a table), as the viewer last chose it: kept
// in this browser, and asked of the server when the list mounts.
import { load, store } from "../lib/settings";

export default {
  mounted() {
    const key = this.el.dataset.store;
    const chosen = load(key);
    if (chosen && chosen !== this.el.dataset.view) {
      this.pushEventTo(this.el, "set_view", { view: chosen });
    }
    this.el.addEventListener("click", (event) => {
      const choice = event.target.closest("[data-view-choice]");
      if (choice) store(key, choice.dataset.viewChoice);
    });
  },
};
