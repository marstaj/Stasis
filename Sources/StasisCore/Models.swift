import Foundation

/// One row of the kernel process table, as seen at sample time.
public struct ProcessRecord: Sendable, Hashable {
    public var pid: pid_t
    public var parentPid: pid_t
    public var name: String
    public var executablePath: String
    public var isStopped: Bool
    public var residentBytes: UInt64
    /// Cumulative user + system CPU time; rates are derived by `CPUSampler`.
    public var cpuTimeNanos: UInt64

    public init(
        pid: pid_t, parentPid: pid_t, name: String, executablePath: String,
        isStopped: Bool, residentBytes: UInt64, cpuTimeNanos: UInt64 = 0
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.executablePath = executablePath
        self.isStopped = isStopped
        self.residentBytes = residentBytes
        self.cpuTimeNanos = cpuTimeNanos
    }
}

/// A GUI application as reported by the workspace (Dock-visible apps only).
public struct RunningApp: Sendable, Hashable {
    public var pid: pid_t
    public var name: String
    public var bundleIdentifier: String?
    public var bundlePath: String?

    public init(pid: pid_t, name: String, bundleIdentifier: String?, bundlePath: String?) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
    }
}

public enum PauseState: Sendable, Hashable {
    case running
    case partiallyPaused
    case paused
}

/// An app together with every process that belongs to it; the main process comes first.
public struct AppGroup: Sendable, Hashable {
    public let app: RunningApp
    public let processes: [ProcessRecord]

    public init(app: RunningApp, processes: [ProcessRecord]) {
        self.app = app
        self.processes = processes
    }

    public var stoppedCount: Int { processes.lazy.filter(\.isStopped).count }

    public var state: PauseState {
        switch stoppedCount {
        case 0: .running
        case processes.count: .paused
        default: .partiallyPaused
        }
    }

    public var totalResidentBytes: UInt64 { processes.reduce(0) { $0 + $1.residentBytes } }
}
