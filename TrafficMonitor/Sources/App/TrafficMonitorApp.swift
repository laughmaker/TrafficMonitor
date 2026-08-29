import AppKit
import SwiftUI

@main
struct TrafficMonitorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: TrafficMonitorAppDelegate

    var body: some Scene {
        WindowGroup("流量监控", id: "dashboard") {
            DashboardSceneRoot(
                store: appDelegate.store,
                statusBarController: appDelegate.statusBarController
            )
        }
        .defaultSize(width: 1_080, height: 760)
        .windowToolbarStyle(.unifiedCompact)
    }
}

private struct DashboardSceneRoot: View {
    @ObservedObject var store: TrafficMonitorStore
    let statusBarController: MenuBarStatusController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DashboardView(store: store)
            .frame(minWidth: 860, minHeight: 600)
            .onAppear {
                store.start()
                statusBarController.openDashboard = {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

@MainActor
final class TrafficMonitorAppDelegate: NSObject, NSApplicationDelegate {
    let store = TrafficMonitorStore()
    let statusBarController = MenuBarStatusController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        statusBarController.install(store: store)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        statusBarController.remove()
    }
}
