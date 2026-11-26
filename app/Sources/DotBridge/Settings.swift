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
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)
            Text("Hosting").font(.subheadline.weight(.semibold))
            Group {
                Picker("Address", selection: $hosting) {
                    Text("Temporary URL").tag("temporary")
                    Text("My permanent URL").tag("permanent")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
            Divider()
            DisclosureGroup("App preferences") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show in Dock", isOn: $showInDock)
                        .onChange(of: showInDock) { _, value in AppSettings.applyDockVisibility(value) }
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, value in setLaunchAtLogin(value) }
                    Toggle("Start the bridge when the app opens", isOn: $startOnLaunch)
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }.padding(.top, 6)
            }
            Divider()
            DisclosureGroup("Advanced bridge settings") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Allowed folders") {
                        TextField("Allowed folders", text: $allowedRoots, prompt: Text(NSHomeDirectory())).labelsHidden()
                    }
                    LabeledContent("Node path") {
                        TextField("Node path", text: $nodePath, prompt: Text("Automatic")).labelsHidden()
                    }
                    LabeledContent("Local port") {
                        TextField("Local port", value: $port, format: .number.grouping(.never)).labelsHidden()
                    }
                    Text("Separate folder paths with a colon.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
            Text("Hosting and bridge changes apply on the next start.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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
