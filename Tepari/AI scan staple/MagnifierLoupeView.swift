import UIKit

final class MagnifierLoupeView: UIView {

    // Provide the source image and the point (in image pixel coords) to sample
    var sourceImage: UIImage? { didSet { setNeedsDisplay() } }
    var imagePixelPoint: CGPoint = .zero { didSet { setNeedsDisplay() } }

    // Loupe tuning
    var zoom: CGFloat = 3.0 { didSet { setNeedsDisplay() } }
    var sampleSizePx: CGFloat = 140 // crop size in pixels before scaling

    override init(frame: CGRect) {
        super.init(frame: frame)
        common()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        common()
    }

    private func common() {
        backgroundColor = .clear
        isOpaque = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    override func draw(_ rect: CGRect) {
        guard let img = sourceImage, let cg = img.cgImage, let ctx = UIGraphicsGetCurrentContext() else { return }

        // circular clip
        let circle = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        circle.addClip()

        // compute crop rect in *pixel* space
        let pxW = CGFloat(cg.width)
        let pxH = CGFloat(cg.height)

        let half = sampleSizePx / 2
        var crop = CGRect(
            x: imagePixelPoint.x - half,
            y: imagePixelPoint.y - half,
            width: sampleSizePx,
            height: sampleSizePx
        )

        // clamp crop
        crop.origin.x = max(0, min(crop.origin.x, pxW - crop.size.width))
        crop.origin.y = max(0, min(crop.origin.y, pxH - crop.size.height))

        guard let cropped = cg.cropping(to: crop) else { return }

        let croppedImg = UIImage(cgImage: cropped, scale: img.scale, orientation: img.imageOrientation)

        // draw scaled to fill loupe
        croppedImg.draw(in: rect)

        // border
        ctx.resetClip()
        UIColor.white.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = 3
        circle.stroke()

        // crosshair inside loupe (center)
        let cx = rect.midX
        let cy = rect.midY
        let arm: CGFloat = 16
        let gap: CGFloat = 6

        ctx.setLineWidth(2)
        ctx.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.95).cgColor)

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
    }
}
