/**
 * AutoScrollAI Hook
 *
 * Keeps the AI conversation at its newest message as messages and steps
 * arrive, unless the reader has scrolled up to read an earlier one.
 */
export default {
  mounted() {
    this.pinned = true;
    this.el.addEventListener("scroll", () => {
      const { scrollTop, scrollHeight, clientHeight } = this.el;
      this.pinned = scrollHeight - scrollTop - clientHeight < 48;
    });
    this.scrollToBottom("auto");
  },

  updated() {
    if (this.pinned) this.scrollToBottom("smooth");
  },

  scrollToBottom(behavior) {
    this.el.scrollTo({ top: this.el.scrollHeight, behavior });
  },
};
