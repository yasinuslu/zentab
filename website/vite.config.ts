import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import { copyFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

// GitHub Pages serves a project site from a subpath (e.g. /zentab/). CI sets
// BASE_PATH=/zentab/ for the build; local `bun dev` stays at the root.
const base = process.env.BASE_PATH ?? "/";

// GitHub Pages has no catch-all rewrite, so a hard refresh of /overlay or
// /brand 404s. Serving a copy of index.html as 404.html lets the SPA boot and
// the client-side router resolve the path. .nojekyll keeps Pages from filtering
// the build through Jekyll.
function githubPagesSpa(): Plugin {
  let outDir = "dist";
  return {
    name: "github-pages-spa",
    apply: "build",
    configResolved(cfg) {
      outDir = cfg.build.outDir;
    },
    closeBundle() {
      copyFileSync(resolve(outDir, "index.html"), resolve(outDir, "404.html"));
      writeFileSync(resolve(outDir, ".nojekyll"), "");
    },
  };
}

// ZenTab marketing website — bun + vite + react + typescript.
export default defineConfig({
  base,
  plugins: [react(), githubPagesSpa()],
  server: { port: 4310 },
  preview: { port: 4311 },
});
