import SwiftUI

struct WeighModeView: View {
    let eid: String
    let weight: Decimal
    let locked: Bool
    let stable: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // MARK: - Weight styling (matches WeightDisplayView, but LOCKED = blue)

    private var highlightColor: Color {
        if locked { return .blue }
        if stable { return .green }
        return (scheme == .dark ? .white : .black)
    }

    private var isHighlightMode: Bool {
        locked || stable
    }

    private var boardBG: Color {
        if isHighlightMode {
            return highlightColor.opacity(scheme == .dark ? 0.22 : 0.14)
        } else {
            return scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
    }

    private var boardStroke: Color {
        if isHighlightMode {
            return highlightColor.opacity(scheme == .dark ? 0.75 : 0.55)
        } else {
            return Color.white.opacity(scheme == .dark ? 0.18 : 0.12)
        }
    }

    private var digitsColor: Color {
        isHighlightMode ? highlightColor : (scheme == .dark ? .white : .black)
    }

    private var unitColor: Color {
        (isHighlightMode ? highlightColor : Color.secondary)
            .opacity(scheme == .dark ? 0.9 : 1.0)
    }

    private var weightText: String {
        String(format: "%.1f", NSDecimalNumber(decimal: weight).doubleValue)
    }

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 18) {

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(eid.isEmpty ? "—" : eid)
                            .font(.headline)

                        HStack(spacing: 10) {
                            Label(
                                stable ? "Stable" : "Unstable",
                                systemImage: stable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            Label(
                                locked ? "Locked" : "Live",
                                systemImage: locked ? "lock.fill" : "dot.radiowaves.left.and.right"
                            )
                            .font(.subheadline)
                            .foregroundStyle(locked ? Color.blue : Color.secondary) // ✅ blue when locked
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                // ✅ BIG auction-board weight, pinned bottom-right
                HStack {
                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {

                        // keep the diagnostic pills logic (same labels)
                        HStack(spacing: 8) {
                            StatusPill("LOCKED", on: locked)
                            StatusPill("LIVE", on: !locked)
                            StatusPill("STABLE FLAG", on: stable)
                            StatusPill("GREEN MODE", on: (locked || stable))
                            Spacer()
                        }

                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(weightText)
                                .font(.system(size: 450, weight: .heavy, design: .monospaced)) // ✅ match
                                .foregroundStyle(digitsColor)                                  // ✅ match + blue lock
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)

                            Text("kg")
                                .font(.system(size: 80, weight: .semibold, design: .rounded))
                                .foregroundStyle(unitColor)
                                .padding(.bottom, 450 * 0.10)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(boardBG)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(boardStroke, lineWidth: isHighlightMode ? 2 : 1)
                    )
                    .animation(.easeInOut(duration: 0.18), value: locked)
                    .animation(.easeInOut(duration: 0.18), value: stable)
                }
                .padding(.horizontal, 16)

                Spacer()

                Text("Tap ✕ to exit Weigh Mode")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Small helper pill (same as WeightDisplayView)

private struct StatusPill: View {
    let text: String
    let on: Bool

    init(_ text: String, on: Bool) {
        self.text = text
        self.on = on
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(on ? Color.green.opacity(scheme == .dark ? 0.22 : 0.14)
                             : Color.secondary.opacity(scheme == .dark ? 0.18 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(on ? Color.green.opacity(scheme == .dark ? 0.75 : 0.55)
                               : Color.secondary.opacity(scheme == .dark ? 0.25 : 0.18),
                            lineWidth: 1)
            )
            .foregroundStyle(on ? Color.green : Color.secondary)
    }
}
