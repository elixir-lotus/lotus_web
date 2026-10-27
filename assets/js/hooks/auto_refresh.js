export default {
  mounted() {
    this.intervalId = null;
    this.startTimer();
  },

  updated() {
    this.startTimer();
  },

  startTimer() {
    this.stopTimer();
    const seconds = parseInt(this.el.dataset.seconds, 10);
    // The event to send (a live dashboard's `live_tick`), and whether to
    // skip a tick while the page is not on screen.
    const event = this.el.dataset.event || "auto_refresh_tick";
    const whenVisible = "whenVisible" in this.el.dataset;
    if (seconds && seconds > 0) {
      this.intervalId = setInterval(() => {
        if (whenVisible && document.hidden) return;
        // To the component the timer is in (its phx-target): the
        // dashboard, not the LiveView around it.
        if (this.el.hasAttribute("phx-target")) {
          this.pushEventTo(this.el, event, {});
        } else {
          this.pushEvent(event, {});
        }
      }, seconds * 1000);
    }
  },

  stopTimer() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  },

  destroyed() {
    this.stopTimer();
  }
};
