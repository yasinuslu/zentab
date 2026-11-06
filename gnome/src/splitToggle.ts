// The "Split screen" button in Quick Settings: turns virtual monitors on and off in one click,
// because nobody wants the split all the time. It is a view of config.toml, not a second source
// of truth: a click rewrites `[virtual_monitors] enabled` in the file (applied at once, and the
// file watcher's reload then agrees), so the choice survives a re-login. Shown only while some
// monitor is wide enough to be split.
//
// The same switch has a fixed shortcut, Super+\ (the key reads as a divider), so flipping
// between one wide screen and two halves is a key press away; an on-screen notice says which
// way it went. Fixed on purpose (VISION: no settings), held in the private gschema only because
// Mutter keybindings need a GSettings key.
import Gio from "gi://Gio";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { QuickToggle, SystemIndicator } from "resource:///org/gnome/shell/ui/quickSettings.js";

import { Disposable, logError } from "./util.js";
import type { VirtualMonitorLayout } from "./vmonitors.js";

export const SPLIT_KEYBINDING_KEY = "toggle-split-keybinding";

export class SplitToggle implements Disposable {
  private _indicator: SystemIndicator | null = null;
  private _toggle: QuickToggle | null = null;
  private _monitorsChangedId: number | null = null;
  private _keybindingAdded = false;

  constructor(
    private readonly _settings: Gio.Settings,
    private readonly _layout: VirtualMonitorLayout,
    private readonly _onToggled: (enabled: boolean) => void,
  ) {}

  enable(): void {
    const toggle = new QuickToggle({ title: "Split screen", iconName: "view-dual-symbolic", toggleMode: true });
    toggle.checked = this._layout.enabled;
    toggle.connect("clicked", () => this._onToggled(toggle.checked));
    const indicator = new SystemIndicator();
    indicator.quickSettingsItems.push(toggle);
    Main.panel.statusArea.quickSettings?.addExternalIndicator(indicator);
    this._toggle = toggle;
    this._indicator = indicator;
    this._monitorsChangedId = Main.layoutManager.connect("monitors-changed", () => this._updateVisible());
    this._updateVisible();

    try {
      const action = Main.wm.addKeybinding(
        SPLIT_KEYBINDING_KEY,
        this._settings,
        Meta.KeyBindingFlags.NONE,
        Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
        () => this._flip(),
      );
      this._keybindingAdded = action !== Meta.KeyBindingAction.NONE;
    } catch (error) {
      logError(error, "SplitToggle: could not add the Super+\\ binding");
    }
  }

  /** The shortcut: same as clicking the button, plus a notice, since there is nothing else on
   * screen to confirm it. A no-op without a wide monitor (nothing to split). */
  private _flip(): void {
    if (!this._layout.hasWideMonitor()) return;
    const enabled = !this._layout.enabled;
    if (this._toggle) this._toggle.checked = enabled;
    this._onToggled(enabled);
    try {
      const icon = new Gio.ThemedIcon({ name: enabled ? "view-dual-symbolic" : "view-paged-symbolic" });
      Main.osdWindowManager.show(-1, icon, enabled ? "Split screen on" : "Split screen off", null, null);
    } catch (error) {
      logError(error, "SplitToggle: OSD");
    }
  }

  /** Mirror the current state (after a click, or a hand edit of config.toml). */
  sync(): void {
    if (this._toggle) this._toggle.checked = this._layout.enabled;
  }

  private _updateVisible(): void {
    if (this._toggle) this._toggle.visible = this._layout.hasWideMonitor();
  }

  destroy(): void {
    if (this._keybindingAdded) Main.wm.removeKeybinding(SPLIT_KEYBINDING_KEY);
    this._keybindingAdded = false;
    if (this._monitorsChangedId !== null) Main.layoutManager.disconnect(this._monitorsChangedId);
    this._monitorsChangedId = null;
    try {
      for (const item of this._indicator?.quickSettingsItems ?? []) item.destroy();
      this._indicator?.destroy();
    } catch (error) {
      logError(error, "SplitToggle.destroy");
    }
    this._indicator = null;
    this._toggle = null;
  }
}
