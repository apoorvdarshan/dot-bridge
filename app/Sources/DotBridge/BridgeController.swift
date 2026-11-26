import AppKit
import Foundation

struct ActivityEntry: Identifiable {
    let id = UUID()
    let time: Date
    let event: String
    let summary: String
}

@MainActor
final class BridgeController: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var mcpURL: String?
    @Published private(set) var pairingCode: String?
    @Published private(set) var logFile: String?
    @Published private(set) var activity: [ActivityEntry] = []

    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var stopping = false

    var isActive: Bool { status == .starting || status == .running }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive else { return }
        guard let serverDir = Self.serverDirectory() else {
            status = .failed("Can't find server.mjs inside the app.")
            return
        }
        guard let node = Self.findExecutable("node", override: AppSettings.nodePath) else {
            status = .failed("Node.js not found. Install it with: brew install node")
            return
        }
        let permanent = AppSettings.hosting == "permanent"
        let address = AppSettings.publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if permanent {
            guard let url = URLComponents(string: address), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  ["", "/", "/mcp"].contains(url.path), url.query == nil, url.fragment == nil else {
                status = .failed("Enter your permanent HTTPS hostname in Settings, or select Temporary URL.")
                return
            }
        } else if Self.findExecutable("cloudflared", override: "") == nil {
            status = .failed("cloudflared not found. Install it with: brew install cloudflared")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = [serverDir.appendingPathComponent("server.mjs").path]
        proc.currentDirectoryURL = serverDir

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.searchPath.joined(separator: ":")
        env["DOT_BRIDGE_STATUS_JSON"] = "1"
        env["PORT"] = String(AppSettings.port)
        let roots = AppSettings.allowedRoots.trimmingCharacters(in: .whitespacesAndNewlines)
        if !roots.isEmpty { env["DOT_BRIDGE_ROOTS"] = roots }
        env["PUBLIC_URL"] = permanent ? address : nil
        env["DOT_BRIDGE_CHECK_ROUTE"] = permanent ? "1" : nil
        proc.environment = env

        let out = Pipe()
        let input = Pipe()
        proc.standardOutput = out
        proc.standardError = out
        proc.standardInput = input

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor in self?.processEnded(code: code) }
        }

        do {
            try proc.run()
        } catch {
            status = .failed("Couldn't start: \(error.localizedDescription)")
            return
        }
        process = proc
        stdinPipe = input
        stopping = false
        buffer.removeAll()
        mcpURL = nil
        pairingCode = nil
        status = .starting
    }

    func stop() {
        guard let proc = process else { return }
        stopping = true
        proc.terminate()
        try? stdinPipe?.fileHandleForWriting.close()
    }

    func shutdownSync() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
    }

    func copy(_ value: String?) {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func openLog() {
        guard let logFile else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: logFile))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line: line)
        }
    }

    private func handle(line: String) {
        let prefix = "DOTBRIDGE "
        guard line.hasPrefix(prefix),
              let data = line.dropFirst(prefix.count).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "ready":
            mcpURL = obj["url"] as? String
            pairingCode = obj["pairingCode"] as? String
            logFile = obj["logFile"] as? String
            status = .running
        case "error":
            status = .failed(obj["message"] as? String ?? "Unknown error")
        case "activity":
            let event = obj["event"] as? String ?? "event"
            activity.insert(ActivityEntry(time: Date(), event: event, summary: Self.summarize(obj)), at: 0)
            if activity.count > 100 { activity.removeLast(activity.count - 100) }
        default:
            break
        }
    }

    private func processEnded(code: Int32) {
        process = nil
        stdinPipe = nil
        mcpURL = nil
        pairingCode = nil
        if stopping || code == 0 {
            if case .failed = status {} else { status = .stopped }
        } else if case .failed = status {
        } else {
            status = .failed("Stopped unexpectedly (exit \(code)).")
        }
    }

    private static func summarize(_ obj: [String: Any]) -> String {
        let event = obj["event"] as? String ?? ""
        switch event {
        case "tool":
            let name = obj["name"] as? String ?? "tool"
            let detail = (obj["command"] as? String) ?? (obj["path"] as? String) ?? (obj["cwd"] as? String) ?? ""
            return detail.isEmpty ? name : "\(name): \(detail)"
        case "authorized": return "ChatGPT connected"
        case "client_registered": return "Registered \(obj["name"] as? String ?? "client")"
        case "approval_failed": return "Wrong pairing code"
        case "codex_done": return "Codex job \(obj["job"] as? String ?? "") \(obj["status"] as? String ?? "")"
        default: return event
        }
    }

    static let searchPath: [String] = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        NSHomeDirectory() + "/.local/bin"
    ]

    static func findExecutable(_ name: String, override: String) -> String? {
        let fm = FileManager.default
        if !override.isEmpty { return fm.isExecutableFile(atPath: override) ? override : nil }
        return searchPath.map { "\($0)/\(name)" }.first { fm.isExecutableFile(atPath: $0) }
    }

    static func serverDirectory() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("server"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../..").standardized
        ].compactMap { $0 }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("server.mjs").path)
        }
    }
}
