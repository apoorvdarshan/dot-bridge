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

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    private let configuredKey = "loginItemConfigured"
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func configureDefault() {
        refresh()
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        if status == .enabled || status == .requiresApproval {
            UserDefaults.standard.set(true, forKey: configuredKey)
        } else {
            // A fresh main-app login item can also report .notFound.
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: configuredKey)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
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
    @ObservedObject private var loginItem = LoginItem.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.system(size: 17, weight: .semibold, design: .rounded))
            Label("Hosting", systemImage: "network").font(.subheadline.weight(.semibold))
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
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    preference("Show in Dock", icon: "dock.rectangle", isOn: $showInDock)
                        .onChange(of: showInDock) { _, value in AppSettings.applyDockVisibility(value) }
                    Divider()
                    preference("Open at login", icon: "sunrise", isOn: Binding(
                        get: { loginItem.status == .enabled || loginItem.status == .requiresApproval },
                        set: { loginItem.setEnabled($0) }
                    ))
                    if loginItem.status == .requiresApproval {
                        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if let message = loginItem.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                    Divider()
                    preference("Start bridge on launch", icon: "bolt", isOn: $startOnLaunch)
                }
                .padding(.horizontal, 12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            } label: {
                Text("App preferences").font(.subheadline.weight(.semibold))
            }
            DisclosureGroup {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow {
                        Text("Allowed folders")
                        TextField("Allowed folders", text: $allowedRoots, prompt: Text(NSHomeDirectory()))
                    }
                    GridRow {
                        Text("Node path")
                        TextField("Node path", text: $nodePath, prompt: Text("Automatic"))
                    }
                    GridRow {
                        Text("Local port")
                        TextField("Local port", value: $port, format: .number.grouping(.never))
                    }
                    Text("Separate folder paths with a colon.")
                        .font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            } label: {
                Text("Advanced bridge settings").font(.subheadline.weight(.semibold))
            }
            Text("Hosting and bridge changes apply on the next start.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private func preference(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden()
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
}
