import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var bridge: BridgeController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var inWindow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if bridge.status == .running {
                connectionDetails
                Divider()
            } else if case .failed(let message) = bridge.status {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            } else if bridge.status == .starting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Opening tunnel…").foregroundStyle(.secondary)
                }
                Divider()
            }
            activityList
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("dot-bridge").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { bridge.isActive }, set: { _ in bridge.toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(bridge.isActive ? "Stop the bridge" : "Start the bridge")
        }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            copyRow(title: "MCP server URL", value: bridge.mcpURL, monospaced: true)
            copyRow(title: "Pairing code", value: bridge.pairingCode, monospaced: true, large: true)
            Text("In ChatGPT on the web: Plugins → + → Add custom MCP server. Paste the URL, choose OAuth, then enter the pairing code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyRow(title: String, value: String?, monospaced: Bool, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(value ?? "—")
                    .font(large ? .system(.title2, design: .monospaced).weight(.semibold)
                                : .system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    bridge.copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Activity").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if bridge.logFile != nil {
                    Button("Open log") { bridge.openLog() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if bridge.activity.isEmpty {
                Text("Nothing yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(bridge.activity) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(entry.time, format: .dateTime.hour().minute().second())
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.summary)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .frame(height: inWindow ? 220 : 140)
            }
        }
    }

    private var footer: some View {
        HStack {
            if !inWindow {
                Button("Open window") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private var statusColor: Color {
        switch bridge.status {
        case .running: .green
        case .starting: .yellow
        case .failed: .red
        case .stopped: .gray
        }
    }

    private var statusText: String {
        switch bridge.status {
        case .running: "Connected to the internet"
        case .starting: "Starting…"
        case .failed: "Error"
        case .stopped: "Stopped"
        }
    }
}
