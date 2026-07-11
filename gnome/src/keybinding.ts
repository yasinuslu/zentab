// Claims the trigger gestures two ways, per the spec: (1) SUPERSEDE the built-in switcher
// handlers GNOME already has grabbed by default, via `Main.wm.setCustomKeybindingHandler` —
// this makes ZenTab fire on the stock Alt+Tab/Alt+`/Ctrl+Alt+Tab the instant it's enabled,
// with no dconf writes and a trivially reversible disable(); (2) ALSO register a private
// keybinding per mode on our own gschema (seeded by config.ts's write-through), via
// `Main.wm.addKeybinding`, so a chord the user re-mapped to something with no built-in
// (e.g. `other_apps = "super+tab"`) still works. `Meta.Display.add_keybinding` is a no-op
// (returns `Meta.KeyBindingAction.NONE`) when the accelerator is already grabbed elsewhere —
// so when the configured chord happens to match a default we already override via (1), (2)
// simply fails to grab and nothing double-fires.
import Clutter from "gi://Clutter";
import type Gio from "gi://Gio";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

import { SETTINGS_KEY_BY_MODE } from "./config.js";
import { Mode } from "./model.js";
import { Disposable, logError } from "./util.js";

/** `modifierMask` is the *real* modifier mask of the accelerator that actually fired
 * (`Meta.KeyBinding.get_mask()` for the OVERRIDES path, same for the private addKeybinding
 * path), not a re-derivation from config.toml's chord string — see switcher.ts's `start()` for
 * why this distinction matters (a stock GNOME install has more than one accelerator bound to
 * the same built-in action, e.g. both `<Super>Tab` and `<Alt>Tab` fire `switch-applications`,
 * so the mask must come from whichever one actually fired). */
export type ModeFireHandler = (mode: Mode, isBackward: boolean, modifierMask: number) => void;

type PrivateMethodName = "_startSwitcher" | "_startA11ySwitcher";

/**
 * Which of GNOME's own built-in switcher keybindings each ZenTab mode supersedes, and which
 * of `Main.wm`'s own private methods to restore on disable(). Verified against
 * `js/ui/windowManager.js` (gnome-shell main branch):
 *   `setCustomKeybindingHandler('switch-applications', Shell.ActionMode.NORMAL, this._startSwitcher.bind(this))`
 *   `setCustomKeybindingHandler('switch-windows', Shell.ActionMode.NORMAL, this._startSwitcher.bind(this))`
 *   `setCustomKeybindingHandler('switch-panels', NORMAL|OVERVIEW|LOCK_SCREEN|UNLOCK_SCREEN|LOGIN_SCREEN, this._startA11ySwitcher.bind(this))`
 * `switch-group(-backward)` (GNOME's own "cycle this app's windows", conventionally Alt+`)
 * shares `_startSwitcher` with switch-applications/switch-windows in the same file.
 *
 * Mapping to ZenTab's three modes follows GNOME's own semantics: `switch-applications` +
 * `switch-windows` are both "cycle everything" families (-> everyday switch); `switch-group`
 * is GNOME's own "this app's windows" (-> current-app windows, matching Alt+` by default);
 * `switch-panels` is what Ctrl+Alt+Tab natively does (-> global escape hatch, per the task
 * spec's explicit note that this is the one that collides).
 */
const OVERRIDES: ReadonlyArray<{
  bindingName: string;
  actionMode: Shell.ActionMode;
  mode: Mode;
  originalMethodName: PrivateMethodName;
}> = [
  { bindingName: "switch-applications", actionMode: Shell.ActionMode.NORMAL, mode: Mode.EverydaySwitch, originalMethodName: "_startSwitcher" },
  { bindingName: "switch-applications-backward", actionMode: Shell.ActionMode.NORMAL, mode: Mode.EverydaySwitch, originalMethodName: "_startSwitcher" },
  { bindingName: "switch-windows", actionMode: Shell.ActionMode.NORMAL, mode: Mode.EverydaySwitch, originalMethodName: "_startSwitcher" },
  { bindingName: "switch-windows-backward", actionMode: Shell.ActionMode.NORMAL, mode: Mode.EverydaySwitch, originalMethodName: "_startSwitcher" },
  { bindingName: "switch-group", actionMode: Shell.ActionMode.NORMAL, mode: Mode.CurrentAppWindows, originalMethodName: "_startSwitcher" },
  { bindingName: "switch-group-backward", actionMode: Shell.ActionMode.NORMAL, mode: Mode.CurrentAppWindows, originalMethodName: "_startSwitcher" },
  // GNOME's own `switch-panels` registration additionally covers LOCK_SCREEN | UNLOCK_SCREEN |
  // LOGIN_SCREEN (it's an accessibility "cycle Shell UI panels" affordance kept reachable at
  // the lock/login screen for keyboard/screen-reader users). `session-modes: ["user"]` in
  // metadata.json means GNOME disables ZenTab (restoring the original handler) before the
  // session ever transitions into those modes, but that correctness depends on
  // ExtensionManager's disable-before-transition ordering with zero race window — and
  // `disable()`'s own restore below depends on `Main.wm._startA11ySwitcher` still existing
  // under that exact name on whatever shell version is running, which isn't guaranteed across
  // point releases. ZenTab's own switcher has no legitimate reason to ever run at the lock or
  // login screen, so it deliberately does NOT request those action-mode bits here: even in the
  // worst case (a shell-version rename breaks `disable()`'s restore), a leaked handler bound to
  // NORMAL | OVERVIEW alone can never fire at the lock screen.
  {
    bindingName: "switch-panels",
    actionMode: Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
    mode: Mode.GlobalEscapeHatch,
    originalMethodName: "_startA11ySwitcher",
  },
  {
    bindingName: "switch-panels-backward",
    actionMode: Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
    mode: Mode.GlobalEscapeHatch,
    originalMethodName: "_startA11ySwitcher",
  },
];

export class KeybindingController implements Disposable {
  private readonly _settings: Gio.Settings;
  private readonly _onFire: ModeFireHandler;
  private _overriddenNames: string[] = [];
  private _privateBindingNames: string[] = [];

  constructor(settings: Gio.Settings, onFire: ModeFireHandler) {
    this._settings = settings;
    this._onFire = onFire;
  }

  enable(): void {
    for (const o of OVERRIDES) {
      try {
        // Called directly (not via `Main.wm.setCustomKeybindingHandler`) so the real boolean
        // result is visible: `Main.wm`'s own wrapper is `if (Meta.keybindings_set_custom_handler(...))
        // this.allowKeybinding(...)` and returns nothing itself, so going through it would
        // silently swallow a "this binding name doesn't exist on this shell version" failure —
        // the override would no-op with zero log line, and `_overriddenNames` would still record
        // it as active. Calling the two steps ourselves gets the same net effect with a real
        // success signal to act on.
        const ok = Meta.keybindings_set_custom_handler(
          o.bindingName,
          (_display, _window, _event, binding) => {
            // `binding.is_reversed()` is the same call `windowManager.js`'s own
            // `_startSwitcher`/`_startA11ySwitcher` use to pick forward vs backward — each
            // `-backward` name in OVERRIDES is registered by Mutter as its own binding with the
            // reverse flag baked in, so this reflects which of the pair actually fired (more
            // robust than string-matching the name ourselves). `binding.get_mask()` is the real
            // accelerator's modifier mask (the same call `_startSwitcher` itself makes to hand
            // to `tabPopup.show()`) — stock GNOME binds more than one accelerator to the same
            // built-in action (e.g. both `<Super>Tab` and `<Alt>Tab` fire `switch-applications`),
            // so this must come from whichever one actually fired, never re-derived from
            // config.toml's chord string.
            this._onFire(o.mode, binding.is_reversed(), binding.get_mask());
          },
        );
        if (ok) {
          Main.wm.allowKeybinding(o.bindingName, o.actionMode);
          this._overriddenNames.push(o.bindingName);
        } else {
          logError(
            new Error(`Meta.keybindings_set_custom_handler("${o.bindingName}") returned false — this binding name may not exist on this shell version; the built-in gesture (if any) is untouched, but ZenTab will not fire for it`),
            "KeybindingController.enable",
          );
        }
      } catch (error) {
        logError(error, `KeybindingController.enable: could not override "${o.bindingName}"`);
      }
    }

    for (const [mode, settingsKey] of Object.entries(SETTINGS_KEY_BY_MODE) as [Mode, string][]) {
      try {
        const action = Main.wm.addKeybinding(
          settingsKey,
          this._settings,
          Meta.KeyBindingFlags.NONE,
          Shell.ActionMode.NORMAL,
          (_display, _window, event, binding) => {
            // Our own private bindings (config.toml chords with no built-in match) have no
            // paired "-backward" name for `is_reversed()` to read, unlike the OVERRIDES above
            // — so backward here is simply "was Shift down when the chord fired", read off the
            // triggering event itself. The modifier mask, though, comes from the real binding
            // (same as the OVERRIDES path) rather than being re-derived from config.toml.
            const shiftHeld = (event.get_state() & Clutter.ModifierType.SHIFT_MASK) !== 0;
            this._onFire(mode, shiftHeld, binding.get_mask());
          },
        );
        if (action !== Meta.KeyBindingAction.NONE) this._privateBindingNames.push(settingsKey);
      } catch (error) {
        logError(error, `KeybindingController.enable: could not add private binding "${settingsKey}"`);
      }
    }
  }

  /** Symmetric with enable(): restores every overridden built-in handler to `Main.wm`'s own
   * original method, and removes every private binding this session actually grabbed. Must
   * run in full even if enable() partially failed, so disable() never leaves a built-in
   * switcher permanently hijacked. */
  disable(): void {
    for (const o of OVERRIDES) {
      if (!this._overriddenNames.includes(o.bindingName)) continue;
      try {
        // `Main.wm`'s private switcher methods aren't part of its public `@girs` surface —
        // this is the same reach-into-private-internals every extension that overrides these
        // bindings needs.
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const original = (Main.wm as any)[o.originalMethodName]?.bind(Main.wm);
        if (typeof original === "function") {
          Main.wm.setCustomKeybindingHandler(o.bindingName, o.actionMode, original);
        } else {
          logError(
            new Error(`Main.wm.${o.originalMethodName} is not a function on this shell version`),
            "KeybindingController.disable",
          );
        }
      } catch (error) {
        logError(error, `KeybindingController.disable: could not restore "${o.bindingName}"`);
      }
    }
    this._overriddenNames = [];

    for (const settingsKey of this._privateBindingNames) {
      try {
        Main.wm.removeKeybinding(settingsKey);
      } catch (error) {
        logError(error, `KeybindingController.disable: could not remove "${settingsKey}"`);
      }
    }
    this._privateBindingNames = [];
  }

  destroy(): void {
    this.disable();
  }
}
