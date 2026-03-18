import UIKit
import ARKit
import SceneKit
import simd

final class ARMeasureUIView: UIView, ARSessionDelegate {

    var onUpdate: ((ARMeasureUpdate) -> Void)?

    private let sceneView = ARSCNView(frame: .zero)
    private var pointsWorld: [simd_float3] = []

    // Visuals in 3D
    private var markerNodes: [SCNNode] = []
    private var lineNode: SCNNode?

    // Freeze UI (frozen image + zoom/pan)
    private var isFrozen: Bool = false
    private let freezeScrollView = UIScrollView()
    private let freezeImageView = UIImageView()

    // Draggable crosshair + loupe
    private let crosshairOverlay = DraggableCrosshairOverlay()
    private let loupeView = MagnifierLoupeView()

    // Snapshot + mapping
    private var frozenUIImage: UIImage?
    private var frozenSceneViewSize: CGSize = .zero  // sceneView.bounds.size when frozen

    // =====================================================
    // MARK: - Haptics (max strength)
    // =====================================================

    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    private func prepareHaptics() {
        heavyImpact.prepare()
        notify.prepare()
    }

    private func hapticHeavy() {
        if #available(iOS 13.0, *) {
            heavyImpact.impactOccurred(intensity: 1.0)
        } else {
            heavyImpact.impactOccurred()
        }
        prepareHaptics()
    }

    private func hapticSuccess() {
        notify.notificationOccurred(.success)
        hapticHeavy()
    }

    private func hapticError() {
        notify.notificationOccurred(.error)
        prepareHaptics()
    }

    private var supported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // AR view (bottom)
        addSubview(sceneView)
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene = SCNScene()

        // Freeze overlay (above AR)
        freezeScrollView.backgroundColor = .black
        freezeScrollView.isHidden = true
        freezeScrollView.delegate = self
        freezeScrollView.minimumZoomScale = 1.0
        freezeScrollView.maximumZoomScale = 6.0
        freezeScrollView.showsHorizontalScrollIndicator = false
        freezeScrollView.showsVerticalScrollIndicator = false
        freezeScrollView.bouncesZoom = true
        freezeScrollView.alwaysBounceVertical = true
        freezeScrollView.alwaysBounceHorizontal = true
        freezeScrollView.delaysContentTouches = false

        freezeImageView.contentMode = .scaleAspectFit
        freezeImageView.isUserInteractionEnabled = true

        addSubview(freezeScrollView)
        freezeScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            freezeScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            freezeScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            freezeScrollView.topAnchor.constraint(equalTo: topAnchor),
            freezeScrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        freezeScrollView.addSubview(freezeImageView)

        // Crosshair overlay (top)
        addSubview(crosshairOverlay)
        crosshairOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            crosshairOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            crosshairOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            crosshairOverlay.topAnchor.constraint(equalTo: topAnchor),
            crosshairOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Loupe (hidden until press/drag)
        loupeView.isHidden = true
        loupeView.frame = CGRect(x: 16, y: 90, width: 140, height: 140)
        addSubview(loupeView)

        // Wire crosshair movement
        crosshairOverlay.onMove = { [weak self] p in
            self?.updateLoupe(forCrosshairPoint: p)
        }
        crosshairOverlay.onPressingChanged = { [weak self] pressing in
            guard let self else { return }
            // When pressing, show loupe and stop scroll view so finger drag moves crosshair only
            self.loupeView.isHidden = !pressing
            self.freezeScrollView.isScrollEnabled = !pressing
        }

        // Notifications (from your SwiftUI buttons)
        NotificationCenter.default.addObserver(self, selector: #selector(reset),   name: .stapleMeasureReset, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stop),    name: .stapleMeasureStop, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(freeze),  name: .stapleMeasureFreeze, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(live),    name: .stapleMeasureLive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setBase), name: .stapleMeasureSetBase, object: nil) // Point A
        NotificationCenter.default.addObserver(self, selector: #selector(setTip),  name: .stapleMeasureSetTip, object: nil)  // Point B

        prepareHaptics()

        startSession(resetTracking: true)
        push(mm: nil, prompt: supported ? "Press Freeze, then press+drag crosshair and set Point A" : "AR not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutFreezeImageIfNeeded()
    }

    private func startSession(resetTracking: Bool) {
        guard supported else { return }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        let opts: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
        sceneView.session.run(config, options: opts)
    }

    @objc private func stop() {
        sceneView.session.pause()
        isFrozen = false
        hideFreezeOverlay()
        clearVisuals()
        pointsWorld.removeAll()
        loupeView.isHidden = true
    }

    @objc private func reset() {
        hapticHeavy()
        clearVisuals()
        pointsWorld.removeAll()
        push(mm: nil, prompt: isFrozen ? "Frozen — press+drag crosshair, set Point A" : "Press Freeze first")
    }

    @objc private func freeze() {
        guard supported else { return }
        hapticHeavy()
        isFrozen = true

        frozenSceneViewSize = sceneView.bounds.size

        let img = sceneView.snapshot()
        frozenUIImage = img

        showFreezeOverlay(image: img)

        // Pause so the frozen image and AR state match (less drift)
        sceneView.session.pause()

        loupeView.sourceImage = img
        loupeView.isHidden = true

        push(mm: nil, prompt: "Frozen — press+drag crosshair. Set Point A, then Set Point B")
    }

    @objc private func live() {
        guard supported else { return }
        hapticHeavy()
        isFrozen = false
        hideFreezeOverlay()
        loupeView.isHidden = true

        startSession(resetTracking: false)
        push(mm: nil, prompt: "Live — press Freeze to place points")
    }

    /// Point A
    @objc private func setBase() {
        guard isFrozen else {
            hapticError()
            push(mm: nil, prompt: "Press Freeze first")
            return
        }

        guard let p = sampleWorldPoint(atCrosshair: atCrosshair()) else {
            hapticError()
            push(mm: nil, prompt: "No hit — try closer / different angle")
            return
        }

        if pointsWorld.count == 0 { pointsWorld.append(p) } else { pointsWorld[0] = p }

        clearVisuals()
        addMarker(at: pointsWorld[0])
        hapticSuccess()
        push(mm: nil, prompt: "Point A set — press+drag crosshair to Point B, then Set Point B")
    }

    /// Point B
    @objc private func setTip() {
        guard isFrozen else {
            hapticError()
            push(mm: nil, prompt: "Press Freeze first")
            return
        }
        guard pointsWorld.count >= 1 else {
            hapticError()
            push(mm: nil, prompt: "Set Point A first")
            return
        }
        guard let p = sampleWorldPoint(atCrosshair: atCrosshair()) else {
            hapticError()
            push(mm: nil, prompt: "No hit — try closer / different angle")
            return
        }

        if pointsWorld.count == 1 { pointsWorld.append(p) } else { pointsWorld[1] = p }

        clearVisuals()
        addMarker(at: pointsWorld[0])
        addMarker(at: pointsWorld[1])
        drawLine(from: pointsWorld[0], to: pointsWorld[1])

        let meters = simd_distance(pointsWorld[0], pointsWorld[1])
        let mm = Double(meters * 1000.0)

        hapticSuccess()
        push(mm: mm, prompt: "OK — Reset to measure again")
    }

    // MARK: - Crosshair → Raycast mapping

    private func atCrosshair() -> CGPoint {
        // Crosshair point is in overlay coords which matches self bounds.
        crosshairOverlay.crosshairPoint
    }

    /// Convert crosshair position (in self coords) to a sceneView point (in sceneView coords) then raycast.
    private func sampleWorldPoint(atCrosshair crosshairInSelf: CGPoint) -> simd_float3? {
        guard supported else { return nil }

        // If not frozen, raycast from live sceneView point directly
        guard isFrozen, !freezeScrollView.isHidden else {
            let ptInScene = convert(crosshairInSelf, to: sceneView)
            return raycastWorldPoint(atSceneViewPoint: ptInScene)
        }

        // Frozen: map crosshair to pixel in frozen snapshot
        guard let img = frozenUIImage, let cg = img.cgImage else { return nil }

        // crosshair (self coords) -> freezeImageView coords
        let crossInImageView = convert(crosshairInSelf, to: freezeImageView)

        // If crosshair is outside the imageView bounds, bail
        guard freezeImageView.bounds.width > 0, freezeImageView.bounds.height > 0 else { return nil }

        // Normalize within imageView
        let nx = crossInImageView.x / freezeImageView.bounds.width
        let ny = crossInImageView.y / freezeImageView.bounds.height

        // Clamp 0..1
        let clampedNx = min(max(nx, 0), 1)
        let clampedNy = min(max(ny, 0), 1)

        // Map to sceneView point space (the size of sceneView at freeze time)
        guard frozenSceneViewSize.width > 0, frozenSceneViewSize.height > 0 else { return nil }

        let scenePt = CGPoint(
            x: clampedNx * frozenSceneViewSize.width,
            y: clampedNy * frozenSceneViewSize.height
        )

        // Also update loupe pixel point properly (in image pixel coords)
        let px = clampedNx * CGFloat(cg.width)
        let py = clampedNy * CGFloat(cg.height)
        loupeView.imagePixelPoint = CGPoint(x: px, y: py)

        return raycastWorldPoint(atSceneViewPoint: scenePt)
    }

    private func raycastWorldPoint(atSceneViewPoint pt: CGPoint) -> simd_float3? {
        guard let query = sceneView.raycastQuery(from: pt, allowing: .estimatedPlane, alignment: .any) else {
            return nil
        }
        let hits = sceneView.session.raycast(query)
        guard let hit = hits.first else { return nil }

        let t = hit.worldTransform
        return simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    // MARK: - Loupe updates

    private func updateLoupe(forCrosshairPoint p: CGPoint) {
        guard isFrozen, let img = frozenUIImage, let cg = img.cgImage else { return }

        // Position loupe near finger/crosshair (above-left if possible)
        var lx = p.x - 160
        var ly = p.y - 180
        if lx < 10 { lx = p.x + 20 }
        if ly < 10 { ly = p.y + 20 }
        if lx + 140 > bounds.width - 10 { lx = bounds.width - 150 }
        if ly + 140 > bounds.height - 10 { ly = bounds.height - 150 }
        loupeView.frame = CGRect(x: lx, y: ly, width: 140, height: 140)

        loupeView.sourceImage = img

        // compute image pixel point for loupe sampling
        let crossInImageView = convert(p, to: freezeImageView)
        guard freezeImageView.bounds.width > 0, freezeImageView.bounds.height > 0 else { return }

        let nx = min(max(crossInImageView.x / freezeImageView.bounds.width, 0), 1)
        let ny = min(max(crossInImageView.y / freezeImageView.bounds.height, 0), 1)

        let px = nx * CGFloat(cg.width)
        let py = ny * CGFloat(cg.height)
        loupeView.imagePixelPoint = CGPoint(x: px, y: py)
    }

    // MARK: - 3D visuals

    private func clearVisuals() {
        markerNodes.forEach { $0.removeFromParentNode() }
        markerNodes.removeAll()
        lineNode?.removeFromParentNode()
        lineNode = nil
    }

    private func addMarker(at p: simd_float3) {
        let sphere = SCNSphere(radius: 0.004)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemGreen
        sphere.firstMaterial?.emission.contents = UIColor.systemGreen

        let node = SCNNode(geometry: sphere)
        node.simdPosition = p
        sceneView.scene.rootNode.addChildNode(node)
        markerNodes.append(node)
    }

    private func drawLine(from a: simd_float3, to b: simd_float3) {
        lineNode?.removeFromParentNode()

        let vertices: [SCNVector3] = [
            SCNVector3(a.x, a.y, a.z),
            SCNVector3(b.x, b.y, b.z)
        ]

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: [0, 1], primitiveType: .line)

        let geom = SCNGeometry(sources: [source], elements: [element])
        geom.firstMaterial?.diffuse.contents = UIColor.systemYellow
        geom.firstMaterial?.emission.contents = UIColor.systemYellow

        let node = SCNNode(geometry: geom)
        sceneView.scene.rootNode.addChildNode(node)
        lineNode = node
    }

    private func push(mm: Double?, prompt: String) {
        onUpdate?(ARMeasureUpdate(
            isSupported: supported,
            tapCount: pointsWorld.count,
            mm: mm,
            prompt: prompt
        ))
    }

    // MARK: - Freeze overlay layout

    private func showFreezeOverlay(image: UIImage) {
        freezeImageView.image = image
        freezeScrollView.zoomScale = 1.0
        freezeScrollView.contentOffset = .zero
        freezeScrollView.isHidden = false

        layoutFreezeImageIfNeeded()
        centerFreezeImage()
    }

    private func hideFreezeOverlay() {
        freezeScrollView.isHidden = true
        freezeImageView.image = nil
        freezeScrollView.zoomScale = 1.0
        freezeScrollView.contentOffset = .zero
        freezeScrollView.contentSize = .zero
        frozenUIImage = nil
    }

    private func layoutFreezeImageIfNeeded() {
        guard let img = freezeImageView.image else { return }

        let boundsSize = freezeScrollView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let imgAspect = img.size.width / max(img.size.height, 1)
        let boundsAspect = boundsSize.width / max(boundsSize.height, 1)

        var fitSize = boundsSize
        if imgAspect > boundsAspect {
            fitSize.height = boundsSize.width / imgAspect
        } else {
            fitSize.width = boundsSize.height * imgAspect
        }

        freezeImageView.frame = CGRect(origin: .zero, size: fitSize)
        freezeScrollView.contentSize = fitSize
    }

    private func centerFreezeImage() {
        let boundsSize = freezeScrollView.bounds.size
        let contentSize = freezeScrollView.contentSize

        let offsetX = max((contentSize.width - boundsSize.width) / 2, 0)
        let offsetY = max((contentSize.height - boundsSize.height) / 2, 0)
        freezeScrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    // ARSessionDelegate
    func session(_ session: ARSession, didFailWithError error: Error) {
        hapticError()
        push(mm: nil, prompt: "AR error — Reset")
    }
}

extension ARMeasureUIView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        freezeImageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = freezeImageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        freezeImageView.frame = frameToCenter
    }
}
