import Foundation
import Combine

@MainActor
final class DrafterController: ObservableObject {

    // =========================================================
    // MARK: - Published state
    // =========================================================

    @Published private(set) var currentPosition: DraftPosition = .straight
    @Published private(set) var isMoving: Bool = false

    /// ✅ Optional debug hook for UI/status feeds
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
        }
    }

    // =========================================================
    // MARK: - Public API (PHYSICAL)
    // =========================================================

    func draftAnimal(to position: DraftPosition) {
        executeMovement(to: position, isManualTest: false)
    }

    func manualTest(position: DraftPosition) {
        executeMovement(to: position, isManualTest: true)
    }

    /// Call this when all required jobs for the current animal are complete.
    /// Only releases automatically when auto release mode is job-based.
    func releaseIfJobsComplete() {
        guard settings.autoReleaseMode == .whenJobsComplete else { return }

        movementTask?.cancel()
        movementTask = Task { [weak self] in
            await self?.runReleaseSequence()
        }
    }

    /// Force release regardless of release mode.
    func releaseNow() {
        movementTask?.cancel()
        movementTask = Task { [weak self] in
            await self?.runReleaseSequence()
        }
    }

    func sessionEnded() {
        cancelMovement()

        if settings.returnHomeOnSessionEnd {
            moveToHome()
        }
    }

    func cancelMovement() {
        movementTask?.cancel()
        movementTask = nil
        isMoving = false
    }

    func moveToHome() {
        movementTask?.cancel()
        movementTask = Task { [weak self] in
            await self?.runMoveToHomeSequence()
        }
    }

    // =========================================================
    // MARK: - Public API (LOGICAL)
    // =========================================================
    /// ✅ NEW: Draft by logical target (preg/keep/cull/etc)
    /// Keeps preg / future flows independent of physical gate layout.
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
            try await sleep(settings.triggerDelaySeconds)

            try await performGateMove(to: target)
            currentPosition = target

            let holdSeconds = isManualTest
                ? settings.manualTestHoldSeconds
                : settings.gateHoldSeconds

            switch settings.autoReleaseMode {
            case .off:
                break

            case .timed:
                try await sleep(holdSeconds)
                try await runReleaseSequenceInline()

            case .whenJobsComplete:
                // Hold current position until session workflow says release.
                // No timed release here.
                break
            }

        } catch {
            // cancelled / timeout
        }

        isMoving = false
    }

    private func runReleaseSequence() async {
        if settings.blockWhileMoving && isMoving {
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

    private func runReleaseSequenceInline() async throws {
        if settings.releaseDelaySeconds > 0 {
            try await sleep(settings.releaseDelaySeconds)
        }

        if settings.releaseToHomePosition {
            try await performGateMove(to: .straight)
            currentPosition = .straight
        } else {
            releaseAllDraftRelays()
        }
    }

    private func runMoveToHomeSequence() async {
        isMoving = true

        do {
            try await performGateMove(to: .straight)
            currentPosition = .straight
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

    private func sendGateCommand(_ position: DraftPosition) {
        lastCommandSent = position
        print("DRAFT MOVE → \(position.label) (\(position.rawValue))")

        switch position {
        case .left:
            // Left = relay 1 on, relay 2 off
            DraftWifiController.releaseGate(2)
            DraftWifiController.holdGate(1)

        case .straight:
            // Centre/home = both off
            DraftWifiController.releaseGate(1)
            DraftWifiController.releaseGate(2)

        case .right:
            // Right = relay 2 on, relay 1 off
            DraftWifiController.releaseGate(1)
            DraftWifiController.holdGate(2)

        case .farRight:
            // Far right not wired yet - park in centre/home
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
