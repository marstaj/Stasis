import Foundation

/// Which signal to send to which processes for a toggle request.
public struct SignalPlan: Sendable, Hashable {
    public enum Signal: Sendable, Hashable {
        case stop
        case `continue`

        public var number: Int32 {
            switch self {
            case .stop: SIGSTOP
            case .continue: SIGCONT
            }
        }
    }

    public let signal: Signal
    public let pids: [pid_t]

    public init(signal: Signal, pids: [pid_t]) {
        self.signal = signal
        self.pids = pids
    }

    /// A running app is stopped whole; a paused or partially paused app is continued whole,
    /// since a partial pause is almost always the system's doing and never what the user wants.
    public static func toggle(_ group: AppGroup) -> SignalPlan {
        SignalPlan(signal: group.state == .running ? .stop : .continue, pids: group.processes.map(\.pid))
    }

    public static func toggle(_ process: ProcessRecord) -> SignalPlan {
        SignalPlan(signal: process.isStopped ? .continue : .stop, pids: [process.pid])
    }

    /// Stops every process of every app that is not already fully paused.
    public static func stopAll(_ groups: [AppGroup]) -> SignalPlan {
        SignalPlan(signal: .stop, pids: groups.filter { $0.state != .paused }.flatMap { $0.processes.map(\.pid) })
    }

    /// Continues every process of every app that has at least one stopped process.
    public static func continueAll(_ groups: [AppGroup]) -> SignalPlan {
        SignalPlan(signal: .continue, pids: groups.filter { $0.state != .running }.flatMap { $0.processes.map(\.pid) })
    }
}
