import SwiftUI

enum SessionLayoutFactory {

    /// Compute the layout mode from session types.
    /// IMPORTANT:
    /// "scan" is already shown in the fixed top area of the screen,
    /// so it must NOT consume one of the main body tile positions.
    static func mode(for types: Set<SetupSessionType>) -> SessionLayoutMode {

        let hasScan = types.contains(.scan)
        let hasDraft = types.contains(.draft)
        let hasWeigh = types.contains(.weigh) || types.contains(.fleeceWeigh)
        let hasTreat = types.contains(.treatment)

        // Scanner-style workflows
        let hasScannerish =
            hasScan ||
            hasDraft ||
            types.contains(.transfer) ||
            types.contains(.sale) ||
            hasTreat

        // Stick-reader workflows (no scanner-style workflow present)
        let isStickReaderOnly =
            (types.contains(.lambMarking) || types.contains(.fleeceWeigh)) && !hasScannerish

        if types.contains(.traitInput) {
            return .traitInput
        }

        if isStickReaderOnly {
            return .stickReader
        }

        // Transfer/Sale often share the same UX
        if types.contains(.transfer) || types.contains(.sale) {
            return .transferSale
        }

        // Main body tile count is based only on:
        // weigh / draft / treat
        // Scan does not count as a tile.
        if hasScannerish {
            switch (hasWeigh, hasDraft, hasTreat) {
            case (true, true, true):
                return .scanWeighTreatDraft

            case (true, true, false):
                return .scanWeighDraft

            case (true, false, true):
                return .scanWeighTreat

            case (false, true, true):
                // No dedicated draft+treat layout yet.
                // Prefer the draft-led scanner layout until one exists.
                return .scanDraft

            case (true, false, false):
                return .scanWeigh

            case (false, true, false):
                return .scanDraft

            case (false, false, true):
                return .treat

            case (false, false, false):
                return .scan
            }
        }

        return .unknown
    }

    /// Produce the correct runtime view.
    /// Keep the signatures consistent so swapping is painless.
    @ViewBuilder
    static func makeView(
        vm: SessionViewModel,
        activeTypes: Set<SetupSessionType>,
        showWeighMode: Binding<Bool>,
        showZeroConfirmation: Binding<Bool>,
        showDetails: Binding<Bool>,
        isPhone: Bool,
        isTCPConnected: Bool,
        scannedCount: Int,
        onStartNewSession: @escaping () -> Void,
        onSyncCoordinator: @escaping () -> Void,
        onGoToDraftTab: @escaping () -> Void = {}
    ) -> some View {

        let layoutMode = mode(for: activeTypes)

        switch layoutMode {

        case .scan:
            SessionLayoutScanView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession,
                onSyncCoordinator: onSyncCoordinator
            )

        case .scanWeigh:
            SessionLayoutScanWeighView(
                vm: vm,
                showWeighMode: showWeighMode,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount
            )

        case .scanDraft:
            SessionLayoutScanDraftView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession,
                onSyncCoordinator: onSyncCoordinator
            )

        case .scanWeighDraft:
            // Scan is handled at the top of screen, so this is a TWO-tile body:
            // weigh + draft
            SessionLayoutWeighDraftView(
                vm: vm,
                activeTypes: activeTypes,
                showWeighMode: showWeighMode,
                showZeroConfirmation: showZeroConfirmation,
                showDetails: showDetails,
                isPhone: isPhone,
                isTCPConnected: isTCPConnected,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession,
                onSyncCoordinator: onSyncCoordinator,
                onGoToDraftTab: onGoToDraftTab
            )

        case .scanWeighTreat:
            // Scan is handled at the top of screen, so this is a TWO-tile body:
            // weigh + treat
            SessionLayoutScanWeighTreatView(
                vm: vm,
                showWeighMode: showWeighMode,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount,
                onOpenTreatments: onGoToDraftTab
            )


        case .scanWeighTreatDraft:
            // Scan is handled at the top of screen, so this is a THREE-tile body:
            // weigh + draft + treat
            SessionLayoutScanWeighTreatDraftView(
                vm: vm,
                activeTypes: activeTypes,
                showWeighMode: showWeighMode,
                showZeroConfirmation: showZeroConfirmation,
                showDetails: showDetails,
                isPhone: isPhone,
                isTCPConnected: isTCPConnected,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession,
                onSyncCoordinator: onSyncCoordinator,
                onOpenTreatments: onGoToDraftTab,
                onGoToDraftTab: onGoToDraftTab
            )

        case .stickReader:
            SessionLayoutStickReaderView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                onStartNewSession: onStartNewSession
            )

        case .transferSale:
            SessionLayoutTransferSaleStubView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession
            )

        case .treat:
            SessionLayoutTreatmentView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                scannedCount: scannedCount,
                onStartNewSession: onStartNewSession
            )

        case .traitInput:
            SessionLayoutTraitInputView(
                vm: vm,
                activeTypes: activeTypes,
                showDetails: showDetails,
                isPhone: isPhone,
                onStartNewSession: onStartNewSession
            )

        case .unknown:
            SessionLayoutFallbackView(
                vm: vm,
                activeTypes: activeTypes,
                onStartNewSession: onStartNewSession
            )
        }
    }
}
