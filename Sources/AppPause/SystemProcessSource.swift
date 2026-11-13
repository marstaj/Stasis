import AppPauseCore
import Darwin
import Foundation
import os

/// Reads the live process table. Pure OS glue; the logic that interprets it lives in AppPauseCore.
enum SystemProcessSource {
    /// `SSTOP` from <sys/proc.h>; the macro is not importable from Swift.
    private static let stoppedState: UInt8 = 4
    private static let logger = Logger(subsystem: "dev.marstaj.AppPause", category: "process-source")

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// `includeUsage: false` skips the per-process rusage read and leaves memory and CPU time at 0,
    /// for callers that only need the pause state.
    static func allProcesses(includeUsage: Bool = true) -> [ProcessRecord] {
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
        return ProcessRecord(
            pid: pid,
            parentPid: entry.kp_eproc.e_ppid,
            name: comm,
            executablePath: executablePath(of: pid) ?? comm,
            isStopped: entry.kp_proc.p_stat == stoppedState,
            residentBytes: usage?.bytes ?? 0,
            cpuTimeNanos: usage?.cpuNanos ?? 0
        )
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
