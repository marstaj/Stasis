import Foundation

/// Which signal to send to which processes for a pause, resume or kill request.
public struct SignalPlan: Sendable, Hashable {
    public enum Signal: Sendable, Hashable {
        case stop
        case `continue`
        case kill

        public var number: Int32 {
            switch self {
            case .stop: SIGSTOP
            case .continue: SIGCONT
            // Not SIGTERM: a stopped process only acts on it once resumed.
            case .kill: SIGKILL
            }
        }
    }

    public let signal: Signal
    /// Whole records, not bare pids, so the sender can tell a process from a later one that
    /// reused its pid.
    public let targets: [ProcessRecord]

    public var pids: [pid_t] { targets.map(\.pid) }

    public init(signal: Signal, targets: [ProcessRecord]) {
        self.signal = signal
        self.targets = targets
    }

    /// A running app is stopped whole; a paused or partially paused app is continued whole,
    /// since a partial pause is almost always the system's doing and never what the user wants.
    public static func toggle(_ group: AppGroup) -> SignalPlan {
        SignalPlan(signal: group.state == .running ? .stop : .continue, targets: group.processes)
    }

    public static func toggle(_ process: ProcessRecord) -> SignalPlan {
        SignalPlan(signal: process.isStopped ? .continue : .stop, targets: [process])
    }

    /// Kills the app with all its processes, whatever their pause state.
    public static func kill(_ group: AppGroup) -> SignalPlan {
        SignalPlan(signal: .kill, targets: group.processes)
    }

    public static func kill(_ process: ProcessRecord) -> SignalPlan {
        SignalPlan(signal: .kill, targets: [process])
    }

    /// The apps a "pause all" stops: every app that is not already fully paused, except the
    /// spared one (the app the user is in).
    public static func pauseAllTargets(in groups: [AppGroup], sparing spared: pid_t?) -> [AppGroup] {
        groups.filter { $0.app.pid != spared && $0.state != .paused }
    }

    /// Stops every process of every app that is not already fully paused.
    public static func stopAll(_ groups: [AppGroup]) -> SignalPlan {
        SignalPlan(signal: .stop, targets: groups.filter { $0.state != .paused }.flatMap(\.processes))
    }

    /// Continues every process of every app that has at least one stopped process.
    public static func continueAll(_ groups: [AppGroup]) -> SignalPlan {
        SignalPlan(signal: .continue, targets: groups.filter { $0.state != .running }.flatMap(\.processes))
    }
}
