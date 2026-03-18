import Foundation

final class DemoDataGenerator {

    struct Output {
        var eid: String
        var weight: Double
        var stable: Bool
    }

    // Your SessionViewModel timer runs ~10Hz
    private let hz: Int = 10

    // Per-animal state
    private var currentEID: String = "000000000000000"
    private var targetWeight: Double = 42.0

    private var animalTick: Int = 0              // ticks since this animal began
    private var animalDurationTicks: Int = 80    // total ticks until next animal (randomised each animal)

    // Wave/jitter
    private var phase: Double = 0

    // Tuning
    private let minWeight: Double = 30.0
    private let maxWeight: Double = 50.0

    // How long we “settle” before stable (seconds)
    private let settleSecondsRange: ClosedRange<Double> = 1.5...3.0

    // Once stable, keep stable true for the remaining time for this animal
    // (gives you a big stable window to lock/save/draft)
    private var stableStartsAtTick: Int = 25

    func next() -> Output {

        // -----------------------------------------------------
        // Start a new animal when needed
        // -----------------------------------------------------
        if animalTick == 0 || animalTick >= animalDurationTicks {
            startNewAnimal()
        }

        // -----------------------------------------------------
        // Weight behaviour:
        // - Unstable settle phase: bigger wobble + jitter
        // - Stable phase: tiny ripple only
        // -----------------------------------------------------
        phase += 0.20

        let isStable = (animalTick >= stableStartsAtTick)

        let weight: Double
        if isStable {
            // Stable: tiny movement
            let tinyRipple = sin(phase) * 0.03
            let tinyNoise  = sin(Double(animalTick) * 1.7) * 0.01
            weight = targetWeight + tinyRipple + tinyNoise
        } else {
            // Unstable: converge towards target with wobble
            // amplitude decays as we approach stable tick
            let progress = Double(animalTick) / Double(max(stableStartsAtTick, 1)) // 0..~1
            let amp = (1.0 - min(progress, 1.0)) * 2.8 + 0.4                       // starts big, decays

            let bigWave = sin(phase / 1.2) * amp
            let jitter  = sin(Double(animalTick) * 2.2) * 0.18
            weight = targetWeight + bigWave + jitter
        }

        let out = Output(
            eid: currentEID,
            weight: round(weight * 10) / 10.0, // 0.1kg steps like your UI
            stable: isStable
        )

        animalTick += 1
        return out
    }

    // MARK: - New animal setup

    private func startNewAnimal() {
        currentEID = DemoDataGenerator.randomEID()
        targetWeight = Double.random(in: minWeight...maxWeight)

        animalTick = 0

        // New animal every 5–10 seconds at ~10Hz => 50–100 ticks
        animalDurationTicks = Int.random(in: (5 * hz)...(10 * hz))

        // Settle for 1.5–3.0 seconds before stable
        let settleSeconds = Double.random(in: settleSecondsRange)
        stableStartsAtTick = max(5, Int(settleSeconds * Double(hz))) // minimum 0.5s-ish

        // Reset phase so each animal feels distinct
        phase = Double.random(in: 0...(Double.pi * 2))
    }

    static func randomEID() -> String {
        // 15 digits with possible leading zeros (same as your original)
        let n = Int.random(in: 0..<1_000_000_000)
        let m = Int.random(in: 0..<1_000_000_000)
        let s = String(format: "%06d%09d", n % 1_000_000, m)
        return s
    }
}
