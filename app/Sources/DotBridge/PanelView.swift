import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var bridge: BridgeController
    @Environment(\.openWindow) private var openWindow
    var inWindow = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(bridge.requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Approve on this Mac", systemImage: "lock.shield").font(.headline)
                            Text("Match \(request.id.prefix(8)) with your browser. Approving lets this client run commands as you.")
                            Text("Callback: \(request.host)").font(.caption)
                            HStack {
                                Button("Deny") { bridge.decide("deny", for: request) }
                                Button("Approve") { bridge.decide("approve", for: request) }
                            }
                        }
                    }
                    connectionDetails
                    if !bridge.paired.isEmpty {
                        DisclosureGroup("Paired connections (\(bridge.paired.count))") {
                            ForEach(bridge.paired) { client in
                                HStack {
                                    Text("\(client.host) · \(client.id.prefix(8))")
                                    Spacer()
                                    Button("Revoke", role: .destructive) { bridge.decide("revoke", for: client) }
                                }
                            }
                        }
                    }
                    SettingsView()
                    Divider()
                    activityList
                }
                .padding(16)
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 9)
        }
        .frame(width: inWindow ? 440 : 378, height: inWindow ? 620 : 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PERSONAL CONNECTOR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.4)
                Text("dot-bridge").font(.system(size: 37, weight: .bold, design: .rounded)).tracking(-1.7)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.25), in: Capsule())
            }
            Spacer(minLength: 0)
            if let mascot = NSImage(named: "desk-dot") {
                Image(nsImage: mascot).resizable().scaledToFit()
                    .frame(width: inWindow ? 125 : 105, height: 110).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .foregroundStyle(.white)
        .background(Color(red: 0.12, green: 0.23, blue: 0.49))
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Connection", systemImage: "cable.connector").font(.headline)
                Spacer()
                Toggle("Bridge running", isOn: Binding(get: { bridge.isActive }, set: { _ in bridge.toggle() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help(bridge.isActive ? "Stop the bridge" : "Start the bridge")
            }
            if bridge.status == .running {
                copyRow(title: "MCP server URL", value: bridge.mcpURL)
                Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(.secondary.opacity(0.45)).frame(height: 1)
                copyRow(title: "Pairing code", value: bridge.pairingCode, large: true)
                DisclosureGroup("Connect to ChatGPT") {
                    Text("In ChatGPT Plugins, add the URL with OAuth. Enter the pairing code, then match the request ID and approve here on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }.font(.caption)
            } else if case .failed(let message) = bridge.status {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
            } else if bridge.status == .starting {
                HStack { ProgressView().controlSize(.small); Text("Preparing your connection…") }
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Turn on the bridge to connect ChatGPT to this Mac.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            Capsule().fill(.blue).frame(width: 3).padding(.vertical, 12)
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
                Label("Waiting for the first tool call", systemImage: "waveform.path")
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
