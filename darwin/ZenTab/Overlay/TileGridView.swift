import AppKit

/// The hot path: a hand-rolled board of recycled `CALayer` tiles inside one frosted card,
/// a faithful native rendering of the **website overlay** (`website/src/pages/Overlay.tsx`).
/// All mutations run inside a single `CATransaction` with implicit animations disabled, so
/// navigation is instant. Keyboard and mouse both drive one shared selection (the view
/// reports hover/click; the controller owns state).
///
/// One centered card holds everything: a **header** (key pill · mode label · count), the
/// **tiles**, and a **footer** hint row. Two content layouts, chosen by `hereStart`:
///  • **Flat** (`hereStart == 0` or `== count`, e.g. the everyday Cmd+Tab list): one grid.
///  • **Two-zone** (the cross-Space modes): an **ELSEWHERE** block above a hairline divider
///    and a **THIS SPACE** block below, same-size tiles in both (matching the website). The
///    `↓` summon flies a tile down from ELSEWHERE into THIS SPACE; fling sends it off an edge.
///
/// Each selected tile lifts with a soft accent glow and shows its action chips (↓ here · W ·
/// Q); every tile carries a 1…9 index chip and, when relevant, a status badge.
final class TileGridView: NSView {
  /// The header strip's two pieces: the trigger-key glyphs and the mode label.
  struct Header: Equatable {
    var key: String
    var label: String
  }

  var onHover: (@MainActor (Int) -> Void)?
  var onActivate: (@MainActor (Int) -> Void)?
  /// A click landed on the dimmed void, not on a tile — VISION's one cancel gesture.
  var onCancel: (@MainActor () -> Void)?
  /// The close (W) chip on the selected tile was clicked.
  var onClose: (@MainActor (Int) -> Void)?
  /// The quit (Q) chip on the selected tile was clicked.
  var onQuit: (@MainActor (Int) -> Void)?
  /// The "↓ here" chip on the selected (elsewhere) tile was clicked.
  var onSummon: (@MainActor (Int) -> Void)?

  private final class Tile {
    let container = CALayer()
    let thumbnail = CALayer()
    let icon = CALayer()
    let title = CATextLayer()
    let indexBadge = CALayer()
    let indexText = CATextLayer()
    let hereChip = CALayer()  // "↓ here"
    let closeChip = CALayer()  // "W"
    let quitChip = CALayer()  // "Q"
    let statusBadge = CALayer()  // "Minimized" / "Fullscreen"
    let statusText = CATextLayer()
    var windowID: CGWindowID = 0
    var isElsewhere = false
  }

  private enum Zone { case flat, here, elsewhere }
  /// Which chip (if any) a click landed on, for the selected tile.
  private enum TileChip { case here, close, quit }

  private var tiles: [Tile] = []
  private var windows: [WindowInfo] = []
  private var hereStart = 0
  private var thumbnails: [CGWindowID: CGImage] = [:]
  private var selectedIndex = 0
  private var visibleCount = 0
  private var hoveredTileIndex: Int?
  private var trackingArea: NSTrackingArea?
  private var header = Header(key: "", label: "")

  // Chrome: one frosted card, dividers, the header strip, the zone heads, the footer.
  private let card = CALayer()
  private let zoneDivider = CALayer()
  private let footerDivider = CALayer()
  private let keyPill = CALayer()
  private let keyPillText = CATextLayer()
  private let headerLabel = CATextLayer()
  private let headerCount = CATextLayer()
  private let elsewhereHead = CATextLayer()
  private let elsewhereHint = CATextLayer()
  private let hereHead = CATextLayer()
  private let emptyHereHint = CATextLayer()
  private let footerLeft = CATextLayer()
  private let footerRight = CATextLayer()

  // The transient fly animation layer (summon/fling), snapshotted before a relayout.
  private var ghost: CALayer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    setUpChrome()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not supported") }

  override var isFlipped: Bool { false }

  func setHeader(_ header: Header) { self.header = header }

  /// Play the website's `ovIn` appear: a quick scale .97 → 1 around the screen center (the
  /// card sits there), paired with the controller's alpha fade. Transient — the model value
  /// stays identity, so nothing is left scaled.
  func playSummon() {
    guard let root = layer else { return }
    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = OverlayTheme.summonScaleFrom
    scale.toValue = 1.0
    scale.duration = OverlayTheme.fadeDuration
    scale.timingFunction = OverlayTheme.summonEase
    root.add(scale, forKey: "summon")
  }

  // MARK: - Chrome

  private func setUpChrome() {
    guard let root = layer else { return }

    card.cornerRadius = OverlayTheme.Card.radius
    card.backgroundColor = OverlayTheme.Card.fill.cgColor
    card.borderColor = OverlayTheme.Card.border.cgColor
    card.borderWidth = OverlayTheme.Card.borderWidth
    card.shadowColor = OverlayTheme.Card.shadowColor.cgColor
    card.shadowOpacity = 1
    card.shadowRadius = OverlayTheme.Card.shadowRadius
    card.shadowOffset = OverlayTheme.Card.shadowOffset
    card.isHidden = true
    root.addSublayer(card)

    for divider in [zoneDivider, footerDivider] {
      divider.backgroundColor = OverlayTheme.Card.divider.cgColor
      divider.isHidden = true
      root.addSublayer(divider)
    }

    keyPill.cornerRadius = OverlayTheme.Header.pillRadius
    keyPill.backgroundColor = OverlayTheme.Header.pillFill.cgColor
    keyPill.borderColor = OverlayTheme.Header.pillBorder.cgColor
    keyPill.borderWidth = 1
    keyPill.isHidden = true
    keyPillText.alignmentMode = .center
    keyPillText.contentsScale = OverlayTheme.textScale
    keyPill.addSublayer(keyPillText)
    root.addSublayer(keyPill)

    for label in [
      headerLabel, headerCount, elsewhereHead, elsewhereHint, hereHead, emptyHereHint, footerLeft, footerRight,
    ] {
      label.contentsScale = OverlayTheme.textScale
      label.truncationMode = .end
      label.isHidden = true
      root.addSublayer(label)
    }
  }

  // MARK: - Configuration

  /// Lay out `windows` (split at `hereStart`) to fill the view's current bounds, and select
  /// `selectedIndex`. Tiles are reused across summons. `keepThumbnails` preserves already
  /// captured frames across a relayout. The controller sizes the panel to the active screen
  /// *before* calling this, so the layout reads `bounds` as the full screen.
  func configure(
    windows: [WindowInfo], hereStart: Int, selectedIndex: Int, header: Header? = nil,
    keepThumbnails: Bool = false
  ) {
    if let header { self.header = header }
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

    withoutAnimations {
      guard let root = layer else { return }
      while tiles.count < windows.count {
        let tile = makeTile()
        root.addSublayer(tile.container)
        tiles.append(tile)
      }
      for index in windows.count..<tiles.count { tiles[index].container.isHidden = true }
      applyLayout()
    }
  }

  // MARK: - Layout

  private struct Grid {
    let columns: Int
    let rows: Int
    let width: CGFloat
    let height: CGFloat
  }

  /// Flow-grid metrics (no outer padding) for `n` tiles of `size`.
  private func grid(_ n: Int, tile size: CGSize) -> Grid {
    guard n > 0 else { return Grid(columns: 0, rows: 0, width: 0, height: 0) }
    let spacing = OverlayTheme.Tile.spacing
    let columns = max(1, min(OverlayTheme.Tile.maxColumns, n))
    let rows = Int(ceil(Double(n) / Double(columns)))
    let width = CGFloat(columns) * size.width + CGFloat(columns - 1) * spacing
    let height = CGFloat(rows) * size.height + CGFloat(rows - 1) * spacing
    return Grid(columns: columns, rows: rows, width: width, height: height)
  }

  /// Position the card and everything inside it for the current window list.
  private func applyLayout() {
    let count = windows.count
    let twoZone = hereStart > 0 && hereStart < count
    let pad = OverlayTheme.Card.padding
    let tileSize = OverlayTheme.Tile.size
    let zoneHeadBlock = OverlayTheme.Zone.headHeight + OverlayTheme.Zone.headBottomGap

    // Content metrics.
    let eGrid = twoZone ? grid(hereStart, tile: tileSize) : Grid(columns: 0, rows: 0, width: 0, height: 0)
    let hereCount = count - hereStart
    let hGrid = twoZone ? grid(hereCount, tile: tileSize) : Grid(columns: 0, rows: 0, width: 0, height: 0)
    let flatGrid = twoZone ? Grid(columns: 0, rows: 0, width: 0, height: 0) : grid(count, tile: tileSize)

    var contentW: CGFloat
    var contentH: CGFloat
    if twoZone {
      contentW = max(eGrid.width, hGrid.width)
      let hereInner = hereCount > 0 ? hGrid.height : OverlayTheme.Zone.emptyHintHeight
      let elsewhereBlock = zoneHeadBlock + eGrid.height
      let hereBlock = zoneHeadBlock + hereInner
      contentH = elsewhereBlock + OverlayTheme.Zone.gap + OverlayTheme.Zone.dividerTopGap + hereBlock
    } else {
      contentW = flatGrid.width
      contentH = flatGrid.height
    }

    let innerW = max(contentW, OverlayTheme.Card.minContentWidth)
    let cardW = innerW + pad * 2
    let headerH = OverlayTheme.Header.height
    let footerH = OverlayTheme.Footer.height
    let cardH = 2 * pad + footerH + OverlayTheme.Footer.topGap + contentH + OverlayTheme.Header.bottomGap + headerH
    let cardX = ((bounds.width - cardW) / 2).rounded()
    let cardY = ((bounds.height - cardH) / 2).rounded()

    card.frame = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
    card.isHidden = false

    let innerLeft = cardX + pad
    let innerRight = cardX + cardW - pad
    let innerWidth = innerRight - innerLeft
    let topY = cardY + cardH - pad

    layoutHeader(innerLeft: innerLeft, innerWidth: innerWidth, top: topY, height: headerH, count: count)

    // Footer (bottom), with its hairline rule.
    let footerBottom = cardY + pad
    footerDivider.frame = CGRect(
      x: innerLeft, y: footerBottom + footerH + OverlayTheme.Footer.topGap / 2, width: innerWidth, height: 1)
    footerDivider.isHidden = false
    layoutFooter(left: innerLeft, right: innerRight, bottom: footerBottom, height: footerH, board: twoZone)

    // Content sits between the header and the footer.
    let contentTop = footerBottom + footerH + OverlayTheme.Footer.topGap + contentH

    if twoZone {
      layoutTwoZone(
        contentTop: contentTop, cardX: cardX, cardW: cardW, eGrid: eGrid, hGrid: hGrid,
        hereCount: hereCount, zoneHeadBlock: zoneHeadBlock)
    } else {
      hideTwoZoneChrome()
      layoutTiles(
        0..<count, gridOrigin: CGPoint(x: innerLeft, y: contentTop - flatGrid.height),
        gridHeight: flatGrid.height, columns: flatGrid.columns, availableWidth: innerWidth, tile: tileSize,
        zone: .flat)
    }
  }

  private func layoutHeader(
    innerLeft: CGFloat, innerWidth: CGFloat, top: CGFloat, height: CGFloat, count: Int
  ) {
    let keyFont = OverlayTheme.mono(OverlayTheme.Header.pillSize, weight: .semibold)
    let labelFont = OverlayTheme.ui(OverlayTheme.Header.labelSize, weight: .semibold)
    let countFont = OverlayTheme.mono(OverlayTheme.Header.countSize)
    let headerBottom = top - height

    // Key pill (accent-outlined chip).
    let pillH: CGFloat = 22
    let pillW = measure(header.key, keyFont) + OverlayTheme.Header.pillHPad * 2
    keyPill.frame = CGRect(
      x: innerLeft, y: headerBottom + (height - pillH) / 2, width: pillW, height: pillH)
    keyPill.isHidden = header.key.isEmpty
    setText(keyPillText, header.key, font: keyFont, color: OverlayTheme.Header.pillText, alignment: .center)
    centerVertically(keyPillText, in: pillH, width: pillW)

    // Count, right-aligned.
    let countString = "\(count) " + (count == 1 ? "window" : "windows")
    let countW = measure(countString, countFont)
    setText(headerCount, countString, font: countFont, color: OverlayTheme.Header.countColor, alignment: .right)
    headerCount.frame = CGRect(
      x: innerLeft, y: headerBottom + (height - lineH(countFont)) / 2, width: innerWidth, height: lineH(countFont))
    headerCount.isHidden = false

    // Mode label, between the pill and the count.
    let labelX = innerLeft + (header.key.isEmpty ? 0 : pillW + OverlayTheme.Header.gap)
    let labelW = max(0, innerLeft + innerWidth - labelX - countW - 12)
    setText(headerLabel, header.label, font: labelFont, color: OverlayTheme.Header.labelColor, alignment: .left)
    headerLabel.frame = CGRect(
      x: labelX, y: headerBottom + (height - lineH(labelFont)) / 2, width: labelW, height: lineH(labelFont))
    headerLabel.isHidden = false
  }

  private func layoutFooter(left: CGFloat, right: CGFloat, bottom: CGFloat, height: CGFloat, board: Bool) {
    let font = OverlayTheme.mono(OverlayTheme.Footer.size)
    let key = OverlayTheme.Footer.keyColor
    let dim = OverlayTheme.Footer.textColor
    let accent = OverlayTheme.Footer.accentColor
    let sep = "      "
    var segments: [(String, NSColor)] = [
      ("Tab", key), (" move", dim), (sep, dim),
      ("↵", key), (" switch", dim), (sep, dim),
      ("W", key), (" close window", dim), (sep, dim),
      ("Q", key), (" quit app", dim),
    ]
    if board { segments += [(sep, dim), ("↓", accent), (" bring here", dim)] }
    footerLeft.string = attributed(segments, font: font)
    footerLeft.alignmentMode = .left
    footerLeft.frame = CGRect(x: left, y: bottom + (height - lineH(font)) / 2, width: right - left, height: lineH(font))
    footerLeft.isHidden = false

    footerRight.string = attributed([("Esc", key), (" cancel", dim)], font: font)
    footerRight.alignmentMode = .right
    footerRight.frame = CGRect(
      x: left, y: bottom + (height - lineH(font)) / 2, width: right - left, height: lineH(font))
    footerRight.isHidden = false
  }

  private func layoutTwoZone(
    contentTop: CGFloat, cardX: CGFloat, cardW: CGFloat, eGrid: Grid, hGrid: Grid, hereCount: Int,
    zoneHeadBlock: CGFloat
  ) {
    let tileSize = OverlayTheme.Tile.size
    let headFont = OverlayTheme.mono(OverlayTheme.Zone.headSize, weight: .semibold)
    let headH = OverlayTheme.Zone.headHeight
    // Zone heads span the full content width (title flush-left, hint flush-right, like the
    // website's space-between row); the tile grids below center within that same width.
    let innerLeft = cardX + OverlayTheme.Card.padding
    let innerWidth = cardW - OverlayTheme.Card.padding * 2
    let eOriginX = innerLeft
    let hOriginX = innerLeft

    // ELSEWHERE head + "↓ bring here" hint on one line, over the grid.
    setAttr(
      elsewhereHead, "ELSEWHERE", font: headFont, color: OverlayTheme.Zone.headColor, kern: OverlayTheme.Zone.headKern,
      alignment: .left)
    elsewhereHead.frame = CGRect(x: eOriginX, y: contentTop - headH, width: innerWidth, height: headH)
    elsewhereHead.isHidden = false
    setAttr(
      elsewhereHint, "↓ bring here", font: OverlayTheme.mono(OverlayTheme.Zone.headSize + 1),
      color: OverlayTheme.Zone.hintColor, kern: 0, alignment: .right)
    elsewhereHint.frame = CGRect(x: eOriginX, y: contentTop - headH, width: innerWidth, height: headH)
    elsewhereHint.isHidden = false

    let eGridTop = contentTop - zoneHeadBlock
    layoutTiles(
      0..<hereStart, gridOrigin: CGPoint(x: eOriginX, y: eGridTop - eGrid.height),
      gridHeight: eGrid.height, columns: eGrid.columns, availableWidth: innerWidth, tile: tileSize,
      zone: .elsewhere)

    // Divider between the two zones.
    let dividerY = (eGridTop - eGrid.height - OverlayTheme.Zone.gap).rounded()
    zoneDivider.frame = CGRect(
      x: cardX + OverlayTheme.Card.padding, y: dividerY, width: cardW - OverlayTheme.Card.padding * 2, height: 1)
    zoneDivider.isHidden = false

    // THIS SPACE head + grid (or an empty-state hint).
    let hereHeadTop = dividerY - OverlayTheme.Zone.dividerTopGap
    setAttr(
      hereHead, "THIS SPACE", font: headFont, color: OverlayTheme.Zone.headColor, kern: OverlayTheme.Zone.headKern,
      alignment: .left)
    hereHead.frame = CGRect(x: hOriginX, y: hereHeadTop - headH, width: innerWidth, height: headH)
    hereHead.isHidden = false

    if hereCount > 0 {
      emptyHereHint.isHidden = true
      let hGridTop = hereHeadTop - zoneHeadBlock
      layoutTiles(
        hereStart..<windows.count, gridOrigin: CGPoint(x: hOriginX, y: hGridTop - hGrid.height),
        gridHeight: hGrid.height, columns: hGrid.columns, availableWidth: innerWidth, tile: tileSize,
        zone: .here)
    } else {
      let hintFont = OverlayTheme.mono(13)
      setText(
        emptyHereHint, "press ↓ to bring a window here", font: hintFont, color: OverlayTheme.Zone.headColor,
        alignment: .left)
      let y = hereHeadTop - zoneHeadBlock - (OverlayTheme.Zone.emptyHintHeight + lineH(hintFont)) / 2
      emptyHereHint.frame = CGRect(x: hOriginX, y: y, width: 360, height: lineH(hintFont))
      emptyHereHint.isHidden = false
    }
  }

  private func hideTwoZoneChrome() {
    zoneDivider.isHidden = true
    elsewhereHead.isHidden = true
    elsewhereHint.isHidden = true
    hereHead.isHidden = true
    emptyHereHint.isHidden = true
  }

  /// Position the tiles in `range` as a flow grid whose bottom-left is `gridOrigin`, filling
  /// each with its window styled for `zone`. Row 0 is the top row. Each row is centered within
  /// `availableWidth` (the card's inner content width), so a partial last row — or a whole grid
  /// narrower than the card — sits centered, matching the website's `justify-content: center`.
  private func layoutTiles(
    _ range: Range<Int>, gridOrigin: CGPoint, gridHeight: CGFloat, columns: Int, availableWidth: CGFloat,
    tile size: CGSize, zone: Zone
  ) {
    guard columns > 0 else { return }
    let spacing = OverlayTheme.Tile.spacing
    let total = range.count
    for (offset, index) in range.enumerated() {
      let tile = tiles[index]
      tile.container.isHidden = false
      let row = offset / columns
      let column = offset % columns
      let tilesInRow = min(columns, total - row * columns)
      let rowWidth = CGFloat(tilesInRow) * size.width + CGFloat(tilesInRow - 1) * spacing
      let rowInset = ((availableWidth - rowWidth) / 2).rounded()
      let x = gridOrigin.x + rowInset + CGFloat(column) * (size.width + spacing)
      let y = gridOrigin.y + gridHeight - CGFloat(row + 1) * size.height - CGFloat(row) * spacing
      tile.container.frame = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
      fill(tile, with: windows[index], at: index, size: size, zone: zone, selected: index == selectedIndex)
    }
  }

  // MARK: - Thumbnails & selection

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
}

extension TileGridView {
  // MARK: - Fly animations (summon / fling)

  /// Snapshot the moving window's tile into a ghost layer, BEFORE the relayout. The ghost
  /// stays put while the board relays out underneath; `flyGhostToHere` / `flyGhostOff` then
  /// animates it. No-op if the window has no visible tile.
  func beginGhost(windowID: CGWindowID) {
    ghost?.removeFromSuperlayer()
    ghost = nil
    guard let tile = visibleTile(for: windowID), let root = layer else { return }
    let snapshot = makeGhost(windowID: windowID, frame: tile.container.frame)
    withoutAnimations { root.addSublayer(snapshot) }
    ghost = snapshot
  }

  /// Fly the ghost from its old (ELSEWHERE) slot down across the divider to the window's new
  /// (HERE) slot, then remove it.
  func flyGhostToHere(windowID: CGWindowID) {
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
    group.duration = 0.26
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
    ghost.cornerRadius = OverlayTheme.Tile.radius
    ghost.backgroundColor = OverlayTheme.Tile.selectedFill.cgColor
    ghost.borderColor = OverlayTheme.Tile.selectionRing.cgColor
    ghost.borderWidth = OverlayTheme.Tile.borderWidth
    let pad = OverlayTheme.Tile.pad
    let footer = OverlayTheme.Tile.footerHeight
    let thumb = CALayer()
    thumb.frame = CGRect(
      x: pad, y: footer, width: frame.width - pad * 2, height: frame.height - footer - pad)
    thumb.contentsGravity = .resizeAspect
    thumb.contents = thumbnails[windowID]
    thumb.backgroundColor = OverlayTheme.Tile.thumbFill.cgColor
    thumb.cornerRadius = OverlayTheme.Tile.thumbRadius
    thumb.masksToBounds = true
    ghost.addSublayer(thumb)
    return ghost
  }

  // MARK: - Tile building

  private func makeTile() -> Tile {
    let tile = Tile()
    tile.container.cornerRadius = OverlayTheme.Tile.radius
    tile.container.borderColor = OverlayTheme.Tile.selectionRing.cgColor
    tile.container.masksToBounds = false  // let the selection glow + chips spill past the corner

    tile.thumbnail.contentsGravity = .resizeAspect
    tile.thumbnail.backgroundColor = OverlayTheme.Tile.thumbFill.cgColor
    tile.thumbnail.cornerRadius = OverlayTheme.Tile.thumbRadius
    tile.thumbnail.borderColor = OverlayTheme.Tile.thumbBorder.cgColor
    tile.thumbnail.borderWidth = 1
    tile.thumbnail.masksToBounds = true
    tile.container.addSublayer(tile.thumbnail)

    tile.icon.contentsGravity = .resizeAspect
    tile.container.addSublayer(tile.icon)

    tile.title.fontSize = OverlayTheme.Tile.titleSize
    tile.title.foregroundColor = OverlayTheme.Tile.titleSecondary.cgColor
    tile.title.truncationMode = .end
    tile.title.alignmentMode = .left
    tile.title.contentsScale = OverlayTheme.textScale
    tile.container.addSublayer(tile.title)

    // Status badge (Minimized / Fullscreen), bottom-left of the thumbnail.
    tile.statusBadge.cornerRadius = OverlayTheme.Index.radius
    tile.statusBadge.backgroundColor = OverlayTheme.WindowBadge.fill.cgColor
    tile.statusBadge.isHidden = true
    tile.statusText.alignmentMode = .center
    tile.statusText.contentsScale = OverlayTheme.textScale
    tile.statusBadge.addSublayer(tile.statusText)
    tile.container.addSublayer(tile.statusBadge)

    // The 1…9 index chip, top-left.
    tile.indexBadge.cornerRadius = OverlayTheme.Index.radius
    tile.indexBadge.backgroundColor = OverlayTheme.Index.fill.cgColor
    tile.indexText.alignmentMode = .center
    tile.indexText.contentsScale = OverlayTheme.textScale
    tile.indexBadge.addSublayer(tile.indexText)
    tile.container.addSublayer(tile.indexBadge)

    // Action chips on the selected tile, top-right.
    configureChip(
      tile.hereChip, glyph: "↓ here", fill: OverlayTheme.Chip.hereFill, border: nil, width: OverlayTheme.Chip.hereWidth)
    configureChip(
      tile.closeChip, glyph: "W", fill: OverlayTheme.Chip.fill, border: OverlayTheme.Chip.border,
      width: OverlayTheme.Chip.size)
    configureChip(
      tile.quitChip, glyph: "Q", fill: OverlayTheme.Chip.fill, border: OverlayTheme.Chip.border,
      width: OverlayTheme.Chip.size)
    for chip in [tile.hereChip, tile.closeChip, tile.quitChip] { tile.container.addSublayer(chip) }

    return tile
  }

  /// A small chip with a centered glyph, hidden by default. Built once per tile.
  private func configureChip(_ chip: CALayer, glyph: String, fill: NSColor, border: NSColor?, width: CGFloat) {
    let size = OverlayTheme.Chip.size
    chip.frame = CGRect(x: 0, y: 0, width: width, height: size)
    chip.cornerRadius = OverlayTheme.Chip.radius
    chip.backgroundColor = fill.cgColor
    if let border {
      chip.borderColor = border.cgColor
      chip.borderWidth = 1
    }
    chip.isHidden = true
    let glyphFont = OverlayTheme.mono(OverlayTheme.Chip.fontSize, weight: .semibold)
    let glyphHeight = lineH(glyphFont)
    let text = CATextLayer()
    text.string = glyph
    text.font = glyphFont
    text.fontSize = OverlayTheme.Chip.fontSize
    text.foregroundColor = OverlayTheme.Chip.glyph.cgColor
    text.alignmentMode = .center
    text.contentsScale = OverlayTheme.textScale
    text.frame = CGRect(x: 0, y: (size - glyphHeight) / 2, width: width, height: glyphHeight)
    chip.addSublayer(text)
  }

  /// Fill a tile for `window`, laying out its internals for `size` and styling it for `zone`.
  private func fill(_ tile: Tile, with window: WindowInfo, at index: Int, size: CGSize, zone: Zone, selected: Bool) {
    tile.windowID = window.windowID
    tile.isElsewhere = zone == .elsewhere
    let pad = OverlayTheme.Tile.pad
    let footer = OverlayTheme.Tile.footerHeight
    let icon = OverlayTheme.Tile.iconSize

    tile.thumbnail.frame = CGRect(
      x: pad, y: footer, width: size.width - pad * 2, height: size.height - footer - pad)
    tile.icon.frame = CGRect(x: pad + 3, y: (footer - icon) / 2, width: icon, height: icon)
    let titleX = pad + 3 + icon + 8
    let titleFont = OverlayTheme.ui(OverlayTheme.Tile.titleSize, weight: selected ? .semibold : .medium)
    tile.title.frame = CGRect(
      x: titleX, y: (footer - lineH(titleFont)) / 2, width: size.width - titleX - pad, height: lineH(titleFont))

    // Index chip, top-left over the thumbnail.
    let iSize = OverlayTheme.Index.size
    let iInset = OverlayTheme.Index.inset
    tile.indexBadge.frame = CGRect(x: pad + iInset, y: size.height - pad - iInset - iSize, width: iSize, height: iSize)
    let iFont = OverlayTheme.mono(OverlayTheme.Index.fontSize, weight: .bold)
    tile.indexText.string = "\(index + 1)"
    tile.indexText.font = iFont
    tile.indexText.fontSize = OverlayTheme.Index.fontSize
    tile.indexText.frame = CGRect(x: 0, y: (iSize - lineH(iFont)) / 2, width: iSize, height: lineH(iFont))

    // Action chips, top-right (rightmost: Q, then W, then "↓ here").
    let cSize = OverlayTheme.Chip.size
    let cInset = OverlayTheme.Chip.inset
    let cGap = OverlayTheme.Chip.gap
    let chipY = size.height - pad - cInset - cSize
    let qX = size.width - pad - cInset - cSize
    let wX = qX - cGap - cSize
    let hereX = wX - cGap - OverlayTheme.Chip.hereWidth
    tile.quitChip.frame = CGRect(x: qX, y: chipY, width: cSize, height: cSize)
    tile.closeChip.frame = CGRect(x: wX, y: chipY, width: cSize, height: cSize)
    tile.hereChip.frame = CGRect(x: hereX, y: chipY, width: OverlayTheme.Chip.hereWidth, height: cSize)

    // Status badge, bottom-left of the thumbnail.
    if let badge = statusText(for: window) {
      let font = OverlayTheme.mono(OverlayTheme.WindowBadge.fontSize, weight: .medium)
      let w = measure(badge, font) + OverlayTheme.WindowBadge.hPad * 2
      tile.statusBadge.frame = CGRect(x: pad + iInset, y: footer + 4, width: w, height: OverlayTheme.WindowBadge.height)
      tile.statusText.string = badge
      tile.statusText.font = font
      tile.statusText.fontSize = OverlayTheme.WindowBadge.fontSize
      tile.statusText.foregroundColor = OverlayTheme.WindowBadge.text.cgColor
      tile.statusText.frame = CGRect(
        x: 0, y: (OverlayTheme.WindowBadge.height - lineH(font)) / 2, width: w, height: lineH(font))
      tile.statusBadge.isHidden = false
    } else {
      tile.statusBadge.isHidden = true
    }

    tile.title.string = window.title.isEmpty ? window.appName : window.title
    tile.icon.contents = appIcon(for: window.pid)
    tile.thumbnail.contents = thumbnails[window.windowID]
    applySelection(tile, selected: selected)
  }

  private func statusText(for window: WindowInfo) -> String? {
    if window.isMinimized { return "Minimized" }
    if window.isFullscreen { return "Fullscreen" }
    return nil
  }

  private func applySelection(_ tile: Tile, selected: Bool) {
    tile.container.borderWidth = OverlayTheme.Tile.borderWidth
    tile.container.borderColor = (selected ? OverlayTheme.Tile.selectionRing : .clear).cgColor
    tile.container.backgroundColor = (selected ? OverlayTheme.Tile.selectedFill : OverlayTheme.Tile.fill).cgColor
    tile.container.shadowColor = OverlayTheme.Tile.glowColor.cgColor
    tile.container.shadowOpacity = selected ? OverlayTheme.Tile.glowOpacity : 0
    tile.container.shadowRadius = OverlayTheme.Tile.glowRadius
    tile.container.shadowOffset = OverlayTheme.Tile.glowOffset

    tile.indexText.foregroundColor = (selected ? OverlayTheme.Index.selectedText : OverlayTheme.Index.text).cgColor
    tile.title.foregroundColor = (selected ? OverlayTheme.Tile.titlePrimary : OverlayTheme.Tile.titleSecondary).cgColor
    tile.title.font = OverlayTheme.ui(OverlayTheme.Tile.titleSize, weight: selected ? .semibold : .medium)

    tile.closeChip.isHidden = !selected
    tile.quitChip.isHidden = !selected
    tile.hereChip.isHidden = !(selected && tile.isElsewhere)
  }

  private func appIcon(for pid: pid_t) -> CGImage? {
    guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  // MARK: - Text helpers

  private func setText(
    _ layer: CATextLayer, _ string: String, font: NSFont, color: NSColor,
    alignment: CATextLayerAlignmentMode = .left
  ) {
    layer.string = string
    layer.font = font
    layer.fontSize = font.pointSize
    layer.foregroundColor = color.cgColor
    layer.alignmentMode = alignment
  }

  private func setAttr(
    _ layer: CATextLayer, _ string: String, font: NSFont, color: NSColor, kern: CGFloat,
    alignment: CATextLayerAlignmentMode
  ) {
    layer.string = NSAttributedString(
      string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    layer.alignmentMode = alignment
  }

  private func attributed(_ segments: [(String, NSColor)], font: NSFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (text, color) in segments {
      result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    }
    return result
  }

  private func centerVertically(_ layer: CATextLayer, in height: CGFloat, width: CGFloat) {
    let font = (layer.font as? NSFont) ?? OverlayTheme.mono(layer.fontSize)
    layer.frame = CGRect(x: 0, y: (height - lineH(font)) / 2, width: width, height: lineH(font))
  }

  private func measure(_ string: String, _ font: NSFont) -> CGFloat {
    ceil((string as NSString).size(withAttributes: [.font: font]).width)
  }

  private func lineH(_ font: NSFont) -> CGFloat {
    ceil(font.ascender - font.descender + font.leading)
  }

  private func withoutAnimations(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }
}

extension TileGridView {
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
    hoveredTileIndex = index
    if let index { onHover?(index) }
  }

  override func mouseExited(with event: NSEvent) {
    hoveredTileIndex = nil
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let index = tileIndex(at: point) else {
      onCancel?()  // a click on the dimmed void dismisses, no focus change
      return
    }
    // The action chips live on the selected tile; a click on one runs that action.
    if index == selectedIndex, let chip = chipHit(at: point, in: tiles[index]) {
      switch chip {
      case .here: onSummon?(index)
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

  /// Which chip (if any) `point` lands on, in the view's coordinates.
  private func chipHit(at point: CGPoint, in tile: Tile) -> TileChip? {
    let origin = tile.container.frame.origin
    if !tile.hereChip.isHidden, tile.hereChip.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) {
      return .here
    }
    if !tile.closeChip.isHidden, tile.closeChip.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) {
      return .close
    }
    if !tile.quitChip.isHidden, tile.quitChip.frame.offsetBy(dx: origin.x, dy: origin.y).contains(point) {
      return .quit
    }
    return nil
  }

  /// Re-detect the tile under the cursor after a show/relayout; if the mouse is over a tile,
  /// move the selection there (matching the website's hover-selects behavior).
  func refreshHoveredTile() {
    let next = window.map { tileIndex(at: convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? nil
    hoveredTileIndex = next
    if let next, next != selectedIndex { onHover?(next) }
  }
}
