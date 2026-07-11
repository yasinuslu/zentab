// Small, dependency-free helpers shared across modules. Nothing here does GNOME-specific
// work beyond wrapping `console` (GJS's ambient logging, safe to call from any context) and
// GObject's `connect`/`disconnect`, so it's safe to import from any module including at
// module scope (no side effects run until a function here is actually called).

const LOG_PREFIX = "[zentab]";

export function log(message: string): void {
  console.log(`${LOG_PREFIX} ${message}`);
}

export function logError(error: unknown, context?: string): void {
  const prefix = context ? `${LOG_PREFIX} ${context}:` : LOG_PREFIX;
  if (error instanceof Error) {
    console.error(prefix, error.message, error.stack ?? "");
  } else {
    console.error(prefix, error);
  }
}

/** Anything enable() creates that disable() must symmetrically tear down. */
export interface Disposable {
  destroy(): void;
}

/** Any GObject-derived instance: St/Clutter/Meta/Shell/Gio all share `disconnect(id)`. */
interface Disconnectable {
  disconnect(id: number): void;
}

/**
 * Bookkeeping for `connect()` ids, so `disable()` (or any teardown) can walk them all and call
 * `disconnect()` without each module hand-rolling its own array. Deliberately does NOT wrap
 * `connect()` itself — call the object's own (fully, correctly typed by `@girs`) `.connect()`
 * directly and hand the id to `track()`, e.g.:
 *
 *   bag.track(win, win.connect('unmanaging', () => this._untrack(id)));
 *
 * GNOME Shell's review guidelines are strict here: every signal connected in enable() must be
 * disconnected in disable() — a leaked connection keeps `this` (and everything it closes over)
 * alive for the lifetime of the shell process.
 */
export class SignalBag implements Disposable {
  private readonly _entries: Array<{ object: Disconnectable; id: number }> = [];

  /** Records an id already returned by `object.connect(...)`; returns it unchanged so this
   * can wrap the connect call inline: `bag.track(obj, obj.connect(...))`. */
  track(object: Disconnectable, id: number): number {
    this._entries.push({ object, id });
    return id;
  }

  /** Disconnects everything tracked so far, in reverse-connection order, then clears. */
  destroy(): void {
    for (let i = this._entries.length - 1; i >= 0; i--) {
      const { object, id } = this._entries[i]!;
      try {
        object.disconnect(id);
      } catch (error) {
        // An already-destroyed GObject can throw on disconnect(); never let that abort the
        // rest of teardown, since disable() must always finish.
        logError(error, "SignalBag.destroy");
      }
    }
    this._entries.length = 0;
  }
}

export function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(`${LOG_PREFIX} assertion failed: ${message}`);
  }
}
