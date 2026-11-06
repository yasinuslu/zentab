// Virtual monitors: one wide physical monitor (21:9, 32:9) behaves like two real monitors.
//
// Mutter (Wayland) has no way to split one output into two logical monitors: its monitor
// layout is computed in C from real outputs, and X11's `xrandr --setmonitor` has no Wayland
// equivalent. Overriding `Main.layoutManager.monitors` only fools the Shell's JS chrome (and
// breaks backgrounds, hot corners and the overview), while Mutter keeps maximizing, placing and
// tiling against the whole output. So the split lives here, at the few places where "which
// monitor am I on" actually changes behavior:
//
//   - Alt+Tab (ZenTab's everyday switch) lists only the half under the pointer, and the overlay
//     is centered on that half (`VirtualMonitorLayout.current()` / `.forWindow()`).
//   - Maximize (Super+Up, double-click, drag to top) fills only the window's half.
//   - New windows open in the half under the pointer instead of straddling the split.
//   - Super+Shift+Left/Right moves a window to the neighbouring half (then to the next real
//     monitor), keeping its maximized/tiled state, like moving between real monitors.
//   - Super+Left/Right tiles to the left/right half *of the half*, like on a real monitor.
//
// Workspaces stay shared (Mutter still sees one monitor). Fullscreen, the top bar, the overview
// and notifications still span the whole physical monitor — see README "Virtual monitors".
//
// "Maximized to a half" is a vertical maximize at half width. That is the closest a non-Mutter
// caller can get (Mutter's own tile modes are not exposed to JS), and it is what every GNOME
// tiling extension does. Apps therefore see a vertically tiled window, not a maximized one.
import GLib from "gi://GLib";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

import { Disposable, SignalBag, log, logError } from "./util.js";

/** Physical monitors at least this wide (width / height) are split. 16:9 is 1.78, 21:9 ultrawides
 * are 2.33-2.39, 32:9 is 3.56. One fixed rule instead of a per-monitor list. */
const MIN_SPLIT_ASPECT = 2.0;

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface VirtualMonitor {
  /** Stable for the current monitor layout: `${physical}:${part}`. Compare these, not objects. */
  readonly key: string;
  readonly physical: number;
  /** 0 = left half (or the whole monitor when not split), 1 = right half. */
  readonly part: number;
  readonly split: boolean;
  readonly geometry: Rect;
}

type Direction = "left" | "right";

/** Pure geometry over the live monitor layout. Cheap enough to call on every query (a handful of
 * Mutter getters), so nothing is cached and a monitor change never leaves stale halves behind. */
export class VirtualMonitorLayout {
  private _enabled = false;
  private _ratio = 0.5;

  configure(enabled: boolean, ratio: number): void {
    this._enabled = enabled;
    this._ratio = Math.min(0.8, Math.max(0.2, ratio));
  }

  get enabled(): boolean {
    return this._enabled;
  }

  isSplit(physical: number): boolean {
    return this._enabled && this._isWide(physical);
  }

  /** Whether any monitor is wide enough to split (whether or not the split is on). */
  hasWideMonitor(): boolean {
    for (let i = 0; i < global.display.get_n_monitors(); i++) if (this._isWide(i)) return true;
    return false;
  }

  get ratio(): number {
    return this._ratio;
  }

  private _isWide(physical: number): boolean {
    if (physical < 0) return false;
    const geo = global.display.get_monitor_geometry(physical);
    return geo.height > 0 && geo.width / geo.height >= MIN_SPLIT_ASPECT;
  }

  /** x of the split line in stage coordinates, or null when `physical` is not split. */
  splitX(physical: number): number | null {
    if (!this.isSplit(physical)) return null;
    const geo = global.display.get_monitor_geometry(physical);
    return geo.x + Math.round(geo.width * this._ratio);
  }

  monitorsOf(physical: number): VirtualMonitor[] {
    const geo = global.display.get_monitor_geometry(physical);
    const whole = { x: geo.x, y: geo.y, width: geo.width, height: geo.height };
    const split = this.splitX(physical);
    if (split === null) return [{ key: `${physical}:0`, physical, part: 0, split: false, geometry: whole }];
    return [
      { key: `${physical}:0`, physical, part: 0, split: true, geometry: { ...whole, width: split - geo.x } },
      {
        key: `${physical}:1`,
        physical,
        part: 1,
        split: true,
        geometry: { ...whole, x: split, width: geo.x + geo.width - split },
      },
    ];
  }

  /** The virtual monitor of `physical` that contains stage x coordinate `x`. */
  at(physical: number, x: number): VirtualMonitor {
    const parts = this.monitorsOf(physical);
    const split = this.splitX(physical);
    return split !== null && x >= split ? parts[1]! : parts[0]!;
  }

  /** The virtual monitor under the pointer — what "current monitor" means everywhere. */
  current(): VirtualMonitor {
    const [x] = global.get_pointer();
    return this.at(global.display.get_current_monitor(), x);
  }

  /** The virtual monitor a window belongs to: the half holding the centre of its frame. */
  forWindow(win: Meta.Window): VirtualMonitor {
    const physical = win.get_monitor();
    if (!this.isSplit(physical)) return this.monitorsOf(Math.max(0, physical))[0]!;
    const rect = win.get_frame_rect();
    return this.at(physical, rect.x + rect.width / 2);
  }

  /** The work area (minus panels/struts) of a virtual monitor on the active workspace. */
  workArea(vm: VirtualMonitor): Rect {
    const area = global.workspace_manager.get_active_workspace().get_work_area_for_monitor(vm.physical);
    const left = Math.max(area.x, vm.geometry.x);
    const right = Math.min(area.x + area.width, vm.geometry.x + vm.geometry.width);
    return { x: left, y: area.y, width: Math.max(0, right - left), height: area.height };
  }

  /** The adjacent virtual monitor: the other half first, then the nearest half of the real
   * neighbouring monitor (its right half when moving left, its left half when moving right). */
  neighbor(vm: VirtualMonitor, direction: Direction): VirtualMonitor | null {
    const parts = this.monitorsOf(vm.physical);
    const next = vm.part + (direction === "left" ? -1 : 1);
    if (next >= 0 && next < parts.length) return parts[next]!;
    const physical = global.display.get_monitor_neighbor_index(
      vm.physical,
      direction === "left" ? Meta.DisplayDirection.LEFT : Meta.DisplayDirection.RIGHT,
    );
    if (physical < 0) return null;
    const theirs = this.monitorsOf(physical);
    return direction === "left" ? theirs[theirs.length - 1]! : theirs[0]!;
  }
}

/** Where a window sits inside its virtual monitor when ZenTab placed it. */
type Placement = "max" | "left" | "right";

interface Tracked {
  readonly win: Meta.Window;
  readonly ids: number[];
  /** Last rect the window had while floating (not maximized/tiled/fullscreen): where it goes back
   * to on unmaximize, and which half a maximize from the keyboard belongs to. */
  floating: Rect | null;
  /** Set while ZenTab holds the window maximized or tiled inside a half. */
  placement: Placement | null;
  placedOn: string | null;
  firstShown: boolean;
  maxPending: boolean;
}

// Mutter 49 dropped the flags argument of maximize()/unmaximize() for set_(un)maximize_flags();
// these keep GNOME 48 working too.
/* eslint-disable @typescript-eslint/no-explicit-any */
function maxFlags(win: Meta.Window): number {
  const w = win as any;
  if (typeof w.get_maximize_flags === "function") return w.get_maximize_flags();
  return (w.maximized_horizontally ? Meta.MaximizeFlags.HORIZONTAL : 0) | (w.maximized_vertically ? Meta.MaximizeFlags.VERTICAL : 0);
}

function setMax(win: Meta.Window, flags: Meta.MaximizeFlags): void {
  const w = win as any;
  if (typeof w.set_maximize_flags === "function") w.set_maximize_flags(flags);
  else w.maximize(flags);
}

function setUnmax(win: Meta.Window, flags: Meta.MaximizeFlags): void {
  const w = win as any;
  if (typeof w.set_unmaximize_flags === "function") w.set_unmaximize_flags(flags);
  else w.unmaximize(flags);
}
/* eslint-enable @typescript-eslint/no-explicit-any */

function rectOf(win: Meta.Window): Rect {
  const r = win.get_frame_rect();
  return { x: r.x, y: r.y, width: r.width, height: r.height };
}

/** `rect` resized to fit `area` (never larger) and centred in it. */
function centeredIn(rect: Rect, area: Rect): Rect {
  const width = Math.min(rect.width, area.width);
  const height = Math.min(rect.height, area.height);
  return {
    x: area.x + Math.round((area.width - width) / 2),
    y: area.y + Math.round((area.height - height) / 2),
    width,
    height,
  };
}

/** `rect` moved from virtual monitor area `from` to `to`, keeping its relative position. */
function translated(rect: Rect, from: Rect, to: Rect): Rect {
  const width = Math.min(rect.width, to.width);
  const height = Math.min(rect.height, to.height);
  const fx = from.width > rect.width ? (rect.x - from.x) / (from.width - rect.width) : 0.5;
  const fy = from.height > rect.height ? (rect.y - from.y) / (from.height - rect.height) : 0.5;
  return {
    x: to.x + Math.round(Math.min(1, Math.max(0, fx)) * (to.width - width)),
    y: to.y + Math.round(Math.min(1, Math.max(0, fy)) * (to.height - height)),
    width,
    height,
  };
}

function straddles(rect: Rect, splitX: number): boolean {
  return rect.x < splitX && rect.x + rect.width > splitX;
}

/** Built-in bindings ZenTab takes over while virtual monitors are on. Restored with a null
 * handler (Mutter then falls back to its own default) on disable. */
const BINDINGS: ReadonlyArray<{ name: string; action: "move" | "tile"; direction: Direction }> = [
  { name: "move-to-monitor-left", action: "move", direction: "left" },
  { name: "move-to-monitor-right", action: "move", direction: "right" },
  { name: "toggle-tiled-left", action: "tile", direction: "left" },
  { name: "toggle-tiled-right", action: "tile", direction: "right" },
];

/**
 * The behaviors that make each half act like a monitor. Event-driven and idle-free: per-window
 * signals only (maximize flags, size/position for the floating rect, first show), no
 * timers beyond the one idle per placement that lets a Wayland unmaximize land first.
 */
export class VirtualMonitorManager implements Disposable {
  private readonly _layout: VirtualMonitorLayout;
  private readonly _bag = new SignalBag();
  private readonly _tracked = new Map<number, Tracked>();
  private readonly _idles = new Set<number>();
  private _bindings: string[] = [];
  private _grabbing = false;
  /** Windows maximized by a drag (to the top edge) while the grab was still held: placed into
   * the pointer's half once the grab ends, since Mutter finishes its own maximize at release. */
  private readonly _maxAfterGrab = new Set<Tracked>();
  /** Re-entrancy guard: our own maximize/move calls emit the signals we listen to. */
  private _applying = false;
  private _active = false;

  constructor(layout: VirtualMonitorLayout) {
    this._layout = layout;
  }

  /** Turns the behaviors on or off to match the layout's `enabled` (called on config change). */
  sync(): void {
    if (this._layout.enabled && !this._active) this._enable();
    else if (!this._layout.enabled && this._active) this._disable(true);
  }

  /** Extension disable, which also runs on every screen lock: windows keep their geometry, so
   * unlocking doesn't reshuffle anyone's halves. */
  destroy(): void {
    if (this._active) this._disable(false);
  }

  private _enable(): void {
    this._active = true;
    for (const actor of global.get_window_actors()) {
      const win = actor.get_meta_window();
      if (win) this._track(win, false);
    }
    // Windows already maximized across a monitor that is now split fill one half instead (the
    // half under the pointer: nothing better is known about where they "belong").
    for (const t of this._tracked.values()) {
      if (maxFlags(t.win) === Meta.MaximizeFlags.BOTH && !t.win.is_fullscreen() && this._isPlaceable(t.win)) {
        if (this._layout.isSplit(t.win.get_monitor())) this._place(t, this._layout.current(), "max");
      }
    }
    this._bag.track(
      global.display,
      global.display.connect("window-created", (_d: Meta.Display, win: Meta.Window) => this._track(win, true)),
    );
    this._bag.track(
      global.display,
      global.display.connect("grab-op-begin", () => {
        this._grabbing = true;
      }),
    );
    this._bag.track(
      global.display,
      global.display.connect("grab-op-end", () => {
        this._grabbing = false;
        const pending = [...this._maxAfterGrab];
        this._maxAfterGrab.clear();
        this._later(() => {
          for (const t of pending) {
            if (this._tracked.get(t.win.get_id()) !== t) continue;
            if (maxFlags(t.win) === Meta.MaximizeFlags.BOTH) this._place(t, this._layout.current(), "max");
          }
        });
      }),
    );

    for (const b of BINDINGS) {
      try {
        const ok = Meta.keybindings_set_custom_handler(b.name, (_display, win) => {
          if (!win) return;
          if (b.action === "move") this._moveToNeighbor(win, b.direction);
          else this._toggleTile(win, b.direction);
        });
        if (ok) {
          Main.wm.allowKeybinding(b.name, Shell.ActionMode.NORMAL);
          this._bindings.push(b.name);
        }
      } catch (error) {
        logError(error, `VirtualMonitorManager: could not take over "${b.name}"`);
      }
    }
    log("virtual monitors on");
  }

  /** `remaximize`: the split itself was turned off (config), so windows maximized into a half
   * become really maximized again. */
  private _disable(remaximize: boolean): void {
    this._active = false;
    for (const name of this._bindings) {
      try {
        Meta.keybindings_set_custom_handler(name, null);
      } catch (error) {
        logError(error, `VirtualMonitorManager: could not restore "${name}"`);
      }
    }
    this._bindings = [];
    for (const id of this._idles) GLib.source_remove(id);
    this._idles.clear();
    this._bag.destroy();

    // With the split turned off, windows maximized into a half become really maximized again:
    // that is what "maximized" means now. Tiled halves stay where they are (still a sensible
    // layout). On a plain extension disable (lock screen) nothing moves.
    for (const t of this._tracked.values()) {
      for (const id of t.ids) {
        try {
          t.win.disconnect(id);
        } catch {
          // window already gone
        }
      }
      if (remaximize && t.placement === "max") {
        try {
          setMax(t.win, Meta.MaximizeFlags.BOTH);
        } catch (error) {
          logError(error, "VirtualMonitorManager: re-maximize on disable");
        }
      }
    }
    this._tracked.clear();
    this._maxAfterGrab.clear();
    this._grabbing = false;
    log("virtual monitors off");
  }

  private _track(win: Meta.Window, isNew: boolean): void {
    const id = win.get_id();
    if (this._tracked.has(id)) return;
    const t: Tracked = {
      win,
      ids: [],
      floating: null,
      placement: null,
      placedOn: null,
      firstShown: !isNew,
      maxPending: false,
    };
    if (maxFlags(win) === 0 && !win.is_fullscreen()) t.floating = rectOf(win);
    this._tracked.set(id, t);

    t.ids.push(win.connect("notify::maximized-horizontally", () => this._onMaximizeChanged(t)));
    t.ids.push(win.connect("notify::maximized-vertically", () => this._onMaximizeChanged(t)));
    t.ids.push(win.connect("size-changed", () => this._rememberFloating(t)));
    t.ids.push(win.connect("position-changed", () => this._rememberFloating(t)));
    t.ids.push(win.connect("unmanaging", () => this._untrack(id)));
    if (isNew) {
      t.ids.push(win.connect("shown", () => this._onFirstShown(t)));
    }
  }

  private _untrack(id: number): void {
    const t = this._tracked.get(id);
    if (!t) return;
    this._tracked.delete(id);
    for (const sid of t.ids) {
      try {
        t.win.disconnect(sid);
      } catch {
        // already disposed
      }
    }
  }

  private _isPlaceable(win: Meta.Window): boolean {
    return win.get_window_type() === Meta.WindowType.NORMAL && !win.get_transient_for() && !win.is_fullscreen();
  }

  private _rememberFloating(t: Tracked): void {
    // Not gated on _applying: ZenTab's own floating moves (initial placement, restore, move to the
    // other half) must update it too, or the next maximize picks the half the window left.
    if (t.placement !== null || maxFlags(t.win) !== 0 || t.win.is_fullscreen()) return;
    t.floating = rectOf(t.win);
  }

  // New window: Mutter centres it on the physical monitor, i.e. right on the split line. Open
  // it in the half under the pointer instead, the way a new window opens on the monitor you're
  // looking at. A window that already sits wholly inside one half (an app restoring its own
  // position) is left alone. Done on the first `shown`, which Mutter emits while mapping, before
  // the first frame is painted. (Mutter's `configure` signal would be earlier, but its
  // MetaWindowConfig getters are not usable from GJS: get_rect() comes back null and
  // get_position()/get_size() lack out-annotations.)
  private _onFirstShown(t: Tracked): void {
    if (t.firstShown) return;
    t.firstShown = true;
    if (!this._isPlaceable(t.win)) return;
    if (maxFlags(t.win) === Meta.MaximizeFlags.BOTH) {
      this._handleMaximize(t);
      return;
    }
    const rect = rectOf(t.win);
    const target = this._initialTarget(rect);
    if (target) this._moveResize(t.win, centeredIn(rect, this._layout.workArea(target)));
  }

  /** The half a new window at `rect` should open in, or null to leave it where it is. */
  private _initialTarget(rect: Rect): VirtualMonitor | null {
    const current = this._layout.current();
    if (!current.split) return null;
    const splitX = this._layout.splitX(current.physical)!;
    const geo = global.display.get_monitor_geometry(current.physical);
    const onCurrent = rect.x + rect.width / 2 >= geo.x && rect.x + rect.width / 2 < geo.x + geo.width;
    if (onCurrent && !straddles(rect, splitX)) return null;
    return current;
  }

  // Maximize (Super+Up, double-click, the maximize button, drag to the top edge) arrives as
  // both flags set. Turn it into "maximized inside the half". Because apps never learn they are
  // maximized (Mutter reports a vertical tile), the next maximize request on a half-maximized
  // window is treated as the toggle back.
  private _onMaximizeChanged(t: Tracked): void {
    // One maximize notifies both flags; coalesce them so a single request is handled once.
    if (this._applying || t.maxPending) return;
    t.maxPending = true;
    this._later(() => {
      t.maxPending = false;
      if (this._tracked.get(t.win.get_id()) === t) this._handleMaximize(t);
    });
  }

  private _handleMaximize(t: Tracked): void {
    const win = t.win;
    const flags = maxFlags(win);
    if (flags === Meta.MaximizeFlags.BOTH) {
      if (win.is_fullscreen() || !this._layout.isSplit(win.get_monitor())) return;
      if (this._grabbing) {
        this._maxAfterGrab.add(t);
        return;
      }
      if (t.placement === "max") {
        this._restore(t);
        return;
      }
      const vm = !t.floating ? this._layout.current() : this._vmForRect(win.get_monitor(), t.floating);
      this._place(t, vm, "max");
      return;
    }
    if (t.placement !== null && (flags & Meta.MaximizeFlags.VERTICAL) === 0) {
      // Unmaximized by the user (Super+Down, or dragged off). A keyboard unmaximize goes back to
      // the floating rect; a drag keeps the rect Mutter gives the window under the pointer.
      const wasDragged = this._grabbing;
      t.placement = null;
      t.placedOn = null;
      if (!wasDragged && t.floating) {
        const vm = this._layout.forWindow(win);
        const floating = t.floating;
        this._later(() => this._moveResize(win, this._fitInto(floating, vm)));
      }
    }
  }

  private _vmForRect(physical: number, rect: Rect): VirtualMonitor {
    return this._layout.at(physical, rect.x + rect.width / 2);
  }

  /** `rect` if it already lies in `vm`, else moved into it keeping its size where possible. */
  private _fitInto(rect: Rect, vm: VirtualMonitor): Rect {
    const area = this._layout.workArea(vm);
    const inside =
      rect.x >= area.x && rect.x + rect.width <= area.x + area.width && rect.y >= area.y && rect.y + rect.height <= area.y + area.height;
    return inside ? rect : centeredIn(rect, area);
  }

  private _restore(t: Tracked): void {
    const win = t.win;
    const vm = this._layout.forWindow(win);
    // A window maximized before ZenTab saw it float has no remembered size: give it a centred
    // two-thirds of its half rather than leaving it half-wide and full-height.
    const area = this._layout.workArea(vm);
    const floating =
      t.floating ?? centeredIn({ x: 0, y: 0, width: Math.round(area.width * 0.66), height: Math.round(area.height * 0.66) }, area);
    t.placement = null;
    t.placedOn = null;
    this._applying = true;
    try {
      setUnmax(win, Meta.MaximizeFlags.BOTH);
    } finally {
      this._applying = false;
    }
    this._later(() => this._moveResize(win, this._fitInto(floating, vm)));
  }

  /** Maximizes `t.win` inside `vm` ("max"), or tiles it to its left/right half. */
  private _place(t: Tracked, vm: VirtualMonitor, placement: Placement): void {
    const win = t.win;
    const area = this._layout.workArea(vm);
    let rect: Rect = area;
    if (placement !== "max") {
      const half = Math.round(area.width / 2);
      rect = placement === "left" ? { ...area, width: half } : { ...area, x: area.x + half, width: area.width - half };
    }
    t.placement = placement;
    t.placedOn = vm.key;
    this._applying = true;
    try {
      const flags = maxFlags(win);
      // A real maximize is undone fully, not just horizontally: a drag to the top edge also sets
      // Mutter's internal "maximized" tile mode, which survives a horizontal-only unmaximize and
      // keeps constraining the width to the whole monitor. Only a full unmaximize clears it.
      if (flags & Meta.MaximizeFlags.HORIZONTAL) setUnmax(win, Meta.MaximizeFlags.BOTH);
      if (!(maxFlags(win) & Meta.MaximizeFlags.VERTICAL)) setMax(win, Meta.MaximizeFlags.VERTICAL);
    } finally {
      this._applying = false;
    }
    // Let the unmaximize configure land before the final geometry, or Mutter's own restore of
    // the saved rect overrides it on Wayland.
    this._later(() => {
      if (t.placement !== placement || t.placedOn !== vm.key) return;
      this._moveResize(win, rect);
    });
  }

  private _moveResize(win: Meta.Window, rect: Rect): void {
    const t = this._tracked.get(win.get_id());
    if (t && t.placement === null && maxFlags(win) === 0) t.floating = rect;
    this._applying = true;
    try {
      win.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
    } catch (error) {
      logError(error, "VirtualMonitorManager._moveResize");
    } finally {
      this._applying = false;
    }
  }

  private _later(fn: () => void): void {
    const id = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
      this._idles.delete(id);
      try {
        fn();
      } catch (error) {
        logError(error, "VirtualMonitorManager idle");
      }
      return GLib.SOURCE_REMOVE;
    });
    this._idles.add(id);
  }

  // Super+Shift+Left/Right: to the next virtual monitor, keeping maximized/tiled state and the
  // relative position of a floating window, like moving between real monitors.
  private _moveToNeighbor(win: Meta.Window, direction: Direction): void {
    const t = this._tracked.get(win.get_id());
    const from = this._layout.forWindow(win);
    const to = this._layout.neighbor(from, direction);
    if (!to || !t) return;

    if (!to.split) {
      // A real, unsplit monitor: hand over to Mutter's own move, then restore the state there.
      const wasMax = t.placement === "max" || maxFlags(win) === Meta.MaximizeFlags.BOTH;
      if (t.placement !== null) this._restoreSilently(t);
      win.move_to_monitor(to.physical);
      if (wasMax) setMax(win, Meta.MaximizeFlags.BOTH);
      return;
    }

    if (t.placement !== null) {
      // Moving left out of a right tile lands in the other half's right tile, and so on, the way
      // a tiled window keeps its side on a real monitor.
      this._place(t, to, t.placement);
      return;
    }
    if (maxFlags(win) === Meta.MaximizeFlags.BOTH) {
      // Really maximized (coming from an unsplit monitor).
      this._place(t, to, "max");
      return;
    }
    const rect = rectOf(win);
    const next = translated(rect, this._layout.workArea(from), this._layout.workArea(to));
    if (from.physical !== to.physical) win.move_to_monitor(to.physical);
    this._moveResize(win, next);
  }

  /** Drops ZenTab's placement without restoring geometry (the caller moves the window next). */
  private _restoreSilently(t: Tracked): void {
    t.placement = null;
    t.placedOn = null;
    this._applying = true;
    try {
      setUnmax(t.win, Meta.MaximizeFlags.BOTH);
    } finally {
      this._applying = false;
    }
  }

  // Super+Left/Right: tile to the left/right half of the window's own virtual monitor. Pressing
  // the same side again restores, pressing the other side switches sides. (On an unsplit
  // monitor this is the same as Mutter's own half tile.)
  private _toggleTile(win: Meta.Window, direction: Direction): void {
    const t = this._tracked.get(win.get_id());
    if (!t || !win.allows_resize()) return;
    const vm = this._layout.forWindow(win);
    if (t.placement === direction && t.placedOn === vm.key) this._restore(t);
    else this._place(t, vm, direction);
  }
}
