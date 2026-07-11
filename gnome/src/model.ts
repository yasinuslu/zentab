// Shared data types for ZenTab. Kept in one place so every module (config, windows, switcher,
// overlay) agrees on the exact shape without importing each other's internals.
//
// Authoritative spec: VISION.md (the three-mode model, tap/hold, stable ordering) and
// windows/zentab.toml (the config schema this mirrors 1:1).
import type Meta from "gi://Meta";
import type Shell from "gi://Shell";

/** The three hard-coded modes. Only the *trigger key* per mode is configurable — see Config. */
export enum Mode {
  /** Every window on the current monitor + current workspace, all apps. Default: Alt+Tab. */
  EverydaySwitch = "everyday-switch",
  /** Every window of the active app, all workspaces + monitors (incl. minimized/hidden). */
  CurrentAppWindows = "current-app-windows",
  /** Everything: all apps, all workspaces, all monitors. The "I lost something" valve. */
  GlobalEscapeHatch = "global-escape-hatch",
}

/**
 * One switchable entry in a mode's list. Almost always a real on-screen `Meta.Window`
 * (`window` set, `isAppPlaceholder` false); `CurrentAppWindows` mode's one exception is an
 * app with zero windows, which is still listed (last) as a placeholder so the app itself is
 * still reachable.
 *
 * Wraps `Meta.Window` / `Shell.App` rather than re-declaring their fields: windows.ts is the
 * only module that should reach into GNOME's live object graph, everything downstream
 * (switcher, overlay) works off this snapshot type.
 */
export interface WindowEntry {
  /** Stable identity for React-less diffing / stable ordering key (`window.get_id()`, or a
   * synthetic id for an app placeholder). Never reused within a session. */
  readonly id: number;
  /** The live window, or null for an app-placeholder entry (app has no windows at all). */
  readonly window: Meta.Window | null;
  /** The owning app (grouping key, icon, title fallback, quit target). */
  readonly app: Shell.App;
  readonly title: string;
  /** True only for `CurrentAppWindows` mode's "app with no windows" tail entry. */
  readonly isAppPlaceholder: boolean;
  readonly monitorIndex: number;
  readonly workspaceIndex: number;
  readonly minimized: boolean;
}

/** One resolved trigger chord, already split into modifier flags + the base key. */
export interface KeyChord {
  /** The chord as written in config.toml, e.g. "alt+tab", "ctrl+alt+tab", "alt+`". */
  readonly raw: string;
  /** GNOME accelerator form, e.g. "<Alt>Tab", "<Primary><Alt>Tab", "<Alt>grave". */
  readonly accelerator: string;
}

/** Parsed, defaulted `~/.config/zentab/config.toml`. Mirrors windows/zentab.toml exactly:
 * [keys] other_apps/current_app/everything, [behavior] hold_threshold_ms. Nothing else — per
 * VISION.md, the trigger keys (and the hold threshold) are the only knobs ZenTab has. */
export interface Config {
  readonly keys: {
    /** [keys].other_apps -> Mode.EverydaySwitch. Default "alt+tab". */
    readonly otherApps: KeyChord;
    /** [keys].current_app -> Mode.CurrentAppWindows. Default "alt+`". */
    readonly currentApp: KeyChord;
    /** [keys].everything -> Mode.GlobalEscapeHatch. Default "ctrl+alt+tab". */
    readonly everything: KeyChord;
  };
  readonly behavior: {
    /** [behavior].hold_threshold_ms. Hold past this to reveal the overlay; a quicker
     * tap-and-release commits instantly with no overlay. Default 150. */
    readonly holdThresholdMs: number;
  };
}

export const DEFAULT_CONFIG: Config = {
  keys: {
    otherApps: { raw: "alt+tab", accelerator: "<Alt>Tab" },
    currentApp: { raw: "alt+`", accelerator: "<Alt>grave" },
    everything: { raw: "ctrl+alt+tab", accelerator: "<Primary><Alt>Tab" },
  },
  behavior: {
    holdThresholdMs: 150,
  },
};

/** The two in-overlay actions. Nothing else — VISION.md: "no minimize, fullscreen, or hide". */
export enum OverlayAction {
  CloseWindow = "close-window",
  QuitApp = "quit-app",
}
