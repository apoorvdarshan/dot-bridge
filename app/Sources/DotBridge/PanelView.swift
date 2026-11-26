import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var bridge: BridgeController
    @Environment(\.openWindow) private var openWindow
    var inWindow = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if bridge.status == .running {
                        connectionDetails
                    } else if case .failed(let message) = bridge.status {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).textSelection(.enabled)
                    }
                    Divider()
                    SettingsView()
                    Divider()
                    activityList
                }
                .padding(16)
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 9)
        }
        .frame(width: inWindow ? 420 : 370, height: inWindow ? 590 : 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("dot-bridge").font(.system(size: 22, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption)
                }
            }
            Spacer()
            Toggle("Bridge running", isOn: Binding(get: { bridge.isActive }, set: { _ in bridge.toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(bridge.isActive ? "Stop the bridge" : "Start the bridge")
        }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection").font(.headline)
            copyRow(title: "MCP server URL", value: bridge.mcpURL)
            copyRow(title: "Pairing code", value: bridge.pairingCode, large: true)
            DisclosureGroup("Connect to ChatGPT") {
                Text("In ChatGPT on the web: Plugins → + → Add custom MCP server. Paste the URL, choose OAuth, then enter the pairing code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }.font(.caption)
        }
    }

    private func copyRow(title: String, value: String?, large: Bool = false) -> some View {
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
                .accessibilityLabel("Copy \(title)")
                .help("Copy \(title)")
            }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                if bridge.logFile != nil {
                    Button("Open log") { bridge.openLog() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if bridge.activity.isEmpty {
                Text("No tool calls yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
