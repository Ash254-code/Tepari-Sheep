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
                NavigationLink {
                    CSVImportView()
                } label: {
                    Label("CSV Import", systemImage: "square.and.arrow.down")
                }
                .disabled(store.farms.isEmpty)

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

private struct CSVImportView: View {
    @EnvironmentObject private var store: LocalDataStore

    @State private var text: String = ""
    @State private var status: String = ""

    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

            Button(action: {
                let result = store.importAnimalsCSV(csvText: text)
                status = """
                Total Animals: \(result.totalAnimals)
                Animals Imported: \(result.animalsImported)
                Animals Skipped: \(result.animalsSkipped)
                Duplicates Skipped: \(result.duplicatesSkipped)
                Replaced: \(result.animalsReplaced)
                """
            }) {
                Text("Import")
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !status.isEmpty {
                Text(status)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("CSV Import")
    }
}
