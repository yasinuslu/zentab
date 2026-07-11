// Ambient type wiring for `@girs` — importing these (for side effects only) makes
// TypeScript recognize the *real* GJS runtime import specifiers we write everywhere else in
// this source tree: `gi://Foo` and `resource:///org/gnome/shell/...`. Nothing here emits any
// JS: esbuild only ever sees the `.ts` sources, and this file is `.d.ts` (declarations only).
//
// This is the same wiring real, current (shell-version 50) TypeScript extensions use, e.g.
// christopher-l/space-bar. Keep this file free of anything except these side-effect imports.
import "@girs/gjs";
import "@girs/gjs/dom";
import "@girs/gnome-shell/ambient";
import "@girs/gnome-shell/extensions/global";
