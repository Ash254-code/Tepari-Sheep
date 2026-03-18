import SwiftUI

/// Step: Session name (moved later so Suggest can incorporate session type).
/// NOTE: Renamed to avoid redeclaration collisions with any older legacy file.
struct SessionSetupNameStepView: View {

    @Binding var sessionNameText: String
    @Binding var didAssignSuggestedName: Bool

    /// Should:
    /// - Only assign a suggestion if the field is empty
    /// - Set didAssignSuggestedName = true when it assigns
    let suggestSessionNameIfNeeded: () -> Void

    /// Parent persists the current text into the draft/store
    let persistSessionNameNow: () -> Void

    // =========================================================
    // MARK: - Body
    // =========================================================

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {

                VStack(spacing: 6) {
                    Text("Session name")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("A suggested name is auto-filled. Edit it if you want.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider().opacity(0.18)

                // =========================================================
                // Large Glass Text Field
                // =========================================================

                TextField("Weigh – Main Yards", text: $sessionNameText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .onChange(of: sessionNameText) { _, _ in
                        persistSessionNameNow()
                    }

                HStack(spacing: 10) {

                    Button {
                        sessionNameText = ""
                        didAssignSuggestedName = false
                        suggestSessionNameIfNeeded()
                        persistSessionNameNow()
                    } label: {
                        Label("Suggest", systemImage: "wand.and.stars")
                    }
                    .glassButton(.compact)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)

        // Auto-suggest on entry (only fills if empty)
        .onAppear {
            autoSuggestIfEmpty()
        }
    }

    // =========================================================
    // MARK: - Helpers
    // =========================================================

    private func autoSuggestIfEmpty() {
        let trimmed = sessionNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }

        didAssignSuggestedName = false
        suggestSessionNameIfNeeded()
        persistSessionNameNow()
    }
}
