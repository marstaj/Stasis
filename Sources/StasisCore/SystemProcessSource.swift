import Darwin
import Foundation
import os

/// Reads the live process table and signals its processes. Pure OS glue; the logic that interprets it is in `ProcessGrouper`.
public enum SystemProcessSource {
    /// `SSTOP` from <sys/proc.h>; the macro is not importable from Swift.
    private static let stoppedState: UInt8 = 4
    private static let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "process-source")

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// `includeUsage: false` skips the per-process rusage read and leaves memory and CPU time at 0,
    /// for callers that only need the pause state.
    public static func allProcesses(includeUsage: Bool = true) -> [ProcessRecord] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return sysctlFailed() }
        // Headroom for processes spawned between the size query and the read.
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
        var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &table, &size, nil, 0) == 0 else { return sysctlFailed() }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return table.prefix(count).compactMap { record(for: $0, includeUsage: includeUsage) }
    }

    private static func sysctlFailed() -> [ProcessRecord] {
        logger.error("sysctl KERN_PROC_ALL failed: \(String(cString: strerror(errno)))")
        return []
    }

    /// False once the sampled process has exited, even if another process now has its pid.
    public static func isCurrent(_ record: ProcessRecord) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, record.pid]
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &entry, &size, nil, 0) == 0 else {
            logger.error("sysctl KERN_PROC_PID \(record.pid) failed: \(String(cString: strerror(errno)))")
            return false
        }
        // A pid nobody has is not an error; the call succeeds and returns nothing.
        return size > 0 && startTimeMicros(of: entry) == record.startTimeMicros
    }

    /// Signals the process the record was sampled from and returns the errno if that failed.
    /// A record can be seconds old, so a pid that has since gone to another process is reported
    /// as `ESRCH` instead of signalled.
    public static func send(_ signal: SignalPlan.Signal, to record: ProcessRecord) -> Int32? {
        guard isCurrent(record) else { return ESRCH }
        return kill(record.pid, signal.number) == 0 ? nil : errno
    }

    private static func startTimeMicros(of entry: kinfo_proc) -> Int64 {
        let start = entry.kp_proc.p_un.__p_starttime
        return Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
    }

    private static func record(for entry: kinfo_proc, includeUsage: Bool) -> ProcessRecord? {
        var entry = entry
        let pid = entry.kp_proc.p_pid
        guard pid > 0 else { return nil }
        let comm = withUnsafePointer(to: &entry.kp_proc.p_comm) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer.pointee)) {
                String(cString: $0)
            }
        }
        let usage = includeUsage ? resourceUsage(of: pid) : nil
        let path = executablePath(of: pid) ?? comm
        // macOS keeps idle app extensions (widgets, intents) suspended as a matter of course;
        // counting that would show every app that bundles one as partially paused.
        let isExtension = path.contains(".appex/")
        return ProcessRecord(
            pid: pid,
            parentPid: entry.kp_eproc.e_ppid,
            name: comm.strippingControlCharacters,
            executablePath: path,
            isStopped: entry.kp_proc.p_stat == stoppedState || (!isExtension && isSuspended(pid)),
            residentBytes: usage?.bytes ?? 0,
            cpuTimeNanos: usage?.cpuNanos ?? 0,
            startTimeMicros: startTimeMicros(of: entry)
        )
    }

    /// True while the task's Mach suspend count is above zero. `SIGSTOP` raises it too, but macOS
    /// freezes apps under memory pressure through it alone, leaving `p_stat` untouched.
    /// False when the task cannot be inspected (another user's process, or one that just exited).
    private static func isSuspended(_ pid: pid_t) -> Bool {
        var task: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else { return false }
        defer { mach_port_deallocate(mach_task_self_, task) }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            logger.error("task_info for \(pid) failed: \(String(cString: mach_error_string(status)))")
            return false
        }
        return info.suspend_count > 0
    }

    private static func executablePath(of pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE; the macro itself is not importable.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private static func resourceUsage(of pid: pid_t) -> (bytes: UInt64, cpuNanos: UInt64)? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard status == 0 else { return nil }
        let ticks = info.ri_user_time &+ info.ri_system_time
        let nanos = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        return (info.ri_phys_footprint, nanos)
    }
}
