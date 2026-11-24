import Foundation

/// The JSON shape of `stasis list --json`. The Raycast extension parses it, so field names are a
/// contract; keep `raycast/src/stasis.ts` in step.
public struct AppSummary: Codable, Sendable, Hashable {
    public struct Process: Codable, Sendable, Hashable {
        public var pid: pid_t
        public var name: String
        public var paused: Bool
        public var residentBytes: UInt64
    }

    public var pid: pid_t
    public var name: String
    public var bundleIdentifier: String?
    public var bundlePath: String?
    public var state: String
    public var residentBytes: UInt64
    public var processCount: Int
    public var pausedCount: Int
    public var processes: [Process]?

    public init(_ group: AppGroup, includeProcesses: Bool) {
        pid = group.app.pid
        name = group.app.name
        bundleIdentifier = group.app.bundleIdentifier
        bundlePath = group.app.bundlePath
        state = group.state.label
        residentBytes = group.totalResidentBytes
        processCount = group.processes.count
        pausedCount = group.stoppedCount
        processes = includeProcesses
            ? group.processes.map { Process(pid: $0.pid, name: $0.name, paused: $0.isStopped, residentBytes: $0.residentBytes) }
            : nil
    }
}

public extension PauseState {
    /// Stable identifier used in JSON and CLI output.
    var label: String {
        switch self {
        case .running: "running"
        case .notResponding: "not-responding"
        case .partiallyPaused: "partial"
        case .paused: "paused"
        }
    }
}
