import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // Point at another machine's backend with e.g.
      // API_TARGET=http://Wissems-MacBook-Air.local:8001 npm run dev
      "/api": {
        target: process.env.API_TARGET || "http://localhost:8001",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
    },
  },
});
