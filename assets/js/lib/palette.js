import { load } from "./settings";

// The theme of the dashboard ("lotus", "sumi") lives in data-lotus-theme on
// <html>. The server renders the host's choice (the :theme option of
// lotus_dashboard) and the themes on offer (:themes, in data-lotus-themes);
// a person's own choice, kept in this browser, wins while it is on offer.
export function availablePalettes() {
  return (document.documentElement.dataset.lotusThemes || "lotus sumi").split(" ");
}

export function applyPalette(palette = load("palette")) {
  if (availablePalettes().includes(palette)) {
    document.documentElement.dataset.lotusTheme = palette;
  }
}

// The colour of a theme token as a CSS colour, for code that cannot use the
// custom property itself (the topbar draws on a canvas).
export function tokenColor(name) {
  const channels = getComputedStyle(document.documentElement)
    .getPropertyValue(`--lotus-${name}`)
    .trim();

  return channels ? `rgb(${channels.split(/\s+/).join(",")})` : null;
}
