import Foundation
import Combine

@MainActor
final class DrafterController: ObservableObject {

    // =========================================================
    // MARK: - Published state
    // =========================================================

    @Published private(set) var currentPosition: DraftPosition = .straight
    @Published private(set) var isMoving: Bool = false
    @Published private(set) var isHoldingAnimal: Bool = false

    /// Optional debug hook for UI/status feeds
    @Published private(set) var lastCommandSent: DraftPosition? = nil

    // =========================================================
    // MARK: - Dependencies
    // =========================================================

    let settings: DraftSettings

    // =========================================================
    // MARK: - Internals
    // =========================================================

    private var movementTask: Task<Void, Never>?

    // =========================================================
    // MARK: - Init
    // =========================================================

    init(settings: DraftSettings) {
        self.settings = settings

        if settings.startInHomePosition {
            currentPosition = .straight
            isHoldingAnimal = false
        }
    }

    // =========================================================
    // MARK: - Public API (PHYSICAL)
    // =========================================================

    func draftAnimal(to position: DraftPosition) {
        executeMovement(to: position, isManualTest: false)
    }

    func releaseNow() {
        releaseHeldAnimal()
    }

    /// Explicit physical release for a held animal.
    /// This pulses the release relay and leaves the draft gate where it is.
    func releaseHeldAnimal() {
        movementTask?.cancel()
        movementTask = Task { [weak self] in
            await self?.runReleaseSequence()
        }
    }

    func sessionEnded() {
        cancelMovement()

        if settings.returnHomeOnSessionEnd {
            moveToHome()
        } else {
            isHoldingAnimal = false
        }
    }

    func cancelMovement() {
        movementTask?.cancel()
        movementTask = nil
        isMoving = false
    }

    /// Explicitly return draft gate to centre/home.
    /// This is separate from "release".
    func moveToHome() {
        movementTask?.cancel()
        movementTask = Task { [weak self] in
            await self?.runMoveToHomeSequence()
        }
    }

    // =========================================================
    // MARK: - Public API (LOGICAL)
    // =========================================================

    func draftAnimal(
        logical target: DraftLogicalTarget,
        using map: DraftGateMap
    ) {
        let physical = map.physical(for: target)
        executeMovement(to: physical, isManualTest: false)
    }

    // =========================================================
    // MARK: - Movement engine
    // =========================================================

    private func executeMovement(to target: DraftPosition, isManualTest: Bool) {
        if settings.blockWhileMoving && isMoving {
            return
        }

        movementTask?.cancel()

        movementTask = Task { [weak self] in
            await self?.runMovementSequence(target: target, isManualTest: isManualTest)
        }
    }

    private func runMovementSequence(target: DraftPosition, isManualTest: Bool) async {
        isMoving = true

        do {
            if !isManualTest {
                try await sleep(settings.triggerDelaySeconds)
            }

            try await performGateMove(to: target)
            currentPosition = target
            isHoldingAnimal = target != .straight

            if settings.isAutoReleaseOn {
                try await sleep(settings.gateHoldSeconds)
                try await runReleaseSequenceInline()
            }

        } catch {
            // cancelled / timeout
        }

        isMoving = false
    }

    private func runReleaseSequence() async {
        if !isHoldingAnimal {
            return
        }

        isMoving = true

        do {
            try await runReleaseSequenceInline()
        } catch {
            // cancelled / timeout
        }

        isMoving = false
    }

    /// Real animal release:
    /// pulse the release relay, leave draft gate in its current position.
    private func runReleaseSequenceInline() async throws {
        if settings.releaseDelaySeconds > 0 {
            try await sleep(settings.releaseDelaySeconds)
        }

        DraftWifiController.pulseRelease()
        isHoldingAnimal = false
    }

    private func runMoveToHomeSequence() async {
        isMoving = true

        do {
            try await performReturnToHome()
            currentPosition = .straight
            isHoldingAnimal = false
        } catch {
            // cancelled / timeout
        }

        isMoving = false
    }

    // =========================================================
    // MARK: - Hardware control
    // =========================================================

    private func performGateMove(to position: DraftPosition) async throws {
        sendGateCommand(position)

        try await withTimeout(
            seconds: self.settings.movementTimeoutSeconds
        ) { [self] in
            try await self.sleep(self.settings.gateMoveDurationSeconds)
        }
    }

    private func performReturnToHome() async throws {
        sendGateCommand(.straight)

        try await withTimeout(
            seconds: self.settings.movementTimeoutSeconds
        ) { [self] in
            try await self.sleep(self.settings.gateReturnSeconds)
        }
    }

    private func sendGateCommand(_ position: DraftPosition) {
        lastCommandSent = position
        print("DRAFT MOVE → \(position.label) (\(position.rawValue))")

        switch position {
        case .left:
            DraftWifiController.releaseGate(2)
            DraftWifiController.holdGate(1)

        case .straight:
            DraftWifiController.releaseGate(1)
            DraftWifiController.releaseGate(2)

        case .right:
            DraftWifiController.releaseGate(1)
            DraftWifiController.holdGate(2)

        case .farRight:
            DraftWifiController.releaseGate(1)
            DraftWifiController.releaseGate(2)
        }
    }

    private func releaseAllDraftRelays() {
        DraftWifiController.releaseGate(1)
        DraftWifiController.releaseGate(2)
    }

    // =========================================================
    // MARK: - Helpers
    // =========================================================

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func withTimeout(
        seconds: Double,
        operation: @escaping () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }

            try await group.next()
            group.cancelAll()
        }
    }
}
