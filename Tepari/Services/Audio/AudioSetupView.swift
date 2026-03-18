import SwiftUI

struct AudioSetupView: View {

    @EnvironmentObject private var settings: AppSettings

    @State private var showResetConfirm = false

    var body: some View {
        Form {

            // =====================================================
            // Master Switch
            // =====================================================

            Section("General") {
                Toggle("Voice Announcements Enabled", isOn: $settings.audioEnabled)

                Text("This controls ALL announcements. You can also toggle each trigger below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // =====================================================
            // Audio Library
            // =====================================================

            Section("Audio Library") {
                NavigationLink {
                    AudioLibraryView()
                } label: {
                    HStack {
                        Text("Manage Clips")
                        Spacer()
                        Text("\(settings.audioClips.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Import your own audio then assign clips per trigger.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // =====================================================
            // Trigger List
            // =====================================================

            Section("Speech Triggers") {
                ForEach(SpeechTrigger.allCases) { trigger in
                    TriggerRow(trigger: trigger, settings: settings)
                }
            }

            // =====================================================
            // Reset
            // =====================================================

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Reset Triggers to Defaults")
                }
                .disabled(settings.speechTriggers.isEmpty)
            }
        }
        .navigationTitle("Audio Setup")
        .alert("Reset all triggers?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                settings.resetSpeechTriggersToDefaults()
                // NOTE: We keep clip assignments as-is.
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will restore the default phrases and re-enable all triggers.")
        }
    }
}

// =====================================================
// MARK: - Row
// =====================================================

private struct TriggerRow: View {

    let trigger: SpeechTrigger
    @ObservedObject var settings: AppSettings

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

    // ✅ FIX: bind directly to mode (no “binding-to-struct”)
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

    // ✅ FIX: bind directly to clipID
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

    private var rowEnabled: Bool {
        settings.audioEnabled && settings.speechSetting(for: trigger).enabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Toggle(trigger.title, isOn: triggerEnabledBinding)

            Picker("Output", selection: modeBinding) {
                ForEach(AudioOutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.speechSetting(for: trigger).enabled)

            if modeBinding.wrappedValue == .speech {
                TextField("Spoken phrase", text: phraseBinding)
                    .textInputAutocapitalization(.sentences)
                    .disabled(!settings.speechSetting(for: trigger).enabled)
                    .foregroundStyle(settings.speechSetting(for: trigger).enabled ? .primary : .secondary)
            }

            if modeBinding.wrappedValue == .clip {
                Picker("Clip", selection: clipIDBinding) {
                    Text("None (fallback to speech)").tag(UUID?.none)
                    ForEach(settings.audioClips) { clip in
                        Text(clip.name).tag(UUID?.some(clip.id))
                    }
                }
                .disabled(!settings.speechSetting(for: trigger).enabled || settings.audioClips.isEmpty)

                if settings.audioClips.isEmpty {
                    Text("No clips yet. Go to Manage Clips to import audio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()

                Button {
                    AudioManager.shared.playTrigger(trigger, settings: settings)
                } label: {
                    Label("Test", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!rowEnabled)
            }
        }
        .padding(.vertical, 6)
    }
}
