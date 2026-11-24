import AppKit

/// Dia's "back to the open tab" pill (TabList.TabOverflowIndicatorView, its geometry from
/// TabOverflowGeometryTracker): while the selected tab's row is scrolled out of the list, a
/// capsule with its favicon and an arrow pointing at it sits 7 pt inside the list edge
/// the tab is past. A click scrolls the tab to the middle of the list.
///
/// Splits show their favicons overlapping. The capsule takes the space colour at its list edge.
@MainActor
final class SidebarJumpPill: NSView {
    enum Edge { case top, bottom }

    static let inset: CGFloat = 7
    private static let height: CGFloat = 28
    private static let padding: CGFloat = 10.5
    private static let icon: CGFloat = 16
    /// Each further favicon of a split overlaps the one before by this much.
    private static let overlap: CGFloat = 5
    private var colors = SidebarColors()
    private var surface = NSColor.windowBackgroundColor
    private var fill: NSColor {
        surface.blended(withFraction: hovering ? 0.14 : 0.05, of: colors.textPrimary.withAlphaComponent(1)) ?? surface
    }

    var onClick: () -> Void = {}
    private(set) var edge: Edge?
    private let body = NSView()
    private let innerEdge = CAShapeLayer()
    private var icons: [SidebarFaviconView] = []
    private let arrow = NSImageView()
    /// What the favicons show: their keys and whether each image had loaded.
    private var shownIcons: [String] = []
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        body.wantsLayer = true
        if let l = body.layer {
            l.cornerRadius = Self.height / 2
            l.cornerCurve = .continuous
            l.borderWidth = 0.5
            innerEdge.fillColor = nil
            innerEdge.lineWidth = 0.5
            l.addSublayer(innerEdge)
        }
        addSubview(body)
        arrow.imageScaling = .scaleNone
        body.addSubview(arrow)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Scroll to the open tab")
        refreshFill()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The pill's size for these many favicons.
    static func size(icons n: Int) -> NSSize {
        let iconsW = icon + CGFloat(max(0, n - 1)) * (icon - overlap)
        return NSSize(width: ceil(padding + iconsW + 7 + 7 + padding), height: height)
    }

    /// Shows the pill at `edge` with these favicons, or hides it (nil).
    func show(edge newEdge: Edge?, icons items: [(image: NSImage?, flip: Bool, key: String?)], colors: SidebarColors,
              surface: NSColor, animated: Bool) {
        if let newEdge {
            let recolor = self.colors != colors
            self.colors = colors
            if newEdge != edge || self.surface != surface || recolor {
                self.surface = surface
                body.layer?.borderColor = colors.textPrimary.withAlphaComponent(0.24).cgColor
                innerEdge.strokeColor = colors.separator.cgColor
                arrow.contentTintColor = colors.textPrimary
                refreshFill()
            }
            if recolor || Self.signature(items) != shownIcons { setIcons(items) }
            arrow.image = SidebarSymbols.image(newEdge == .top ? "arrow.up" : "arrow.down", size: 10.5, weight: .light)
        }
        guard newEdge != edge else { return }
        let appearing = edge == nil
        edge = newEdge
        needsLayout = true
        if let newEdge {
            isHidden = false
            alphaValue = 1
            guard animated, appearing, let layer = body.layer else { return }
            // In from the edge it points at: fade in while sliding 4 pt, sprung.
            layoutSubtreeIfNeeded()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.18
            layer.add(fade, forKey: "fade")
            let move = CASpringAnimation(perceptualDuration: 0.32, bounce: 0.2)
            move.keyPath = "sublayerTransform"
            move.fromValue = CATransform3DMakeTranslation(0, newEdge == .top ? -4 : 4, 0)
            move.toValue = CATransform3DIdentity
            move.duration = move.settlingDuration
            self.layer?.add(move, forKey: "rise")
        } else if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.edge == nil else { return }
                    self.isHidden = true
                    self.hovering = false
                }
            }
        } else {
            isHidden = true
            hovering = false
        }
    }

    private func setIcons(_ items: [(image: NSImage?, flip: Bool, key: String?)]) {
        icons.forEach { $0.removeFromSuperview() }
        icons = items.prefix(3).map { item in
            let v = SidebarFaviconView(size: Self.icon)
            v.show(item.image, flip: item.flip, colors: colors)
            body.addSubview(v)
            return v
        }
        shownIcons = Self.signature(items)
        let size = Self.size(icons: icons.count)
        setFrameSize(size)
        needsLayout = true
    }

    private static func signature(_ items: [(image: NSImage?, flip: Bool, key: String?)]) -> [String] {
        items.map { "\($0.key ?? "-")|\($0.image.map { ObjectIdentifier($0).hashValue } ?? 0)|\($0.flip)" }
    }

    private func refreshFill() {
        body.layer?.backgroundColor = fill.cgColor
        for v in icons.dropFirst() {
            v.layer?.borderColor = fill.cgColor
        }
    }

    override func layout() {
        super.layout()
        body.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = body.bounds.insetBy(dx: 0.75, dy: 0.75)
        innerEdge.path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        CATransaction.commit()
        var x = Self.padding
        for (i, v) in icons.enumerated() {
            v.frame = NSRect(x: x, y: (bounds.height - Self.icon) / 2, width: Self.icon, height: Self.icon)
            if i > 0 {
                v.layer?.borderWidth = 1.5
                v.layer?.borderColor = fill.cgColor
            }
            x += Self.icon - Self.overlap
        }
        let arrowX = Self.padding + (Self.icon + CGFloat(max(0, icons.count - 1)) * (Self.icon - Self.overlap)) + 7
        arrow.frame = NSRect(x: arrowX, y: 0, width: 7, height: bounds.height)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func hitTest(_ point: NSPoint) -> NSView? { edge == nil || isHidden ? nil : super.hitTest(point).map { _ in self } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}
