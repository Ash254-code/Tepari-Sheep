import UIKit

final class DraggableCrosshairOverlay: UIView {

    // crosshair point in this view’s coordinate space
    var crosshairPoint: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    var onMove: ((CGPoint) -> Void)?
    var onPressingChanged: ((Bool) -> Void)?

    private let longPress: UILongPressGestureRecognizer

    // =====================================================
    // MARK: - Polish knobs
    // =====================================================

    /// Slight inset so the crosshair never touches the very edge.
    private let edgeInset: CGFloat = 4

    /// Snap-to-center helps “reset” alignment quickly without needing Reset.
    private let snapToCenterThreshold: CGFloat = 16

    /// Visual feedback while pressing
    private let pressScale: CGFloat = 1.08

    /// Small center “bullseye” ring to improve visibility on bright wool
    private let showCenterRing: Bool = true

    /// A subtle halo improves contrast on complex textures
    private let showHalo: Bool = true

    /// Optional haptic when snapping to center (kept subtle)
    private let snapHaptic = UISelectionFeedbackGenerator()
    private var hasSnappedToCenter: Bool = false

    /// Avoid spamming onMove when point changes are tiny
    private var lastReportedPoint: CGPoint = .zero
    private let reportEpsilon: CGFloat = 0.35

    // =====================================================
    // MARK: - Init
    // =====================================================

    override init(frame: CGRect) {
        longPress = UILongPressGestureRecognizer()
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        longPress = UILongPressGestureRecognizer()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        // Quick “press + drag” without feeling like a long press.
        longPress.minimumPressDuration = 0.10
        longPress.allowableMovement = 1000
        longPress.cancelsTouchesInView = true
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)

        snapHaptic.prepare()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // If never set, default to center
        if crosshairPoint == .zero, bounds.width > 0, bounds.height > 0 {
            crosshairPoint = CGPoint(x: bounds.midX, y: bounds.midY)
            reportMoveIfNeeded(crosshairPoint, force: true)
        }
    }

    // =====================================================
    // MARK: - Gesture
    // =====================================================

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        let raw = g.location(in: self)
        let clamped = clamp(raw)
        let snapped = snapIfNeeded(clamped)

        switch g.state {
        case .began:
            hasSnappedToCenter = false
            onPressingChanged?(true)
            animatePressed(true)
            crosshairPoint = snapped
            reportMoveIfNeeded(snapped, force: true)

        case .changed:
            crosshairPoint = snapped
            reportMoveIfNeeded(snapped)

        default:
            onPressingChanged?(false)
            animatePressed(false)
            hasSnappedToCenter = false
        }
    }

    // =====================================================
    // MARK: - Movement helpers
    // =====================================================

    private func clamp(_ p: CGPoint) -> CGPoint {
        let minX = edgeInset
        let minY = edgeInset
        let maxX = max(edgeInset, bounds.width - edgeInset)
        let maxY = max(edgeInset, bounds.height - edgeInset)

        return CGPoint(
            x: min(max(p.x, minX), maxX),
            y: min(max(p.y, minY), maxY)
        )
    }

    private func snapIfNeeded(_ p: CGPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return p }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = p.x - center.x
        let dy = p.y - center.y
        let dist = hypot(dx, dy)

        // Snap to exact center if close enough
        if dist <= snapToCenterThreshold {
            if !hasSnappedToCenter {
                hasSnappedToCenter = true
                snapHaptic.selectionChanged()
                snapHaptic.prepare()
            }
            return center
        } else {
            hasSnappedToCenter = false
            return p
        }
    }

    private func reportMoveIfNeeded(_ p: CGPoint, force: Bool = false) {
        if force {
            lastReportedPoint = p
            onMove?(p)
            return
        }

        let dx = abs(p.x - lastReportedPoint.x)
        let dy = abs(p.y - lastReportedPoint.y)
        if dx > reportEpsilon || dy > reportEpsilon {
            lastReportedPoint = p
            onMove?(p)
        }
    }

    // =====================================================
    // MARK: - Visual feedback
    // =====================================================

    private func animatePressed(_ pressed: Bool) {
        // Keep it snappy; avoid spring wobble (you’re aiming for precision)
        UIView.animate(withDuration: 0.10, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = pressed ? CGAffineTransform(scaleX: self.pressScale, y: self.pressScale) : .identity
            self.alpha = pressed ? 1.0 : 0.98
        }
    }

    // =====================================================
    // MARK: - Drawing
    // =====================================================

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let cx = crosshairPoint.x
        let cy = crosshairPoint.y

        // Slightly larger arms for readability
        let arm: CGFloat = 22
        let gap: CGFloat = 7

        // Line widths
        let outerWidth: CGFloat = 4
        let innerWidth: CGFloat = 2

        // Colors
        let bright = UIColor.white.withAlphaComponent(0.96)
        let dark = UIColor.black.withAlphaComponent(0.75)

        ctx.saveGState()

        // Optional halo (soft circle behind crosshair)
        if showHalo {
            let haloR: CGFloat = 26
            let haloRect = CGRect(x: cx - haloR, y: cy - haloR, width: haloR * 2, height: haloR * 2)
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: haloRect)
        }

        // Shadow improves separation from background textures
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)

        // 1) Outer stroke (dark) — creates contrast on bright areas
        ctx.setLineCap(.round)
        ctx.setLineWidth(outerWidth)
        ctx.setStrokeColor(dark.cgColor)

        // horizontal
        ctx.move(to: CGPoint(x: cx - arm, y: cy))
        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
        ctx.move(to: CGPoint(x: cx + gap, y: cy))
        ctx.addLine(to: CGPoint(x: cx + arm, y: cy))

        // vertical
        ctx.move(to: CGPoint(x: cx, y: cy - arm))
        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
        ctx.move(to: CGPoint(x: cx, y: cy + gap))
        ctx.addLine(to: CGPoint(x: cx, y: cy + arm))

        ctx.strokePath()

        // 2) Inner stroke (bright)
        ctx.setLineWidth(innerWidth)
        ctx.setStrokeColor(bright.cgColor)

        // horizontal
        ctx.move(to: CGPoint(x: cx - arm, y: cy))
        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
        ctx.move(to: CGPoint(x: cx + gap, y: cy))
        ctx.addLine(to: CGPoint(x: cx + arm, y: cy))

        // vertical
        ctx.move(to: CGPoint(x: cx, y: cy - arm))
        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
        ctx.move(to: CGPoint(x: cx, y: cy + gap))
        ctx.addLine(to: CGPoint(x: cx, y: cy + arm))

        ctx.strokePath()

        // Center dot + optional ring
        let dotR: CGFloat = 2.4
        let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)

        // dot outer (dark)
        ctx.setFillColor(dark.cgColor)
        ctx.fillEllipse(in: dotRect.insetBy(dx: -1.2, dy: -1.2))

        // dot inner (bright)
        ctx.setFillColor(bright.cgColor)
        ctx.fillEllipse(in: dotRect)

        if showCenterRing {
            ctx.setLineWidth(2)
            ctx.setStrokeColor(bright.withAlphaComponent(0.75).cgColor)
            let ringR: CGFloat = 7
            let ringRect = CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)
            ctx.strokeEllipse(in: ringRect)
        }

        ctx.restoreGState()
    }
}
