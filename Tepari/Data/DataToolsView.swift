import SwiftUI

struct DataToolsView: View {

    @EnvironmentObject private var store: LocalDataStore

    @State private var selectedFarmID: UUID? = nil
    @State private var exportURL: URL? = nil
    @State private var exportError: String? = nil

    var body: some View {
        List {
            Section("Farm") {
                if store.farms.isEmpty {
                    Text("Add a farm first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Farm", selection: Binding(
                        get: { selectedFarmID ?? store.farms.first?.id },
                        set: { selectedFarmID = $0 }
                    )) {
                        ForEach(store.farms) { f in
                            Text(f.name).tag(Optional(f.id))
                        }
                    }
                }
            }

            Section("CSV") {
                // ✅ Import
                NavigationLink {
                    CSVImportView(farmID: selectedFarmID ?? store.farms.first?.id)
                } label: {
                    Label("CSV Import", systemImage: "square.and.arrow.down")
                }
                .disabled(store.farms.isEmpty)

                // ✅ Export
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        generateExport()
                    } label: {
                        Label("Generate CSV Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.farms.isEmpty)

                    if let url = exportURL {
                        ShareLink(item: url) {
                            Label("Share CSV File", systemImage: "square.and.arrow.up.on.square")
                        }
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Data")
        .onAppear {
            if selectedFarmID == nil {
                selectedFarmID = store.farms.first?.id
            }
        }
    }

    private func generateExport() {
        exportError = nil
        exportURL = nil

        guard let farmID = selectedFarmID ?? store.farms.first?.id else {
            exportError = "No farm selected."
            return
        }

        let csv = store.exportAnimalsCSV(farmID: farmID, includeHeader: true)

        do {
            let safeName = (store.farms.first(where: { $0.id == farmID })?.name ?? "Farm")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")

            let filename = "Tepari_Animals_\(safeName)_\(ISO8601DateFormatter().string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try csv.data(using: .utf8)?.write(to: url, options: [.atomic])
            exportURL = url
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// ----------------------------------------------------------------------
/// Replace this with YOUR existing import view if it has a different name.
/// If you already have a CSV Import screen, rename this NavigationLink destination
/// to your real view.
/// ----------------------------------------------------------------------
private struct CSVImportView: View {
    @EnvironmentObject private var store: LocalDataStore

    let farmID: UUID?

    @State private var text: String = ""
    @State private var status: String = ""

    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

            Button("Import") {
                guard let farmID else { status = "No farm selected."; return }
                let result = store.importAnimalsCSV(farmID: farmID, csvText: text)
                status = "Imported \(result.imported), skipped \(result.skipped)"
            }
            .buttonStyle(.borderedProminent)
            .disabled(farmID == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !status.isEmpty {
                Text(status).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("CSV Import")
    }
}
