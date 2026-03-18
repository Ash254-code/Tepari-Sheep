import SwiftUI

struct GateTimingCalibrationView: View {

    @EnvironmentObject private var draftSettings: DraftSettings
    @EnvironmentObject private var drafter: DrafterController

    var body: some View {
        List {

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
            }

            // =====================================================
            // MARK: Behaviour
            // =====================================================

            Section("Behaviour") {

                Toggle(
                    "Auto return after animal",
                    isOn: $draftSettings.autoReleaseEnabled
                )

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
            }

            // =====================================================
            // MARK: Manual Testing
            // =====================================================

            Section("Manual Test") {

                sliderRow(
                    title: "Manual Hold Time",
                    value: $draftSettings.manualTestHoldSeconds,
                    range: 0.1...20,
                    step: 0.1,
                    unit: "s"
                )

                VStack(spacing: 10) {

                    HStack(spacing: 10) {

                        Button("Left") {
                            drafter.manualTest(position: .left)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Centre") {
                            drafter.manualTest(position: .straight)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 10) {

                        Button("Right") {
                            drafter.manualTest(position: .right)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Far Right") {
                            drafter.manualTest(position: .farRight)
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                Text("\(value.wrappedValue, specifier: "%.1f") \(unit)")
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: value,
                in: range,
                step: step
            )
        }
    }
}
