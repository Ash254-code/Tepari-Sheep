import SwiftUI

struct EIDDisplayView: View {
    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.colorScheme) private var scheme

    let eid: String
    let farmID: UUID?

    private var hasEID: Bool {
        eid != "—" && !eid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mobTintColor: Color? {
        guard hasEID,
              let hex = store.mobColorHexForEID(eid, farmID: farmID) else { return nil }
        return Color(hex: hex)
    }

    private var mobTintOpacity: Double {
        scheme == .dark ? 0.34 : 0.22
    }

    var body: some View {
        HStack(spacing: 10) {

            VStack(alignment: .leading, spacing: 2) {
                Text("EID")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GlassTheme.textSecondary(scheme))

                Text(hasEID ? eid : "—")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GlassTheme.textPrimary(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            if hasEID {
                Button {
                    UIPasteboard.general.string = eid
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GlassTheme.textSecondary(scheme))
                        .padding(8)
                        .background(GlassTheme.surfaceMaterial(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(GlassTheme.surfaceStroke(scheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        GlassCard {
            HStack(spacing: 10) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("EID")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GlassTheme.textSecondary(scheme))

                    Text(hasEID ? eid : "—")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GlassTheme.textPrimary(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                if hasEID {
                    Button {
                        UIPasteboard.general.string = eid
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GlassTheme.textSecondary(scheme))
                            .padding(8)
                            .background(GlassTheme.surfaceMaterial(scheme))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(GlassTheme.surfaceStroke(scheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if let mobTintColor {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(mobTintColor.opacity(mobTintOpacity))
            }
        }
    }
}

private extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: "#", with: "")

        guard raw.count == 6 || raw.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value) else { return nil }

        let r, g, b, a: Double

        if raw.count == 8 {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
            a = Double(value & 0x000000FF) / 255.0
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
            a = 1.0
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
