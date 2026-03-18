import SwiftUI
import UniformTypeIdentifiers

struct AudioLibraryView: View {

    @EnvironmentObject private var settings: AppSettings

    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        Form {

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Audio File", systemImage: "square.and.arrow.down")
                }
            }

            Section("Your Clips") {
                if settings.audioClips.isEmpty {
                    Text("No clips imported yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.audioClips) { clip in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.name)
                                Text(clip.storedFileName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                AudioManager.shared.playAudioFileFromDocuments(storedFileName: clip.storedFileName)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete(perform: deleteClips)
                }
            }
        }
        .navigationTitle("Audio Clips")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importPickedURL(url)

            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importPickedURL(_ url: URL) {
        do {
            let stored = try AudioClipStore.importFile(from: url)
            let display = url.deletingPathExtension().lastPathComponent
            settings.audioClips.append(UserAudioClip(name: display, storedFileName: stored))
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteClips(at offsets: IndexSet) {
        let clips = offsets.map { settings.audioClips[$0] }

        for clip in clips {
            try? AudioClipStore.delete(storedFileName: clip.storedFileName)
        }

        settings.audioClips.remove(atOffsets: offsets)
        // AppSettings will sanitize assignments automatically
    }
}
