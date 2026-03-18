import SwiftUI

extension View {
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}
