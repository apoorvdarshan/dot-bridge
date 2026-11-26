import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let bridge = BridgeController()
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            AppSettings.showInDockKey: true,
            AppSettings.startOnLaunchKey: true
        ])
        AppSettings.applyDockVisibility(UserDefaults.standard.bool(forKey: AppSettings.showInDockKey))
        LoginItem.shared.configureDefault()
        if UserDefaults.standard.bool(forKey: AppSettings.startOnLaunchKey) {
            bridge.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow?() }
        return true
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
    @AppStorage(AppSettings.showInMenuBarKey) private var showInMenuBar = true

    var body: some Scene {
        Window("dot-bridge", id: "main") {
            PanelView(inWindow: true)
                .environmentObject(appDelegate.bridge)
                .background(WindowOpenerRegistrar(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showInMenuBar) {
            PanelView()
                .environmentObject(appDelegate.bridge)
                .background(WindowOpenerRegistrar(appDelegate: appDelegate))
        } label: {
            MenuBarIcon(bridge: appDelegate.bridge)
        }
        .menuBarExtraStyle(.window)

    }
}

private struct WindowOpenerRegistrar: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            appDelegate.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
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
