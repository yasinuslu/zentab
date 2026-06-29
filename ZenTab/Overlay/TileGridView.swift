import AppKit

/// The hot path: a hand-rolled flow grid of recycled `CALayer` tiles. Each tile is
/// a window's thumbnail (or app icon + title until/if a thumbnail loads) with a
/// selection border. All mutations run inside a single `CATransaction` with implicit
/// animations disabled, so navigation is instant. Keyboard and mouse both drive one
/// shared selection (the view just reports hover/click; the controller owns state).
final class TileGridView: NSView {
  var onHover: (@MainActor (Int) -> Void)?
  var onActivate: (@MainActor (Int) -> Void)?

  private let tileSize = CGSize(width: 240, height: 176)
  private let spacing: CGFloat = 16
  private let padding: CGFloat = 24
  private let barHeight: CGFloat = 36
  private let maxColumns = 5

  private final class Tile {
    let container = CALayer()
    let thumbnail = CALayer()
    let icon = CALayer()
    let title = CATextLayer()
    var windowID: CGWindowID = 0
  }

  private var tiles: [Tile] = []
  private var windows: [WindowInfo] = []
  private var thumbnails: [CGWindowID: CGImage] = [:]
  private var selectedIndex = 0
  private var visibleCount = 0
  private var columns = 1
  private var trackingArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not supported") }

  override var isFlipped: Bool { false }

  // MARK: - Configuration

  /// Lay out `windows`, select `selectedIndex`, and return the content size the
  /// panel should adopt. Tiles are reused across summons.
  func configure(windows: [WindowInfo], selectedIndex: Int) -> NSSize {
    self.windows = windows
    self.thumbnails = [:]
    self.selectedIndex = selectedIndex
    self.visibleCount = windows.count

    let count = windows.count
    columns = max(1, min(maxColumns, count))
    let rows = max(1, Int(ceil(Double(count) / Double(columns))))
    let contentWidth =
      padding * 2 + CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
    let contentHeight = padding * 2 + CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * spacing

    withoutAnimations {
      guard let root = layer else { return }
      while tiles.count < count {
        let tile = makeTile()
        root.addSublayer(tile.container)
        tiles.append(tile)
      }
      for (index, tile) in tiles.enumerated() {
        guard index < count else {
          tile.container.isHidden = true
          continue
        }
        tile.container.isHidden = false
        let row = index / columns
        let column = index % columns
        let x = padding + CGFloat(column) * (tileSize.width + spacing)
        let yFromTop = padding + CGFloat(row) * (tileSize.height + spacing)
        tile.container.frame = CGRect(
          x: x, y: contentHeight - yFromTop - tileSize.height,
          width: tileSize.width, height: tileSize.height)
        fill(tile, with: windows[index], selected: index == selectedIndex)
      }
    }

    return NSSize(width: contentWidth, height: contentHeight)
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

    return tile
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
    if let index = tileIndex(at: event) { onHover?(index) }
  }

  override func mouseDown(with event: NSEvent) {
    if let index = tileIndex(at: event) { onActivate?(index) }
  }

  private func tileIndex(at event: NSEvent) -> Int? {
    let point = convert(event.locationInWindow, from: nil)
    for index in 0..<visibleCount where tiles[index].container.frame.contains(point) {
      return index
    }
    return nil
  }
}
