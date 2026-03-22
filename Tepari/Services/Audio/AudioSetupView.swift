import SwiftUI

struct AudioSetupView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var classStore: AnimalClassStore

    @State private var showResetConfirm = false

    private var standardTriggers: [SpeechTrigger] {
        SpeechTrigger.allCases.filter { $0 != .animalClassAnnouncement }
    }

    private var sortedClassNames: [String] {
        classStore.classes
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var enabledTriggerCount: Int {
        let baseCount = standardTriggers.filter { settings.speechSetting(for: $0).enabled }.count
        let classCount = sortedClassNames.filter { settings.classSpeechSetting(for: $0).enabled }.count
        return baseCount + classCount
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.08),
                    Color.cyan.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    generalCard
                    libraryCard
                    triggersCard
                    classTriggersCard
                    resetCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Audio Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pruneMissingClassAudio()
        }
        .onChange(of: classStore.classes) { _, _ in
            pruneMissingClassAudio()
        }
        .alert("Reset all triggers?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                settings.resetSpeechTriggersToDefaults()

                for className in sortedClassNames {
                    settings.setClassSpeech(for: className, enabled: false, phrase: className)
                    settings.setClassAudioConfig(for: className, .default)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will restore the default trigger phrases and re-enable all triggers.")
        }
    }

    private var headerCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice announcements")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Choose spoken phrases or imported clips for each trigger.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(12)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(spacing: 10) {
                    statusPill(
                        title: settings.audioEnabled ? "Enabled" : "Disabled",
                        systemImage: settings.audioEnabled ? "waveform.circle.fill" : "speaker.slash.fill",
                        tint: settings.audioEnabled ? .blue : .secondary
                    )

                    statusPill(
                        title: "\(settings.audioClips.count) clips",
                        systemImage: "music.note",
                        tint: .indigo
                    )

                    statusPill(
                        title: "\(enabledTriggerCount) active",
                        systemImage: "bolt.fill",
                        tint: .teal
                    )
                }
            }
        }
    }

    private var generalCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("General", systemImage: "slider.horizontal.3")

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice Announcements")
                            .font(.headline)

                        Text("Master control for all spoken phrases and clip playback.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.audioEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }

                Text("You can still turn individual triggers on or off below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var libraryCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Audio Library", systemImage: "waveform.badge.plus")

                NavigationLink {
                    AudioLibraryView()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.18))
                                .frame(width: 46, height: 46)

                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Clips")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Import, preview and delete your audio clips.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(settings.audioClips.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var triggersCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Speech Triggers", systemImage: "waveform.path.ecg")

                LazyVStack(spacing: 14) {
                    ForEach(standardTriggers) { trigger in
                        TriggerGlassCard(trigger: trigger)
                            .environmentObject(settings)
                    }
                }
            }
        }
    }

    private var classTriggersCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Class Speech Triggers", systemImage: "tag.fill")

                if sortedClassNames.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)

                        Text("No classes added yet. Add classes in Settings first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(sortedClassNames, id: \.self) { className in
                            ClassTriggerGlassCard(className: className)
                                .environmentObject(settings)
                        }
                    }
                }
            }
        }
    }

    private var resetCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Reset", systemImage: "arrow.counterclockwise")

                Text("Restore the default trigger phrases and switch all triggers back on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Triggers to Defaults")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(settings.speechTriggers.isEmpty && sortedClassNames.isEmpty)
            }
        }
    }

    private func pruneMissingClassAudio() {
        settings.pruneClassSpeechSettings(validClassNames: sortedClassNames)
        settings.pruneClassAudioOverrides(validClassNames: sortedClassNames)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }

    private func statusPill(title: String, systemImage: String, tint: Color) -> some View {
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
}

// MARK: - Trigger Card

private struct TriggerGlassCard: View {

    let trigger: SpeechTrigger

    @EnvironmentObject private var settings: AppSettings

    private var triggerEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.speechSetting(for: trigger).enabled },
            set: { settings.setSpeech(trigger, enabled: $0) }
        )
    }

    private var phraseBinding: Binding<String> {
        Binding(
            get: { settings.speechSetting(for: trigger).phrase },
            set: { settings.setSpeech(trigger, phrase: $0) }
        )
    }

    private var modeBinding: Binding<AudioOutputMode> {
        Binding(
            get: { settings.config(for: trigger).mode },
            set: { newMode in
                var c = settings.config(for: trigger)
                c.mode = newMode
                if newMode == .speech {
                    c.clipID = nil
                }
                settings.setConfig(trigger, c)
            }
        )
    }

    private var clipIDBinding: Binding<UUID?> {
        Binding(
            get: { settings.config(for: trigger).clipID },
            set: { newID in
                var c = settings.config(for: trigger)
                c.clipID = newID
                settings.setConfig(trigger, c)
            }
        )
    }

    private var isEnabled: Bool {
        settings.speechSetting(for: trigger).enabled
    }

    private var rowEnabled: Bool {
        settings.audioEnabled && isEnabled
    }

    private var selectedClipName: String {
        guard
            let clipID = settings.config(for: trigger).clipID,
            let clip = settings.audioClips.first(where: { $0.id == clipID })
        else {
            return "None"
        }
        return clip.name
    }

    private var selectedClip: UserAudioClip? {
        guard let clipID = settings.config(for: trigger).clipID else { return nil }
        return settings.audioClips.first(where: { $0.id == clipID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trigger.title)
                        .font(.headline)

                    Text(isEnabled ? "Configured for playback" : "Trigger turned off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: triggerEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }

            outputModePicker

            if modeBinding.wrappedValue == .speech {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spoken phrase")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Enter spoken phrase", text: phraseBinding)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.55)
                }
            }

            if modeBinding.wrappedValue == .clip {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected clip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if settings.audioClips.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text("No clips imported yet. Open Manage Clips first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        NavigationLink {
                            AudioClipPickerView(
                                selectedClipID: clipIDBinding,
                                settings: settings
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedClipName)
                                        .foregroundStyle(.primary)
                                    Text("Tap to choose audio clip")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.55)
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()

                if modeBinding.wrappedValue == .clip, let clip = selectedClip {
                    Button {
                        AudioManager.shared.playAudioFileFromDocuments(
                            storedFileName: clip.storedFileName
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!rowEnabled)
                    .opacity(rowEnabled ? 1 : 0.55)
                } else {
                    Button {
                        AudioManager.shared.playTrigger(trigger, settings: settings)
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!rowEnabled)
                    .opacity(rowEnabled ? 1 : 0.55)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        )
        .opacity(settings.audioEnabled ? 1 : 0.72)
    }

    private var outputModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(AudioOutputMode.allCases) { mode in
                    let selected = modeBinding.wrappedValue == mode

                    Button {
                        modeBinding.wrappedValue = mode
                    } label: {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? Color.blue : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
                }
            }
        }
    }
}

// MARK: - Class Trigger Card

private struct ClassTriggerGlassCard: View {

    let className: String

    @EnvironmentObject private var settings: AppSettings

    private var triggerEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.classSpeechSetting(for: className).enabled },
            set: { settings.setClassSpeech(for: className, enabled: $0) }
        )
    }

    private var phraseBinding: Binding<String> {
        Binding(
            get: { settings.classSpeechSetting(for: className).phrase },
            set: { settings.setClassSpeech(for: className, phrase: $0) }
        )
    }

    private var modeBinding: Binding<AudioOutputMode> {
        Binding(
            get: { settings.classAudioConfig(for: className).mode },
            set: { newMode in
                var c = settings.classAudioConfig(for: className)
                c.mode = newMode
                if newMode == .speech {
                    c.clipID = nil
                }
                settings.setClassAudioConfig(for: className, c)
            }
        )
    }

    private var clipIDBinding: Binding<UUID?> {
        Binding(
            get: { settings.classAudioConfig(for: className).clipID },
            set: { newID in
                var c = settings.classAudioConfig(for: className)
                c.clipID = newID
                settings.setClassAudioConfig(for: className, c)
            }
        )
    }

    private var isEnabled: Bool {
        settings.classSpeechSetting(for: className).enabled
    }

    private var rowEnabled: Bool {
        settings.audioEnabled && isEnabled
    }

    private var selectedClipName: String {
        guard
            let clipID = settings.classAudioConfig(for: className).clipID,
            let clip = settings.audioClips.first(where: { $0.id == clipID })
        else {
            return "None"
        }
        return clip.name
    }

    private var selectedClip: UserAudioClip? {
        guard let clipID = settings.classAudioConfig(for: className).clipID else { return nil }
        return settings.audioClips.first(where: { $0.id == clipID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(className)
                        .font(.headline)

                    Text(isEnabled ? "Speak this class when scanned" : "Class trigger turned off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: triggerEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }

            outputModePicker

            if modeBinding.wrappedValue == .speech {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spoken phrase")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Enter spoken phrase", text: phraseBinding)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.55)
                }
            }

            if modeBinding.wrappedValue == .clip {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected clip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if settings.audioClips.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text("No clips imported yet. Open Manage Clips first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        NavigationLink {
                            AudioClipPickerView(
                                selectedClipID: clipIDBinding,
                                settings: settings
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedClipName)
                                        .foregroundStyle(.primary)
                                    Text("Tap to choose audio clip")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.55)
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()

                if modeBinding.wrappedValue == .clip, let clip = selectedClip {
                    Button {
                        AudioManager.shared.playAudioFileFromDocuments(
                            storedFileName: clip.storedFileName
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!rowEnabled)
                    .opacity(rowEnabled ? 1 : 0.55)
                } else {
                    Button {
                        AudioManager.shared.playTrigger(
                            .animalClassAnnouncement,
                            settings: settings,
                            className: className
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!rowEnabled)
                    .opacity(rowEnabled ? 1 : 0.55)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        )
        .opacity(settings.audioEnabled ? 1 : 0.72)
    }

    private var outputModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(AudioOutputMode.allCases) { mode in
                    let selected = modeBinding.wrappedValue == mode

                    Button {
                        modeBinding.wrappedValue = mode
                    } label: {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? Color.blue : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
                }
            }
        }
    }
}

// MARK: - Clip Picker

private struct AudioClipPickerView: View {
    @Binding var selectedClipID: UUID?
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button {
                selectedClipID = nil
                dismiss()
            } label: {
                HStack {
                    Text("None (fallback to speech)")
                        .foregroundStyle(.primary)

                    Spacer()

                    if selectedClipID == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }

            ForEach(settings.audioClips) { clip in
                Button {
                    selectedClipID = clip.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(clip.name)
                                .foregroundStyle(.primary)

                            Text(clip.storedFileName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedClipID == clip.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Clip")
        .navigationBarTitleDisplayMode(.inline)
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
