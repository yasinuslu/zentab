# Human-only verification: GNOME extension hardening pass

This pass (nine adversarial review personas → triage → fix) was done under a hard
machine-safety constraint: **no `gnome-shell` process could be launched, reloaded, or have its
input/display grabbed**, because the machine was in active use (gaming) the whole time. Every
fix below was verified **by theory** — reading the current GNOME 48-50 source
(`gitlab.gnome.org/GNOME/gnome-shell` `main` branch, fetched live), the real `@girs` type
declarations in `node_modules/@girs/*`, and cross-checking claims against both — never by
actually running the shell. That's a real gap. This file is where the human-only steps to close
it live, per the project's own convention (`feedback_autonomous_groundwork`).

## How to test (when NOT gaming)

```bash
dbus-run-session -- gnome-shell --wayland
```

On GNOME 46+/50 there is **no `--nested` flag** — running as a Wayland compositor from inside
an existing session is nested by default (`--display-server` is what turns it into a full
session-replacing server, which you do *not* want). This opens a second, fully separate Wayland
compositor in a window — never touches your real session. Inside it: `bin/zentab-install` to symlink `dist/`, then
`gnome-extensions enable zentab@zentab.app`. After any source change: `bin/zentab-build`, then
close and relaunch the nested shell (an ESM bundle rewrite isn't picked up by a plain extension
reload). See the README's "Dev loop" section for the full rationale.

## Priority 1 — the architecture change this pass made, unverified

**`Switcher` now owns one persistent grab actor for its whole lifetime, and `OverlayView`'s
scrim/card/tiles are parented as its descendants (`OverlayView.attachTo()`), instead of the
scrim being a sibling actor added via `Main.layoutManager.addChrome` directly.** This was a
genuine architecture fix, not a tweak — the original shape had `Main.pushModal()` grabbing an
invisible actor that was a *sibling* of the visible overlay (both children of `uiGroup`,
neither a descendant of the other). Per `switcherPopup.js`'s real source and
`global.stage.grab()`'s documented behavior (input is restricted to the grabbed actor's own
subtree), that shape would have meant hover-select, tile-click-commit, and click-outside-cancel
never fire once a session reveals — only keyboard would work. The fix reparents the overlay
under the grab actor so it matches `switcherPopup.js`'s own "one actor, both roles" shape.

**This is the single highest-priority thing to test.** In the nested shell:

- [ ] Hold past `hold_threshold_ms` to reveal the overlay, then **hover a different tile with
      the mouse** — does the highlighted tile follow the cursor?
- [ ] With the overlay revealed, **click a tile directly** — does it commit immediately (window
      activates, overlay closes) regardless of which tile was keyboard-highlighted?
- [ ] With the overlay revealed, **click on the dim scrim outside the card** — does the session
      cancel with no window change (not commit, not no-op)?
- [ ] Hover a tile, then hit **W** — does it close that window and keep the overlay open with a
      refreshed list? Same for **Q** (quit the app).
- [ ] Multi-monitor: summon on the monitor **under the cursor**, not the primary one, and
      confirm hover/click still work there.
- [ ] Tap-and-release *faster* than the hold threshold — confirm truly **no overlay ever
      flashes** (the invisible grab actor existing shouldn't paint anything).

If any of the pointer-driven items above don't work, the grab-actor/overlay reparenting is the
first place to look — re-read `switcher.ts`'s file header and `overlay.ts`'s `attachTo()`.

## Priority 2 — the tap/hold modifier-mask fix, unverified

`keybinding.ts` now threads the real `Meta.KeyBinding.get_mask()` through to
`Switcher.start()`, instead of `switcher.ts` re-deriving the modifier mask from config.toml's
chord string. This was a real bug: a stock GNOME install binds **two** accelerators to
`switch-applications` out of the box (`<Super>Tab` *and* `<Alt>Tab`), so re-deriving the mask
from config.toml's `"alt+tab"` string alone would have made the anti-stuck-grab guard
force-commit instantly on `<Super>Tab` (Super never being in the derived mask), silently
breaking hold-to-reveal for anyone using the Super+Tab gesture — a mainstream default, not an
edge case.

- [ ] On a completely stock config (delete/rename `~/.config/zentab/config.toml` for the test),
      **hold Super+Tab** past the threshold — does the overlay reveal and let you cycle, same as
      holding Alt+Tab does?
- [ ] Same test for **Super+`Above_Tab`** (GNOME's second default for `switch-group`, mapped to
      current-app windows here) if your keyboard layout has that key.
- [ ] Confirm **release-to-commit** still fires correctly on whichever modifier you actually
      held (Super vs Alt) — releasing the wrong one shouldn't commit early or hang the grab open.

## Priority 3 — lifecycle / stuck-grab fixes, unverified

- [ ] **`disable()` mid-session**: open a switcher session (hold past threshold so the overlay
      is revealed), then disable the extension from another terminal
      (`gnome-extensions disable zentab@zentab.app`) *while still holding the modifier*. Confirm
      the modal grab releases cleanly and normal Alt+Tab / mouse / keyboard input all resume —
      this exercises `Switcher.destroy()`'s new persistent-grab-actor teardown path.
- [ ] **Lock screen while a session might be open**: this is inherently hard to time by hand
      (GNOME's `session-modes: ["user"]` should disable the extension before the lock-screen
      transition completes, which is the whole safety net) — the goal is just to confirm nothing
      weird happens (frozen input, orphaned overlay) if you lock the screen right after an
      Alt+Tab.
- [ ] **Re-enable after disable** (`gnome-extensions disable` then `enable` again, or toggle in
      the Extensions app) several times in a row — confirm each cycle behaves identically (no
      accumulating lag, no duplicate overlays, no leaked keybinding claims). This exercises the
      persistent-grab-actor and `KeyController` now living for `Switcher`'s whole lifetime
      instead of being recreated per session — confirm that reuse doesn't leak state across
      disable/enable cycles.
- [ ] **Close the selected window from outside ZenTab while a session is open** (e.g. hold the
      chord to reveal the overlay, then from a terminal `wmctrl -c` or otherwise kill the
      currently-highlighted window while still holding the modifier) — confirm release-to-commit
      either activates gracefully or no-ops without hanging; this exercises the new
      try/catch around `Switcher._end()`'s `activate()` call. A caught exception is expected to
      log to `journalctl`, not crash or freeze anything.

## Priority 4 — config validation, unverified

`config.ts` now rejects (falls back to defaults, logging via `logError`) any chord with an
unrecognized modifier token or an unresolvable base key, instead of silently producing a
partial or dangerous accelerator (the worst case being a bare, modifier-less accelerator like
`"Tab"` for a chord like `"win+tab"`, which would have grabbed every Tab keypress system-wide).

- [ ] Set `other_apps = "win+tab"` (an unrecognized modifier) in `config.toml`, save, and
      confirm: (a) `other_apps` falls back to the default `alt+tab` gesture rather than doing
      nothing or grabbing bare Tab, and (b) `journalctl /usr/bin/gnome-shell -f` (or
      `journalctl -f` while filtering for `[zentab]`) shows a `resolveConfig` warning naming the
      bad field.
- [ ] Set `current_app = "alt+f1"` and confirm it resolves to `<Alt>F1` and actually works (the
      new function-key regex path), and that `alt+pageup` resolves to `<Alt>Page_Up` (the newly
      expanded `BASE_KEY_TOKENS`).
- [ ] Confirm the live-reload path (`Gio.FileMonitor`) picks up a `config.toml` edit without
      restarting the shell — edit a chord, save, and try the new gesture within a few seconds.

## Deliberately deferred (not fixed this pass) — read before acting on them

These were real findings but judged not worth the risk/scope tradeoff for this hardening pass.
If any of these bite in practice, revisit:

- **Private-binding Shift-reversed direction** (`keybinding.ts`'s `addKeybinding` path): a mode
  remapped to a chord with no GNOME built-in equivalent (e.g. `other_apps = "super+tab"` on a
  system where Super+Tab isn't already a default) only fires forward on Shift+chord — Mutter
  grabs accelerators by exact modifier match, so Shift+chord is a genuinely different
  accelerator that would need its own `gschema` key + `addKeybinding` call with
  `Meta.KeyBindingFlags.IS_REVERSED` to register. Deferred because it requires a `gschema`
  surface change (new keys) for a narrow edge case (only affects remapped-to-non-built-in
  chords). If you hit this, it's `keybinding.ts` + `schemas/*.gschema.xml` + `config.ts`'s
  write-through that need the new key.
- **Monitor unplugged mid-session**: if a monitor is disconnected/resized while a switcher
  session is open and revealed, the overlay stays pinned to stale geometry (possibly off the
  remaining screen) until Escape or another commit path ends it — click-outside-to-cancel would
  be unreachable in that state, but Escape still works, so this isn't a stuck-grab risk, just a
  rare-edge-case rough spot. Not fixed (would need `Switcher` to listen for
  `monitors-changed` during an open session).
- **A closed window's tile staying selectable mid-session** (not via W/Q, but externally — the
  app quitting on its own, crashing, etc.): the guarded-`activate()` fix (Priority 3 above)
  means this can no longer hang the grab, but the stale tile can still show briefly until the
  next W/Q-triggered refresh or the session ends. Not fixed as a live-refresh feature (would
  need `Switcher` to subscribe to `WindowSnapshotService`'s per-window `unmanaging` signal for
  the duration of an open session).
- **`setCustomKeybindingHandler`-style override-success detection for the OVERRIDES table**:
  this pass DID fix the override loop to call `Meta.keybindings_set_custom_handler` directly and
  check its real boolean result (previously silently swallowed by `Main.wm`'s own wrapper) — but
  `disable()`'s restore path still goes through `Main.wm.setCustomKeybindingHandler` without a
  similar success check. Left as-is: restoring a handler we know exists (we just successfully
  overrode it in `enable()`) is much lower risk than the original "did the override even take"
  question this pass did fix.
- **ESLint type-checked rules** (`recommendedTypeChecked` / `parserOptions.project`) — flagged
  as a coverage gap (would catch floating promises, unsafe `any` flow through GObject signal
  payloads) but not enabled this pass: doing so risks surfacing a batch of new findings that
  would need their own triage pass, out of scope for a hardening pass focused on the nine
  personas' actual findings.
- **Digit 1-9 jump-to-tile**: chips render, no key is wired. VISION.md is silent on whether this
  should exist at all — a product decision, not a bug, left for Yasin to call.

## Still explicitly deferred from the original build (unchanged by this pass)

- **Blur-behind on the scrim** (`TODO(blur)` in `theme.ts`/`overlay.ts`) — flat dim scrim only,
  no GPU blur-behind, until St/Clutter exposes a cheap blur path.
- **Live window thumbnails** (`TODO(thumbnail)` in `overlay.ts`) — icon + title identification
  only, no `Clutter.Clone` window preview.
- **No packaged release / EGO submission** — build-it-yourself only; no `gnome-vN*` CI workflow.

## Environment note

`glib-compile-schemas` isn't on this NixOS machine's default `PATH` (nixpkgs splits it into the
`glib.dev` output, not `glib`/`glib.bin`). Run the build under a nix shell that provides both
Node and it, e.g. `nix shell nixpkgs#nodejs_24 nixpkgs#glib.dev -c bin/zentab-build`. Real GNOME
desktops ship `glib-compile-schemas` as part of `glib` itself — this is only a dev-shell quirk,
not a shipped-product issue. (A `flake.nix` dev shell would be the tidy fix, but locking it here
needs a healthy `channels.nixos.org` fetch — deferred, do it when not on a flaky connection.)
