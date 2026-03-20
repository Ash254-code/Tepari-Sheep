import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CSVToolsView: View {

    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.colorScheme) private var scheme

    private enum ImportMode: String, Identifiable {
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

        var icon: String {
            switch self {
            case .animals:
                return "hare"
            case .historicalPreg:
                return "calendar.badge.clock"
            }
        }

        var helperText: String {
            switch self {
            case .animals:
                return "Import animal CSV files. Farm and PIC can be matched automatically from the CSV."
            case .historicalPreg:
                return "Import historical preg data using Eid, Year and LambNumber. This matches existing animals by EID and writes yearly lambing history."
            }
        }

        var loadedMessage: String {
            switch self {
            case .animals:
                return "Loaded animal CSV file."
            case .historicalPreg:
                return "Loaded historical preg CSV file."
            }
        }

        var summaryTitle: String {
            switch self {
            case .animals:
                return "Animal Import Complete"
            case .historicalPreg:
                return "Historical Preg Import Complete"
            }
        }

        var importButtonTitle: String {
            switch self {
            case .animals:
                return "Import Animals"
            case .historicalPreg:
                return "Import Historical Preg"
            }
        }
    }

    private enum DuplicateImportAction {
        case skip
        case replace
    }

    private struct ImportSummary: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var importText: String = ""
    @State private var importStatus: String = ""
    @State private var selectedImportMode: ImportMode = .animals

    @State private var isImporting: Bool = false
    @State private var importProgress: Double = 0
    @State private var importProgressLabel: String = "Preparing import..."
    @State private var importSummary: ImportSummary? = nil

    @State private var showFileImporter: Bool = false

    @State private var exportURL: URL? = nil
    @State private var exportStatus: String = ""
    @State private var exportError: String? = nil
    @State private var showExportFarmPicker: Bool = false

    @State private var pendingDuplicateImportText: String? = nil
    @State private var duplicateCount: Int = 0
    @State private var showDuplicateAlert: Bool = false

    private var trimmedImportText: String {
        importText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !isImporting && !trimmedImportText.isEmpty
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 22) {
                    headerCard
                    importCard
                    exportCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }

            if isImporting {
                importingOverlay
            }

            if let summary = importSummary {
                summaryOverlay(summary)
            }
        }
        .navigationTitle("CSV Tools")
        .navigationBarTitleDisplayMode(.inline)
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
        .confirmationDialog("Export Farm", isPresented: $showExportFarmPicker, titleVisibility: .visible) {
            ForEach(store.farms) { farm in
                Button(farm.name) {
                    generateExport(for: farm.id)
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose which farm to export.")
        }
        .alert("Duplicates Found", isPresented: $showDuplicateAlert) {
            Button("Skip \(duplicateCount) Duplicate\(duplicateCount == 1 ? "" : "s")") {
                runImportConfirmed(using: .skip)
            }

            Button("Replace \(duplicateCount) Existing") {
                runImportConfirmed(using: .replace)
            }

            Button("Cancel", role: .cancel) {
                pendingDuplicateImportText = nil
                duplicateCount = 0
                isImporting = false
                importProgress = 0
                importProgressLabel = "Preparing import..."
                importStatus = "Import cancelled."
            }
        } message: {
            Text("Found \(duplicateCount) duplicate record\(duplicateCount == 1 ? "" : "s"). Do you want to skip duplicates or replace existing records?")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tokenFillStrong)
                        .frame(width: 54, height: 54)

                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary(scheme))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Import and export farm data")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(GlassTheme.textPrimary(scheme))

                    Text("Use the buttons below to import animal CSVs, historical preg records, or export animal data.")
                        .font(.subheadline)
                        .foregroundStyle(GlassTheme.textSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
    }

    // MARK: - Import

    private var importCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "CSV Import",
                    subtitle: "Choose what you want to import, then load or paste your CSV."
                )

                HStack(spacing: 12) {
                    importTypeButton(.animals)
                    importTypeButton(.historicalPreg)
                }

                activeModeCard

                HStack(spacing: 12) {
                    actionButton(
                        title: "Browse CSV File",
                        icon: "folder",
                        prominent: false,
                        fullWidth: true
                    ) {
                        showFileImporter = true
                    }
                    .disabled(isImporting)

                    actionButton(
                        title: isImporting ? "Importing…" : selectedImportMode.importButtonTitle,
                        icon: isImporting ? nil : "square.and.arrow.down",
                        prominent: true,
                        fullWidth: true
                    ) {
                        runImport()
                    }
                    .disabled(!canImport)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Paste CSV", systemImage: "doc.plaintext")
                        .font(.headline)
                        .foregroundStyle(GlassTheme.textPrimary(scheme))

                    ZStack(alignment: .topLeading) {
                        editorBackground

                        TextEditor(text: $importText)
                            .scrollContentBackground(.hidden)
                            .padding(14)
                            .frame(minHeight: 240)
                            .foregroundStyle(GlassTheme.textPrimary(scheme))
                            .disabled(isImporting)
                            .background(Color.clear)

                        if trimmedImportText.isEmpty {
                            Text("Paste CSV content here...")
                                .foregroundStyle(GlassTheme.textTertiary(scheme))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }
                    }
                }

                if !importStatus.isEmpty {
                    infoBanner(
                        text: importStatus,
                        icon: "info.circle"
                    )
                }
            }
        }
    }

    private func importTypeButton(_ mode: ImportMode) -> some View {
        Button {
            selectedImportMode = mode
            importStatus = ""
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .semibold))

                Text(mode.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .glassButton(.fullWidth, tint: selectedImportMode == mode ? .blue : .gray)
        .disabled(isImporting)
    }

    private var activeModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: selectedImportMode.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GlassTheme.textPrimary(scheme))

                Text(selectedImportMode.title)
                    .font(.headline)
                    .foregroundStyle(GlassTheme.textPrimary(scheme))
            }

            Text(selectedImportMode.helperText)
                .font(.subheadline)
                .foregroundStyle(GlassTheme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokenFillSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tokenStrokeSoft, lineWidth: 1)
        )
    }

    // MARK: - Export

    private var exportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "CSV Export",
                    subtitle: "Export animal records for a farm."
                )

                if store.farms.isEmpty {
                    infoBanner(
                        text: "Add a farm first.",
                        icon: "exclamationmark.triangle"
                    )
                } else {
                    HStack(spacing: 12) {
                        actionButton(
                            title: "Generate CSV Export",
                            icon: "square.and.arrow.up",
                            prominent: true,
                            fullWidth: true
                        ) {
                            startExportFlow()
                        }

                        if let url = exportURL {
                            ShareLink(item: url) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up.on.square")
                                    Text("Share File")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .glassButton(.fullWidth, tint: .blue)
                        }
                    }
                }

                if !exportStatus.isEmpty {
                    infoBanner(text: exportStatus, icon: "checkmark.circle")
                }

                if let exportError {
                    errorBanner(exportError)
                }
            }
        }
    }

    // MARK: - Theme Styling

    private var tokenFillSoft: Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
    }

    private var tokenFillStrong: Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var tokenStrokeSoft: Color {
        GlassTheme.surfaceStroke(scheme)
    }

    // MARK: - Overlays

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.18 : 0.10)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Importing CSV...")
                    .font(.headline)
                    .foregroundStyle(GlassTheme.textPrimary(scheme))

                ProgressView(value: importProgress, total: 1.0)
                    .tint(.blue)
                    .frame(width: 220)

                Text("\(Int(importProgress * 100))% complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlassTheme.textPrimary(scheme))

                Text(importProgressLabel)
                    .font(.footnote)
                    .foregroundStyle(GlassTheme.textSecondary(scheme))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(
                GlassTheme.surfaceMaterial(scheme),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(GlassTheme.surfaceStroke(scheme), lineWidth: 1)
            )
        }
        .zIndex(10)
    }

    private func summaryOverlay(_ summary: ImportSummary) -> some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.30 : 0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(summary.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GlassTheme.textPrimary(scheme))

                Text(summary.message)
                    .font(.body)
                    .foregroundStyle(GlassTheme.textPrimary(scheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    importSummary = nil
                } label: {
                    Text("OK")
                        .frame(maxWidth: .infinity)
                }
                .glassButton(.fullWidth, tint: .blue)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(GlassTheme.surfaceMaterial(scheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(GlassTheme.surfaceStroke(scheme), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(GlassTheme.shadowOpacity(scheme)),
                radius: 20,
                x: 0,
                y: 12
            )
            .padding(.horizontal, 24)
        }
        .zIndex(20)
    }

    // MARK: - Reusable UI

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(GlassTheme.textPrimary(scheme))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(GlassTheme.textSecondary(scheme))
        }
    }

    private func infoBanner(text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(GlassTheme.textPrimary(scheme))
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(GlassTheme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tokenFillSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tokenStrokeSoft, lineWidth: 1)
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red.opacity(0.9))
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(GlassTheme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.red.opacity(scheme == .dark ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.red.opacity(scheme == .dark ? 0.24 : 0.18), lineWidth: 1)
        )
    }

    private func actionButton(
        title: String,
        icon: String?,
        prominent: Bool,
        fullWidth: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .glassButton(.fullWidth, tint: prominent ? .blue : .gray)
    }

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(tokenFillSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tokenStrokeSoft, lineWidth: 1)
            )
    }

    // MARK: - File Handling / Import / Export

    private func readCSV(from url: URL) {
        importStatus = ""

        do {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .utf16) else {
                importStatus = "Could not read CSV (unsupported encoding)."
                return
            }

            importText = text
            importStatus = selectedImportMode.loadedMessage
        } catch {
            importStatus = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func runImport() {
        importStatus = ""
        exportStatus = ""
        exportError = nil
        importSummary = nil
        importProgress = 0
        importProgressLabel = "Preparing import..."

        let trimmed = trimmedImportText
        guard !trimmed.isEmpty else {
            importStatus = "Paste or load a CSV first."
            return
        }

        switch selectedImportMode {
        case .animals:
            let foundDuplicates = store.animalDuplicateCountForImport(csvText: trimmed)
            duplicateCount = foundDuplicates

            if foundDuplicates > 0 {
                pendingDuplicateImportText = trimmed
                showDuplicateAlert = true
                return
            }

            pendingDuplicateImportText = trimmed
            performAnimalImport(using: .skip)

        case .historicalPreg:
            let foundDuplicates = store.historicalPregDuplicateCountForImport(
                csvText: trimmed,
                farmID: nil
            )
            duplicateCount = foundDuplicates

            if foundDuplicates > 0 {
                pendingDuplicateImportText = trimmed
                showDuplicateAlert = true
                return
            }

            pendingDuplicateImportText = trimmed
            performHistoricalPregImport(using: .skip)
        }
    }

    private func runImportConfirmed(using action: DuplicateImportAction) {
        switch selectedImportMode {
        case .animals:
            performAnimalImport(using: action)
        case .historicalPreg:
            performHistoricalPregImport(using: action)
        }
    }

    private func performAnimalImport(using action: DuplicateImportAction) {
        guard let text = pendingDuplicateImportText ?? Optional(trimmedImportText), !text.isEmpty else {
            importStatus = "Paste or load a CSV first."
            isImporting = false
            return
        }

        isImporting = true
        importProgress = 0.5
        importProgressLabel = "Importing animals..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let storeAction: LocalDataStore.DuplicateImportAction =
                (action == .skip) ? .skip : .replace

            let result = store.importAnimalsCSV(
                csvText: text,
                duplicateAction: storeAction
            )

            let summaryText = """
Total Animals: \(result.totalAnimals)
Animals Imported: \(result.animalsImported)
Animals Skipped: \(result.animalsSkipped)
Duplicates Skipped: \(result.duplicatesSkipped)
Replaced: \(result.animalsReplaced)
"""

            pendingDuplicateImportText = nil
            duplicateCount = 0
            importStatus = ""
            importProgress = 1
            importProgressLabel = "Animal import complete"
            isImporting = false
            importSummary = ImportSummary(
                title: selectedImportMode.summaryTitle,
                message: summaryText
            )
        }
    }

    private func performHistoricalPregImport(using action: DuplicateImportAction) {
        guard let text = pendingDuplicateImportText ?? Optional(trimmedImportText), !text.isEmpty else {
            importStatus = "Paste or load a CSV first."
            isImporting = false
            return
        }

        isImporting = true
        importProgress = 0
        importProgressLabel = "Preparing historical preg import..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let storeAction: LocalDataStore.DuplicateImportAction =
                (action == .skip) ? .skip : .replace

            let result = store.importHistoricalPregCSV(
                csvText: text,
                farmID: nil,
                duplicateAction: storeAction,
                progress: { completed, total in
                    let safeTotal = max(total, 1)
                    importProgress = min(max(Double(completed) / Double(safeTotal), 0), 1)
                    importProgressLabel = "Processing \(completed) of \(total) records"
                }
            )

            let summaryText = """
Imported: \(result.imported)
Unmatched: \(result.unmatched)
Skipped: \(result.skipped)
Duplicates Skipped: \(result.duplicatesSkipped)
Replaced: \(result.replaced)
"""

            pendingDuplicateImportText = nil
            duplicateCount = 0
            importStatus = ""
            importProgress = 1
            importProgressLabel = "Historical preg import complete"
            isImporting = false
            importSummary = ImportSummary(
                title: selectedImportMode.summaryTitle,
                message: summaryText
            )
        }
    }

    private func startExportFlow() {
        exportError = nil
        exportStatus = ""
        exportURL = nil

        guard !store.farms.isEmpty else {
            exportError = "No farm available."
            return
        }

        if store.farms.count == 1, let onlyFarmID = store.farms.first?.id {
            generateExport(for: onlyFarmID)
        } else {
            showExportFarmPicker = true
        }
    }

    private func generateExport(for farmID: UUID) {
        exportError = nil
        exportStatus = ""
        exportURL = nil

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
