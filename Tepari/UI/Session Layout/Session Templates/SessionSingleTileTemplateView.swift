import SwiftUI

struct SessionSingleTileTemplateView<Content: View>: View {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let reservedBottomHeight: CGFloat
    let content: () -> Content

    init(
        horizontalPadding: CGFloat = 12,
        topPadding: CGFloat = 8,
        bottomPadding: CGFloat = 8,
        reservedBottomHeight: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.reservedBottomHeight = reservedBottomHeight
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let usableHeight = max(
                0,
                geo.size.height - topPadding - bottomPadding - reservedBottomHeight
            )

            VStack(spacing: 0) {
                content()
                    .frame(
                        width: geo.size.width - (horizontalPadding * 2),
                        height: usableHeight,
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
