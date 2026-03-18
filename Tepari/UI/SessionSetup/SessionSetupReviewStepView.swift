import SwiftUI

/// Extracted Step: Review (confirm settings before starting)
struct SessionSetupReviewStepView: View {

    // =========================================================
    // MARK: Treatment summary models (for Review)
    // =========================================================

    struct TreatmentSummary: Identifiable, Hashable, Codable {
        let id: UUID
        var product: String
        var doseValue: String
        var doseUnit: DoseUnit
        var withholding: String

        init(
            id: UUID,
            product: String,
            doseValue: String,
            doseUnit: DoseUnit = .mL,
            withholding: String = ""
        ) {
            self.id = id
            self.product = product
            self.doseValue = doseValue
            self.doseUnit = doseUnit
            self.withholding = withholding
        }

        var doseLabel: String {
            let v = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { return "—" }
            return "\(v) \(doseUnit.rawValue)"
        }

        var withholdingLabel: String {
            withholding.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // =========================================================
    // MARK: Inputs
    // =========================================================

    let resolvedFarmName: String
    let selectedYard: String?
    let sessionNameText: String

    let hasFarmsConfigured: Bool
    let selectedFarmPIC: String?

    let selectedTypesText: String
    let selectedEquipmentText: String

    let scannerLabel: String
    let weighingEnabled: Bool
    let weightSourceLabel: String

    // Fields
    let recordTreatments: Bool
    let recordLambsProduced: Bool
    let recordFleeceWeight: Bool
    let recordStapleLength: Bool
    let recordMicron: Bool

    // Defaults
    let defaultSexLabel: String
    let defaultClassLabel: String
    let defaultMobName: String

    // Overwrite
    let overwriteSex: Bool
    let overwriteClass: Bool
    let overwriteMob: Bool

    // Treatments shown on review
    let sessionTreatments: [TreatmentSummary]

    // =========================================================
    // MARK: Derived state
    // =========================================================

    private var isMixedMobSelection: Bool {
        defaultMobName.isMobMixed
    }

    private var isNoMobSelection: Bool {
        defaultMobName.isMobNone
    }

    private var resolvedMobLabel: String {
        if isMixedMobSelection { return "Mixed" }
        if isNoMobSelection { return "—" }

        let trimmed = defaultMobName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private var resolvedMobOverwriteLabel: String {
        if isMixedMobSelection {
            return "Preserve existing mobs"
        }
        return overwriteMob ? "Overwrite enabled" : "Off"
    }

    // =========================================================
    // MARK: Body
    // =========================================================

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            stepCard(title: "Review", subtitle: "Confirm settings before starting.") {
                if isLandscape {
                    HStack(alignment: .top, spacing: 14) {
                        leftColumn
                        rightColumn
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        leftColumn
                        rightColumn
                    }
                }
            }
        }
    }

    // =========================================================
    // MARK: Columns
    // =========================================================

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            summarySection
            lockedSetupSection
            fieldsSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if recordTreatments {
                treatmentsSection
            }
            defaultsSection
            overwriteRulesSection
            footerNote
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // =========================================================
    // MARK: Sections
    // =========================================================

    private var summarySection: some View {
        reviewSectionCard(title: "Session Summary", systemImage: "doc.text") {
            VStack(spacing: 10) {
                reviewRow("Farm", resolvedFarmName)

                if let y = selectedYard?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
                    reviewRow("Yard", y)
                }

                let nameTrim = sessionNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nameTrim.isEmpty {
                    reviewRow("Session Name", nameTrim)
                }

                if hasFarmsConfigured, let pic = selectedFarmPIC, !pic.isEmpty {
                    reviewRow("PIC", pic)
                }

                reviewRow("Session Types", selectedTypesText)
            }
        }
    }

    private var lockedSetupSection: some View {
        reviewSectionCard(title: "Locked Setup", systemImage: "lock.fill") {
            VStack(spacing: 10) {
                reviewRow("Equipment", selectedEquipmentText)

                if scannerLabel != "—" {
                    reviewRow("Reader", scannerLabel)
                }

                if weighingEnabled, weightSourceLabel != "—" {
                    reviewRow("Weights", weightSourceLabel)
                }
            }
        }
    }

    private var fieldsSection: some View {
        reviewSectionCard(title: "Fields", systemImage: "checklist") {
            flowWrap {
                statusChip("Treatments", enabled: recordTreatments)
                statusChip("Lambs Produced", enabled: recordLambsProduced)
                statusChip("Fleece Weight", enabled: recordFleeceWeight)
                statusChip("Staple Length", enabled: recordStapleLength)
                statusChip("Micron", enabled: recordMicron)
            }
        }
    }

    private var treatmentsSection: some View {
        reviewSectionCard(title: "Treatments", systemImage: "cross.case.fill") {
            if sessionTreatments.isEmpty {
                Text("No session treatments selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessionTreatments) { t in
                        treatmentRow(t)
                    }
                }
            }
        }
    }

    private var defaultsSection: some View {
        reviewSectionCard(title: "Defaults", systemImage: "slider.horizontal.3") {
            VStack(spacing: 10) {
                reviewRow("Sex", defaultSexLabel)
                reviewRow("Class", defaultClassLabel)
                reviewRow("Mob", resolvedMobLabel)

                if isMixedMobSelection {
                    reviewNoteRow(
                        systemImage: "shuffle",
                        text: "Mixed session selected. Each animal keeps its existing mob."
                    )
                }
            }
        }
    }

    private var overwriteRulesSection: some View {
        reviewSectionCard(title: "Overwrite Rules", systemImage: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                flowWrap {
                    overwriteChip("Sex", enabled: overwriteSex)
                    overwriteChip("Class", enabled: overwriteClass)
                    overwriteChip("Mob", enabled: overwriteMob && !isMixedMobSelection)
                }

                if isMixedMobSelection {
                    reviewNoteRow(
                        systemImage: "lock.arrow.circlepath",
                        text: resolvedMobOverwriteLabel
                    )
                }
            }
        }
    }

    private var footerNote: some View {
        Text(
            isMixedMobSelection
            ? "Tap Start to begin the session. Mixed will preserve each animal’s current mob."
            : "Tap Start to begin the session with these settings."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // =========================================================
    // MARK: Local helpers
    // =========================================================

    private func stepCard(title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider().opacity(0.18)

                content()
            }
        }
    }

    private func reviewSectionCard(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reviewNoteRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func treatmentRow(_ t: TreatmentSummary) -> some View {
        let w = t.withholdingLabel
        let rhs = w.isEmpty ? t.doseLabel : "\(t.doseLabel) • \(w)"

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.case.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.product)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(rhs)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func statusChip(_ label: String, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(enabled ? .primary : .secondary)
        .opacity(enabled ? 1 : 0.55)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.white.opacity(enabled ? 0.07 : 0.03))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func overwriteChip(_ label: String, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: enabled ? "exclamationmark.triangle.fill" : "circle")
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(enabled ? .red : .secondary)
        .opacity(enabled ? 1 : 0.7)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(enabled ? Color.red.opacity(0.10) : Color.white.opacity(0.03))
        )
        .overlay(
            Capsule()
                .stroke(enabled ? Color.red.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func flowWrap<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        _FlowWrap(spacing: 8, lineSpacing: 8, content: content)
    }
}

// =========================================================
// MARK: - Simple Flow Wrap
// =========================================================

private struct _FlowWrap<Content: View>: View {
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
        _FlowWrapLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
    }
}

private struct _FlowWrapLayout: Layout {
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
            let size = s.sizeThatFits(.unspecified)

            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            let nextX = x == 0 ? size.width : x + spacing + size.width
            x = nextX
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
            let size = s.sizeThatFits(.unspecified)

            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            s.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + (x == 0 ? 0 : spacing)
            rowHeight = max(rowHeight, size.height)
        }
    }
}
