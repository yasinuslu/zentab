// The interaction state machine: tap-vs-hold, the modal grab, Tab/Shift+Tab/hover selection,
// and release-to-commit. This is VISION's "feel crux" — the shape below is a faithful port of
// GNOME Shell's own `switcherPopup.js` (verified against the current gnome-shell `main` branch
// source, fetched live from gitlab.gnome.org while writing this — not guessed from older
// Clutter conventions):
//
//   - The grab actor: `switcherPopup.js` grabs the popup itself — a single actor that is BOTH
//     the modal-grab target AND the visible, interactive UI (its icon list is a child of the
//     grabbed actor, so pointer picking for hover/click stays inside the grabbed subtree).
//     `global.stage.grab(actor)` (what `Main.pushModal` calls under the hood) restricts input
//     delivery to the grabbed actor's own subtree — an actor OUTSIDE that subtree simply never
//     receives pointer events while the grab holds, no matter how it's positioned on screen.
//     ZenTab's own overlay (built lazily by `OverlayView`, since VISION's tap path must show NO
//     overlay at all) can't itself be the grab target from session start — so `Switcher` owns
//     one persistent, invisible `_grabActor` (sized to the whole stage, alive for this
//     `Switcher`'s entire lifetime, not recreated per session) and hands it to `OverlayView` via
//     `attachTo()` as the parent every future `scrim` gets built under. That keeps the tap path
//     working (grab an actor with nothing visible in it yet) while guaranteeing that once the
//     overlay *does* reveal, its scrim/card/tiles are genuine descendants of the grabbed actor —
//     matching `switcherPopup.js`'s own "one actor, both roles" shape instead of the disjoint
//     sibling-actors bug that shape is here to avoid.
//   - The grab: `Main.pushModal(actor)` with no extra params (so `actionMode` defaults to
//     NONE, which is what blocks every *other* global keybinding while a session is open,
//     matching `SwitcherPopup.show()`'s own `Main.pushModal(this)` call). `popModal(grab)`
//     takes the `Clutter.Grab` object `pushModal` returned — the pre-45 `(actor, timestamp)`
//     form is gone from the current API surface (`main.d.ts` only declares the grab-object
//     overload), so there is no fallback path to keep here.
//   - Key input: NOT `key-press-event`/`key-release-event` (that Clutter 1.x actor-signal
//     API is what the older switcherPopup used and is what this file's first draft assumed —
//     current `switcherPopup.js` has moved off it entirely). The current mechanism is a
//     `Clutter.KeyController` action added to the grabbed actor via `add_action()`, whose
//     `key-press` signal hands back nothing but a `this`-bound controller — key/modifier
//     state is read back out via `controller.get_key()` / `controller.get_state()`, called
//     only from inside the signal handler (per the girs doc comment on those methods). Like
//     `_grabActor` itself, the `KeyController` and its two signal connections are created once
//     and live for the whole `Switcher` lifetime — every handler already guards on
//     `this._session` being non-null, so there's nothing session-scoped left to leak by keeping
//     them wired between sessions.
//   - Release-to-commit: NOT a key-release event on Tab/the modifier key. Current
//     `switcherPopup.js` connects the *same* `Clutter.KeyController`'s `modifier-change`
//     signal and finishes when `(pressed|latched|locked) & modifierMask === 0` — i.e. it
//     watches the *aggregate* modifier state, not any specific key's up-event. `modifierMask`
//     itself is `primaryModifier(mask)`: the single highest bit of the binding's mask, not
//     the whole mask — so a Ctrl+Alt chord commits on Alt release alone (Alt is numerically
//     the higher X11 modifier bit), matching what a user's fingers actually do letting go of
//     a combo, and avoiding a mask that can only ever clear if *every* modifier's key-up is
//     delivered (a real stuck-grab risk if one of them is ever swallowed upstream). The mask
//     itself always comes from the real `Meta.KeyBinding` that fired (threaded through from
//     keybinding.ts's `ModeFireHandler`), never re-derived from config.toml's chord string —
//     a stock GNOME install binds more than one accelerator to the same built-in action (e.g.
//     both `<Super>Tab` and `<Alt>Tab` fire `switch-applications`), so re-deriving from
//     config.toml alone would get the wrong mask for every accelerator except the one
//     config.toml happens to name.
//   - The initial "is the modifier already not held?" guard in `show()` (checked via
//     `global.get_pointer()`'s modifier field right after the grab is taken, before the hold
//     timer is even armed) is reproduced here too: it's GNOME's own belt-and-suspenders
//     against a session opening with nothing left to release.
import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import St from "gi://St";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

import { Config, Mode, OverlayAction, WindowEntry } from "./model.js";
import { OverlayView } from "./overlay.js";
import { WindowSnapshotService } from "./windows.js";
import { Disposable, SignalBag, logError } from "./util.js";

/** One in-flight switch session: from the initial chord press to commit/cancel. */
interface Session {
  readonly mode: Mode;
  entries: WindowEntry[];
  selectedIndex: number;
  /** True once we've crossed hold_threshold_ms and shown the overlay. A tap that releases
   * before this flips stays true to its "no overlay" promise. */
  revealed: boolean;
  /** The single modifier bit whose release commits — `primaryModifier()` of the mode's
   * configured chord, matching `switcherPopup.js`'s own reduction (see file header). Never 0
   * for any of ZenTab's three default/documented chords (each always carries a modifier);
   * a user who configures a bare, modifier-less chord in config.toml gets a session that
   * simply never auto-commits on "release" (there's nothing to release) — it still ends
   * cleanly via Escape, W/Q, or click-outside once revealed, so this is a degraded-but-safe
   * fallback, not a stuck grab. */
  readonly modifierMask: number;
  /** The `Clutter.Grab` `Main.pushModal()` returned for this session — `_grabActor` itself is
   * `Switcher`-lifetime, not session-lifetime (see file header), so this is the only
   * session-scoped piece of the grab. */
  readonly grab: Clutter.Grab;
  holdTimeoutId: number | null;
}

export class Switcher implements Disposable {
  private readonly _windows: WindowSnapshotService;
  private readonly _overlay: OverlayView;
  private readonly _getConfig: () => Config;
  private _session: Session | null = null;

  /** The one persistent modal-grab target for this `Switcher`'s whole lifetime — see the file
   * header for why this can't be recreated per session. Sized to the whole stage via the same
   * `Clutter.BindConstraint` switcherPopup.js itself uses, invisible by default so it never
   * intercepts input outside an active session (an invisible actor is never picked). */
  private readonly _grabActor: St.Widget;
  private readonly _keyController: Clutter.KeyController;
  private readonly _bag = new SignalBag();

  constructor(windows: WindowSnapshotService, overlay: OverlayView, getConfig: () => Config) {
    this._windows = windows;
    this._overlay = overlay;
    this._getConfig = getConfig;

    this._grabActor = new St.Widget({ reactive: true, visible: false });
    this._grabActor.add_constraint(
      new Clutter.BindConstraint({ source: global.stage, coordinate: Clutter.BindCoordinate.ALL }),
    );

    this._keyController = new Clutter.KeyController();
    this._bag.track(
      this._keyController,
      this._keyController.connect("key-press", (controller: Clutter.KeyController) => this._onKeyPress(controller)),
    );
    this._bag.track(
      this._keyController,
      this._keyController.connect("modifier-change", (controller: Clutter.KeyController) =>
        this._onModifierChange(controller),
      ),
    );
    this._grabActor.add_action(this._keyController);

    Main.layoutManager.addChrome(this._grabActor);
    // The overlay's scrim/card/tiles must be genuine descendants of the grabbed actor once
    // revealed (see file header) — OverlayView builds them lazily, parented here.
    this._overlay.attachTo(this._grabActor);
  }

  /** Fired by keybinding.ts on the *initial* chord press (Meta/Main only fires the
   * keybinding once — every subsequent Tab while the modifier is held is a raw key event this
   * module's own modal grab reads directly via its `Clutter.KeyController`, matching
   * `switcherPopup.js`; Meta's own global keybinding dispatch can't even reach us again once
   * the grab holds keyboard focus with `actionMode` NONE). */
  start(mode: Mode, isBackward: boolean, realModifierMask?: number): void {
    if (this._session) {
      if (this._session.mode === mode) {
        // Same chord fired again while a session is already open (e.g. a fast double-tap
        // before the hold timer even elapsed): treat it like the windows/darwin apps do —
        // a second gesture means the user is cycling, so reveal now (idempotent if already
        // revealed) rather than making them keep holding past the threshold.
        this._reveal();
        this._advance(isBackward);
        return;
      }
      // A different mode's chord fired mid-session — shouldn't normally happen (the first
      // session's modal grab should be eating all key input), but end cleanly rather than
      // leaking a grab if it ever does.
      this._end(/* commit */ false);
    }

    const entries = this._windows.getEntries(mode);
    if (entries.length === 0) return;

    const focusWindow = global.display.get_focus_window();
    const initial = this._windows.getMostRecentOther(entries, focusWindow?.get_id());
    const selectedIndex = Math.max(
      0,
      entries.findIndex((e) => e.id === initial?.id),
    );

    let grab: Clutter.Grab;
    try {
      grab = Main.pushModal(this._grabActor);
    } catch (error) {
      logError(error, "Switcher.start: Main.pushModal failed");
      return;
    }

    // Prefer the real accelerator's mask (threaded through from `Meta.KeyBinding.get_mask()` by
    // keybinding.ts); config.toml's own chord string is only a fallback for whatever caller
    // genuinely has no binding object to read from (see file header for why re-deriving from
    // config.toml is wrong in general — a stock GNOME install binds more than one accelerator to
    // the same built-in action).
    const rawMask = realModifierMask ?? this._modifierMaskForMode(mode);

    const session: Session = {
      mode,
      entries,
      selectedIndex,
      revealed: false,
      modifierMask: primaryModifier(rawMask),
      grab,
      holdTimeoutId: null,
    };
    this._session = session;

    // `SwitcherPopup.show()`'s own anti-stuck-grab guard: if the chord's modifier is somehow
    // *already* not held the instant the grab goes live (fired via something other than a
    // genuinely-held-down chord), commit immediately instead of arming a hold timer that will
    // then wait forever for a `modifier-change` that already happened before we were
    // listening for it.
    if (session.modifierMask !== 0) {
      const [, , mods] = global.get_pointer();
      if ((mods & session.modifierMask) === 0) {
        this._end(/* commit */ true);
        return;
      }
    }

    const holdMs = this._getConfig().behavior.holdThresholdMs;
    session.holdTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, holdMs, () => {
      session.holdTimeoutId = null;
      this._reveal();
      return GLib.SOURCE_REMOVE;
    });
  }

  /** Mouse hover moved the selection to `entry` — VISION: "keyboard and mouse drive one
   * shared selection; the most recent input wins." Wire this to overlay.ts's
   * `OverlayCallbacks.onHoverSelect`. No-op before reveal: there is nothing to hover over
   * while the overlay doesn't exist yet. */
  selectHovered(entry: WindowEntry): void {
    const session = this._session;
    if (!session || !session.revealed) return;
    const index = session.entries.findIndex((e) => e.id === entry.id);
    if (index < 0) return;
    session.selectedIndex = index;
    this._overlay.setSelected(entry.id);
  }

  /** A tile was clicked: commit straight to `entry`, regardless of which entry is currently
   * highlighted (a click is its own, independent commit gesture — it doesn't need to move the
   * keyboard selection first). Wire this to `OverlayCallbacks.onTileClicked`. */
  commit(entry: WindowEntry): void {
    this._end(/* commit */ true, entry);
  }

  /** Click landed outside the card: cancel with no focus change — the one cancel gesture
   * besides Escape, distinct from release-to-commit. Wire this to
   * `OverlayCallbacks.onClickOutside`. */
  cancel(): void {
    this._end(/* commit */ false);
  }

  /** W (close) or Q (quit) clicked on a tile's action chip. Wire this to
   * `OverlayCallbacks.onAction`. */
  performAction(entry: WindowEntry, action: OverlayAction): void {
    this._performCloseOrQuit(entry, action);
  }

  /** Symmetric with the constructor: ends any open session (releasing its grab), disconnects
   * the persistent `KeyController` signals, un-registers and destroys the persistent grab
   * actor. Call from `disable()`. */
  destroy(): void {
    if (this._session) this._end(/* commit */ false);
    this._bag.destroy();
    Main.layoutManager.removeChrome(this._grabActor);
    this._grabActor.destroy();
  }

  private _reveal(): void {
    const session = this._session;
    if (!session || session.revealed) return;
    session.revealed = true;
    this._overlay.show(
      session.mode,
      this._keyHintForMode(session.mode),
      session.entries,
      session.entries[session.selectedIndex]?.id ?? null,
    );
  }

  private _advance(isBackward: boolean): void {
    const session = this._session;
    if (!session || session.entries.length === 0) return;
    const delta = isBackward ? -1 : 1;
    session.selectedIndex =
      (session.selectedIndex + delta + session.entries.length) % session.entries.length;
    if (session.revealed) {
      this._overlay.setSelected(session.entries[session.selectedIndex]?.id ?? null);
    }
    // No reveal here — by the time this runs a session is always already open, and the only
    // two paths that call it (a raw Tab key-press, or `start()`'s same-mode re-fire branch)
    // each own revealing on their own terms already.
  }

  /** `Clutter.KeyController::key-press` — no event payload beyond the controller itself;
   * `get_key()`/`get_state()` are only meaningful called from inside this handler (per the
   * girs doc comment on those methods). Every key while a session is open is ours: the modal
   * grab has exclusive keyboard focus, so there is nowhere else for an unhandled key to
   * usefully propagate to — this always returns `EVENT_STOP`. */
  private _onKeyPress(controller: Clutter.KeyController): boolean {
    const session = this._session;
    if (!session) return Clutter.EVENT_PROPAGATE;

    const [, keysym] = controller.get_key();

    if (keysym === Clutter.KEY_Escape) {
      this._end(/* commit */ false);
      return Clutter.EVENT_STOP;
    }

    // VISION's interaction contract names exactly two navigation inputs — "Tab (forward) /
    // Shift+Tab (backward), or by hovering the mouse" — deliberately not arrow keys. The tile
    // grid wraps at `TILE.maxColumns`, so a flat-list Up/Down alias would silently stop meaning
    // "the tile above/below" the moment a session has more than one row (an ordinary 6+ window
    // case), and VISION says to delete rather than half-build an unrequested gesture like that.
    if (keysym === Clutter.KEY_Tab || keysym === Clutter.KEY_ISO_Left_Tab) {
      const [, pressed, latched, locked] = controller.get_state();
      const shiftHeld = ((pressed | latched | locked) & Clutter.ModifierType.SHIFT_MASK) !== 0;
      const backward = keysym === Clutter.KEY_ISO_Left_Tab || shiftHeld;
      this._advance(backward);
      return Clutter.EVENT_STOP;
    }

    if (session.revealed && (keysym === Clutter.KEY_w || keysym === Clutter.KEY_W)) {
      const entry = session.entries[session.selectedIndex];
      if (entry) this._performCloseOrQuit(entry, OverlayAction.CloseWindow);
      return Clutter.EVENT_STOP;
    }
    if (session.revealed && (keysym === Clutter.KEY_q || keysym === Clutter.KEY_Q)) {
      const entry = session.entries[session.selectedIndex];
      if (entry) this._performCloseOrQuit(entry, OverlayAction.QuitApp);
      return Clutter.EVENT_STOP;
    }

    return Clutter.EVENT_STOP;
  }

  /** `Clutter.KeyController::modifier-change` — fires on *every* change to the aggregate
   * pressed/latched/locked modifier state; only ends the session once none of
   * `session.modifierMask`'s bit remains set anywhere in that aggregate (see the file header
   * for why this uses `primaryModifier()` rather than the chord's full mask). */
  private _onModifierChange(controller: Clutter.KeyController): void {
    const session = this._session;
    if (!session || session.modifierMask === 0) return;
    const [, pressed, latched, locked] = controller.get_state();
    const state = (pressed | latched | locked) & session.modifierMask;
    if (state === 0) this._end(/* commit */ true);
  }

  private _performCloseOrQuit(entry: WindowEntry, action: OverlayAction): void {
    const session = this._session;
    if (!session) return;
    if (action === OverlayAction.CloseWindow) this._windows.closeWindow(entry);
    else this._windows.quitApp(entry);

    // Re-fetch immediately rather than waiting for the snapshot's async `unmanaging` signal,
    // so the tile disappears the same frame it's closed instead of on the next signal tick.
    const entries = this._windows.getEntries(session.mode);
    if (entries.length === 0) {
      // Nothing left to switch to — W/Q act on the switcher itself, they don't leave an empty
      // overlay hanging open.
      this._end(/* commit */ false);
      return;
    }
    session.entries = entries;
    session.selectedIndex = Math.min(session.selectedIndex, entries.length - 1);
    if (session.revealed) {
      this._overlay.update(
        session.mode,
        this._keyHintForMode(session.mode),
        entries,
        entries[session.selectedIndex]?.id ?? null,
      );
    }
  }

  /** Commits (if `commit`) or discards the selection, then tears the whole session down: pops
   * the modal grab, cancels the hold timer, hides the overlay. Must be safe to call at any
   * point in a session's lifecycle, including before reveal — every exit path from a session
   * (Escape, modifier release, click-outside, tile click, W/Q emptying the list, or `destroy()`
   * itself) funnels through here so there is exactly one place a grab gets released.
   * `commitEntry` overrides the current keyboard selection for the mouse-click commit path,
   * where the clicked tile isn't necessarily the highlighted one.
   *
   * The commit branch is wrapped in try/catch, matching every other risky GNOME API call in
   * this file: `entry.window` came from a snapshot that isn't re-validated against the live
   * cache, and VISION's hold-to-browse design lets a session stay open far longer than
   * upstream's typically sub-second popup — long enough for the selected window to close out
   * from under it (the app quitting normally, crashing, etc.) while the modifier is still held.
   * If `activate()` threw here unguarded, the function would return before `Main.popModal()`
   * ever ran, leaking the modal grab for the rest of the shell session — exactly the "stuck
   * grab" class of bug this file is written to never produce. */
  private _end(commit: boolean, commitEntry?: WindowEntry): void {
    const session = this._session;
    if (!session) return;
    this._session = null;

    if (session.holdTimeoutId !== null) GLib.source_remove(session.holdTimeoutId);

    if (commit) {
      const entry = commitEntry ?? session.entries[session.selectedIndex];
      if (entry) {
        try {
          this._windows.activate(entry);
        } catch (error) {
          logError(error, "Switcher._end: activate failed");
        }
      }
    }

    if (session.revealed) this._overlay.hide();

    try {
      Main.popModal(session.grab);
    } catch (error) {
      logError(error, "Switcher._end: Main.popModal failed");
    }
  }

  /** The resolved chord's display string for the mode currently switching — passed through to
   * `OverlayView.show()`/`update()`'s `keyHint` param (overlay.ts's own header-row rendering
   * is a separate, still-TODO visual pass; this makes sure the real data is already flowing
   * so that pass has something correct to render once it lands). */
  private _keyHintForMode(mode: Mode): string {
    const keys = this._getConfig().keys;
    switch (mode) {
      case Mode.EverydaySwitch:
        return keys.otherApps.raw;
      case Mode.CurrentAppWindows:
        return keys.currentApp.raw;
      case Mode.GlobalEscapeHatch:
        return keys.everything.raw;
    }
  }

  /** Derives the mode's configured chord's *full* modifier mask (e.g. "ctrl+alt+tab" ->
   * Primary|Alt) purely from config.toml's own chord string — no GNOME API needed. `start()`
   * reduces this further via `primaryModifier()` before storing it on the session; kept as a
   * separate step so the reduction rule lives in exactly one place (see file header). */
  private _modifierMaskForMode(mode: Mode): number {
    const chord =
      mode === Mode.EverydaySwitch
        ? this._getConfig().keys.otherApps
        : mode === Mode.CurrentAppWindows
          ? this._getConfig().keys.currentApp
          : this._getConfig().keys.everything;

    let mask = 0;
    for (const token of chord.raw.split("+").map((t) => t.trim().toLowerCase())) {
      if (token === "ctrl" || token === "control" || token === "primary") {
        mask |= Clutter.ModifierType.CONTROL_MASK;
      } else if (token === "alt" || token === "option") {
        mask |= Clutter.ModifierType.MOD1_MASK;
      } else if (token === "shift") {
        mask |= Clutter.ModifierType.SHIFT_MASK;
      } else if (token === "super" || token === "cmd" || token === "meta") {
        mask |= Clutter.ModifierType.SUPER_MASK;
      }
    }
    return mask;
  }
}

/** Isolates the single highest set bit of `mask` — a direct port of `switcherPopup.js`'s own
 * module-level `primaryModifier()`. For a single-modifier chord (e.g. `<Alt>Tab`) this is a
 * no-op; for a combo (e.g. `<Primary><Alt>Tab`) it picks the numerically higher modifier bit
 * (Alt's `MOD1_MASK` over Control's `CONTROL_MASK`), i.e. the one a user's hand actually lifts
 * last off a combo chord — see the file header for why this beats requiring the *whole* mask
 * to clear. */
function primaryModifier(mask: number): number {
  if (mask === 0) return 0;
  let primary = 1;
  while (mask > 1) {
    mask >>= 1;
    primary <<= 1;
  }
  return primary;
}
