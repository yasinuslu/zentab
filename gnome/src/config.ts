// Config: the ONE knob-holding file (VISION.md: "config is a file"). Source of truth is
// ~/.config/zentab/config.toml, mirroring windows/zentab.toml's schema exactly:
//
//   [keys]
//   other_apps  = "alt+tab"
//   current_app = "alt+`"
//   everything  = "ctrl+alt+tab"
//
//   [behavior]
//   hold_threshold_ms = 150
//
// GJS ships no TOML library, so this hand-rolls just enough of the format for this schema —
// two flat sections, string/number scalars, `#` comments — with a graceful fallback to
// DEFAULT_CONFIG on anything missing or malformed. It is NOT a general-purpose TOML parser
// (no arrays, tables-of-tables, multiline strings, etc.) — deliberately, since the schema it
// serves never grows past these two sections per VISION's "delete the knob" principle.
import Gio from "gi://Gio";
import GLib from "gi://GLib";

import { Config, DEFAULT_CONFIG, KeyChord, Mode } from "./model.js";
import { Disposable, log, logError } from "./util.js";

// Computed lazily (not at module scope) so importing this module is side-effect-free — the
// GNOME Shell Extensions Review Guidelines require enable()/disable() to own all work,
// including trivial/pure calls into GLib. Cached after the first call since neither the home
// dir nor the config path can change during a running process.
let _configDir: string | null = null;
let _configPath: string | null = null;

export function getConfigDir(): string {
  return (_configDir ??= GLib.build_filenamev([GLib.get_home_dir(), ".config", "zentab"]));
}

export function getConfigPath(): string {
  return (_configPath ??= GLib.build_filenamev([getConfigDir(), "config.toml"]));
}

/** GSettings keys backing the three trigger-key accelerators (see schemas/*.gschema.xml). */
export const SETTINGS_KEY_BY_MODE: Record<Mode, string> = {
  [Mode.EverydaySwitch]: "other-apps-keybinding",
  [Mode.CurrentAppWindows]: "current-app-keybinding",
  [Mode.GlobalEscapeHatch]: "everything-keybinding",
};

interface RawConfig {
  keys?: {
    other_apps?: string;
    current_app?: string;
    everything?: string;
  };
  behavior?: {
    hold_threshold_ms?: number;
  };
}

/**
 * Minimal line-oriented parser for exactly this schema: `[section]` headers, `key = "value"`
 * or `key = 123` assignments, `#` line comments (only outside quotes). Unknown sections/keys
 * are ignored rather than rejected, so the file can grow comments/documentation (like
 * windows/zentab.toml's header block) without tripping anything.
 */
export function parseToml(text: string): RawConfig {
  const result: RawConfig = {};
  let section: "keys" | "behavior" | null = null;

  for (const rawLine of text.split("\n")) {
    const line = stripComment(rawLine).trim();
    if (line.length === 0) continue;

    const sectionMatch = /^\[([\w.-]+)]$/.exec(line);
    if (sectionMatch) {
      const name = sectionMatch[1];
      section = name === "keys" || name === "behavior" ? name : null;
      continue;
    }

    const assignMatch = /^([\w-]+)\s*=\s*(.+)$/.exec(line);
    if (!assignMatch || section === null) continue;
    const [, key, rawValue] = assignMatch;
    if (key === undefined || rawValue === undefined) continue;

    if (section === "keys" && (key === "other_apps" || key === "current_app" || key === "everything")) {
      const value = parseTomlString(rawValue);
      if (value !== null) (result.keys ??= {})[key] = value;
    } else if (section === "behavior" && key === "hold_threshold_ms") {
      const value = Number(rawValue.trim());
      if (Number.isFinite(value)) (result.behavior ??= {}).hold_threshold_ms = value;
    }
  }

  return result;
}

/** Strips a `#` comment that isn't inside a `"..."` string (chords never contain `#`, but
 * this keeps the parser honest about quoting regardless). */
function stripComment(line: string): string {
  let inString = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inString = !inString;
    else if (ch === "#" && !inString) return line.slice(0, i);
  }
  return line;
}

function parseTomlString(rawValue: string): string | null {
  const value = rawValue.trim();
  const match = /^"([^"]*)"$/.exec(value);
  return match ? (match[1] ?? null) : null;
}

/** Maps a modifier/base-key token (as written in config.toml, e.g. `"ctrl"`, `"alt"`,
 * `` "`" ``) to its GNOME/GTK accelerator spelling. Extend this table, not the parser, if a
 * new chord ever needs a key it doesn't cover yet. */
const MODIFIER_TOKENS: Record<string, string> = {
  ctrl: "<Primary>",
  control: "<Primary>",
  primary: "<Primary>",
  alt: "<Alt>",
  option: "<Alt>",
  shift: "<Shift>",
  super: "<Super>",
  cmd: "<Super>",
  meta: "<Super>",
};

/** Base (non-modifier) key spellings that don't match their GTK keysym name verbatim. Named,
 * multi-character keysyms need their EXACT capitalized spelling (GTK's accelerator parser is
 * only case-insensitive for single-character tokens — plain letters/digits — not named keys),
 * so every named key ZenTab is willing to accept must be listed here explicitly rather than
 * passed through in whatever case the user typed. */
const BASE_KEY_TOKENS: Record<string, string> = {
  tab: "Tab",
  "`": "grave",
  esc: "Escape",
  escape: "Escape",
  space: "space",
  enter: "Return",
  return: "Return",
  backspace: "BackSpace",
  delete: "Delete",
  up: "Up",
  down: "Down",
  left: "Left",
  right: "Right",
  home: "Home",
  end: "End",
  insert: "Insert",
  print: "Print",
  pageup: "Page_Up",
  page_up: "Page_Up",
  pagedown: "Page_Down",
  page_down: "Page_Down",
};

/** Resolves a base (non-modifier) key token to its GTK/GNOME keysym spelling, or `null` if it
 * can't be resolved to a known-good spelling. Three cases: (1) a named key in
 * `BASE_KEY_TOKENS`; (2) a function key `f1`..`f24`, capitalized to `F1`..`F24`; (3) a single
 * ASCII letter/digit, passed through verbatim (GTK's accelerator parser genuinely is
 * case-insensitive for these, per `gtk_accelerator_parse`'s length-1 special case). Anything
 * else is rejected rather than guessed at — a chord we can't confidently resolve must fall back
 * to the default, not silently bind to a wrong/broken accelerator. */
function resolveBaseKey(token: string): string | null {
  const named = BASE_KEY_TOKENS[token];
  if (named) return named;
  const fKeyMatch = /^f([1-9]|1\d|2[0-4])$/.exec(token);
  if (fKeyMatch) return `F${fKeyMatch[1]}`;
  if (/^[a-z0-9]$/.test(token)) return token;
  return null;
}

/** Turns a config chord like `"ctrl+alt+tab"` into GNOME accelerator form
 * `"<Primary><Alt>Tab"`, or `null` if any modifier token is unrecognized or the base key can't
 * be resolved (see `resolveBaseKey`). Never silently drops a modifier token it doesn't
 * recognize — a chord like `"win+tab"` (an unmapped modifier) must fail outright rather than
 * collapse to a bare, modifier-less `"Tab"` accelerator, which would grab every Tab keypress
 * system-wide. Callers must fall back to the default chord for that field on `null`. */
export function chordToAccelerator(raw: string): string | null {
  const tokens = raw
    .split("+")
    .map((token) => token.trim().toLowerCase())
    .filter((token) => token.length > 0);
  if (tokens.length === 0) return null;

  const baseToken = tokens[tokens.length - 1]!;
  const modifierTokens = tokens.slice(0, -1);

  const modifiers: string[] = [];
  for (const token of modifierTokens) {
    const mapped = MODIFIER_TOKENS[token];
    if (!mapped) return null;
    modifiers.push(mapped);
  }

  const base = resolveBaseKey(baseToken);
  if (base === null) return null;

  return `${modifiers.join("")}${base}`;
}

export function chord(raw: string): KeyChord | null {
  const accelerator = chordToAccelerator(raw);
  return accelerator === null ? null : { raw, accelerator };
}

/** Merges parsed TOML over DEFAULT_CONFIG, falling back per-field (not all-or-nothing) so a
 * partially malformed file still gets every field it *did* specify correctly. A field whose raw
 * string fails to resolve to a real accelerator (unknown modifier, unresolvable base key) also
 * falls back to its default rather than writing a broken/dangerous accelerator through — see
 * `chordToAccelerator`. */
export function resolveConfig(raw: RawConfig): Config {
  return {
    keys: {
      otherApps: resolveChordField(raw.keys?.other_apps, DEFAULT_CONFIG.keys.otherApps, "other_apps"),
      currentApp: resolveChordField(raw.keys?.current_app, DEFAULT_CONFIG.keys.currentApp, "current_app"),
      everything: resolveChordField(raw.keys?.everything, DEFAULT_CONFIG.keys.everything, "everything"),
    },
    behavior: {
      holdThresholdMs: raw.behavior?.hold_threshold_ms ?? DEFAULT_CONFIG.behavior.holdThresholdMs,
    },
  };
}

function resolveChordField(rawValue: string | undefined, fallback: KeyChord, fieldName: string): KeyChord {
  if (!rawValue) return fallback;
  const resolved = chord(rawValue);
  if (resolved) return resolved;
  logError(
    new Error(
      `config.toml: [keys].${fieldName} = "${rawValue}" is not a recognized chord — falling back to default "${fallback.raw}"`,
    ),
    "resolveConfig",
  );
  return fallback;
}

/**
 * Owns the config lifecycle: load -> resolve -> write-through into the extension's private
 * `Gio.Settings` (so `Main.wm.addKeybinding` has a GSettings-backed accelerator to read) ->
 * watch the file for live-reload. `settings` must be the `Gio.Settings` this extension got
 * from `Extension.getSettings()` (schema `org.gnome.shell.extensions.zentab`).
 */
export class ConfigManager implements Disposable {
  private readonly _settings: Gio.Settings;
  private _current: Config = DEFAULT_CONFIG;
  private _monitor: Gio.FileMonitor | null = null;
  private _monitorSignalId: number | null = null;
  private _onChange: ((config: Config) => void) | null = null;

  constructor(settings: Gio.Settings) {
    this._settings = settings;
  }

  get current(): Config {
    return this._current;
  }

  /** Loads once, writes through to GSettings, and (if `onChange` is given) starts watching
   * config.toml for edits, re-resolving and re-writing-through on every change. Call from
   * enable(); pair with destroy() in disable(). */
  start(onChange?: (config: Config) => void): Config {
    this._onChange = onChange ?? null;
    this._current = this._load();
    this._writeThrough(this._current);

    try {
      const file = Gio.File.new_for_path(getConfigPath());
      this._monitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
      this._monitorSignalId = this._monitor.connect("changed", (_monitor, _file, _otherFile, eventType) => {
        // Editors typically emit CHANGES_DONE_HINT after a burst of CHANGED events on save;
        // reacting only to that (and to CREATED/RENAMED for editors that write-then-rename)
        // avoids re-parsing mid-write and avoids the double-fire most watchers see on save.
        if (
          eventType !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
          eventType !== Gio.FileMonitorEvent.CREATED &&
          eventType !== Gio.FileMonitorEvent.RENAMED
        ) {
          return;
        }
        this._current = this._load();
        this._writeThrough(this._current);
        this._onChange?.(this._current);
      });
    } catch (error) {
      // A missing ~/.config/zentab directory (first run, no config yet) is fine — defaults
      // already loaded above. Anything else is logged but never fatal: ZenTab must keep
      // working on defaults even if live-reload can't be set up.
      logError(error, "ConfigManager.start: could not watch config.toml");
    }

    return this._current;
  }

  destroy(): void {
    if (this._monitor && this._monitorSignalId !== null) {
      this._monitor.disconnect(this._monitorSignalId);
    }
    this._monitor?.cancel();
    this._monitor = null;
    this._monitorSignalId = null;
    this._onChange = null;
  }

  private _load(): Config {
    try {
      const [ok, bytes] = GLib.file_get_contents(getConfigPath());
      if (!ok || bytes === null) return DEFAULT_CONFIG;
      const text = new TextDecoder("utf-8").decode(bytes);
      return resolveConfig(parseToml(text));
    } catch {
      // Missing file (never configured) or unreadable — both are "use the shipping
      // defaults", not an error worth surfacing (VISION: "strong defaults keep it near-empty").
      return DEFAULT_CONFIG;
    }
  }

  private _writeThrough(config: Config): void {
    this._settings.set_strv(SETTINGS_KEY_BY_MODE[Mode.EverydaySwitch], [config.keys.otherApps.accelerator]);
    this._settings.set_strv(SETTINGS_KEY_BY_MODE[Mode.CurrentAppWindows], [
      config.keys.currentApp.accelerator,
    ]);
    this._settings.set_strv(SETTINGS_KEY_BY_MODE[Mode.GlobalEscapeHatch], [
      config.keys.everything.accelerator,
    ]);
    log(
      `config loaded: other_apps=${config.keys.otherApps.raw} current_app=${config.keys.currentApp.raw} ` +
        `everything=${config.keys.everything.raw} hold_threshold_ms=${config.behavior.holdThresholdMs}`,
    );
  }
}
