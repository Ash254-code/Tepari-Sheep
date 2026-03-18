import SwiftUI

/// Extracted Steps: Scanner Type, Weight Source, Session Name
/// plus the shared card helpers used by these steps.
struct SessionSetupSimpleCardSteps {

    // MARK: - Step Card Wrapper

    static func stepCard(title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider().opacity(0.18)

                content()
            }
        }
    }

    // MARK: - Picker Row

    static func pickerRow(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Toggle Row (with optional lock)

    static func toggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        isLocked: Bool,
        lockedReason: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                HStack(spacing: 8) {
                    Text(title)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.55 : 1)

            if isLocked, let reason = lockedReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// =========================================================
// MARK: - Individual Step Views (small, compile-friendly)
// =========================================================

struct SessionSetupScannerTypeStepView: View {

    @Binding var scannerType: LocalDataStore.ScannerType?

    var body: some View {
        SessionSetupSimpleCardSteps.stepCard(
            title: "Scanner Type",
            subtitle: "Choose your scanner hardware."
        ) {
            VStack(spacing: 10) {
                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Handler HD4",
                    subtitle: "Wi-Fi bridge",
                    isSelected: scannerType == .racewell
                ) {
                    scannerType = .racewell
                }

                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Stick Reader",
                    subtitle: "Bluetooth",
                    isSelected: scannerType == .stickReader
                ) {
                    scannerType = .stickReader
                }

                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Manual / Backup",
                    subtitle: "Keyboard entry",
                    isSelected: scannerType == .manual
                ) {
                    scannerType = .manual
                }
            }
        }
    }
}

struct SessionSetupWeightSourceStepView: View {

    @Binding var weightSource: LocalDataStore.WeightSource?

    var body: some View {
        SessionSetupSimpleCardSteps.stepCard(
            title: "Weight Source",
            subtitle: "Select where weight values come from."
        ) {
            VStack(spacing: 10) {
                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Tepari T1",
                    subtitle: "Wi-Fi / TCP stream",
                    isSelected: weightSource == .tepariT1
                ) {
                    weightSource = .tepariT1
                }

                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Manual",
                    subtitle: "Enter weights by hand",
                    isSelected: weightSource == .manual
                ) {
                    weightSource = .manual
                }

                SessionSetupSimpleCardSteps.pickerRow(
                    title: "Demo",
                    subtitle: "Generate sample weights",
                    isSelected: weightSource == .demo
                ) {
                    weightSource = .demo
                }
            }
        }
    }
}

struct SessionSetupSessionNameStepView: View {

    @Binding var sessionNameText: String

    var body: some View {
        SessionSetupSimpleCardSteps.stepCard(
            title: "Session Name",
            subtitle: "You can rename it any time."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("e.g. Weaning – North Paddock", text: $sessionNameText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
