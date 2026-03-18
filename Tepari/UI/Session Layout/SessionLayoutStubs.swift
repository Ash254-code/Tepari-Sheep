import SwiftUI

// MARK: - Scan only

struct SessionLayoutScanView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool
    let isPhone: Bool
    let scannedCount: Int
    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan View")
            Text("scanned: \(scannedCount)")
            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}



// MARK: - Stick Reader workflows

struct SessionLayoutStickReaderView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool
    let isPhone: Bool
    let onStartNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Stick Reader View")
            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}

// MARK: - Transfer / Sale (STUB)
// NOTE: Renamed to avoid colliding with your real SessionLayoutTransferSaleView elsewhere in the project.

struct SessionLayoutTransferSaleStubView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool
    let isPhone: Bool
    let scannedCount: Int
    let onStartNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Transfer / Sale View (Stub)")
            Text("scanned: \(scannedCount)")
            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}

// MARK: - Treatment

struct SessionLayoutTreatmentView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool
    let isPhone: Bool
    let scannedCount: Int
    let onStartNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Treatment View")
            Text("scanned: \(scannedCount)")
            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}

// MARK: - Trait Input

struct SessionLayoutTraitInputView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    @Binding var showDetails: Bool
    let isPhone: Bool
    let onStartNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Trait Input View")
            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}

// MARK: - Fallback

struct SessionLayoutFallbackView: View {
    @ObservedObject var vm: SessionViewModel
    let activeTypes: Set<SetupSessionType>
    let onStartNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Unsupported session mode")
            Text(activeTypes.map { "\($0)" }.joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("New Session", action: onStartNewSession)
        }
        .padding()
    }
}
