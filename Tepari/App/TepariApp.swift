import SwiftUI
import UIKit

@main
struct TepariApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store = LocalDataStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var transport = TransportManager()

    // Global preset stores
    @StateObject private var treatmentPresets = TreatmentPresetStore()
    @StateObject private var animalClasses = AnimalClassStore()

    // Gun tools
    @StateObject private var tepariGun = TepariGunManager()
    @StateObject private var gunListener = GunListener()

    init() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            configureTabBarAppearance()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(transport)
                .environmentObject(treatmentPresets)
                .environmentObject(animalClasses)
                .environmentObject(tepariGun)
                .environmentObject(gunListener)
                .buttonStyle(HapticButtonStyle())
                .onAppear {
                    // Start gun listener automatically
                    gunListener.start(port: 2000)

                    // Ensure T1 scale connects when app opens
                    transport.ensureT1Connected()

                    // Start drafter auto-discovery on local network
                    DraftWifiController.startDiscovery()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        transport.appBecameActive()
                        DraftWifiController.startDiscovery()
                    } else if newPhase == .background {
                        DraftWifiController.stopDiscovery()
                    }
                }
        }
    }

    // =========================================================
    // MARK: - Tab bar appearance (iPhone only)
    // =========================================================

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = .clear

        func style(_ item: UITabBarItemAppearance) {
            item.normal.iconColor = .secondaryLabel
            item.selected.iconColor = .label

            item.normal.titleTextAttributes = [
                .foregroundColor: UIColor.secondaryLabel
            ]
            item.selected.titleTextAttributes = [
                .foregroundColor: UIColor.label
            ]

            item.normal.titlePositionAdjustment = .zero
            item.selected.titlePositionAdjustment = .zero
        }

        style(appearance.stackedLayoutAppearance)
        style(appearance.inlineLayoutAppearance)
        style(appearance.compactInlineLayoutAppearance)

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }

        tabBar.isTranslucent = true
        tabBar.itemPositioning = .centered
        tabBar.itemSpacing = 12
    }
}
