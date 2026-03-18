import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CSVToolsView: View {

    @EnvironmentObject private var store: LocalDataStore

    private enum ImportMode: String, CaseIterable, Identifiable {
        case animals
        case historicalPreg

        var id: String { rawValue }

        var title: String {
            switch self {
            case .animals:
                return "Animals"
            case .historicalPreg:
                return "Historical Preg"
            }
        }

        var helperText: String {
            switch self {
            case .animals:
                return "Browse for a CSV file, or paste CSV below. CSV can include multiple farms using farm and/or pic columns. Minimum column: eid"
            case .historicalPreg:
                return "Import historical preg data using columns Eid, Year and LambNumber. This matches existing animals by EID and writes yearly history."
            }
        }

        var buttonLabel: String {
            switch self {
            case .animals:
                return "Import Animals"
            case .historicalPreg:
                return "Import Historical Preg"
            }
        }

        var loadedMessage: String {
            switch self {
            case .animals:
                return "Loaded file. Tap Import Animals."
            case .historicalPreg:
                return "Loaded file. Tap Import Historical Preg."
            }
        }
    }

    private struct ImportSummary: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var selectedFarmID: UUID? = nil

    @State private var importText: String = ""
    @State private var importStatus: String = ""
    @State private var importMode: ImportMode = .animals
    @State private var isImporting: Bool = false
    @State private var importSummary: ImportSummary? = nil

    @State private var showFileImporter: Bool = false

    @State private var exportURL: URL? = nil
    @State private var exportStatus: String = ""
    @State private var exportError: String? = nil

    var body: some View {
        ZStack {
            GlassBackground()
                .allowsHitTesting(false)

            List {

                // =========================
                // CSV Import
                // =========================
                Section("CSV Import") {
                    Picker("Import Type", selection: $importMode) {
                        ForEach(ImportMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isImporting)

                    Text(importMode.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if importMode == .historicalPreg {
                        if store.farms.isEmpty {
                            Text("Optional: choose a farm to limit matching, or leave it blank to match any farm.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Match Farm", selection: $selectedFarmID) {
                                Text("Any Farm").tag(Optional<UUID>.none)
                                ForEach(store.farms) { f in
                                    Text(f.name).tag(Optional(f.id))
                                }
                            }
                            .disabled(isImporting)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Browse CSV File", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImporting)

                        Button {
                            runImport()
                        } label: {
                            Group {
                                if isImporting {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Importing…")
                                    }
                                    .frame(maxWidth: .infinity)
                                } else {
                                    Label(importMode.buttonLabel, systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextEditor(text: $importText)
                        .frame(minHeight: 180)
                        .disabled(isImporting)

                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // =========================
                // CSV Export
                // =========================
                Section("CSV Export") {
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
                        .disabled(isImporting)

                        Button {
                            generateExport()
                        } label: {
                            Label("Generate CSV Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isImporting)

                        if let url = exportURL {
                            ShareLink(item: url) {
                                Label("Share CSV File", systemImage: "square.and.arrow.up.on.square")
                            }
                        }
                    }

                    if !exportStatus.isEmpty {
                        Text(exportStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            if isImporting {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.25)

                    Text("Importing CSV…")
                        .font(.headline)

                    Text("Please wait")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(radius: 12)
            }
        }
        .navigationTitle("CSV Import / Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedFarmID == nil {
                selectedFarmID = store.farms.first?.id
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                .commaSeparatedText,
                .plainText,
                UTType(filenameExtension: "csv") ?? .commaSeparatedText
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                readCSV(from: url)
            case .failure(let error):
                importStatus = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert(item: $importSummary) { summary in
            Alert(
                title: Text(summary.title),
                message: Text(summary.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func readCSV(from url: URL) {
        importStatus = ""
        do {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                importStatus = "Could not read CSV (unsupported encoding)."
                return
            }

            importText = text
            importStatus = importMode.loadedMessage
        } catch {
            importStatus = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func runImport() {
        importStatus = ""

        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            importStatus = "Paste or load a CSV first."
            return
        }

        isImporting = true

        DispatchQueue.main.async {
            switch importMode {
            case .animals:
                let result = store.importAnimalsCSV(csvText: trimmed)
                importStatus = "Imported \(result.imported), skipped \(result.skipped)"
                importSummary = ImportSummary(
                    title: "Animal Import Complete",
                    message: """
Imported: \(result.imported)
Skipped: \(result.skipped)
"""
                )

            case .historicalPreg:
                let result = store.importHistoricalPregCSV(
                    csvText: trimmed,
                    farmID: selectedFarmID
                )
                importStatus = "Imported \(result.imported), unmatched \(result.unmatched), skipped \(result.skipped)"
                importSummary = ImportSummary(
                    title: "Historical Preg Import Complete",
                    message: """
Imported: \(result.imported)
Unmatched: \(result.unmatched)
Skipped: \(result.skipped)
"""
                )
            }

            isImporting = false
        }
    }

    private func generateExport() {
        exportError = nil
        exportStatus = ""
        exportURL = nil

        guard let farmID = selectedFarmID ?? store.farms.first?.id else {
            exportError = "No farm selected."
            return
        }

        let csv = store.exportAnimalsCSV(farmID: farmID, includeHeader: true)

        do {
            let farmName = store.farms.first(where: { $0.id == farmID })?.name ?? "Farm"
            let safeFarm = farmName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")

            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")

            let filename = "Tepari_Animals_\(safeFarm)_\(stamp).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            guard let data = csv.data(using: .utf8) else {
                exportError = "Could not encode CSV."
                return
            }

            try data.write(to: url, options: [.atomic])
            exportURL = url
            exportStatus = "Ready to share."
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}
