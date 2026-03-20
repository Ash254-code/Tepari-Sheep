import SwiftUI

struct SessionSetupMobStepView: View {

    @Binding var selectedMobName: String

    let mobs: [LocalDataStore.Mob]

    // ✅ Kept for compatibility with existing wizard container calls,
    // but no longer used because the Add New tile is removed.
    let addMobSentinel: String
    let onTapAddNew: () -> Void

    /// ✅ Wizard container injects this (same thing your Next button does)
    let onAutoNext: () -> Void

    @State private var didAutoAdvance: Bool = false
    @State private var pendingAutoNextWork: DispatchWorkItem? = nil

    // ✅ match Farm feel
    private let selectionPulseDuration: Double = 0.6
    private let autoAdvanceDelay: Double = 0.2

    // =========================================================
    // MARK: - Sentinels
    // =========================================================

    /// Session-only flag:
    /// Mixed means animals keep their existing mob values.
    static let mixedSentinel = "__MOB_MIXED__"
    static let noneSentinel  = "__MOB_NONE__"

    // =========================================================
    // MARK: - Body
    // =========================================================

    var body: some View {
        WizardTileGrid(
            title: "Mob",
            caption: "Pick the mob for this session. Use Mixed to preserve each animal’s existing mob.",
            tiles: mobTiles,
            selection: selectionBinding,
            allowsMultipleSelection: false,
            onSelectionChanged: { selected in

                guard let first = selected.first else { return }
                guard !didAutoAdvance else { return }
                didAutoAdvance = true

                pendingAutoNextWork?.cancel()

                // ✅ animate selection so user sees it
                withAnimation(.spring(response: selectionPulseDuration, dampingFraction: 1.0)) {
                    let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        selectedMobName = SessionSetupMobStepView.noneSentinel
                    } else {
                        selectedMobName = trimmed
                    }
                }

                let work = DispatchWorkItem { onAutoNext() }
                pendingAutoNextWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay, execute: work)
            }
        )
        .onAppear {
            didAutoAdvance = false
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
        }
        .onDisappear {
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
        }
        .onChange(of: selectedMobName) { _, _ in
            // if user comes back and changes choice, allow auto-advance again
            didAutoAdvance = false
        }
    }

    // =========================================================
    // MARK: - Tiles
    // =========================================================

    private var mobTiles: [WizardTile] {
        var out: [WizardTile] = []

        // Mixed + None first (always present)
        out.append(
            WizardTile(
                id: SessionSetupMobStepView.mixedSentinel,
                title: "Mixed",
                systemImage: "shuffle",
                tint: nil
            )
        )

        out.append(
            WizardTile(
                id: SessionSetupMobStepView.noneSentinel,
                title: "None",
                systemImage: "minus.circle",
                tint: nil
            )
        )

        // Farm mobs (show their configured colour)
        out.append(contentsOf: mobs.map { mob in
            WizardTile(
                id: mob.name,
                title: mob.name,
                systemImage: "circle.fill",
                subtitle: nil,
                tint: Color(hex: mob.colorHex)
            )
        })

        // ✅ Add New tile removed entirely

        return out
    }

    // =========================================================
    // MARK: - Selection Binding
    // =========================================================

    private var selectionBinding: Binding<Set<String>> {
        Binding(
            get: {
                let trimmed = selectedMobName.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = trimmed.isEmpty ? SessionSetupMobStepView.noneSentinel : trimmed
                return Set([v])
            },
            set: { newSet in
                guard let first = newSet.first else { return }

                // Keep sentinel values explicit in state.
                if first == SessionSetupMobStepView.noneSentinel {
                    selectedMobName = SessionSetupMobStepView.noneSentinel
                    return
                }

                if first == SessionSetupMobStepView.mixedSentinel {
                    selectedMobName = SessionSetupMobStepView.mixedSentinel
                    return
                }

                // Normal mob name
                selectedMobName = first
            }
        )
    }
}

// =========================================================
// MARK: - Helpers
// =========================================================

extension String {
    var isMobNone: Bool {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == SessionSetupMobStepView.noneSentinel
    }

    var isMobMixed: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines) == SessionSetupMobStepView.mixedSentinel
    }
}

private extension Color {
    /// Supports "#RRGGBB" or "RRGGBB" (and also "#AARRGGBB" if you ever store alpha).
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw

        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        switch s.count {
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)

        case 8:
            let a = Double((value >> 24) & 0xFF) / 255.0
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)

        default:
            // fallback
            self = .secondary
        }
    }
}
