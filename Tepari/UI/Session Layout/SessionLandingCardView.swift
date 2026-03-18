import SwiftUI

struct SessionLandingCardView: View {

    let recentTitle: String?
    let onContinueRecent: (() -> Void)?
    let onStartNew: () -> Void

    var scannerConnected: Bool? = nil
    var scalesConnected: Bool? = nil
    var draftConnected: Bool? = nil

    var minCardHeight: CGFloat = 420

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let cardPadding: CGFloat = isLandscape ? 14 : 18
            let topPadding: CGFloat = isLandscape ? 14 : 18
            let heroSize: CGFloat = isLandscape ? 154 : 175
            let buttonVerticalPadding: CGFloat = isLandscape ? 14 : 16
            let bottomPillsPadding: CGFloat = isLandscape ? 18 : 14
            let interBlockGap: CGFloat = isLandscape ? 18 : 26
            let bottomSpacerMin: CGFloat = isLandscape ? 10 : 18
            let effectiveMinHeight = max(minCardHeight, isLandscape ? 380 : minCardHeight)

            VStack(spacing: 0) {

                VStack(spacing: isLandscape ? 8 : 10) {

                    heroMark(size: heroSize)
                        .padding(.top, topPadding)

                    Text("Ready to work")
                        .font(.title2.weight(.semibold))

                    VStack(spacing: 6) {
                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let recentTitle {
                            Text(recentTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Spacer().frame(height: interBlockGap)

                VStack(spacing: 14) {

                    Button(action: onStartNew) {
                        Label("Start New Session", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, buttonVerticalPadding)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if let onContinueRecent {
                        Button(action: onContinueRecent) {
                            Label("Resume Last Session", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, buttonVerticalPadding)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: bottomSpacerMin)

                if scannerConnected != nil || scalesConnected != nil || draftConnected != nil {
                    HStack(spacing: 10) {
                        if let v = scannerConnected { StatusPill(title: "Scanner", ok: v) }
                        if let v = scalesConnected { StatusPill(title: "Scale", ok: v) }
                        if let v = draftConnected { StatusPill(title: "Draft", ok: v) }
                    }
                    .padding(.bottom, bottomPillsPadding)
                } else {
                    Spacer().frame(height: bottomPillsPadding)
                }
            }
            .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .top)
            .padding(cardPadding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .frame(
                width: geo.size.width,
                height: geo.size.height,
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minCardHeight)
    }

    private func heroMark(size: CGFloat) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 1.1) + 1.0) * 0.5

            let ringScale = 1.00 + (0.06 * pulse)
            let ringOpacity = 0.30 + (0.35 * pulse)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.35),
                                Color.blue.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(Color.blue.opacity(0.75), lineWidth: 10)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                VStack(spacing: 6) {
                    Image("sheep")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(
                            width: size * 0.69,
                            height: size * 0.69
                        )

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: size * 0.103, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .offset(y: size * 0.034)
            }
            .frame(width: size, height: size, alignment: .center)
            .compositingGroup()
        }
        .frame(width: size, height: size)
    }

    private var subtitleText: String {
        onContinueRecent == nil
        ? "Start a new session to begin recording."
        : "Start a new session, or resume the last one."
    }
}

private struct StatusPill: View {
    let title: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
