// The window model: a pre-warmed, event-driven snapshot of every real window, kept current
// off the hot path via display/workspace/monitor signals (VISION: "near-zero idle cost... no
// cold full enumeration on summon"). `getEntries()` never walks `global.get_window_actors()` —
// that walk happens exactly once, in `start()`, to prime the cache; after that the cache tracks
// itself via `window-created` (add), each window's own removal signals (`unmanaging` plus its
// actor's `destroy`), and a handful of cheap, additive-only self-heal passes.
//
// Deliberately does NOT cache anything mutable about a window (monitor, workspace, minimized,
// title) — `getEntries()` always reads those live off the `Meta.Window` at query time. The only
// thing cached is *identity* (which windows exist) and *first-seen order* (VISION's stable,
// never-MRU-reshuffled ordering). That's what makes the self-heal signals below cheap: they
// never need to invalidate derived state, only to catch a window that slipped past
// `window-created` (there is no such state to slip out of sync).
import Meta from "gi://Meta";
import Shell from "gi://Shell";

import { Mode, WindowEntry } from "./model.js";
import { Disposable, SignalBag, log, logError } from "./util.js";

let nextFirstSeenSeq = 0;

interface CacheEntry {
  readonly id: number;
  readonly window: Meta.Window;
  /** Insertion order — the basis of VISION's "stable, first-seen sequence (NOT MRU-reshuffled)"
   * ordering. Never recomputed after the window is first tracked. */
  readonly firstSeenSeq: number;
  /** `Meta.Window`'s own removal signal — the documented, always-available way to know a
   * window is going away (fires before the window becomes invalid, so this is safe to read
   * from). Disconnected explicitly in `_untrack`, not left for `SignalBag.destroy()`, so a long
   * day of windows opening/closing never grows an unbounded connection list (VISION: "resident
   * all day... near-zero idle cost"). */
  readonly unmanagingId: number;
  /** The window's compositor actor, if it had one by the time it was tracked (it may not yet on
   * a freshly created Wayland window — `unmanaging` alone is sufficient for correctness; this is
   * belt-and-suspenders). */
  readonly actor: Meta.WindowActor | null;
  readonly actorDestroyId: number | null;
}

export class WindowSnapshotService implements Disposable {
  private readonly _cache = new Map<number, CacheEntry>();
  private readonly _bag = new SignalBag();
  private _tracker: Shell.WindowTracker | null = null;
  private _started = false;
  /** Subscribers notified whenever the cache's *identity* set changes (a window newly tracked
   * or untracked) — see `subscribe()`. The Switcher uses this to keep an open session's overlay
   * in sync when a window it's showing closes or a new one appears mid-session. */
  private readonly _changeListeners = new Set<() => void>();
  /** Re-entrancy guard for `_notifyChanged`: a listener may re-query the service (`getEntries` ->
   * `_reconcile` -> `_track`) and re-enter notification. One level of dispatch is enough. */
  private _notifying = false;

  /** Primes the cache from the windows already on screen (the one and only cold walk this
   * service ever does), then wires signals to stay current. Call once from enable(). */
  start(): void {
    if (this._started) return;
    this._started = true;
    this._tracker = Shell.WindowTracker.get_default();

    for (const actor of global.get_window_actors()) {
      const win = actor.get_meta_window();
      if (win) this._track(win);
    }

    this._bag.track(
      global.display,
      global.display.connect("window-created", (_display: Meta.Display, win: Meta.Window) => {
        this._track(win);
      }),
    );

    // Everything below is a cheap, additive-only self-heal pass — never a removal path (each
    // window's own signals in `_track` own removal exclusively) and never a cold rebuild. It
    // exists purely to guard against a window that appears without `window-created` ever firing
    // for it (rare compositor races: e.g. an XWayland window mapped before its create event is
    // dispatched). Deliberately NOT hooked to `restacked`: that fires on ordinary, frequent
    // desktop activity (every click-to-focus, minimize, workspace-switch animation) — far wider
    // than the rare race it would guard against. `getEntries()` below runs the same reconcile
    // lazily, right before it's actually needed (a switch is being summoned), which catches the
    // exact same race with zero idle cost between summons (VISION: "near-zero idle cost").
    this._bag.track(
      global.workspace_manager,
      global.workspace_manager.connect("active-workspace-changed", () => this._reconcile()),
    );
    try {
      const monitorManager = global.backend.get_monitor_manager();
      this._bag.track(
        monitorManager,
        monitorManager.connect("monitors-changed", () => this._reconcile()),
      );
    } catch (error) {
      // Best-effort: losing this one self-heal hook still leaves window-created/restacked/
      // active-workspace-changed covering the vast majority of cases.
      logError(error, "WindowSnapshotService.start: monitor manager unavailable");
    }
  }

  /** Symmetric with start(): disconnects every signal (the display's/workspace's/monitor
   * manager's, and every still-tracked window's own), drops all cached references. Call from
   * disable(). */
  destroy(): void {
    for (const cached of this._cache.values()) {
      this._disconnectEntry(cached);
    }
    this._cache.clear();
    this._bag.destroy();
    this._tracker = null;
    this._started = false;
  }

  private _track(win: Meta.Window): void {
    const id = win.get_id();
    if (this._cache.has(id)) return;

    const unmanagingId = win.connect("unmanaging", () => this._untrack(id));

    // The actor may not exist yet for a just-created window; `unmanaging` alone is already a
    // reliable removal signal (confirmed: it's the documented "about to be unmanaged" hook and
    // doesn't depend on the compositor's actor being present). Hooking the actor's own generic
    // `destroy` too is a second, independent removal path for the rare case `unmanaging` doesn't
    // fire (abnormal teardown) — harmless to have both since `_untrack` is idempotent.
    let actor: Meta.WindowActor | null = null;
    try {
      actor = win.get_compositor_private<Meta.WindowActor>();
    } catch (error) {
      logError(error, "WindowSnapshotService._track: get_compositor_private");
    }
    const actorDestroyId = actor ? actor.connect("destroy", () => this._untrack(id)) : null;

    this._cache.set(id, {
      id,
      window: win,
      firstSeenSeq: nextFirstSeenSeq++,
      unmanagingId,
      actor,
      actorDestroyId,
    });
    this._notifyChanged();
  }

  private _untrack(id: number): void {
    const cached = this._cache.get(id);
    if (!cached) return; // already removed by whichever of unmanaging/actor-destroy fired first
    this._cache.delete(id);
    this._disconnectEntry(cached);
    // Notify AFTER the cache mutation so a subscriber that re-queries `getEntries()` sees the
    // window already gone (this is what makes a W/Q-closed window's tile disappear the frame its
    // `unmanaging` fires — see the Switcher's window-change handler).
    this._notifyChanged();
  }

  /** Subscribe to cache-identity changes (a window newly tracked or untracked). The listener
   * fires AFTER the cache mutation, so re-querying `getEntries(mode, false)` (reconcile off) from
   * inside it sees the updated set. Returns an unsubscribe fn. This exists for one job: keeping
   * an open switch session's overlay in sync when a window it's showing goes away — because
   * `closeWindow()`/`quitApp()` are asynchronous requests to the client, the window is still
   * cached the instant they return and only leaves (firing `unmanaging` -> `_untrack` -> here) a
   * frame or more later, or never if the app declines the close. */
  subscribe(listener: () => void): () => void {
    this._changeListeners.add(listener);
    return () => {
      this._changeListeners.delete(listener);
    };
  }

  private _notifyChanged(): void {
    if (this._notifying) return;
    this._notifying = true;
    try {
      // Snapshot to an array so a listener that (un)subscribes during dispatch can't mutate the
      // set mid-iteration.
      for (const listener of [...this._changeListeners]) {
        try {
          listener();
        } catch (error) {
          logError(error, "WindowSnapshotService._notifyChanged: listener threw");
        }
      }
    } finally {
      this._notifying = false;
    }
  }

  /** Disconnects a cache entry's own signals. Safe to call from inside one of those very signal
   * handlers (GObject completes the in-flight emission before honoring a disconnect) and safe to
   * call on a partially-torn-down object (each disconnect is individually try/caught so one
   * already-dead object never aborts the rest of teardown). */
  private _disconnectEntry(cached: CacheEntry): void {
    try {
      cached.window.disconnect(cached.unmanagingId);
    } catch (error) {
      logError(error, "WindowSnapshotService: disconnect unmanaging");
    }
    if (cached.actor && cached.actorDestroyId !== null) {
      try {
        cached.actor.disconnect(cached.actorDestroyId);
      } catch (error) {
        logError(error, "WindowSnapshotService: disconnect actor destroy");
      }
    }
  }

  /** Additive-only resync: tracks any on-screen window actor this cache doesn't already know
   * about. Never removes anything (removal is owned solely by each window's own signals) and
   * never touches derived state (nothing here is cached beyond identity + first-seen order). */
  private _reconcile(): void {
    try {
      for (const actor of global.get_window_actors()) {
        const win = actor.get_meta_window();
        if (win) this._track(win);
      }
    } catch (error) {
      logError(error, "WindowSnapshotService._reconcile");
    }
  }

  /** Builds one mode's list, live, from the warm cache — this is the only "query" entry
   * point the switcher should call. Ordering is always the cache's stable first-seen order.
   * Runs the additive-only self-heal reconcile first (see `start()`'s comment on why this is
   * lazy rather than tied to a frequent signal like `restacked`) so a rare compositor race
   * never shows a stale list at the one moment it would actually matter: right before a switch
   * session opens.
   *
   * Pass `reconcile: false` for an *in-session refresh* driven by the cache-change subscription
   * (a window closing after W/Q): the cache was just mutated to the correct set, and the
   * additive `_reconcile()` walk would re-`_track` a window that's mid-`unmanaging` — its actor
   * can still be in `global.get_window_actors()` for a beat after it left the cache — resurrecting
   * the very tile we're trying to drop. The reconcile is only there to catch a window that never
   * got a `window-created`, which a close-refresh has no reason to do. */
  getEntries(mode: Mode, reconcile = true): WindowEntry[] {
    if (reconcile) this._reconcile();
    switch (mode) {
      case Mode.EverydaySwitch:
        return this._everydaySwitch();
      case Mode.CurrentAppWindows:
        return this._currentAppWindows();
      case Mode.GlobalEscapeHatch:
        return this._globalEscapeHatch();
    }
  }

  /** Current monitor + current workspace, all apps, real on-screen windows only (no
   * minimized/hidden — VISION: "real on-screen windows only"). "Current monitor" is the
   * monitor under the mouse cursor (`Meta.Display.get_current_monitor()`'s documented
   * semantics), matching the refinement already noted in windows/WindowService.cs and the
   * overlay's own monitor-under-cursor positioning — not the focused window's monitor.
   *
   * One carve-out to "no minimized": a *fullscreen* window is still surfaced even when
   * minimized. Fullscreen exclusive games (especially Wine/Proton titles like CryEngine)
   * minimize *themselves* the instant they lose focus, so the moment you Alt+Tab away the
   * game drops out of its own switch list and you can't Alt+Tab back to it (it's only left
   * in the global escape hatch, a surprising place to hunt for the thing you were just
   * playing). A minimized-yet-fullscreen window was never one the user *tucked away*; it's a
   * live task that self-minimized, so it stays in the everyday list. Regular minimized
   * windows (the deliberate "hide this for now") remain excluded, as VISION wants.
   * `is_fullscreen()` stays true while such a window is minimized (mutter keeps
   * `_NET_WM_STATE_FULLSCREEN` alongside `_NET_WM_STATE_HIDDEN`), so this reliably readmits
   * exactly the self-minimizing-game case and nothing else. */
  private _everydaySwitch(): WindowEntry[] {
    const monitor = global.display.get_current_monitor();
    const workspace = global.workspace_manager.get_active_workspace();
    return this._buildFromCache(
      (win) =>
        win.get_monitor() === monitor &&
        win.get_workspace() === workspace &&
        (!win.minimized || win.is_fullscreen()),
    );
  }

  /** Every window of the currently-focused app, from every workspace + monitor, including
   * minimized/hidden/fullscreen. If the app has no windows at all it's still represented by
   * one trailing placeholder entry (VISION: "app listed last if it has no window"). */
  private _currentAppWindows(): WindowEntry[] {
    const app = this._tracker?.focus_app ?? null;
    if (!app) return [];

    const entries = this._buildFromCache((win) => this._tracker?.get_window_app(win) === app);
    if (entries.length > 0) return entries;

    return [
      {
        id: placeholderId(app.get_id()),
        window: null,
        app,
        title: app.get_name(),
        isAppPlaceholder: true,
        monitorIndex: -1,
        workspaceIndex: -1,
        minimized: false,
      },
    ];
  }

  /** Everything: every app, every workspace, every monitor — the "I lost something" valve.
   * Includes minimized windows (that's usually exactly what got "lost"). */
  private _globalEscapeHatch(): WindowEntry[] {
    return this._buildFromCache(() => true);
  }

  /** Skip-taskbar windows (notifications, splash screens, tooltip-style helpers) are dropped in
   * every mode, not surfaced as a flag for callers to filter themselves — VISION's three modes
   * are about real, switchable windows in every scope, and a skip-taskbar window is never one. */
  private _buildFromCache(predicate: (win: Meta.Window) => boolean): WindowEntry[] {
    const entries: Array<{ seq: number; entry: WindowEntry }> = [];
    for (const cached of this._cache.values()) {
      const win = cached.window;
      if (win.is_skip_taskbar()) continue;
      if (!predicate(win)) continue;

      const app = this._tracker?.get_window_app(win) ?? null;
      if (!app) continue; // No owning app to group/icon/quit by — can't represent it. TODO:
      // decide whether orphaned windows (rare: some settings dialogs, XWayland oddities)
      // deserve a fallback pseudo-app rather than being silently dropped.

      const workspace = win.get_workspace();
      entries.push({
        seq: cached.firstSeenSeq,
        entry: {
          id: cached.id,
          window: win,
          app,
          title: win.get_title() ?? app.get_name(),
          isAppPlaceholder: false,
          monitorIndex: win.get_monitor(),
          workspaceIndex: workspace ? workspace.index() : -1,
          minimized: win.minimized,
        },
      });
    }
    entries.sort((a, b) => a.seq - b.seq);
    return entries.map((e) => e.entry);
  }

  /**
   * Picks the initial highlight for a fresh summon: the most-recently-used *other* window
   * among `entries` (VISION: "the selection starts on the most-recent OTHER window", and
   * recency is used in exactly this one place — never to reorder the visible list). Backed by
   * `Meta.Display`'s own MRU tab list, the same source GNOME's native switcher uses.
   *
   * Queried with `workspace: null` (every workspace) and `NORMAL_ALL_MRU` ("all windows in pure
   * MRU order") rather than scoping to the active workspace: `entries` itself already carries
   * whatever scope the calling mode wants (Everyday is monitor+workspace-scoped,
   * CurrentAppWindows/GlobalEscapeHatch span everything), so this always over-fetches and lets
   * the `byId` lookup below narrow it back down — scoping the *query* to one workspace would
   * silently break recency for the two modes that reach beyond it.
   */
  getMostRecentOther(entries: readonly WindowEntry[], excludeWindowId?: number): WindowEntry | undefined {
    if (entries.length === 0) return undefined;
    const byId = new Map(entries.map((e) => [e.id, e] as const));

    try {
      const mru = global.display.get_tab_list(Meta.TabList.NORMAL_ALL_MRU, null);
      for (const win of mru) {
        const id = win.get_id();
        if (id === excludeWindowId) continue;
        const entry = byId.get(id);
        if (entry) return entry;
      }
    } catch (error) {
      logError(error, "WindowSnapshotService.getMostRecentOther");
    }

    return entries.find((e) => e.id !== excludeWindowId) ?? entries[0];
  }

  /** Focuses `entry` — de-minimizing first if needed, or activating the app itself for an
   * app-placeholder entry that has no window yet. */
  activate(entry: WindowEntry): void {
    if (entry.window) {
      if (entry.window.minimized) entry.window.unminimize();
      entry.window.activate(global.get_current_time());
    } else {
      entry.app.activate();
    }
  }

  /** W: close the selected window. No-op for an app-placeholder entry (nothing to close). */
  closeWindow(entry: WindowEntry): void {
    entry.window?.delete(global.get_current_time());
  }

  /** Q: quit the entry's whole app. */
  quitApp(entry: WindowEntry): void {
    const accepted = entry.app.request_quit();
    if (!accepted) {
      // Not an error — most commonly the app declined because it has an unsaved-changes prompt
      // (or a save dialog) to show first; the OS-level quit request is still the right call.
      log(`request_quit() declined by ${entry.app.get_name()} (likely an unsaved-changes prompt)`);
    }
  }
}

/** Deterministic, collision-free synthetic id for `CurrentAppWindows`' "app with zero windows"
 * placeholder. `Shell.App.get_id()` returns a *string* (its desktop file id, e.g.
 * "org.gnome.Nautilus.desktop"), but `WindowEntry.id` is a `number` shared with real
 * `Meta.Window` ids (always non-negative) — so this hashes the string down to a negative
 * number, a namespace no real window id can ever occupy, rather than trying to coerce the
 * string itself into a number. */
function placeholderId(appId: string): number {
  let hash = 5381;
  for (let i = 0; i < appId.length; i++) {
    hash = (hash * 33 + appId.charCodeAt(i)) | 0;
  }
  return -1 - (hash >>> 0);
}
