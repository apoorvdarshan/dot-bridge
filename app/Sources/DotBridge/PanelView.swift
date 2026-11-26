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
                VStack(alignment: .leading, spacing: 12) {
                    if bridge.status == .running {
                        connectionDetails.dashboardCard()
                    } else if case .failed(let message) = bridge.status {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).textSelection(.enabled).dashboardCard()
                    }
                    activityList.dashboardCard()
                    SettingsView().dashboardCard()
                }
                .padding(12)
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 9)
        }
        .frame(width: inWindow ? 420 : 370, height: inWindow ? 590 : 500)
        .background(LinearGradient(colors: [.teal.opacity(0.12), .clear, .indigo.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2.weight(.semibold)).foregroundStyle(.teal)
                .frame(width: 42, height: 42)
                .background(.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text("dot-bridge").font(.system(.title3, design: .rounded).weight(.bold))
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
            Label("Connection", systemImage: "link").font(.headline)
            copyRow(title: "MCP server URL", value: bridge.mcpURL)
            copyRow(title: "Pairing code", value: bridge.pairingCode, large: true)
            Text("In ChatGPT on the web: Plugins → + → Add custom MCP server. Paste the URL, choose OAuth, then enter the pairing code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                Text("Bridge activity will appear here.")
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

private extension View {
    func dashboardCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)) }
    }
}
