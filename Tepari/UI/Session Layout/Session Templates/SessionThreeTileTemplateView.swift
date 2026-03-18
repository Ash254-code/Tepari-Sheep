import SwiftUI

struct SessionThreeTileTemplateView<TopContent: View, BottomLeadingContent: View, BottomTrailingContent: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let reservedBottomHeight: CGFloat
    let verticalSpacing: CGFloat
    let horizontalSpacing: CGFloat
    let topTileHeightRatio: CGFloat

    let topContent: () -> TopContent
    let bottomLeadingContent: () -> BottomLeadingContent
    let bottomTrailingContent: () -> BottomTrailingContent

    init(
        horizontalPadding: CGFloat = 12,
        topPadding: CGFloat = 8,
        bottomPadding: CGFloat = 8,
        reservedBottomHeight: CGFloat = 0,
        verticalSpacing: CGFloat = 10,
        horizontalSpacing: CGFloat = 10,
        topTileHeightRatio: CGFloat = 0.46,
        @ViewBuilder topContent: @escaping () -> TopContent,
        @ViewBuilder bottomLeadingContent: @escaping () -> BottomLeadingContent,
        @ViewBuilder bottomTrailingContent: @escaping () -> BottomTrailingContent
    ) {
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.reservedBottomHeight = reservedBottomHeight
        self.verticalSpacing = verticalSpacing
        self.horizontalSpacing = horizontalSpacing
        self.topTileHeightRatio = topTileHeightRatio
        self.topContent = topContent
        self.bottomLeadingContent = bottomLeadingContent
        self.bottomTrailingContent = bottomTrailingContent
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

                let rightWidth = max(0, (totalWidth - horizontalSpacing) / 3)
                let leftWidth = max(0, totalWidth - rightWidth - horizontalSpacing)

                let topHeight = max(0, (usableHeight - verticalSpacing) * 0.6)
                let bottomHeight = max(0, (usableHeight - verticalSpacing) * 0.4)

                HStack(spacing: horizontalSpacing) {

                    // LEFT: Weight (top) + Draft (bottom)
                    VStack(spacing: verticalSpacing) {

                        topContent() // 👉 Weight
                            .frame(
                                width: leftWidth,
                                height: topHeight,
                                alignment: .top
                            )
                            .clipped()

                        bottomLeadingContent() // 👉 Draft
                            .frame(
                                width: leftWidth,
                                height: bottomHeight,
                                alignment: .top
                            )
                            .clipped()
                    }

                    // RIGHT: Treatment (unchanged)
                    bottomTrailingContent()
                        .frame(
                            width: rightWidth,
                            height: usableHeight,
                            alignment: .top
                        )
                        .clipped()
                }
                .frame(
                    width: totalWidth,
                    height: usableHeight,
                    alignment: .top
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding + reservedBottomHeight)
            }else {
                let clampedTopRatio = min(max(topTileHeightRatio, 0.30), 0.70)
                let topTileHeight = max(0, (usableHeight - verticalSpacing) * clampedTopRatio)
                let bottomRowHeight = max(0, usableHeight - verticalSpacing - topTileHeight)
                let bottomTileWidth = max(0, (totalWidth - horizontalSpacing) / 2)

                VStack(spacing: verticalSpacing) {
                    topContent()
                        .frame(
                            width: totalWidth,
                            height: topTileHeight,
                            alignment: .top
                        )
                        .clipped()

                    HStack(spacing: horizontalSpacing) {
                        bottomLeadingContent()
                            .frame(
                                width: bottomTileWidth,
                                height: bottomRowHeight,
                                alignment: .top
                            )
                            .clipped()

                        bottomTrailingContent()
                            .frame(
                                width: bottomTileWidth,
                                height: bottomRowHeight,
                                alignment: .top
                            )
                            .clipped()
                    }
                    .frame(width: totalWidth, height: bottomRowHeight, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding + reservedBottomHeight)
            }
        }
    }
}
