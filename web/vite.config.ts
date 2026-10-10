import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// 手元で動かすときは、/api を Worker(wrangler dev)に回す
export default defineConfig({
  plugins: [react()],
  server: { proxy: { "/api": "http://localhost:8799" } },
  test: { environment: "node" },
});
