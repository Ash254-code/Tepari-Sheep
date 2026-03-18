import SwiftUI

struct WeightDisplayView: View {

    let weight: Double
    let locked: Bool
    let stable: Bool

    let eid: String?

    /// New: lets you hide the top diagnostic pills if you want a cleaner UI.
    var showDiagnostics: Bool = true

    @Environment(\.colorScheme) private var scheme

    // MARK: - Styling

    private var isGreenMode: Bool {
        locked || stable
    }

    private var boardBG: Color {
        if isGreenMode {
            return scheme == .dark ? Color.green.opacity(0.22) : Color.green.opacity(0.14)
        } else {
            return scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
    }

    private var boardStroke: Color {
        if isGreenMode {
            return Color.green.opacity(scheme == .dark ? 0.75 : 0.55)
        } else {
            return Color.white.opacity(scheme == .dark ? 0.18 : 0.12)
        }
    }

    private var digitsColor: Color {
        isGreenMode ? .green : (scheme == .dark ? .white : .black)
    }

    private var unitColor: Color {
        (isGreenMode ? Color.green : Color.secondary)
            .opacity(scheme == .dark ? 0.9 : 1.0)
    }

    // MARK: - UI

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            if showDiagnostics {
                HStack(spacing: 8) {
                    StatusPill("LOCKED", on: locked)
                    StatusPill("LIVE", on: !locked)
                    StatusPill("STABLE FLAG", on: stable)
                    StatusPill("GREEN MODE", on: isGreenMode)
                    Spacer()
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Drive size mainly from width so it grows in the new wide card.
                let dynamicDigitSize = max(88, min(w * 0.24, h * 0.80))
                let dynamicUnitSize = max(24, dynamicDigitSize * 0.28)

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(weight, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: dynamicDigitSize, weight: .heavy, design: .monospaced))
                        .foregroundStyle(digitsColor)
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text("kg")
                        .font(.system(size: dynamicUnitSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(unitColor)
                        .padding(.bottom, dynamicDigitSize * 0.10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(boardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(boardStroke, lineWidth: isGreenMode ? 2 : 1)
        )
        .overlay(alignment: .bottomLeading) {
            if let eid {
                Text(eid)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(scheme == .dark ? 0.35 : 0.08))
                    )
                    .padding(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: locked)
        .animation(.easeInOut(duration: 0.18), value: stable)
    }
}

// MARK: - Small helper pill

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
                    .fill(
                        on
                        ? Color.green.opacity(scheme == .dark ? 0.22 : 0.14)
                        : Color.secondary.opacity(scheme == .dark ? 0.18 : 0.10)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        on
                        ? Color.green.opacity(scheme == .dark ? 0.75 : 0.55)
                        : Color.secondary.opacity(scheme == .dark ? 0.25 : 0.18),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(on ? Color.green : Color.secondary)
    }
}
