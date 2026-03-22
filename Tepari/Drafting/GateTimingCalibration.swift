import SwiftUI

struct GateTimingCalibrationView: View {

    @EnvironmentObject private var draftSettings: DraftSettings
    @EnvironmentObject private var drafter: DrafterController

    var body: some View {
        List {

            // =====================================================
            // MARK: Auto Release
            // =====================================================

            Section("Auto Release") {
                Picker("Release Mode", selection: $draftSettings.autoReleaseMode) {
                    ForEach(DraftSettings.AutoReleaseMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("This screen calibrates physical gate timing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Auto Release On uses Trigger Delay, Move Duration, Hold Duration and Return Duration from this screen. Auto Release Off keeps the animal held until released by another control action.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // =====================================================
            // MARK: Movement Timing
            // =====================================================

            Section("Movement Timing") {

                sliderRow(
                    title: "Trigger Delay",
                    value: $draftSettings.triggerDelaySeconds,
                    range: 0...5,
                    step: 0.1,
                    unit: "s"
                )

                sliderRow(
                    title: "Move Duration",
                    value: $draftSettings.gateMoveDurationSeconds,
                    range: 0.1...5,
                    step: 0.1,
                    unit: "s"
                )

                sliderRow(
                    title: "Hold Duration",
                    value: $draftSettings.gateHoldSeconds,
                    range: 0.1...10,
                    step: 0.1,
                    unit: "s"
                )

                sliderRow(
                    title: "Return Duration",
                    value: $draftSettings.gateReturnSeconds,
                    range: 0.1...5,
                    step: 0.1,
                    unit: "s"
                )

                Text("Hold Duration is the timing used when Auto Release is On. With Auto Release Off, the animal stays held until explicitly released.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // =====================================================
            // MARK: Behaviour
            // =====================================================

            Section("Behaviour") {

                Toggle(
                    "Return home when session ends",
                    isOn: $draftSettings.returnHomeOnSessionEnd
                )

                Toggle(
                    "Start in home position",
                    isOn: $draftSettings.startInHomePosition
                )

                Toggle(
                    "Block new draft while moving",
                    isOn: $draftSettings.blockWhileMoving
                )

                Toggle(
                    "Release returns to home position",
                    isOn: $draftSettings.releaseToHomePosition
                )

                sliderRow(
                    title: "Release Delay",
                    value: $draftSettings.releaseDelaySeconds,
                    range: 0...5,
                    step: 0.1,
                    unit: "s"
                )
            }

            // =====================================================
            // MARK: Draft Controls
            // =====================================================

            Section("Draft Controls") {

                sliderRow(
                    title: "Gate Hold Time",
                    value: $draftSettings.gateHoldSeconds,
                    range: 0.1...20,
                    step: 0.1,
                    unit: "s"
                )

                Text("Use these controls to release the current animal or return the gate to home during calibration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {

                    Button("Release Now") {
                        drafter.releaseNow()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Move To Home") {
                        drafter.moveToHome()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }

            // =====================================================
            // MARK: Safety
            // =====================================================

            Section("Safety") {

                sliderRow(
                    title: "Movement Timeout",
                    value: $draftSettings.movementTimeoutSeconds,
                    range: 1...30,
                    step: 1,
                    unit: "s"
                )
            }
        }
        .navigationTitle("Gate Calibration")
    }
}

//////////////////////////////////////////////////////////////////
// MARK: - Slider Row Helper
//////////////////////////////////////////////////////////////////

private extension GateTimingCalibrationView {

    func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {

        VStack(alignment: .leading, spacing: 6) {

            HStack {
                Text(title)
                Spacer()
                Text(displayValue(for: value.wrappedValue, step: step, unit: unit))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: value,
                in: range,
                step: step
            )
        }
    }

    func displayValue(for value: Double, step: Double, unit: String) -> String {
        let usesWholeNumbers = step >= 1 && abs(step.rounded() - step) < 0.0001
        if usesWholeNumbers {
            return "\(Int(value.rounded())) \(unit)"
        } else {
            return String(format: "%.1f %@", value, unit)
        }
    }
}
