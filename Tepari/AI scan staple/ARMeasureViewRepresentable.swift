import SwiftUI
import UIKit

struct ARMeasureUpdate: Equatable {
    var isSupported: Bool
    var tapCount: Int
    var mm: Double?
    var prompt: String
}

struct ARMeasureViewRepresentable: UIViewRepresentable {

    let onUpdate: (ARMeasureUpdate) -> Void

    // Keep a stable bridge (prevents any weirdness if SwiftUI rebuilds closures/views)
    final class Coordinator {
        var onUpdate: (ARMeasureUpdate) -> Void
        init(onUpdate: @escaping (ARMeasureUpdate) -> Void) {
            self.onUpdate = onUpdate
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUpdate: onUpdate)
    }

    func makeUIView(context: Context) -> ARMeasureUIView {
        let v = ARMeasureUIView()
        v.onUpdate = { update in
            context.coordinator.onUpdate(update)
        }
        return v
    }

    func updateUIView(_ uiView: ARMeasureUIView, context: Context) {
        // Ensure the latest closure is used
        context.coordinator.onUpdate = onUpdate
        uiView.onUpdate = { update in
            context.coordinator.onUpdate(update)
        }
    }
}
