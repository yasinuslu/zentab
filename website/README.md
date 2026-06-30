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
## Deploy

Deployed to **GitHub Pages** at `https://yasinuslu.github.io/zentab/` by
[`../.github/workflows/website-pages.yml`](../.github/workflows/website-pages.yml) on every push
to `main` that touches `website/**` (or via the workflow's manual run button). One-time setup:
repo **Settings → Pages → Source: GitHub Actions**.

- The CI build runs with `BASE_PATH=/zentab/` so Vite emits asset URLs and a router `basename`
  under the project subpath. Local `bun dev`/`bun run build` default to `/`; reproduce the Pages
  build locally with `BASE_PATH=/zentab/ bun run build`.
- It's a SPA with client-side routing, so the Vite config writes a `404.html` (a copy of
  `index.html`) plus `.nojekyll` into `dist/`, letting `/overlay` and `/brand` resolve on a hard
  refresh.
