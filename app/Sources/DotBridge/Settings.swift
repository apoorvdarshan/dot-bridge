import AppKit
import ServiceManagement
import SwiftUI

enum AppSettings {
    static let showInDockKey = "showInDock"
    static let startOnLaunchKey = "startOnLaunch"
    static let allowedRootsKey = "allowedRoots"
    static let publicURLKey = "publicURL"
    static let hostingKey = "hostingMode"
    static let nodePathKey = "nodePath"
    static let portKey = "port"

    private static var defaults: UserDefaults { .standard }

    static var allowedRoots: String { defaults.string(forKey: allowedRootsKey) ?? "" }
    static var publicURL: String { defaults.string(forKey: publicURLKey) ?? "" }
    static var defaultHosting: String { publicURL.isEmpty ? "temporary" : "permanent" }
    static var hosting: String { defaults.string(forKey: hostingKey) ?? defaultHosting }
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
    @AppStorage(AppSettings.hostingKey) private var hosting = AppSettings.defaultHosting
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
            Section("Hosting") {
                Picker("Address", selection: $hosting) {
                    Text("Temporary URL").tag("temporary")
                    Text("My permanent URL").tag("permanent")
                }
                if hosting == "permanent" {
                    TextField("Public HTTPS URL", text: $publicURL, prompt: Text("https://bridge.example.com"))
                    Text("In your own Cloudflare account, create a tunnel, install its connector on this Mac, and route your hostname to http://127.0.0.1:\(String(port)). An existing HTTPS reverse proxy also works.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Cloudflare tunnel setup ↗", destination: URL(string: "https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/")!)
                } else {
                    Text("No account required. The address changes when the bridge restarts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Allowed folders", text: $allowedRoots, prompt: Text(NSHomeDirectory()))
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
