// The switcher's visible surface: a full-screen scrim + one frosted card of tiles, shown on
// the monitor under the cursor. v1 is deliberately minimal — see theme.ts's `TODO(blur)` for
// the one explicitly-deferred piece (a real GPU blur-behind on the scrim). Everything here is
// built from St/Clutter primitives added above all windows via `Main.layoutManager.addChrome`,
// never a `Meta.Window` of its own — there is no separate process, no protocol, just actors.
import Clutter from "gi://Clutter";
import GObject from "gi://GObject";
import St from "gi://St";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

import { Mode, OverlayAction, WindowEntry } from "./model.js";
import {
  ACCENT,
  ACTION_CHIP,
  BACKDROP,
  CARD,
  COLOR,
  FONT,
  HAIRLINE,
  HEADER,
  INDEX_CHIP,
  KEY_PILL,
  MOTION,
  TILE,
} from "./theme.js";
import { Disposable, SignalBag, logError } from "./util.js";

const MODE_LABEL: Record<Mode, string> = {
  [Mode.EverydaySwitch]: "Switch",
  [Mode.CurrentAppWindows]: "This App",
  [Mode.GlobalEscapeHatch]: "Everything",
};

export interface OverlayCallbacks {
  /** Mouse hover moved the selection to `entry` (not a commit). */
  onHoverSelect(entry: WindowEntry): void;
  /** A tile was clicked: commit to it immediately. */
  onTileClicked(entry: WindowEntry): void;
  /** Click landed outside the card: cancel with no focus change (VISION: distinct from
   * release-to-commit). */
  onClickOutside(): void;
  /** W or Q clicked on a tile's action chips. */
  onAction(entry: WindowEntry, action: OverlayAction): void;
}

/**
 * One tile: app icon + title, an index chip, and (only while hovered/selected) the W/Q action
 * chips. `GObject.registerClass` in function form (not the decorator form) per project
 * convention — keeps tsconfig decorator-free.
 */
const Tile = GObject.registerClass(
  {
    // Only the action chips need a custom signal: St.Button already emits its own native
    // "clicked", and hover is observable via the inherited "notify::hover" — redeclaring
    // either of those names here would collide with the base class's own signal.
    Signals: {
      "action-clicked": { param_types: [GObject.TYPE_STRING] },
    },
  },
  class Tile extends St.Button {
    entry!: WindowEntry;
    private _selected = false;
    private _indexLabel!: St.Label;
    private _titleLabel!: St.Label;
    private _actionRow!: St.BoxLayout;

    override _init(entry: WindowEntry, index: number) {
      super._init({
        style_class: "zentab-tile",
        reactive: true,
        can_focus: false,
        track_hover: true,
        x_expand: false,
        y_expand: false,
      });
      this.entry = entry;
      this.set_size(TILE.width, TILE.height);

      const root = new St.BoxLayout({ vertical: true, x_expand: true, y_expand: true });
      root.set_style("padding: 6px;");
      this.set_child(root);

      // Top row: the 1..9 index chip (left) and the W/Q action chips (right — shown only on
      // the selected tile, matching BRANDING.md's "shown on the focused tile").
      const topRow = new St.BoxLayout({ vertical: false, x_expand: true });
      root.add_child(topRow);

      const indexBin = new St.Bin({
        width: INDEX_CHIP.size,
        height: INDEX_CHIP.size,
        x_align: Clutter.ActorAlign.CENTER,
        y_align: Clutter.ActorAlign.CENTER,
      });
      indexBin.set_style(`border-radius: ${INDEX_CHIP.radius}px; background-color: ${INDEX_CHIP.fill};`);
      this._indexLabel = new St.Label({ text: String(index + 1) });
      indexBin.set_child(this._indexLabel);
      topRow.add_child(indexBin);

      const spacer = new St.Widget({ x_expand: true });
      topRow.add_child(spacer);

      this._actionRow = new St.BoxLayout({ vertical: false, visible: false });
      this._actionRow.set_style("spacing: 5px;");
      topRow.add_child(this._actionRow);
      this._actionRow.add_child(this._buildActionChip("W", OverlayAction.CloseWindow));
      this._actionRow.add_child(this._buildActionChip("Q", OverlayAction.QuitApp));

      // Live window preview: a Clutter.Clone of the window's compositor actor (the same
      // zero-copy GPU texture Mutter already composites — no screenshot, no portal, no capture
      // round-trip), scaled to fit the thumbnail box. Falls back to a plain dark box for entries
      // with no live actor (an app placeholder with no window, or a window whose actor isn't
      // realised). TODO(blur) on the scrim behind the card is still deferred (see theme.ts).
      root.add_child(this._buildThumbnail(entry));

      // Footer: app icon + title — the fast "which window is this" glance cue (darwin's own
      // reasoning for a deliberately prominent icon size, see OverlayTheme.Tile.iconSize).
      const footer = new St.BoxLayout({ vertical: false, x_expand: true });
      footer.set_style("spacing: 8px;");
      root.add_child(footer);

      const icon = entry.app.create_icon_texture(TILE.iconSize);
      footer.add_child(icon);

      this._titleLabel = new St.Label({ text: entry.title, x_expand: true, y_align: Clutter.ActorAlign.CENTER });
      footer.add_child(this._titleLabel);

      this._applyStyle();
    }

    /** A small W/Q chip that emits `action-clicked` and stops the press from bubbling up to
     * the tile's own `clicked` (which would otherwise also commit-activate this tile). */
    private _buildActionChip(glyph: string, action: OverlayAction): St.Bin {
      const chip = new St.Bin({
        reactive: true,
        width: ACTION_CHIP.size,
        height: ACTION_CHIP.size,
        x_align: Clutter.ActorAlign.CENTER,
        y_align: Clutter.ActorAlign.CENTER,
      });
      chip.set_style(
        `border-radius: ${ACTION_CHIP.radius}px; background-color: ${ACTION_CHIP.fill}; ` +
          `border: 1px solid ${ACTION_CHIP.border};`,
      );
      const glyphLabel = new St.Label({ text: glyph });
      glyphLabel.set_style(
        `color: ${ACTION_CHIP.glyph}; font-family: ${FONT.mono}; font-size: 9px; font-weight: 600; text-align: center;`,
      );
      chip.set_child(glyphLabel);
      chip.connect("button-press-event", () => {
        this.emit("action-clicked", action);
        return Clutter.EVENT_STOP;
      });
      return chip;
    }

    /** A live GPU-texture preview of the window: a `Clutter.Clone` of its compositor actor
     * (the same texture Mutter already composites — zero-copy, no screenshot/portal), scaled to
     * fit the fixed thumbnail box while preserving aspect ratio and centered. Returns a plain
     * dark box when there is no actor to clone (an app placeholder with no window, or a window
     * whose actor isn't realised). The clone is live: it tracks the real window's content. */
    private _buildThumbnail(entry: WindowEntry): St.Widget {
      const box = new St.Widget({
        width: TILE.thumbnailWidth,
        height: TILE.thumbnailHeight,
        x_align: Clutter.ActorAlign.CENTER,
        clip_to_allocation: true,
        layout_manager: new Clutter.BinLayout(),
      });
      box.set_style(
        `background-color: rgba(0, 0, 0, 0.3); border: 1px solid ${TILE.thumbnailBorder}; ` +
          `border-radius: ${TILE.thumbnailRadius}px; margin: 4px 0;`,
      );

      const actor = entry.window?.get_compositor_private() as Clutter.Actor | null | undefined;
      if (actor) {
        const [actorWidth, actorHeight] = actor.get_size();
        if (actorWidth > 0 && actorHeight > 0) {
          const scale = Math.min(TILE.thumbnailWidth / actorWidth, TILE.thumbnailHeight / actorHeight);
          const clone = new Clutter.Clone({
            source: actor,
            width: Math.round(actorWidth * scale),
            height: Math.round(actorHeight * scale),
            x_expand: false,
            y_expand: false,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
          });
          box.add_child(clone);
        }
      }
      return box;
    }

    setSelected(selected: boolean): void {
      if (this._selected === selected) return;
      this._selected = selected;
      this._applyStyle();
    }

    private _applyStyle(): void {
      const border = this._selected ? `2px solid ${ACCENT}` : `${TILE.borderWidth}px solid transparent`;
      const background = this._selected ? TILE.selectedWash : TILE.fillUnselected;
      const glow = this._selected ? `box-shadow: ${TILE.selectedGlow};` : "";
      this.set_style(`border-radius: ${TILE.radius}px; border: ${border}; background-color: ${background}; ${glow}`);

      this._indexLabel?.set_style(
        `color: ${this._selected ? INDEX_CHIP.textSelected : INDEX_CHIP.textDim}; font-family: ${FONT.mono}; ` +
          "font-size: 11px; font-weight: 700; text-align: center;",
      );
      this._titleLabel?.set_style(
        `color: ${this._selected ? COLOR.text : COLOR.dim}; font-family: ${FONT.ui}; font-size: ${TILE.titleSize}px; ` +
          `font-weight: ${this._selected ? 600 : 500};`,
      );
      if (this._actionRow) this._actionRow.visible = this._selected;
    }
  },
);

export class OverlayView implements Disposable {
  private readonly _callbacks: OverlayCallbacks;
  /** Long-lived: owns the scrim's own single `button-press-event` connection (click-outside),
   * which lives as long as the scrim actor itself. Per-tile connections use their own
   * short-lived `_tileBag` instead — see `_renderTiles()`. */
  private readonly _bag = new SignalBag();
  /** Recreated at the top of every `_renderTiles()` call so each render's tile signal
   * connections (`clicked`/`notify::hover`/`action-clicked`) are torn down together with that
   * render's tiles, instead of accumulating in `_bag` for the extension's entire enabled
   * lifetime — this extension is meant to stay resident all day, and every summon *and* every
   * in-session W/Q refresh calls `_renderTiles()` again. */
  private _tileBag = new SignalBag();
  /** Where `_buildActors()` parents `_scrim` — must be a descendant of whatever actor holds the
   * switcher's modal grab (see switcher.ts's file header for why a disjoint grab/visible-UI
   * split silently breaks hover/click while a session is revealed). Set once via `attachTo()`
   * before the first `show()`. */
  private _parent: Clutter.Actor | null = null;
  private _scrim: St.Widget | null = null;
  private _card: St.BoxLayout | null = null;
  private _tileContainer: St.BoxLayout | null = null;
  private _headerPill: St.Bin | null = null;
  private _headerPillLabel: St.Label | null = null;
  private _headerLabel: St.Label | null = null;
  private _headerCount: St.Label | null = null;
  // Tile is a registerClass() return value (a GObject.Object subclass constructor), not
  // directly nameable as a type.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private _tiles: any[] = [];
  private _selectedId: number | null = null;
  private _visible = false;

  constructor(callbacks: OverlayCallbacks) {
    this._callbacks = callbacks;
  }

  get isVisible(): boolean {
    return this._visible;
  }

  /** Sets the actor `_buildActors()` parents the scrim under. Must be called before the first
   * `show()` — Switcher calls this once, immediately after constructing its persistent grab
   * actor, so the overlay's own actors are always genuine descendants of the grabbed subtree by
   * the time anything can reveal them. */
  attachTo(parent: Clutter.Actor): void {
    this._parent = parent;
  }

  /** Builds the actor tree (once) and fades it in on the monitor under the cursor. Call this
   * for a fresh summon; use update()/setSelected() for changes while already shown. */
  show(mode: Mode, keyHint: string, entries: readonly WindowEntry[], selectedId: number | null): void {
    if (!this._scrim) this._buildActors();
    this._positionOnMonitorUnderCursor();
    this._renderModeHeader(mode, keyHint, entries.length);
    this._renderTiles(entries);
    this.setSelected(selectedId);

    const scrim = this._scrim!;
    scrim.show();
    scrim.opacity = 0;
    scrim.set_scale(MOTION.summonScaleFrom, MOTION.summonScaleFrom);
    scrim.ease({
      // camelCase is correct here, verified two ways against an initial (mistaken) review
      // finding that claimed otherwise: (1) GJS gives every multi-word GObject property BOTH a
      // native `underscore_case` *and* a native `camelCase` accessor (gjs.guide's GObject guide:
      // "If using native accessors, you can use `underscore_case` or `camelCase`" — e.g.
      // `actor.scaleX` and `actor.scale_x` are both real setters on the prototype, so
      // `GObject.Object.prototype.set()`'s `Object.assign(this, params)` invokes the correct
      // one either way); (2) `@girs/gnome-shell`'s own `EasingParamsWithProperties` type (the
      // real declared type of `.ease()`'s argument) types this exact field as `scaleX`/`scaleY`
      // — `scale_x`/`scale_y` isn't even in its `AnimatableActorFields` union, so passing those
      // instead would fail `tsc --noEmit` outright, not silently no-op.
      opacity: 255,
      scaleX: 1,
      scaleY: 1,
      duration: MOTION.fadeDurationMs,
      mode: Clutter.AnimationMode.EASE_OUT_QUAD,
    });
    this._visible = true;
  }

  /** Re-renders the tile list in place (no fade) — for a mode/scope change while the modifier
   * is still held. */
  update(mode: Mode, keyHint: string, entries: readonly WindowEntry[], selectedId: number | null): void {
    if (!this._scrim) return;
    this._renderModeHeader(mode, keyHint, entries.length);
    this._renderTiles(entries);
    this.setSelected(selectedId);
  }

  setSelected(id: number | null): void {
    this._selectedId = id;
    for (const tile of this._tiles) {
      tile.setSelected(tile.entry.id === id);
    }
  }

  /** Fades out and hides (but does not destroy) the actor tree — the common case, since the
   * next summon reuses it. Use destroy() for the hard, unconditional teardown in disable(). */
  hide(): void {
    if (!this._scrim || !this._visible) return;
    this._visible = false;
    const scrim = this._scrim;
    scrim.ease({
      opacity: 0,
      duration: MOTION.fadeDurationMs,
      mode: Clutter.AnimationMode.EASE_OUT_QUAD,
      onComplete: () => scrim.hide(),
    });
  }

  /** Unconditional, immediate teardown: disconnects every signal, destroys the actor tree,
   * nulls every reference. Must be safe to call from disable() at any point in the lifecycle,
   * including while a fade is mid-flight. */
  destroy(): void {
    this._bag.destroy();
    this._tileBag.destroy();
    this._scrim?.remove_all_transitions();
    this._scrim?.destroy();
    this._scrim = null;
    this._card = null;
    this._tileContainer = null;
    this._headerPill = null;
    this._headerPillLabel = null;
    this._headerLabel = null;
    this._headerCount = null;
    this._tiles = [];
    this._selectedId = null;
    this._visible = false;
    this._parent = null;
  }

  private _buildActors(): void {
    const scrim = new St.Widget({
      style_class: "zentab-scrim",
      reactive: true,
      visible: false,
      layout_manager: new Clutter.BinLayout(),
    });
    scrim.set_style(`background-color: ${BACKDROP.scrim};`);
    // TODO(blur): composite a real blur-behind under this scrim once St/Clutter exposes one
    // cheaply (see theme.ts). Until then this is a flat dim only.

    this._bag.track(
      scrim,
      scrim.connect("button-press-event", (_actor: St.Widget, event: Clutter.Event) => {
        // Only a press that lands on the scrim itself (not bubbled up from a tile) counts as
        // "outside" — St.Button children stop propagation on their own press by not
        // rethrowing, but we double-check via event coordinates against the card's box.
        if (this._card && this._pointInActor(this._card, event)) return Clutter.EVENT_PROPAGATE;
        this._callbacks.onClickOutside();
        return Clutter.EVENT_STOP;
      }),
    );

    const card = new St.BoxLayout({
      style_class: "zentab-card",
      vertical: true,
      x_align: Clutter.ActorAlign.CENTER,
      y_align: Clutter.ActorAlign.CENTER,
    });
    card.set_style(
      `background-color: ${CARD.fill}; border: ${CARD.borderWidth}px solid ${CARD.border}; ` +
        `border-radius: ${CARD.radius}px; padding: ${CARD.padding}px; min-width: ${CARD.minContentWidth}px;`,
    );
    scrim.add_child(card);

    // Header: key pill (trigger chord) · mode label · window count.
    const headerBox = new St.BoxLayout({ vertical: false, x_expand: true, y_align: Clutter.ActorAlign.CENTER });
    headerBox.set_style(`margin-bottom: ${HEADER.bottomGap}px;`);
    card.add_child(headerBox);

    const headerPill = new St.Bin({ visible: false, y_align: Clutter.ActorAlign.CENTER });
    headerPill.set_style(
      `border: 1px solid ${KEY_PILL.border}; border-radius: ${KEY_PILL.radius}px; ` +
        `padding: 3px ${KEY_PILL.hPad}px; margin-right: ${HEADER.gap}px;`,
    );
    const headerPillLabel = new St.Label();
    headerPillLabel.set_style(
      `color: ${KEY_PILL.text}; font-family: ${FONT.mono}; font-size: ${KEY_PILL.fontSize}px; font-weight: 600;`,
    );
    headerPill.set_child(headerPillLabel);
    headerBox.add_child(headerPill);

    const headerLabel = new St.Label({ x_expand: true, y_align: Clutter.ActorAlign.CENTER });
    headerLabel.set_style(
      `color: ${HEADER.labelColor}; font-family: ${FONT.ui}; font-size: ${HEADER.labelSize}px; font-weight: 600;`,
    );
    headerBox.add_child(headerLabel);

    const headerCount = new St.Label({ y_align: Clutter.ActorAlign.CENTER });
    headerCount.set_style(
      `color: ${HEADER.countColor}; font-family: ${FONT.mono}; font-size: ${HEADER.countSize}px;`,
    );
    headerBox.add_child(headerCount);

    const divider = new St.Widget({ x_expand: true, height: 1 });
    divider.set_style(`background-color: ${HAIRLINE}; margin-bottom: ${HEADER.bottomGap}px;`);
    card.add_child(divider);

    // Tile grid: a vertical stack of horizontal rows, each centered — St/Clutter has no CSS
    // grid/flex-wrap, so _renderTiles wraps entries into rows of TILE.maxColumns itself.
    const tileContainer = new St.BoxLayout({ vertical: true, x_expand: true });
    card.add_child(tileContainer);

    // Parented under whatever `attachTo()` was given (Switcher's persistent grab actor), NOT
    // `Main.layoutManager.addChrome` directly — the scrim/card/tiles must be genuine
    // descendants of the grabbed actor for pointer picking (hover, click) to reach them once a
    // session reveals; a sibling actor outside the grabbed subtree simply never receives
    // pointer events while `Main.pushModal()` holds the grab (see switcher.ts's file header).
    // The grab actor itself is the one thing added via `addChrome`.
    this._parent?.add_child(scrim);

    this._scrim = scrim;
    this._card = card;
    this._tileContainer = tileContainer;
    this._headerPill = headerPill;
    this._headerPillLabel = headerPillLabel;
    this._headerLabel = headerLabel;
    this._headerCount = headerCount;
  }

  private _renderModeHeader(mode: Mode, keyHint: string, count: number): void {
    if (this._headerPill && this._headerPillLabel) {
      this._headerPill.visible = keyHint.length > 0;
      this._headerPillLabel.text = keyHint;
    }
    if (this._headerLabel) this._headerLabel.text = MODE_LABEL[mode];
    if (this._headerCount) this._headerCount.text = `${count} ${count === 1 ? "window" : "windows"}`;
  }

  /** Rebuilds the tile grid from scratch — called on every `show()` AND every in-session
   * refresh (`update()`, which `Switcher._performCloseOrQuit` triggers after every W/Q close).
   * `_tileBag` is destroyed and recreated here, every call, so each generation's tile signal
   * connections are torn down together with that generation's tiles instead of accumulating in
   * a bag that only ever gets drained at `OverlayView.destroy()` — this extension is meant to
   * stay resident (and get re-summoned) all day, so a bag scoped to the extension's whole
   * lifetime would otherwise grow by 3 connections per tile, forever, on every single summon. */
  private _renderTiles(entries: readonly WindowEntry[]): void {
    const container = this._tileContainer;
    if (!container) return;

    this._tileBag.destroy();
    this._tileBag = new SignalBag();

    for (const tile of this._tiles) tile.destroy();
    this._tiles = [];
    container.destroy_all_children();

    const columns = Math.max(1, Math.min(TILE.maxColumns, entries.length));
    let row: St.BoxLayout | null = null;

    entries.forEach((entry, index) => {
      if (index % columns === 0) {
        row = new St.BoxLayout({ vertical: false, x_expand: true, x_align: Clutter.ActorAlign.CENTER });
        row.set_style(`spacing: ${TILE.spacing}px; margin-bottom: ${TILE.spacing}px;`);
        container.add_child(row);
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- see the _tiles field.
      const tile = new (Tile as any)(entry, index);
      this._tileBag.track(
        tile,
        tile.connect("clicked", () => this._callbacks.onTileClicked(entry)),
      );
      this._tileBag.track(
        tile,
        tile.connect("notify::hover", () => {
          if (tile.hover) this._callbacks.onHoverSelect(entry);
        }),
      );
      this._tileBag.track(
        tile,
        tile.connect("action-clicked", (_t: unknown, actionName: string) =>
          this._callbacks.onAction(entry, actionName as OverlayAction),
        ),
      );
      row!.add_child(tile);
      this._tiles.push(tile);
    });
  }

  /** Renders on whichever monitor the cursor is on right now (VISION/task: "Multi-monitor:
   * render on the monitor under the cursor"), matching every mode's summon-time monitor
   * resolution in windows.ts. */
  private _positionOnMonitorUnderCursor(): void {
    if (!this._scrim) return;
    try {
      const monitorIndex = global.display.get_current_monitor();
      const geometry = Main.layoutManager.monitors[monitorIndex] ?? Main.layoutManager.primaryMonitor;
      if (!geometry) return;
      this._scrim.set_position(geometry.x, geometry.y);
      this._scrim.set_size(geometry.width, geometry.height);
    } catch (error) {
      logError(error, "OverlayView._positionOnMonitorUnderCursor");
    }
  }

  /** Simple bounding-box hit test in stage coordinates — enough to distinguish "click landed
   * on the card" from "click landed on the scrim" without depending on a specific Clutter
   * point/box API shape that may vary across the GNOME versions we target. */
  private _pointInActor(actor: St.Widget, event: Clutter.Event): boolean {
    const [eventX, eventY] = event.get_coords();
    const [actorX, actorY] = actor.get_transformed_position();
    const [width, height] = actor.get_transformed_size();
    return eventX >= actorX && eventX <= actorX + width && eventY >= actorY && eventY <= actorY + height;
  }
}
