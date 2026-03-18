import SwiftUI

struct SessionTwoTileTemplateView<TopContent: View, BottomContent: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let reservedBottomHeight: CGFloat
    let interTileSpacing: CGFloat
    let topTileHeightRatio: CGFloat

    let topContent: () -> TopContent
    let bottomContent: () -> BottomContent

    init(
        horizontalPadding: CGFloat = 12,
        topPadding: CGFloat = 8,
        bottomPadding: CGFloat = 8,
        reservedBottomHeight: CGFloat = 0,
        interTileSpacing: CGFloat = 10,
        topTileHeightRatio: CGFloat = 0.46,
        @ViewBuilder topContent: @escaping () -> TopContent,
        @ViewBuilder bottomContent: @escaping () -> BottomContent
    ) {
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.reservedBottomHeight = reservedBottomHeight
        self.interTileSpacing = interTileSpacing
        self.topTileHeightRatio = topTileHeightRatio
        self.topContent = topContent
        self.bottomContent = bottomContent
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = max(0, geo.size.width - (horizontalPadding * 2))
            let usableHeight = max(
                0,
                geo.size.height - topPadding - bottomPadding - reservedBottomHeight
            )

            let isLandscape = geo.size.width > geo.size.height
            let isIPadLandscape = horizontalSizeClass == .regular && isLandscape

            if isIPadLandscape {
                let tileWidth = max(0, (totalWidth - interTileSpacing) / 2)

                HStack(spacing: interTileSpacing) {
                    topContent()
                        .frame(
                            width: tileWidth,
                            height: usableHeight,
                            alignment: .top
                        )
                        .clipped()

                    bottomContent()
                        .frame(
                            width: tileWidth,
                            height: usableHeight,
                            alignment: .top
                        )
                        .clipped()
                }
                .frame(width: totalWidth, height: usableHeight, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding + reservedBottomHeight)
            } else {
                let clampedTopRatio = min(max(topTileHeightRatio, 0.30), 0.70)
                let topTileHeight = max(0, (usableHeight - interTileSpacing) * clampedTopRatio)
                let bottomTileHeight = max(0, usableHeight - interTileSpacing - topTileHeight)

                VStack(spacing: interTileSpacing) {
                    topContent()
                        .frame(
                            width: totalWidth,
                            height: topTileHeight,
                            alignment: .top
                        )
                        .clipped()

                    bottomContent()
                        .frame(
                            width: totalWidth,
                            height: bottomTileHeight,
                            alignment: .top
                        )
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding + reservedBottomHeight)
            }
        }
    }
}
