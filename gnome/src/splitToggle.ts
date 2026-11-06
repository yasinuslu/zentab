// The "Split screen" button in Quick Settings: turns virtual monitors on and off in one click,
// because nobody wants the split all the time. It is a view of config.toml, not a second source
// of truth: a click rewrites `[virtual_monitors] enabled` in the file (applied at once, and the
// file watcher's reload then agrees), so the choice survives a re-login. Shown only while some
// monitor is wide enough to be split.
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { QuickToggle, SystemIndicator } from "resource:///org/gnome/shell/ui/quickSettings.js";

import { Disposable, logError } from "./util.js";
import type { VirtualMonitorLayout } from "./vmonitors.js";

export class SplitToggle implements Disposable {
  private _indicator: SystemIndicator | null = null;
  private _toggle: QuickToggle | null = null;
  private _monitorsChangedId: number | null = null;

  constructor(
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
  }

  /** Mirror the current state (after a click, or a hand edit of config.toml). */
  sync(): void {
    if (this._toggle) this._toggle.checked = this._layout.enabled;
  }

  private _updateVisible(): void {
    if (this._toggle) this._toggle.visible = this._layout.hasWideMonitor();
  }

  destroy(): void {
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
