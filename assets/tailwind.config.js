const plugin = require("tailwindcss/plugin");

const color = (name) => `rgb(var(--lotus-${name}) / <alpha-value>)`;

const scale = (name) =>
  Object.fromEntries(
    [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].map((step) => [
      step,
      color(`${name}-${step}`),
    ]),
  );

module.exports = {
  content: ["./js/**/*.js", "../lib/**/*.*ex"],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        ...require("./tailwind.colors.json"),
        // Every colour that a theme changes reads a CSS custom property, so
        // the theme is picked at runtime (data-lotus-theme on <html>). The
        // values of each theme are in css/app.css.
        gray: scale("gray"),
        zinc: scale("zinc"),
        pink: scale("pink"),
        indigo: scale("indigo"),
        rose: scale("rose"),
        white: color("white"),
        black: color("black"),
        canvas: color("canvas"),
        'canvas-dark': color("canvas-dark"),
        'editor-light': color("editor-light"),
        'editor-dark': color("editor-dark"),
        'input-dark': color("input-dark"),
        'text-light': color("text-light"),
        'text-dark': color("text-dark"),
      },
      borderRadius: {
        sm: "var(--lotus-radius-sm)",
        DEFAULT: "var(--lotus-radius)",
        md: "var(--lotus-radius-md)",
        lg: "var(--lotus-radius-lg)",
        xl: "var(--lotus-radius-xl)",
      },
      boxShadow: {
        sm: "var(--lotus-shadow-sm)",
        DEFAULT: "var(--lotus-shadow)",
        md: "var(--lotus-shadow-md)",
        lg: "var(--lotus-shadow-lg)",
      },
      fontFamily: {
        sans: "var(--lotus-font-sans)",
        mono: [
          "Menlo",
          "Monaco",
          "Consolas",
          "Liberation Mono",
          "Courier New",
          "monospace",
        ],
      },
    },
  },
  variants: {
    display: ["group-hover"],
  },
  plugins: [require("@tailwindcss/forms"), require("@tailwindcss/typography")],
};
