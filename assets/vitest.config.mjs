import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: { fude: fileURLToPath(new URL("./test/stubs/fude.js", import.meta.url)) },
  },
  test: {
    environment: "happy-dom",
    include: ["test/**/*.test.js"],
  },
});
