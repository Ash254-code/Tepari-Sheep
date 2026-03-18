import SwiftUI

/// ✅ Legacy Settings screen (GlassCard-based).
/// We keep it in the project (so nothing breaks), but it now simply routes to the new
/// Settings hub screen (`SettingsMenuView`) which is what "More" should open directly.
///
/// If you still want access to this legacy “all-in-one” settings page later,
/// we can add a row inside SettingsMenuView to open it.
struct SettingsView: View {

    var body: some View {
        SettingsMenuView()
    }
}
