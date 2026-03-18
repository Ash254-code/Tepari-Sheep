import SwiftUI

// =====================================================
// MARK: - Wizard Tile Model
// =====================================================

struct WizardTile: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let subtitle: String?
    let tint: Color?            // ✅ optional tint (e.g. mob colour)

    init(
        id: String,
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        tint: Color? = nil      // ✅ default nil so existing call sites still compile
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.tint = tint
    }
}


// =====================================================
// MARK: - Full-screen 2x5 Tile Grid (ALWAYS 10 tiles)
// =====================================================

struct WizardTileGrid: View {

    @Environment(\.colorScheme) private var scheme

    // ✅ HARD LOCKED GRID SIZE
    private let columns = 2
    private let rows = 5

    // Bigger tiles now that wizard is full screen
    private let tileHeight: CGFloat = 96

    let title: String
    let caption: String?

    /// Provide up to 10 tiles (grid pads with placeholders)
    let tiles: [WizardTile]

    /// Selected IDs
    @Binding var selection: Set<String>

    /// Multi-select or single-select
    var allowsMultipleSelection: Bool = true

    /// Disable rules per tile
    var isTileEnabled: (WizardTile) -> Bool = { _ in true }

    /// Locked appearance
    var isTileLockedOn: (WizardTile) -> Bool = { _ in false }

    /// Callback (now receives the current selection)
    var onSelectionChanged: (Set<String>) -> Void = { _ in }


    // =====================================================
    // MARK: Layout helpers
    // =====================================================

    private var paddedTiles: [WizardTile?] {
        let maxTiles = columns * rows
        let base = tiles.map { Optional($0) }
        if base.count >= maxTiles { return Array(base.prefix(maxTiles)) }
        return base + Array(repeating: nil, count: maxTiles - base.count)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: columns)
    }


    // =====================================================
    // MARK: Body
    // =====================================================

    var body: some View {
        VStack(spacing: 16) {

            header

            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(Array(paddedTiles.enumerated()), id: \.offset) { _, tile in
                    if let tile {
                        tileView(tile)
                    } else {
                        placeholderTile
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }


    // =====================================================
    // MARK: Header
    // =====================================================

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.top, 6)
    }


    // =====================================================
    // MARK: Tile
    // =====================================================

    private func tileView(_ tile: WizardTile) -> some View {

        let isSelected = selection.contains(tile.id)
        let enabled = isTileEnabled(tile)
        let locked = isTileLockedOn(tile)

        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return Button {

            guard enabled else { return }

            if allowsMultipleSelection {
                if isSelected {
                    selection.remove(tile.id)
                } else {
                    selection.insert(tile.id)
                }
            } else {
                selection = [tile.id]
            }

            onSelectionChanged(selection)

        } label: {

            ZStack {
                tileBackground(tile: tile, isSelected: isSelected, locked: locked)

                VStack(spacing: 6) {

                    Image(systemName: tile.systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tileIconStyle(for: tile, isSelected: isSelected, enabled: enabled))

                    Text(tile.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)

                    if let sub = tile.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let tint = tile.tint {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .opacity(enabled ? 1 : 0.35)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .contentShape(shape)
            .shadow(
                color: Color.black.opacity(tileShadowOpacity(isSelected: isSelected, enabled: enabled)),
                radius: tileShadowRadius(isSelected: isSelected),
                x: 0,
                y: tileShadowYOffset(isSelected: isSelected)
            )
            .scaleEffect(isSelected ? 0.985 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .saturation(enabled ? 1 : 0)
    }

    private func tileIconStyle(for tile: WizardTile, isSelected: Bool, enabled: Bool) -> some ShapeStyle {
        if !enabled { return AnyShapeStyle(.secondary) }

        if let tint = tile.tint {
            return AnyShapeStyle(tint)
        }

        return AnyShapeStyle(.primary)
    }

    private func tileBackground(tile: WizardTile, isSelected: Bool, locked: Bool) -> some View {
        let cornerRadius: CGFloat = 20

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tileFill(isSelected: isSelected))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tileStroke(tile: tile, isSelected: isSelected, locked: locked), lineWidth: isSelected || locked ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tileTopHighlight(isSelected: isSelected))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            )
    }

    private func tileFill(isSelected: Bool) -> AnyShapeStyle {
        if isSelected {
            if scheme == .light {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        } else {
            if scheme == .light {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            Color.white.opacity(0.68)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                return AnyShapeStyle(.ultraThinMaterial)
            }
        }
    }

    private func tileTopHighlight(isSelected: Bool) -> AnyShapeStyle {
        if scheme == .light {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.36 : 0.24),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.12 : 0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func tileStroke(tile: WizardTile, isSelected: Bool, locked: Bool) -> Color {
        if locked { return .orange }

        if isSelected {
            return tile.tint ?? Color.accentColor
        }

        if scheme == .light {
            return Color.black.opacity(0.10)
        } else {
            return Color.white.opacity(0.10)
        }
    }

    private func tileShadowOpacity(isSelected: Bool, enabled: Bool) -> Double {
        guard enabled else { return 0 }

        if scheme == .light {
            return isSelected ? 0.16 : 0.10
        } else {
            return isSelected ? 0.26 : 0.18
        }
    }

    private func tileShadowRadius(isSelected: Bool) -> CGFloat {
        isSelected ? 16 : 10
    }

    private func tileShadowYOffset(isSelected: Bool) -> CGFloat {
        isSelected ? 8 : 5
    }


    // =====================================================
    // MARK: Placeholder
    // =====================================================

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.clear)
            .frame(height: tileHeight)
    }
}
