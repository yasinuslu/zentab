// Bundles src/extension.ts into a single GJS ESM module: dist/extension.js.
//
// Config verified against the current (2026, GNOME 50 era) real-world pattern used by
// @girs/gnome-shell's own "hello-world" example (gjsify/gnome-shell/examples/hello-world) —
// the same `external` globs, `format`, and `treeShaking` setting. Run with `node esbuild.js`
// (wrapped by `npm run build` / `bin/zentab-build`).
import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const metadata = JSON.parse(readFileSync(resolve(__dirname, "metadata.json"), "utf8"));

console.log(`Building ${metadata.name} (${metadata.uuid})...`);

await build({
  entryPoints: ["src/extension.ts"],
  outdir: "dist",
  bundle: true,
  // GObject.registerClass side effects and the enable()/disable() exports must survive
  // even though nothing in this file "calls" them from within the bundle itself.
  treeShaking: false,
  // GJS's mozjs engine tracks roughly Firefox's JS engine; firefox78 is a conservative
  // floor (GJS 1.65.90+) that's safely covered by every shell-version we target (48-50).
  // esbuild only uses this to decide which syntax to downlevel — it does not gate which
  // runtime APIs (Meta, Shell, St, ...) are available.
  target: "firefox78",
  platform: "neutral",
  format: "esm",
  sourcemap: true,
  logLevel: "info",
  // Keep `gi://...` and `resource:///...` specifiers exactly as written — GJS resolves them
  // itself at runtime; esbuild must never try to bundle or rewrite them.
  external: ["gi://*", "resource://*", "system", "gettext", "cairo"],
});

const schemasDir = resolve(__dirname, "schemas");
const distSchemasDir = resolve(__dirname, "dist/schemas");
mkdirSync(distSchemasDir, { recursive: true });
copyFileSync(resolve(__dirname, "metadata.json"), resolve(__dirname, "dist/metadata.json"));
// The submission artifact must be self-contained: a reviewer who only opens the uploaded zip
// (built from dist/) should find the license text right there, not have to go hunting the
// linked repo.
const rootLicense = resolve(__dirname, "..", "LICENSE");
if (existsSync(rootLicense)) {
  copyFileSync(rootLicense, resolve(__dirname, "dist/LICENSE"));
}
// Copy only the *.gschema.xml source(s), never a stale gschemas.compiled sitting in the
// source schemas/ dir (that one's a local verification artifact, gitignored) — dist/ always
// gets its own freshly-compiled copy below.
for (const name of readdirSync(schemasDir)) {
  if (name.endsWith(".gschema.xml")) {
    copyFileSync(resolve(schemasDir, name), resolve(distSchemasDir, name));
  }
}
if (existsSync(resolve(__dirname, "src/stylesheet.css"))) {
  copyFileSync(resolve(__dirname, "src/stylesheet.css"), resolve(__dirname, "dist/stylesheet.css"));
}

try {
  // The actual installable artifact needs its OWN compiled schema in dist/schemas/ — GNOME
  // Shell reads gschemas.compiled next to extension.js, not the source tree's copy.
  execFileSync("glib-compile-schemas", [distSchemasDir], { stdio: "inherit" });
} catch (error) {
  console.error(
    "warning: glib-compile-schemas not found or failed — dist/schemas/gschemas.compiled was " +
      "NOT produced. Run it manually (see bin/zentab-build) before installing.",
    error?.message ?? error,
  );
}

console.log("Build complete: dist/extension.js");
