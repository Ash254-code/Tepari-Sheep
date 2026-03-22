import SwiftUI

struct SessionLandingCardView: View {

    let recentTitle: String?
    let onContinueRecent: (() -> Void)?
    let onStartNew: () -> Void

    var minCardHeight: CGFloat = 420

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let cardPadding: CGFloat = isLandscape ? 14 : 18
            let topPadding: CGFloat = isLandscape ? 14 : 18
            let heroSize: CGFloat = isLandscape ? 164 : 188
            let buttonVerticalPadding: CGFloat = isLandscape ? 14 : 16
            let interBlockGap: CGFloat = isLandscape ? 18 : 26
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, buttonVerticalPadding)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.gray.opacity(0.95))
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    if let onContinueRecent {
                        Button(action: onContinueRecent) {
                            Label("Resume Last Session", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, buttonVerticalPadding)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.gray.opacity(0.65))
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 10)
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
            let pulse = (sin(t * 1.15) + 1.0) * 0.5

            let outerRingScale = 1.00 + (0.045 * pulse)
            let outerRingOpacity = 0.58 + (0.22 * pulse)

            let scanArcScale = 0.98 + (0.05 * pulse)
            let scanArcOpacity = 0.40 + (0.35 * pulse)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.blue.opacity(0.30),
                                Color.blue.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: size * 0.65
                        )
                    )

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.blue.opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 12
                    )
                    .scaleEffect(outerRingScale)
                    .opacity(outerRingOpacity)
                    .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 0)

                Group {
                    Circle()
                        .trim(from: 0.16, to: 0.34)
                        .stroke(
                            Color.white.opacity(scanArcOpacity),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .frame(width: size * 0.78, height: size * 0.78)

                    Circle()
                        .trim(from: 0.16, to: 0.34)
                        .stroke(
                            Color.blue.opacity(scanArcOpacity * 0.95),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: size * 0.92, height: size * 0.92)
                }
                .scaleEffect(scanArcScale)
                .rotationEffect(.degrees(6))

                Group {
                    Circle()
                        .trim(from: 0.66, to: 0.84)
                        .stroke(
                            Color.white.opacity(scanArcOpacity),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .frame(width: size * 0.78, height: size * 0.78)

                    Circle()
                        .trim(from: 0.66, to: 0.84)
                        .stroke(
                            Color.blue.opacity(scanArcOpacity * 0.95),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: size * 0.92, height: size * 0.92)
                }
                .scaleEffect(scanArcScale)
                .rotationEffect(.degrees(-6))

                Image("sheep")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                    .frame(
                        width: size * 0.82,
                        height: size * 0.82
                    )
                    .offset(y: size * 0.03)

                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(x: size * 0.26, y: -size * 0.10)
                    .shadow(color: Color.white.opacity(0.55), radius: 8)
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
