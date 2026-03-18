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
        executeMovement(to: position)
    }

    func manualTest(position: DraftPosition) {
        executeMovement(to: position)
    }

    func sessionEnded() {
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
        executeMovement(to: .straight)
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
        executeMovement(to: physical)
    }

    // =========================================================
    // MARK: - Movement engine
    // =========================================================

    private func executeMovement(to target: DraftPosition) {

        if settings.blockWhileMoving && isMoving {
            return
        }

        movementTask?.cancel()

        movementTask = Task { [weak self] in
            await self?.runMovementSequence(target: target)
        }
    }

    private func runMovementSequence(target: DraftPosition) async {

        isMoving = true

        do {
            try await sleep(settings.triggerDelaySeconds)

            try await performGateMove(to: target)
            currentPosition = target

            try await sleep(settings.gateHoldSeconds)

            if settings.autoReleaseEnabled {
                try await performGateMove(to: .straight)
                currentPosition = .straight
            }

        } catch {
            // cancelled / timeout
        }

        isMoving = false
    }

    // =========================================================
    // MARK: - Hardware simulation
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
