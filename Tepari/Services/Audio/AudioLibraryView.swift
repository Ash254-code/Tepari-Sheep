import SwiftUI
import UniformTypeIdentifiers

struct AudioLibraryView: View {

    @EnvironmentObject private var settings: AppSettings

    @State private var showImporter = false
    @State private var importError: String?
    @State private var clipPendingDelete: UserAudioClip?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.08),
                    Color.cyan.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    importCard
                    clipsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Audio Clips")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importPickedURLs(urls)
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
        .alert(
            "Delete clip?",
            isPresented: Binding(
                get: { clipPendingDelete != nil },
                set: { if !$0 { clipPendingDelete = nil } }
            ),
            presenting: clipPendingDelete
        ) { clip in
            Button("Delete", role: .destructive) {
                deleteClip(clip)
            }
            Button("Cancel", role: .cancel) { }
        } message: { clip in
            Text("This will remove \(clip.name) from your library.")
        }
    }

    private var headerCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your audio library")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Import clips, preview them, and use them for voice announcements.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "music.note.list")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(12)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(spacing: 10) {
                    statPill(
                        title: "\(settings.audioClips.count) clips",
                        systemImage: "waveform",
                        tint: .blue
                    )

                    statPill(
                        title: "Multi-import",
                        systemImage: "square.stack.3d.up.fill",
                        tint: .indigo
                    )
                }
            }
        }
    }

    private var importCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Import", systemImage: "square.and.arrow.down")

                Text("Add one or many audio files at once from Files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Import Audio Files")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    private var clipsCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Your Clips", systemImage: "speaker.wave.2.bubble")

                if settings.audioClips.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(settings.audioClips) { clip in
                            AudioClipCard(
                                clip: clip,
                                onPlay: {
                                    AudioManager.shared.playAudioFileFromDocuments(
                                        storedFileName: clip.storedFileName
                                    )
                                },
                                onDelete: {
                                    clipPendingDelete = clip
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 74, height: 74)

                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                Text("No clips imported yet")
                    .font(.headline)

                Text("Import audio files to build your clip library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)

            Text(title)
                .font(.title3.weight(.semibold))
        }
    }

    private func statPill(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.16), in: Capsule())
    }

    private func importPickedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        var failed: [String] = []

        for url in urls {
            do {
                let stored = try AudioClipStore.importFile(from: url)
                let display = url.deletingPathExtension().lastPathComponent
                settings.audioClips.append(
                    UserAudioClip(name: display, storedFileName: stored)
                )
            } catch {
                failed.append(url.lastPathComponent)
            }
        }

        if !failed.isEmpty {
            importError = "Could not import: \(failed.joined(separator: ", "))"
        }
    }

    private func deleteClip(_ clip: UserAudioClip) {
        try? AudioClipStore.delete(storedFileName: clip.storedFileName)
        settings.audioClips.removeAll { $0.id == clip.id }
    }
}

// MARK: - Clip Card

private struct AudioClipCard: View {
    let clip: UserAudioClip
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.14))
                    .frame(width: 52, height: 52)

                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(clip.storedFileName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

// MARK: - Glass Panel

private struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}
