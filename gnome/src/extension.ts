// Entry point. No work happens at module top level (GNOME Shell Extensions Review
// Guidelines: importing an extension must be side-effect-free) — everything lives inside
// enable()/disable(), and disable() undoes every single thing enable() did, symmetrically,
// so the extension is clean to disable at the lock screen and clean to re-enable afterward.
import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";

import { ConfigManager, writeVirtualMonitorsSetting } from "./config.js";
import { KeybindingController } from "./keybinding.js";
import { Mode } from "./model.js";
import { OverlayView } from "./overlay.js";
import { SplitToggle } from "./splitToggle.js";
import { Switcher } from "./switcher.js";
import { logError } from "./util.js";
import { VirtualMonitorLayout, VirtualMonitorManager } from "./vmonitors.js";
import { WindowSnapshotService } from "./windows.js";

export default class ZenTabExtension extends Extension {
  private _configManager: ConfigManager | null = null;
  private _windows: WindowSnapshotService | null = null;
  private _overlay: OverlayView | null = null;
  private _switcher: Switcher | null = null;
  private _keybindings: KeybindingController | null = null;
  private _virtualMonitors: VirtualMonitorManager | null = null;
  private _splitToggle: SplitToggle | null = null;

  // Creation order: config -> windows -> overlay -> switcher -> keybindings. Each later stage
  // depends on the ones before it (Switcher needs both the live window snapshot and the
  // overlay it drives; KeybindingController needs Switcher.start as its fire handler), and
  // disable() below tears everything down in the exact reverse order for symmetry.
  enable(): void {
    try {
      const settings = this.getSettings();

      // Virtual monitors (config.toml [virtual_monitors]) follow live config edits, so turning
      // the split on/off is a save of the file, no Shell restart.
      const layout = new VirtualMonitorLayout();
      const configManager = new ConfigManager(settings);
      this._configManager = configManager;
      const initial = configManager.start((config) => {
        layout.configure(config.virtualMonitors.enabled, config.virtualMonitors.ratio);
        this._virtualMonitors?.sync();
        this._splitToggle?.sync();
      });
      layout.configure(initial.virtualMonitors.enabled, initial.virtualMonitors.ratio);
      // Dragging the divider saves the new ratio, so it survives a re-login like the on/off.
      const virtualMonitors = new VirtualMonitorManager(layout, (ratio) =>
        writeVirtualMonitorsSetting("ratio", ratio.toFixed(3)),
      );
      this._virtualMonitors = virtualMonitors;
      virtualMonitors.sync();

      // Quick Settings "Split screen": apply at once, then persist to config.toml.
      const splitToggle = new SplitToggle(settings, layout, (enabled) => {
        layout.configure(enabled, layout.ratio);
        virtualMonitors.sync();
        writeVirtualMonitorsSetting("enabled", String(enabled));
      });
      this._splitToggle = splitToggle;
      splitToggle.enable();

      // Assigned to `this._windows` *before* `.start()` runs (not after) so that if `.start()`
      // itself throws, the catch block's `this.disable()` can still reach this
      // already-partially-live object and tear it down — `start()`'s per-window tracking has
      // its own internal guards, but should it ever throw outside those, we must not discard a
      // reference that may already hold real signal connections. Same reasoning applies to
      // `keybindings` below.
      const windows = new WindowSnapshotService(layout);
      this._windows = windows;
      windows.start();

      // `switcher` is assigned just below, after construction — the callbacks close over this
      // `let` binding by reference, so by the time GNOME Shell actually fires one of them
      // (always after enable() has returned) the binding is populated. This is the standard
      // way to break the OverlayView <-> Switcher construction cycle (Switcher's constructor
      // needs a live OverlayView, but OverlayView's callbacks need to reach the Switcher).
      let switcher: Switcher | null = null;

      const overlay = new OverlayView({
        onHoverSelect: (entry) => switcher?.selectHovered(entry),
        onTileClicked: (entry) => switcher?.commit(entry),
        onClickOutside: () => switcher?.cancel(),
        onAction: (entry, action) => switcher?.performAction(entry, action),
      }, layout);
      this._overlay = overlay;

      switcher = new Switcher(windows, overlay, () => configManager.current, layout);
      this._switcher = switcher;

      const keybindings = new KeybindingController(
        settings,
        (mode: Mode, isBackward: boolean, modifierMask: number) => {
          switcher?.start(mode, isBackward, modifierMask);
        },
      );
      this._keybindings = keybindings;
      keybindings.enable();
    } catch (error) {
      logError(error, "ZenTabExtension.enable");
      // Never leave a half-enabled extension holding keybindings/grabs/signals: unwind
      // whatever did get created before the failure.
      this.disable();
    }
  }

  disable(): void {
    this._keybindings?.destroy();
    this._keybindings = null;

    // Destroy the overlay BEFORE the switcher: Switcher owns the persistent `_grabActor` that
    // OverlayView's scrim/card/tiles are parented under (via `attachTo`), so tearing the
    // switcher down first would cascade-destroy those actors, leaving OverlayView.destroy() to
    // run over already-disposed objects (the "already disposed / no handler with id" criticals).
    this._overlay?.destroy();
    this._overlay = null;

    this._switcher?.destroy();
    this._switcher = null;

    this._windows?.destroy();
    this._windows = null;

    this._splitToggle?.destroy();
    this._splitToggle = null;

    this._virtualMonitors?.destroy();
    this._virtualMonitors = null;

    this._configManager?.destroy();
    this._configManager = null;
  }
}
