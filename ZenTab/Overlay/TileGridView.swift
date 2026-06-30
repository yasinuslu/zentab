import AppKit

/// The hot path: a hand-rolled flow grid of recycled `CALayer` tiles. Each tile is
/// a window's thumbnail (or app icon + title until/if a thumbnail loads) with a
/// selection border. All mutations run inside a single `CATransaction` with implicit
/// animations disabled, so navigation is instant. Keyboard and mouse both drive one
/// shared selection (the view just reports hover/click; the controller owns state).
///
/// In the curation modes the list is split at `hereStart` into an ELSEWHERE grid above a
/// HERE strip, divided by a labeled line. Summon/fling are given an explicit fly animation
/// via a transient "ghost" layer (decoupled from the recycled tiles): the ghost is snapshotted
/// at the moving window's old slot, the grid relays out instantly underneath, and the ghost
/// then flies to the window's new slot (summon) or off the edge (fling).
final class TileGridView: NSView {
  var onHover: (@MainActor (Int) -> Void)?
  var onActivate: (@MainActor (Int) -> Void)?
  /// The close (✕) button on the hovered tile was clicked.
  var onClose: (@MainActor (Int) -> Void)?
  /// The quit (⏻) button on the hovered tile was clicked.
  var onQuit: (@MainActor (Int) -> Void)?

  private let tileSize = CGSize(width: 240, height: 176)
  private let spacing: CGFloat = 16
  private let padding: CGFloat = 24
  private let barHeight: CGFloat = 36
  private let maxColumns = 5
  private let buttonSize: CGFloat = 22
  private let buttonInset: CGFloat = 8
  private let dividerBand: CGFloat = 30

  /// Which tile's close/quit buttons to draw: the one physically under the cursor.
  /// Tracked separately from the controller's selection (which the keyboard also
  /// moves) because the buttons follow the mouse, per VISION.
  private enum TileButton { case close, quit }

  private final class Tile {
    let container = CALayer()
    let thumbnail = CALayer()
    let icon = CALayer()
    let title = CATextLayer()
    let closeButton = CALayer()
    let quitButton = CALayer()
    var windowID: CGWindowID = 0
  }

  private var tiles: [Tile] = []
  private var windows: [WindowInfo] = []
  private var hereStart = 0
  private var thumbnails: [CGWindowID: CGImage] = [:]
  private var selectedIndex = 0
  private var visibleCount = 0
  private var hoveredTileIndex: Int?
  private var trackingArea: NSTrackingArea?

  // The two-zone divider (line + "here" label), shown only when both zones are present.
  private let dividerLine = CALayer()
  private let hereLabel = CATextLayer()

  // The transient fly animation layer (summon/fling), snapshotted before a relayout.
  private var ghost: CALayer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    setUpDivider()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not supported") }

  override var isFlipped: Bool { false }

  private func setUpDivider() {
    dividerLine.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    dividerLine.isHidden = true
    hereLabel.string = "HERE"
    hereLabel.fontSize = 10
    hereLabel.foregroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
    hereLabel.alignmentMode = .center
    hereLabel.contentsScale = 2
    hereLabel.isHidden = true
    layer?.addSublayer(dividerLine)
    layer?.addSublayer(hereLabel)
  }

  // MARK: - Configuration

  /// Lay out `windows` split at `hereStart` (grid above, strip below), select
  /// `selectedIndex`, and return the content size the panel should adopt. Tiles are reused
  /// across summons. `keepThumbnails` preserves already-captured frames across a relayout.
  @discardableResult
  func configure(
    windows: [WindowInfo], hereStart: Int, selectedIndex: Int, keepThumbnails: Bool = false
  ) -> NSSize {
    self.windows = windows
    self.hereStart = max(0, min(hereStart, windows.count))
    if keepThumbnails {
      let ids = Set(windows.map(\.windowID))
      thumbnails = thumbnails.filter { ids.contains($0.key) }
    } else {
      thumbnails = [:]
    }
    self.selectedIndex = selectedIndex
    self.visibleCount = windows.count

    let count = windows.count
    let gridCount = self.hereStart
    let stripCount = count - gridCount
    let twoZone = gridCount > 0 && stripCount > 0

    let grid = twoZone ? metrics(gridCount) : metrics(count)
    let strip = twoZone ? metrics(stripCount) : Metrics.zero
    let dividerH = twoZone ? dividerBand : 0
    let contentWidth = padding * 2 + max(grid.width, strip.width)
    let contentHeight = padding * 2 + grid.height + dividerH + strip.height

    withoutAnimations {
      guard let root = layer else { return }
      while tiles.count < count {
        let tile = makeTile()
        root.addSublayer(tile.container)
        tiles.append(tile)
      }
      for index in count..<tiles.count { tiles[index].container.isHidden = true }

      if twoZone {
        layoutZone(0..<gridCount, columns: grid.columns, topFromTop: padding, contentHeight: contentHeight)
        layoutZone(
          gridCount..<count, columns: strip.columns, topFromTop: padding + grid.height + dividerH,
          contentHeight: contentHeight)
        let boundaryFromTop = padding + grid.height + dividerH / 2
        dividerLine.frame = CGRect(
          x: padding, y: contentHeight - boundaryFromTop, width: contentWidth - padding * 2, height: 1)
        hereLabel.frame = CGRect(
          x: 0, y: contentHeight - boundaryFromTop - 16, width: contentWidth, height: 13)
        dividerLine.isHidden = false
        hereLabel.isHidden = false
      } else {
        layoutZone(0..<count, columns: grid.columns, topFromTop: padding, contentHeight: contentHeight)
        dividerLine.isHidden = true
        hereLabel.isHidden = true
      }
    }

    return NSSize(width: contentWidth, height: contentHeight)
  }

  private struct Metrics {
    let columns: Int
    let rows: Int
    let width: CGFloat
    let height: CGFloat
    static let zero = Metrics(columns: 0, rows: 0, width: 0, height: 0)
  }

  /// Flow-grid metrics (no outer padding) for `n` tiles.
  private func metrics(_ n: Int) -> Metrics {
    guard n > 0 else { return .zero }
    let columns = max(1, min(maxColumns, n))
    let rows = Int(ceil(Double(n) / Double(columns)))
    let width = CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
    let height = CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * spacing
    return Metrics(columns: columns, rows: rows, width: width, height: height)
  }

  /// Position the tiles in `range` as a flow grid whose top edge is `topFromTop` below the
  /// content's top, filling each with its window. `contentHeight` converts to bottom-origin.
  private func layoutZone(_ range: Range<Int>, columns: Int, topFromTop: CGFloat, contentHeight: CGFloat) {
    for (offset, index) in range.enumerated() {
      let tile = tiles[index]
      tile.container.isHidden = false
      let row = offset / columns
      let column = offset % columns
      let x = padding + CGFloat(column) * (tileSize.width + spacing)
      let yFromTop = topFromTop + CGFloat(row) * (tileSize.height + spacing)
      tile.container.frame = CGRect(
        x: x, y: contentHeight - yFromTop - tileSize.height,
        width: tileSize.width, height: tileSize.height)
      fill(tile, with: windows[index], selected: index == selectedIndex)
    }
  }

  /// Upgrade tiles to live thumbnails as capture completes (progressive).
  func applyThumbnails(_ images: [CGWindowID: CGImage]) {
    guard !images.isEmpty else { return }
    thumbnails.merge(images) { _, new in new }
    withoutAnimations {
      for tile in tiles where !tile.container.isHidden {
        if let image = thumbnails[tile.windowID] {
          tile.thumbnail.contents = image
        }
      }
    }
  }

  /// Move the selection highlight without re-laying anything out.
  func updateSelection(_ index: Int) {
    selectedIndex = index
    withoutAnimations {
      for (i, tile) in tiles.enumerated() where i < visibleCount {
        applySelection(tile, selected: i == index)
      }
    }
  }

  // MARK: - Fly animations (summon / fling)

  /// Snapshot the moving window's tile into a ghost layer, BEFORE the relayout. The ghost
  /// stays put while the grid relays out underneath; `flyGhostToStrip` / `flyGhostOff` then
  /// animates it. No-op if the window has no visible tile.
  func beginGhost(windowID: CGWindowID) {
    ghost?.removeFromSuperlayer()
    ghost = nil
    guard let tile = visibleTile(for: windowID), let root = layer else { return }
    let snapshot = makeGhost(windowID: windowID, frame: tile.container.frame)
    withoutAnimations { root.addSublayer(snapshot) }
    ghost = snapshot
  }

  /// Fly the ghost from its old slot down to the window's new (strip) slot, then remove it.
  func flyGhostToStrip(windowID: CGWindowID) {
    guard let ghost else { return }
    self.ghost = nil
    guard let tile = visibleTile(for: windowID) else {
      ghost.removeFromSuperlayer()
      return
    }
    flyGhost(ghost, to: tile.container.frame, fade: false)
  }

  /// Fly the ghost off the matching edge (← left, → right, ↑ away/up) while fading, then
  /// remove it.
  func flyGhostOff(direction: FlingDirection) {
    guard let ghost else { return }
    self.ghost = nil
    var target = ghost.frame
    switch direction {
    case .left: target.origin.x -= bounds.width
    case .right: target.origin.x += bounds.width
    case .away: target.origin.y += bounds.height  // bottom-origin: up = +y
    }
    flyGhost(ghost, to: target, fade: true)
  }

  private func flyGhost(_ ghost: CALayer, to target: CGRect, fade: Bool) {
    let from = ghost.frame
    CATransaction.begin()
    CATransaction.setCompletionBlock { ghost.removeFromSuperlayer() }
    let position = CABasicAnimation(keyPath: "position")
    position.fromValue = NSValue(point: CGPoint(x: from.midX, y: from.midY))
    position.toValue = NSValue(point: CGPoint(x: target.midX, y: target.midY))
    let group = CAAnimationGroup()
    group.animations = [position]
    group.duration = 0.24
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    group.fillMode = .forwards
    group.isRemovedOnCompletion = false
    ghost.frame = target
    if fade {
      let opacity = CABasicAnimation(keyPath: "opacity")
      opacity.fromValue = 1.0
      opacity.toValue = 0.0
      group.animations?.append(opacity)
      ghost.opacity = 0
    }
    ghost.add(group, forKey: "fly")
    CATransaction.commit()
  }

  private func visibleTile(for windowID: CGWindowID) -> Tile? {
    tiles.prefix(visibleCount).first { !$0.container.isHidden && $0.windowID == windowID }
  }

  private func makeGhost(windowID: CGWindowID, frame: CGRect) -> CALayer {
    let ghost = CALayer()
    ghost.frame = frame
    ghost.cornerRadius = 12
    ghost.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    ghost.borderColor = NSColor.controlAccentColor.cgColor
    ghost.borderWidth = 3
    ghost.masksToBounds = true
    let inset: CGFloat = 8
    let thumb = CALayer()
    thumb.frame = CGRect(
      x: inset, y: barHeight, width: frame.width - inset * 2, height: frame.height - barHeight - inset)
    thumb.contentsGravity = .resizeAspect
    thumb.contents = thumbnails[windowID]
    thumb.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    thumb.cornerRadius = 6
    thumb.masksToBounds = true
    ghost.addSublayer(thumb)
    return ghost
  }

  // MARK: - Tile building

  private func makeTile() -> Tile {
    let tile = Tile()
    tile.container.cornerRadius = 12
    tile.container.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
    tile.container.borderColor = NSColor.controlAccentColor.cgColor
    tile.container.masksToBounds = true

    let inset: CGFloat = 8
    tile.thumbnail.frame = CGRect(
      x: inset, y: barHeight,
      width: tileSize.width - inset * 2, height: tileSize.height - barHeight - inset)
    tile.thumbnail.contentsGravity = .resizeAspect
    tile.thumbnail.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    tile.thumbnail.cornerRadius = 6
    tile.thumbnail.masksToBounds = true
    tile.container.addSublayer(tile.thumbnail)

    tile.icon.frame = CGRect(x: inset, y: (barHeight - 22) / 2, width: 22, height: 22)
    tile.icon.contentsGravity = .resizeAspect
    tile.container.addSublayer(tile.icon)

    tile.title.frame = CGRect(
      x: inset + 30, y: (barHeight - 18) / 2, width: tileSize.width - inset * 2 - 30, height: 18)
    tile.title.fontSize = 13
    tile.title.foregroundColor = NSColor.white.cgColor
    tile.title.truncationMode = .end
    tile.title.alignmentMode = .left
    tile.title.contentsScale = 2
    tile.container.addSublayer(tile.title)

    // Close (✕) / quit (⏻) badges, top-right of the thumbnail. Hidden until this tile
    // is the one under the cursor; added last so they sit above the thumbnail.
    let top = tileSize.height - buttonInset - buttonSize
    let quitX = tileSize.width - buttonInset - buttonSize
    configureBadge(tile.quitButton, glyph: "⏻", x: quitX, y: top)
    configureBadge(tile.closeButton, glyph: "✕", x: quitX - buttonSize - 6, y: top)
    tile.container.addSublayer(tile.closeButton)
    tile.container.addSublayer(tile.quitButton)

    return tile
  }

  /// A small round badge with a centered glyph, hidden by default. Built once per tile
  /// and reused; only its visibility toggles as the hover moves.
  private func configureBadge(_ badge: CALayer, glyph: String, x: CGFloat, y: CGFloat) {
    badge.frame = CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
    badge.cornerRadius = buttonSize / 2
    badge.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
    badge.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    badge.borderWidth = 1
    badge.isHidden = true
    let label = CATextLayer()
    label.string = glyph
    label.fontSize = 12
    label.foregroundColor = NSColor.white.cgColor
    label.alignmentMode = .center
    label.contentsScale = 2
    label.frame = CGRect(x: 0, y: (buttonSize - 16) / 2, width: buttonSize, height: 16)
    badge.addSublayer(label)
  }

  private func fill(_ tile: Tile, with window: WindowInfo, selected: Bool) {
    tile.windowID = window.windowID
    tile.title.string = window.title.isEmpty ? window.appName : window.title
    tile.icon.contents = appIcon(for: window.pid)
    tile.thumbnail.contents = thumbnails[window.windowID]
    applySelection(tile, selected: selected)
  }

  private func applySelection(_ tile: Tile, selected: Bool) {
    tile.container.borderWidth = selected ? 3 : 0
    tile.container.backgroundColor =
      NSColor.black.withAlphaComponent(selected ? 0.4 : 0.22).cgColor
  }

  private func appIcon(for pid: pid_t) -> CGImage? {
    guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  private func withoutAnimations(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }

  // MARK: - Mouse

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    let index = tileIndex(at: convert(event.locationInWindow, from: nil))
    if index != hoveredTileIndex {
      hoveredTileIndex = index
      updateButtonVisibility()
    }
    if let index { onHover?(index) }
  }

  override func mouseExited(with event: NSEvent) {
    guard hoveredTileIndex != nil else { return }
    hoveredTileIndex = nil
    updateButtonVisibility()
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let index = tileIndex(at: point) else { return }
    // A click on the hovered tile's badges closes/quits; anywhere else activates.
    if index == hoveredTileIndex, let button = buttonHit(at: point, in: tiles[index]) {
      switch button {
      case .close: onClose?(index)
      case .quit: onQuit?(index)
      }
      return
    }
    onActivate?(index)
  }

  private func tileIndex(at point: CGPoint) -> Int? {
    for index in 0..<visibleCount where tiles[index].container.frame.contains(point) {
      return index
    }
    return nil
  }

  /// Which badge (if any) `point` lands on, in the tile's container coordinates.
  private func buttonHit(at point: CGPoint, in tile: Tile) -> TileButton? {
    let origin = tile.container.frame.origin
    if tile.closeButton.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) { return .close }
    if tile.quitButton.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) { return .quit }
    return nil
  }

  /// Re-detect the hovered tile from the current cursor position, and show its badges.
  /// The controller calls this after a show/relayout positions the panel (no
  /// mouse-move fires, yet the window set / panel frame shifted under the cursor).
  func refreshHoveredTile() {
    let next =
      window.map { tileIndex(at: convert($0.mouseLocationOutsideOfEventStream, from: nil)) }
      ?? nil
    if next != hoveredTileIndex {
      hoveredTileIndex = next
    }
    updateButtonVisibility()
  }

  /// Show the close/quit badges on the hovered tile only.
  private func updateButtonVisibility() {
    withoutAnimations {
      for (index, tile) in tiles.enumerated() {
        let show = index == hoveredTileIndex && index < visibleCount
        tile.closeButton.isHidden = !show
        tile.quitButton.isHidden = !show
      }
    }
  }
}
