import SwiftUI

struct SessionControlDock: View {

    @ObservedObject var model: SessionDockModel
    var treatTitleOverride: String? = nil
    var undoTitleOverride: String? = nil

    var body: some View {
        HStack(spacing: 0) {

            dockButton(
                state: model.treat,
                titleOverride: treatTitleOverride,
                accessibilityHint: model.treat.enabled
                    ? "Primary session action."
                    : "Primary session action unavailable."
            ) {
                model.onTreat()
            }

            divider

            dockButton(
                state: model.undo,
                titleOverride: undoTitleOverride,
                accessibilityHint: model.undo.enabled
                    ? "Secondary session action."
                    : "Secondary session action unavailable."
            ) {
                model.onUndo()
            }

            divider

            dockButton(
                state: model.newSession,
                accessibilityHint: "Start a new session."
            ) {
                model.onNewSession()
            }

            divider

            dockButton(
                state: model.display,
                accessibilityHint: "Show or hide extra session details."
            ) {
                model.onDisplay()
            }
        }
        .frame(height: dockHeight)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .opacity(0.6)
            .padding(.vertical, 14)
    }

    private var dockHeight: CGFloat { 100 }

    @ViewBuilder
    private func dockButton(
        state: SessionDockModel.ButtonState,
        titleOverride: String? = nil,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        let displayedTitle = titleOverride ?? state.title
        let isInteractable = state.enabled && !state.isLoading

        Button(action: action) {
            VStack(spacing: 8) {
                if state.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(state.isActive ? .white : .blue)
                } else {
                    Image(systemName: state.systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }

                Text(displayedTitle)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(state.isActive ? .white : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(state.isActive ? Color.blue.opacity(0.96) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        state.isActive ? Color.blue.opacity(0.98) : Color.clear,
                        lineWidth: state.isActive ? 1 : 0
                    )
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractable)
        .opacity(isInteractable ? 1.0 : 0.35)
        .accessibilityLabel(Text(displayedTitle))
        .accessibilityHint(Text(accessibilityHint))
        .modifier(EnabledPressFeedback(enabled: isInteractable))
    }
}

// =====================================================
// MARK: - Press feedback (enabled buttons only)
// =====================================================

private struct EnabledPressFeedback: ViewModifier {

    let enabled: Bool
    @State private var isPressed: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.85), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled else { return }
                        if !isPressed { isPressed = true }
                    }
                    .onEnded { _ in
                        if isPressed { isPressed = false }
                    }
            )
    }
}
