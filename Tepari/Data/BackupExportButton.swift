import SwiftUI

struct FullBackupExportButton: View {
    @EnvironmentObject var store: LocalDataStore
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                do {
                    exportURL = try store.exportFullBackupFile()
                    error = nil
                } catch {
                    error = error.localizedDescription
                }
            } label: {
                Label("Export FULL Backup", systemImage: "externaldrive.fill")
            }

            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Share Full Backup", systemImage: "square.and.arrow.up")
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }
}
