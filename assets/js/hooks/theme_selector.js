import { load, store } from "../lib/settings";
import { applyPalette } from "../lib/palette";

export default {
  applyTheme() {
    const wantsDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    const theme = load("theme") || "system";

    if (theme === "dark" || (theme === "system" && wantsDark)) {
      document.documentElement.classList.add("dark");
    } else {
      document.documentElement.classList.remove("dark");
    }

    window.dispatchEvent(
      new CustomEvent("lotus:theme-changed", { detail: { theme } }),
    );

    this.updateTriggerIcon(theme);
    this.updateSelection(theme, document.documentElement.dataset.lotusTheme);
  },

  // Marks the chosen appearance and theme in the menu.
  updateSelection(theme, palette) {
    this.el.querySelectorAll("[data-theme-option]").forEach((option) => {
      option.setAttribute(
        "aria-pressed",
        String(option.getAttribute("data-theme-option") === theme),
      );
    });

    this.el.querySelectorAll("[data-palette-option]").forEach((option) => {
      option.setAttribute(
        "aria-pressed",
        String(option.getAttribute("data-palette-option") === palette),
      );
    });
  },

  updateTriggerIcon(theme) {
    const icons = this.el.querySelectorAll(".theme-icon");
    icons.forEach((icon) => {
      const iconTheme = icon.getAttribute("data-theme");
      if (iconTheme === theme) {
        icon.classList.remove("hidden");
      } else {
        icon.classList.add("hidden");
      }
    });
  },

  toggleDropdown() {
    const menu = this.el.querySelector("[data-dropdown-menu]");
    const isHidden = menu.classList.contains("hidden");

    if (isHidden) {
      menu.classList.remove("hidden");
      setTimeout(() => {
        document.addEventListener("click", this.handleOutsideClick, {
          once: true,
        });
      }, 0);
    } else {
      menu.classList.add("hidden");
    }
  },

  handleOutsideClick(event) {
    const menu = this.el.querySelector("[data-dropdown-menu]");
    if (!this.el.contains(event.target)) {
      menu.classList.add("hidden");
    }
  },

  mounted() {
    this.applyTheme();

    this.handleOutsideClick = this.handleOutsideClick.bind(this);

    const trigger = this.el.querySelector("[data-dropdown-trigger]");
    trigger.addEventListener("click", () => {
      this.toggleDropdown();
    });

    const options = this.el.querySelectorAll("[data-theme-option]");
    options.forEach((option) => {
      option.addEventListener("click", () => {
        const newTheme = option.getAttribute("data-theme-option");

        store("theme", newTheme);

        this.applyTheme();

        const menu = this.el.querySelector("[data-dropdown-menu]");
        menu.classList.add("hidden");
      });
    });

    this.el.querySelectorAll("[data-palette-option]").forEach((option) => {
      option.addEventListener("click", () => {
        const palette = option.getAttribute("data-palette-option");

        store("palette", palette);
        applyPalette(palette);
        this.applyTheme();

        this.el.querySelector("[data-dropdown-menu]").classList.add("hidden");
      });
    });
  },
};
