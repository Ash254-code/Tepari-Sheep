import SwiftUI

struct StapleLengthTestView: View {

    @State private var mmText: String = "—"
    @State private var statusText: String = "Press Freeze, align crosshair, then set Point A"
    @State private var pointsSet: Int = 0
    @State private var supported: Bool = true
    @State private var isFrozen: Bool = false

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var pointASet: Bool { pointsSet >= 1 }
    private var pointBSet: Bool { pointsSet >= 2 }

    var body: some View {
        ZStack(alignment: .bottom) {

            ARMeasureViewRepresentable { update in
                supported = update.isSupported
                pointsSet = update.tapCount

                if !update.isSupported {
                    mmText = "—"
                    statusText = "AR not supported on this device."
                    return
                }

                if let mm = update.mm {
                    mmText = String(format: "%.0f mm", mm)
                } else {
                    mmText = "—"
                }

                statusText = update.prompt
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {

                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isPhone {
                    phoneControls
                } else {
                    defaultControls
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .stapleMeasureStop, object: nil)
        }
    }

    // =====================================================
    // MARK: - iPhone controls
    // =====================================================

    private var phoneControls: some View {
        VStack(spacing: 10) {

            // Row 1: Reset (left) + Freeze (right)
            HStack {
                Button {
                    NotificationCenter.default.post(name: .stapleMeasureReset, object: nil)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(!supported)

                Spacer()

                Button {
                    isFrozen.toggle()
                    if isFrozen {
                        NotificationCenter.default.post(name: .stapleMeasureFreeze, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .stapleMeasureLive, object: nil)
                    }
                } label: {
                    Label(isFrozen ? "Live" : "Freeze",
                          systemImage: isFrozen ? "play.fill" : "pause.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(!supported)
            }

            // Row 2: Measurement centered between A & B
            Text(mmText)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // Row 3: Point A / Point B (big + priority)
            HStack(spacing: 14) {

                Button {
                    NotificationCenter.default.post(name: .stapleMeasureSetBase, object: nil)
                } label: {
                    Text("Point A")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(pointASet ? .blue : .gray)
                .disabled(!supported || !isFrozen)

                Button {
                    NotificationCenter.default.post(name: .stapleMeasureSetTip, object: nil)
                } label: {
                    Text("Point B")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(pointBSet ? .blue : .gray)
                .disabled(!supported || !isFrozen || !pointASet)
            }
        }
    }

    // =====================================================
    // MARK: - Default controls (iPad / fallback)
    // =====================================================

    private var defaultControls: some View {
        VStack(spacing: 10) {

            Text(mmText)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {

                Spacer()

                Button {
                    isFrozen.toggle()
                    if isFrozen {
                        NotificationCenter.default.post(name: .stapleMeasureFreeze, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .stapleMeasureLive, object: nil)
                    }
                } label: {
                    Label(isFrozen ? "Live" : "Freeze",
                          systemImage: isFrozen ? "play.fill" : "pause.fill")
                    .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(!supported)

                Button {
                    NotificationCenter.default.post(name: .stapleMeasureSetBase, object: nil)
                } label: {
                    Text("Point A")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(pointASet ? .blue : .gray)
                .disabled(!supported || !isFrozen)

                Button {
                    NotificationCenter.default.post(name: .stapleMeasureSetTip, object: nil)
                } label: {
                    Text("Point B")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(pointBSet ? .blue : .gray)
                .disabled(!supported || !isFrozen || !pointASet)

                Button {
                    NotificationCenter.default.post(name: .stapleMeasureReset, object: nil)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(!supported)
            }
        }
    }
}

extension Notification.Name {
    static let stapleMeasureReset   = Notification.Name("stapleMeasureReset")
    static let stapleMeasureStop    = Notification.Name("stapleMeasureStop")
    static let stapleMeasureFreeze  = Notification.Name("stapleMeasureFreeze")
    static let stapleMeasureLive    = Notification.Name("stapleMeasureLive")
    static let stapleMeasureSetBase = Notification.Name("stapleMeasureSetBase") // Point A
    static let stapleMeasureSetTip  = Notification.Name("stapleMeasureSetTip")  // Point B
}
