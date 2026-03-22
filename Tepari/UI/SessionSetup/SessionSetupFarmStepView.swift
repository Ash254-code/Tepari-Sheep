import SwiftUI

/// Step 1: Farm selection ONLY.
/// (Yards + Session name moved to later steps)
struct SessionSetupFarmStepView: View {

    // =========================================================
    // MARK: Environment
    // =========================================================

    @EnvironmentObject private var store: LocalDataStore

    // =========================================================
    // MARK: Bindings (owned by SessionSetupView)
    // =========================================================

    @Binding var selectedFarmID: UUID?
    @Binding var manualFarmName: String

    // =========================================================
    // MARK: Inputs
    // =========================================================

    let templates: [LocalDataStore.SessionQuickStartTemplate]
    let onTemplateSelected: (LocalDataStore.SessionQuickStartTemplate) -> Void
    let onAutoNext: () -> Void

    // =========================================================
    // MARK: Local State
    // =========================================================

    @State private var showManualEntry: Bool = false
    @State private var didAutoAdvance: Bool = false
    @State private var pendingAutoNextWork: DispatchWorkItem? = nil
    @State private var pendingTemplateWork: DispatchWorkItem? = nil
    @State private var selectedTemplateID: UUID? = nil

    // =========================================================
    // MARK: Tuning
    // =========================================================

    private let selectionPulseDuration: Double = 0.6
    private let autoAdvanceDelay: Double = 0.2

    // =========================================================
    // MARK: Derived
    // =========================================================

    private var hasFarmsConfigured: Bool { !store.farms.isEmpty }
    private var hasTemplates: Bool { !templates.isEmpty }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var farmTilesData: [FarmTileData] {
        Array(store.farms.prefix(8)).map { farm in
            FarmTileData(
                id: farm.id,
                title: farm.name,
                subtitle: farm.pic.isEmpty ? "No PIC saved" : "PIC \(farm.pic)"
            )
        }
    }

    // =========================================================
    // MARK: Body
    // =========================================================

    var body: some View {
        ZStack {
            GlassBackground()

            if hasFarmsConfigured && !showManualEntry {
                mainPickerContent
            } else {
                noFarmsManualEntryCard
                    .padding(16)
            }
        }
        .onAppear {
            didAutoAdvance = false
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
            pendingTemplateWork?.cancel()
            pendingTemplateWork = nil
        }
        .onDisappear {
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
            pendingTemplateWork?.cancel()
            pendingTemplateWork = nil
        }
        .onChange(of: manualFarmName) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showManualEntry = true
                selectedFarmID = nil
                selectedTemplateID = nil
            }
        }
        .onChange(of: selectedFarmID) { _, _ in
            if !showManualEntry {
                didAutoAdvance = false
            }
        }
    }

    // =========================================================
    // MARK: Main picker
    // =========================================================

    private var mainPickerContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text("Which Farm?")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(
                        hasTemplates
                        ? "Select a farm to build a new session, or choose a quick start template below."
                        : "Select where today’s session belongs."
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(farmTilesData) { farm in
                        farmTile(farm)
                    }
                }
                .padding(.horizontal, 16)

                if hasTemplates {
                    orDivider
                        .padding(.horizontal, 16)
                        .padding(.top, 2)

                    VStack(spacing: 6) {
                        Text("Quick Start Templates")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Tap a template to instantly start a session with saved settings.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(templates) { template in
                            templateTile(template)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)

            Text("OR")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
    }

    // =========================================================
    // MARK: Farm / template tiles
    // =========================================================

    private func farmTile(_ farm: FarmTileData) -> some View {
        let isSelected = selectedFarmID == farm.id && selectedTemplateID == nil

        return Button {
            handleFarmTap(farm.id)
        } label: {
            SessionSetupChoiceTile(
                title: farm.title,
                subtitle: farm.subtitle,
                tertiary: nil,
                systemImage: "leaf.fill",
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }

    private func templateTile(_ template: LocalDataStore.SessionQuickStartTemplate) -> some View {
        let isSelected = selectedTemplateID == template.id

        return Button {
            handleTemplateTap(template)
        } label: {
            SessionSetupChoiceTile(
                title: template.name,
                subtitle: templateSubtitle(template),
                tertiary: nil,
                systemImage: "bolt.circle.fill",
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }

    // =========================================================
    // MARK: No farms / manual entry
    // =========================================================

    private var noFarmsManualEntryCard: some View {
        stepCard(
            title: "Which Farm?",
            subtitle: hasFarmsConfigured ? "Enter a new farm name." : "No farms exist yet — enter one now."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("You can manage farms later in Setup → Farms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Farm name", text: $manualFarmName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                if hasFarmsConfigured {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showManualEntry = false
                            manualFarmName = ""
                            selectedTemplateID = nil
                            didAutoAdvance = false
                        }
                    } label: {
                        Label("Back to farm list", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // =========================================================
    // MARK: Actions
    // =========================================================

    private func handleFarmTap(_ farmID: UUID) {
        guard !didAutoAdvance else { return }
        didAutoAdvance = true

        selectedTemplateID = nil
        pendingAutoNextWork?.cancel()
        pendingTemplateWork?.cancel()

        withAnimation(.spring(response: selectionPulseDuration, dampingFraction: 1.0)) {
            selectedFarmID = farmID
            manualFarmName = ""
        }

        let work = DispatchWorkItem {
            onAutoNext()
        }
        pendingAutoNextWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay, execute: work)
    }

    private func handleTemplateTap(_ template: LocalDataStore.SessionQuickStartTemplate) {
        guard pendingTemplateWork == nil else { return }

        pendingAutoNextWork?.cancel()
        pendingAutoNextWork = nil
        didAutoAdvance = true

        withAnimation(.spring(response: selectionPulseDuration, dampingFraction: 1.0)) {
            selectedTemplateID = template.id
            selectedFarmID = template.farmID
            manualFarmName = ""
        }

        let work = DispatchWorkItem {
            onTemplateSelected(template)
            pendingTemplateWork = nil
        }

        pendingTemplateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay, execute: work)
    }

    private func templateSubtitle(_ template: LocalDataStore.SessionQuickStartTemplate) -> String {
        var parts: [String] = []

        // Mob
        if let mob = template.defaultMobName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mob.isEmpty,
           mob != SessionSetupMobStepView.noneSentinel {
            parts.append(mob == SessionSetupMobStepView.mixedSentinel ? "Mixed" : mob)
        }

        // Session types
        let types = template.sessionTypes
            .map(\.rawValue)
            .sorted()
            .joined(separator: " • ")

        if !types.isEmpty {
            parts.append(types)
        }

        return parts.joined(separator: " • ")
    }

    // =========================================================
    // MARK: Small shared helper
    // =========================================================

    private func stepCard(title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
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
}

private struct FarmTileData: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
}

private struct SessionSetupChoiceTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let tertiary: String?
    let systemImage: String
    let isSelected: Bool

    private var fillColor: Color {
        if isSelected {
            return Color.blue.opacity(colorScheme == .dark ? 0.16 : 0.10)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.72)
    }

    private var strokeColor: Color {
        if isSelected {
            return Color.blue.opacity(0.85)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.16)
            : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let tertiary, !tertiary.isEmpty {
                Text(tertiary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fillColor)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.thinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(strokeColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: shadowColor, radius: 10, x: 0, y: 4)
    }
}
