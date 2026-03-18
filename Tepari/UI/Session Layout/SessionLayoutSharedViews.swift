import SwiftUI

// =========================================================
// MARK: - Draft Arrow Indicator
// =========================================================

struct DraftArrowIndicator: View {
    let position: DraftPosition
    let isMoving: Bool
    let maxArrowSize: CGFloat?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pulse = false
    @State private var wiggle = false

    init(position: DraftPosition, isMoving: Bool, maxArrowSize: CGFloat? = nil) {
        self.position = position
        self.isMoving = isMoving
        self.maxArrowSize = maxArrowSize
    }

    private var arrowSize: CGFloat {
        let base: CGFloat = (sizeClass == .regular ? 330 : 110)
        if let maxArrowSize {
            return max(64, min(base, maxArrowSize))
        }
        return base
    }

    private var tint: Color {
        switch position {
        case .left: return .blue
        case .straight: return .green
        case .right: return .purple
        case .farRight: return .orange
        }
    }

    private var symbolName: String {
        switch position {
        case .left: return "arrow.up.left.circle.fill"
        case .straight: return "arrow.up.circle.fill"
        case .right: return "arrow.up.right.circle.fill"
        case .farRight: return "arrow.right.circle.fill"
        }
    }

    private var label: String {
        switch position {
        case .left: return "LEFT"
        case .straight: return "STRAIGHT"
        case .right: return "RIGHT"
        case .farRight: return "FAR RIGHT"
        }
    }

    private var directionOffset: CGSize {
        guard isMoving else { return .zero }
        let scale = arrowSize / 110

        switch position {
        case .left:
            return wiggle ? CGSize(width: -10 * scale, height: -6 * scale)
                          : CGSize(width: -2 * scale, height: -1 * scale)
        case .straight:
            return wiggle ? CGSize(width: 0, height: -10 * scale)
                          : CGSize(width: 0, height: -2 * scale)
        case .right:
            return wiggle ? CGSize(width: 10 * scale, height: -6 * scale)
                          : CGSize(width: 2 * scale, height: -1 * scale)
        case .farRight:
            return wiggle ? CGSize(width: 12 * scale, height: 0)
                          : CGSize(width: 2 * scale, height: 0)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: arrowSize, weight: .heavy))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .opacity(isMoving ? 1.0 : 0.72)
                .scaleEffect(isMoving ? (pulse ? 1.06 : 1.00) : 0.96)
                .offset(directionOffset)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: position)
                .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
                .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: wiggle)

            Text(isMoving ? "DRAFTING \(label)..." : "NEXT: \(label)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulse = isMoving
            wiggle = isMoving
        }
        .onChange(of: isMoving) { _, moving in
            pulse = moving
            wiggle = moving
        }
    }
}

// =========================================================
// MARK: - Session Weight Board
// =========================================================

struct SessionWeightBoard: View {
    let weight: Double
    let locked: Bool
    let stable: Bool
    let onWeighMode: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var weightText: String {
        String(format: "%.1f", weight)
    }

    private var digitsColor: Color { .blue }

    private var boardBG: Color {
        if locked {
            return Color.blue.opacity(scheme == .dark ? 0.22 : 0.14)
        } else {
            return scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
    }

    private var boardStroke: Color {
        if locked {
            return Color.blue.opacity(scheme == .dark ? 0.75 : 0.55)
        } else {
            return Color.white.opacity(scheme == .dark ? 0.18 : 0.12)
        }
    }

    private var unitColor: Color {
        (locked ? Color.blue : Color.secondary)
            .opacity(scheme == .dark ? 0.9 : 1.0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                let digitSize = min(geo.size.width * 0.38, geo.size.height * 0.64)
                let unitSize = digitSize * 0.18

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(boardBG)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(boardStroke, lineWidth: locked ? 2 : 1)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(weightText)
                            .font(.system(size: digitSize, weight: .heavy, design: .monospaced))
                            .foregroundStyle(digitsColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text("kg")
                            .font(.system(size: unitSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(unitColor)
                            .padding(.bottom, digitSize * 0.10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    HStack(spacing: 10) {
                        SessionStatePill(
                            text: stable ? "Stable" : "Unstable",
                            systemImage: stable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                            color: stable ? .green : .secondary
                        )

                        SessionStatePill(
                            text: locked ? "Locked" : "Live",
                            systemImage: locked ? "lock.fill" : "dot.radiowaves.left.and.right",
                            color: locked ? .blue : .secondary
                        )

                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .padding(.trailing, 56)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onWeighMode) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: locked)
        .animation(.easeInOut(duration: 0.18), value: stable)
    }
}

struct SessionStatePill: View {
    let text: String
    let systemImage: String
    let color: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(scheme == .dark ? 0.22 : 0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(scheme == .dark ? 0.55 : 0.35), lineWidth: 1)
            )
    }
}

// =========================================================
// MARK: - Shared Session Panel Wrapper
// =========================================================

struct SessionTemplatePanel<Content: View>: View {
    let title: String
    let systemImage: String?
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)

                        if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                Divider().opacity(0.18)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// =========================================================
// MARK: - Portrait Stacked Session Templates
// =========================================================

struct SessionTwoPanelTemplateView<Top: View, Bottom: View>: View {
    let topMinHeight: CGFloat
    let bottomMinHeight: CGFloat

    @ViewBuilder let top: Top
    @ViewBuilder let bottom: Bottom

    init(
        topMinHeight: CGFloat = 220,
        bottomMinHeight: CGFloat = 220,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.topMinHeight = topMinHeight
        self.bottomMinHeight = bottomMinHeight
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 14
            let horizontalPad: CGFloat = 16
            let verticalPad: CGFloat = 14
            let safeBottom = geo.safeAreaInsets.bottom

            let availableHeight =
                geo.size.height
                - verticalPad
                - max(12, safeBottom)
                - gap

            let panelHeight = max(120, availableHeight / 2)

            VStack(spacing: gap) {
                top
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)

                bottom
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
            }
            .padding(.horizontal, horizontalPad)
            .padding(.top, verticalPad)
            .padding(.bottom, max(12, safeBottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}


struct SessionThreePanelTemplateView<Top: View, Middle: View, Bottom: View>: View {
    let topMinHeight: CGFloat
    let middleMinHeight: CGFloat
    let bottomMinHeight: CGFloat

    @ViewBuilder let top: Top
    @ViewBuilder let middle: Middle
    @ViewBuilder let bottom: Bottom

    init(
        topMinHeight: CGFloat = 170,
        middleMinHeight: CGFloat = 170,
        bottomMinHeight: CGFloat = 170,
        @ViewBuilder top: () -> Top,
        @ViewBuilder middle: () -> Middle,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.topMinHeight = topMinHeight
        self.middleMinHeight = middleMinHeight
        self.bottomMinHeight = bottomMinHeight
        self.top = top()
        self.middle = middle()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 14
            let horizontalPad: CGFloat = 16
            let verticalPad: CGFloat = 14
            let safeBottom = geo.safeAreaInsets.bottom

            let availableHeight =
                geo.size.height
                - verticalPad
                - max(12, safeBottom)
                - (gap * 2)

            let panelHeight = max(100, availableHeight / 3)

            VStack(spacing: gap) {
                top
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)

                middle
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)

                bottom
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
            }
            .padding(.horizontal, horizontalPad)
            .padding(.top, verticalPad)
            .padding(.bottom, max(12, safeBottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// =========================================================
// MARK: - Legacy Wrappers For Compatibility
// =========================================================

struct SessionTwoPanelTemplate<Top: View, Bottom: View>: View {
    let isPhone: Bool
    let topTitle: String
    let topSystemImage: String?
    let topSubtitle: String?
    let bottomTitle: String
    let bottomSystemImage: String?
    let bottomSubtitle: String?

    @ViewBuilder let topContent: Top
    @ViewBuilder let bottomContent: Bottom

    init(
        isPhone: Bool,
        topTitle: String,
        topSystemImage: String? = nil,
        topSubtitle: String? = nil,
        bottomTitle: String,
        bottomSystemImage: String? = nil,
        bottomSubtitle: String? = nil,
        @ViewBuilder topContent: () -> Top,
        @ViewBuilder bottomContent: () -> Bottom
    ) {
        self.isPhone = isPhone
        self.topTitle = topTitle
        self.topSystemImage = topSystemImage
        self.topSubtitle = topSubtitle
        self.bottomTitle = bottomTitle
        self.bottomSystemImage = bottomSystemImage
        self.bottomSubtitle = bottomSubtitle
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }

    var body: some View {
        SessionTwoPanelTemplateView {
            SessionTemplatePanel(
                title: topTitle,
                systemImage: topSystemImage,
                subtitle: topSubtitle
            ) {
                topContent
            }
        } bottom: {
            SessionTemplatePanel(
                title: bottomTitle,
                systemImage: bottomSystemImage,
                subtitle: bottomSubtitle
            ) {
                bottomContent
            }
        }
    }
}

struct SessionThreePanelTemplate<Top: View, Middle: View, Bottom: View>: View {
    let isPhone: Bool
    let topTitle: String
    let topSystemImage: String?
    let topSubtitle: String?
    let middleTitle: String
    let middleSystemImage: String?
    let middleSubtitle: String?
    let bottomTitle: String
    let bottomSystemImage: String?
    let bottomSubtitle: String?

    @ViewBuilder let topContent: Top
    @ViewBuilder let middleContent: Middle
    @ViewBuilder let bottomContent: Bottom

    init(
        isPhone: Bool,
        topTitle: String,
        topSystemImage: String? = nil,
        topSubtitle: String? = nil,
        middleTitle: String,
        middleSystemImage: String? = nil,
        middleSubtitle: String? = nil,
        bottomTitle: String,
        bottomSystemImage: String? = nil,
        bottomSubtitle: String? = nil,
        @ViewBuilder topContent: () -> Top,
        @ViewBuilder middleContent: () -> Middle,
        @ViewBuilder bottomContent: () -> Bottom
    ) {
        self.isPhone = isPhone
        self.topTitle = topTitle
        self.topSystemImage = topSystemImage
        self.topSubtitle = topSubtitle
        self.middleTitle = middleTitle
        self.middleSystemImage = middleSystemImage
        self.middleSubtitle = middleSubtitle
        self.bottomTitle = bottomTitle
        self.bottomSystemImage = bottomSystemImage
        self.bottomSubtitle = bottomSubtitle
        self.topContent = topContent()
        self.middleContent = middleContent()
        self.bottomContent = bottomContent()
    }

    var body: some View {
        SessionThreePanelTemplateView {
            SessionTemplatePanel(
                title: topTitle,
                systemImage: topSystemImage,
                subtitle: topSubtitle
            ) {
                topContent
            }
        } middle: {
            SessionTemplatePanel(
                title: middleTitle,
                systemImage: middleSystemImage,
                subtitle: middleSubtitle
            ) {
                middleContent
            }
        } bottom: {
            SessionTemplatePanel(
                title: bottomTitle,
                systemImage: bottomSystemImage,
                subtitle: bottomSubtitle
            ) {
                bottomContent
            }
        }
    }
}

// =========================================================
// MARK: - iPhone Actions Grid
// =========================================================

struct SessionActionsPhoneGrid: View {
    let isTCPConnected: Bool
    let isLocked: Bool
    let showDetails: Bool

    let onReweigh: () -> Void
    let onZero: () -> Void
    let onNewSession: () -> Void
    let onToggleDetails: () -> Void

    private let tileHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SessionWideTile(
                    title: "Reweigh",
                    systemImage: "arrow.clockwise",
                    dotColor: nil,
                    height: tileHeight,
                    enabled: true,
                    action: onReweigh
                )

                SessionWideTile(
                    title: "Zero",
                    systemImage: "scalemass.fill",
                    dotColor: nil,
                    height: tileHeight,
                    enabled: (isTCPConnected && !isLocked),
                    action: onZero
                )
            }

            HStack(spacing: 10) {
                SessionWideTile(
                    title: "New Session",
                    systemImage: "plus.circle",
                    dotColor: nil,
                    height: tileHeight,
                    enabled: true,
                    action: onNewSession
                )

                SessionWideTile(
                    title: showDetails ? "Hide" : "Display",
                    systemImage: showDetails ? "chevron.down" : "chevron.up",
                    dotColor: nil,
                    height: tileHeight,
                    enabled: true,
                    action: onToggleDetails
                )
            }
        }
    }
}

// =========================================================
// MARK: - Generic Wide Tile Button
// =========================================================

struct SessionWideTile: View {
    let title: String
    let systemImage: String?
    let dotColor: Color?
    let height: CGFloat
    let enabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        dotColor: Color? = nil,
        height: CGFloat,
        enabled: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.dotColor = dotColor
        self.height = height
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(.plain)
        .glassTileStyle(enabled: enabled)
        .disabled(!enabled)
    }
}

// =========================================================
// MARK: - Shared Tile Styling
// =========================================================

extension View {
    func glassTileStyle(enabled: Bool) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(enabled ? 0.14 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
