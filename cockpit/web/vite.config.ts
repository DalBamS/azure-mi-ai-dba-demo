import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

// The dev server proxies /api to the cockpit backend (default port 5177).
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
  server: {
    port: 5178,
    proxy: {
      "/api": {
        target: process.env.COCKPIT_API ?? "http://localhost:5177",
        changeOrigin: true,
      },
    },
  },
});
