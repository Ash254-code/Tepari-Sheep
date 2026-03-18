import SwiftUI

/// Wrap tab content so it never sits underneath the (possibly floating) tab bar overlay.
/// This solves iPad "card bumps tab bar" issues reliably.
struct TabBarCompactHost<Content: View, TabBar: View>: View {

    private let content: Content
    private let tabBar: TabBar

    // Tuned for iPad floating tab bar + blur + shadow
    private let iPadReservedHeight: CGFloat = 140
    private let iPhoneReservedHeight: CGFloat = 90

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder tabBar: () -> TabBar
    ) {
        self.content = content()
        self.tabBar = tabBar()
    }

    private var reservedBottomSpace: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? iPadReservedHeight : iPhoneReservedHeight
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ✅ This is the key: reserve space so content cannot sit under the bar.
            content
                .padding(.bottom, reservedBottomSpace)

            // ✅ Your custom tab bar overlay
            tabBar
        }
    }
}
