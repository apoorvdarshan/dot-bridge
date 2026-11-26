import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let bridge = BridgeController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            AppSettings.showInDockKey: false,
            AppSettings.startOnLaunchKey: true
        ])
        AppSettings.applyDockVisibility(UserDefaults.standard.bool(forKey: AppSettings.showInDockKey))
        if UserDefaults.standard.bool(forKey: AppSettings.startOnLaunchKey) {
            bridge.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.shutdownSync()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct DotBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(appDelegate.bridge)
        } label: {
            MenuBarIcon(bridge: appDelegate.bridge)
        }
        .menuBarExtraStyle(.window)

        Window("dot-bridge", id: "main") {
            PanelView(inWindow: true)
                .environmentObject(appDelegate.bridge)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarIcon: View {
    @ObservedObject var bridge: BridgeController

    var body: some View {
        switch bridge.status {
        case .running: Image(systemName: "point.3.filled.connected.trianglepath.dotted")
        case .starting: Image(systemName: "point.3.connected.trianglepath.dotted")
        case .failed: Image(systemName: "exclamationmark.triangle")
        case .stopped: Image(systemName: "point.3.connected.trianglepath.dotted")
        }
    }
}
