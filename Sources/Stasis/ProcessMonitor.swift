import AppKit
import StasisCore
import Observation
import os

@MainActor
@Observable
final class ProcessMonitor {
    private(set) var groups: [AppGroup] = []
    private(set) var cpuRates: [pid_t: Double] = [:]
    private(set) var icons: [pid_t: NSImage] = [:]
    private(set) var lastError: String?

    private var sampler = CPUSampler()
    private var timer: Timer?
    private var popoverVisible = false
    private let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "monitor")
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder", "com.apple.dock", Bundle.main.bundleIdentifier ?? "",
    ]

    var anyPaused: Bool { groups.contains { $0.state != .running } }

    init() {
        setPopoverVisible(false)
    }

    /// Fast sampling with memory and CPU while the popover is open; slow pause-state-only sampling
    /// in the background so the menu bar icon still reflects system-initiated pauses.
    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: visible ? 2 : 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // Excluded by pid as well as bundle id: the bundle id is nil when run outside a .app bundle.
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
        icons = Dictionary(running.compactMap { app in app.icon.map { (app.processIdentifier, $0) } }) { $1 }
        let apps = running.map {
            RunningApp(
                pid: $0.processIdentifier,
                name: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)",
                bundleIdentifier: $0.bundleIdentifier,
                bundlePath: $0.bundleURL?.path
            )
        }
        groups = ProcessGrouper.group(
            apps: apps,
            processes: SystemProcessSource.allProcesses(includeUsage: popoverVisible),
            excludedBundleIdentifiers: excludedBundleIdentifiers
        )
        guard popoverVisible else {
            // Usage-free samples must not feed the sampler, or the first open would compute
            // rates against zero.
            sampler = CPUSampler()
            cpuRates = [:]
            return
        }
        let cpuTimes = Dictionary(groups.flatMap(\.processes).map { ($0.pid, $0.cpuTimeNanos) }) { $1 }
        cpuRates = sampler.record(cpuTimes, atNanos: DispatchTime.now().uptimeNanoseconds)
    }

    func cpuRate(of group: AppGroup) -> Double? {
        let rates = group.processes.compactMap { cpuRates[$0.pid] }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }

    func toggle(_ group: AppGroup) {
        send(SignalPlan.toggle(group), target: group.app.name)
    }

    func toggle(_ process: ProcessRecord) {
        send(SignalPlan.toggle(process), target: "\(process.name) (\(process.pid))")
    }

    private func send(_ plan: SignalPlan, target: String) {
        lastError = nil
        for pid in plan.pids where kill(pid, plan.signal.number) != 0 {
            let reason = String(cString: strerror(errno))
            logger.error("kill(\(pid), \(plan.signal.number)) for \(target) failed: \(reason)")
            lastError = "Could not \(plan.signal == .stop ? "pause" : "resume") \(target): \(reason)"
        }
        refresh()
    }
}
