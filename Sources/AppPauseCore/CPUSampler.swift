import Foundation

/// Turns cumulative per-process CPU time into a percentage of one core over the interval
/// between two consecutive samples.
public struct CPUSampler: Sendable {
    private var previousTimes: [pid_t: UInt64] = [:]
    private var previousNanos: UInt64?

    public init() {}

    /// Returns a rate for every pid present in both this and the previous sample.
    public mutating func record(_ cpuTimes: [pid_t: UInt64], atNanos now: UInt64) -> [pid_t: Double] {
        defer {
            previousTimes = cpuTimes
            previousNanos = now
        }
        guard let then = previousNanos, now > then else { return [:] }
        let elapsed = Double(now - then)
        var rates: [pid_t: Double] = [:]
        for (pid, time) in cpuTimes {
            guard let before = previousTimes[pid] else { continue }
            // A smaller value means the pid was reused by a new process.
            rates[pid] = time >= before ? Double(time - before) * 100 / elapsed : 0
        }
        return rates
    }
}
