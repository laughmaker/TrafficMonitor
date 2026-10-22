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
        .windowToolbarStyle(.unified)
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
        // 是否在 Dock 显示图标，由偏好控制（默认显示）。
        // info.plist 里为纯菜单栏（LSUIElement=YES），这里运行时切换为 .regular 即可让 App 出现在 Dock。
        Self.applyDockIconPreference()

        store.start()
        statusBarController.install(store: store)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        statusBarController.remove()
    }

    /// 根据偏好设置 Dock 图标显示。
    /// - `PreferenceKey.showDockIcon` 默认 `true`：Dock 与菜单栏同时存在。
    /// - 设为 `false`：仅菜单栏常驻（等价于 LSUIElement）。
    static func applyDockIconPreference() {
        let showInDock = UserDefaults.standard.object(forKey: PreferenceKey.showDockIcon) as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
