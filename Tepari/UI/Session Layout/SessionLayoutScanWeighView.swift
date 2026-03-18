import SwiftUI

struct SessionLayoutScanWeighView: View {

    @ObservedObject var vm: SessionViewModel

    @Binding var showWeighMode: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    var body: some View {
        SessionSingleTileTemplateView(
            horizontalPadding: 16,
            topPadding: 14,
            bottomPadding: 12,
            reservedBottomHeight: 0
        ) {
            weightPanel
        }
    }

    private var weightPanel: some View {
        SessionLayoutScanWeighPanel(
            title: "Weight",
            systemImage: "scalemass.fill",
            subtitle: "Live scale"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SessionWeightBoard(
                    weight: vm.currentWeight,
                    locked: vm.isLocked,
                    stable: vm.isStable,
                    onWeighMode: { showWeighMode = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Text("Tally")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text("\(scannedCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showWeighMode = true
        }
    }
}

private struct SessionLayoutScanWeighPanel<Content: View>: View {
    let title: String
    let systemImage: String?
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)

                        if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Spacer(minLength: 8)
                }

                Divider().opacity(0.18)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }
}
