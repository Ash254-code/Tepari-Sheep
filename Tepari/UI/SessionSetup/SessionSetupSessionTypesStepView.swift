import SwiftUI

/// Extracted Step: Session Types (full-screen tile grid)
struct SessionSetupSessionTypesStepView: View {

    // =========================================================
    // MARK: Bindings
    // =========================================================

    @Binding var selectedTypes: Set<SetupSessionType>

    // =========================================================
    // MARK: Optional derived plan inputs (locked by types)
    // =========================================================
    /// Still passed in so the background planning can happen,
    /// but no longer shown in the UI here.
    var lockedEquipment: Set<SetupEquipment> = []

    /// Provide any plan error (e.g. invalid combo like Scanner + Stick Reader).
    /// Defaults to nil so this view can be adopted incrementally.
    var planErrorMessage: String? = nil

    // =========================================================
    // MARK: Actions
    // =========================================================

    let onSelectionChanged: () -> Void

    // =========================================================
    // MARK: Body
    // =========================================================

    var body: some View {

        let baseCaption = "Select what you’ll do in this session."
        let rulesMsg = SetupSessionTypeRules.validationMessage(selectedTypes)

        let caption = [baseCaption, rulesMsg]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let hasBottomArea =
            (planErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

        WizardTileGrid(
            title: "Session Type",
            caption: caption,
            tiles: sessionTypeTiles,
            selection: sessionTypeSelectionBinding,
            allowsMultipleSelection: true,
            isTileEnabled: { tile in
                guard let t = SetupSessionType(rawValue: tile.id) else { return true }

                // Always allow deselect
                if selectedTypes.contains(t) { return true }

                // If nothing selected yet, only enable valid starting types (reachable prefix)
                if selectedTypes.isEmpty {
                    return SetupSessionTypeRules.canStart(with: t)
                }

                // Otherwise only enable types that keep us "reachable" from at least one allowed final set
                return SetupSessionTypeRules.canAdd(t, to: selectedTypes)
            },
            onSelectionChanged: { _ in onSelectionChanged() }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasBottomArea {
                VStack(spacing: 10) {
                    if let msg = planErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !msg.isEmpty {
                        planErrorBanner(msg)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 8)
            }
        }
    }

    // =========================================================
    // MARK: Tiles + Binding
    // =========================================================

    /// Explicit UI order (don’t rely on enum case order).
    private var orderedTypes: [SetupSessionType] {
        [
            .scan,
            .draft,
            .treatment,
            .traitInput,
            .weigh,
            .fleeceWeigh,
            .lambMarking,
            .pregTesting,
            .transfer,
            .sale
        ]
    }

    private var sessionTypeTiles: [WizardTile] {
        orderedTypes.map { t in
            WizardTile(id: t.rawValue, title: t.rawValue, systemImage: t.icon, subtitle: nil)
        }
    }

    private var sessionTypeSelectionBinding: Binding<Set<String>> {
        Binding<Set<String>>(
            get: { Set(selectedTypes.map { $0.rawValue }) },
            set: { newSet in
                selectedTypes = Set(newSet.compactMap { SetupSessionType(rawValue: $0) })
            }
        )
    }

    // =========================================================
    // MARK: Bottom UI
    // =========================================================

    private func planErrorBanner(_ msg: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Not allowed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
    }
}

// =========================================================
// MARK: - Simple Flow Layout (chips wrap)
// =========================================================

/// A small wrapping container so chips don’t force a horizontal scroll.
/// Kept here in case it is still used elsewhere from this file later.
private struct FlowWrap<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: () -> Content

    init(
        spacing: CGFloat = 8,
        lineSpacing: CGFloat = 8,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        FlowWrapLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
    }
}

// NOTE: SwiftUI Layout protocol is iOS 16+. If your deployment target is iOS 15,
// this will not compile. Tell me and I’ll give you an iOS 15-compatible version.
private struct FlowWrapLayout: Layout {

    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {

        let maxWidth = proposal.width ?? 300

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize.unspecified)

            // wrap
            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            // advance (only add spacing if not first in row)
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize.unspecified)

            // wrap
            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            s.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
    }
}
