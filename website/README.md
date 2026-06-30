# ZenTab website

Marketing site + a live, playable overlay demo. **Bun + Vite + React + TypeScript.**

The visual source of truth lives in [`design/`](design/) — the original Claude Design
(`claude.ai/design`) `.dc.html` files. Those are reference only; the shipped site is the
React port under [`src/`](src/). Keep the two in sync per the brand tokens in
[`../BRANDING.md`](../BRANDING.md).

## Routes

- `/` — marketing landing (`src/pages/Landing.tsx`)
- `/overlay` — the playable overlay demo, driven by the keyboard (`src/pages/Overlay.tsx`)
- `/brand` — the brand system page (`src/pages/Brand.tsx`)

## Develop

```sh
bun install
bun dev          # vite dev server on http://localhost:4310
bun run build    # tsc -b && vite build  → dist/
bun run preview  # serve the production build on :4311
bun run typecheck
```

## Layout

```
design/        original Claude Design .dc.html sources (reference)
src/
  main.tsx     entry + router
  App.tsx      routes
  theme.css    brand tokens, keyframes, hover utilities
  shared/
    Thumb.tsx  faux-app window thumbnails + shared types
  pages/       Landing / Overlay / Brand
```

## Notes

- The design files use Claude Design's `<x-dc>` runtime (`design/support.js`). The React port
  replaces that runtime; the `DCLogic` classes became typed `React.Component`s nearly verbatim.
- The overlay's ⌘Tab / ⌥Tab gestures are remapped to safe stand-ins (hold **Space**, hold **V**)
  so the browser demo never fights the real OS shortcuts.
- Hosting: this is a SPA with client-side routing. On a static host, add a catch-all rewrite to
  `index.html` so `/overlay` and `/brand` resolve on hard refresh.
