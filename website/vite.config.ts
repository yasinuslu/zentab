import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// ZenTab marketing website — bun + vite + react + typescript.
export default defineConfig({
  plugins: [react()],
  server: { port: 4310 },
  preview: { port: 4311 },
});
