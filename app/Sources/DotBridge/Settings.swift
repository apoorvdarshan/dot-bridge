import AppKit
import ServiceManagement
import SwiftUI

enum AppSettings {
    static let showInDockKey = "showInDock"
    static let startOnLaunchKey = "startOnLaunch"
    static let allowedRootsKey = "allowedRoots"
    static let publicURLKey = "publicURL"
    static let nodePathKey = "nodePath"
    static let portKey = "port"

    private static var defaults: UserDefaults { .standard }

    static var allowedRoots: String { defaults.string(forKey: allowedRootsKey) ?? "" }
    static var publicURL: String { defaults.string(forKey: publicURLKey) ?? "" }
    static var nodePath: String { defaults.string(forKey: nodePathKey) ?? "" }
    static var port: Int {
        let p = defaults.integer(forKey: portKey)
        return p > 0 ? p : 8787
    }

    static func applyDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show { NSApp.activate(ignoringOtherApps: true) }
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.showInDockKey) private var showInDock = true
    @AppStorage(AppSettings.startOnLaunchKey) private var startOnLaunch = true
    @AppStorage(AppSettings.allowedRootsKey) private var allowedRoots = ""
    @AppStorage(AppSettings.publicURLKey) private var publicURL = ""
    @AppStorage(AppSettings.nodePathKey) private var nodePath = ""
    @AppStorage(AppSettings.portKey) private var port = 8787
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("App") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, value in AppSettings.applyDockVisibility(value) }
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in setLaunchAtLogin(value) }
                Toggle("Start the bridge when the app opens", isOn: $startOnLaunch)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                TextField("Allowed folders", text: $allowedRoots, prompt: Text(NSHomeDirectory()))
                TextField("Fixed public URL", text: $publicURL, prompt: Text("Blank uses a Cloudflare quick tunnel"))
                TextField("Node path", text: $nodePath, prompt: Text("Found automatically"))
                TextField("Local port", value: $port, format: .number.grouping(.never))
            } header: {
                Text("Bridge")
            } footer: {
                Text("Separate folders with a colon. Changes apply the next time you start the bridge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
