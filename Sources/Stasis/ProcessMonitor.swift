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
    private var refreshPending = false
    private let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "monitor")
    private let excludedBundleIdentifiers = Workspace.systemExclusions.union([Bundle.main.bundleIdentifier ?? ""])

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
        let running = Workspace.regularApplications()
        icons = Dictionary(running.compactMap { app in app.icon.map { (app.processIdentifier, $0) } }) { $1 }
        groups = Workspace.snapshot(of: running, includeUsage: popoverVisible, excluding: excludedBundleIdentifiers)
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

    /// Refreshes shortly, once for any number of calls in between. For the CLI's notification:
    /// any local process can post it, and each refresh reads the whole process table.
    func refreshSoon() {
        guard !refreshPending else { return }
        refreshPending = true
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPending = false
                self?.refresh()
            }
        }
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

    func forceQuit(_ group: AppGroup) {
        send(SignalPlan.kill(group), target: group.app.name)
    }

    func forceQuit(_ process: ProcessRecord) {
        send(SignalPlan.kill(process), target: "\(process.name) (\(process.pid))")
    }

    /// The app the user is in, which "Pause All Except" keeps running. Nil when that app is not
    /// listed (Finder); there is then nothing to spare.
    var frontApp: RunningApp? {
        let pid = Workspace.foregroundApplicationPid(excluding: excludedBundleIdentifiers)
        return groups.first { $0.app.pid == pid }?.app
    }

    func pauseAllTargets(sparingFrontApp: Bool) -> [AppGroup] {
        SignalPlan.pauseAllTargets(in: groups, sparing: sparingFrontApp ? frontApp?.pid : nil)
    }

    func pauseAll(sparingFrontApp: Bool) {
        // The background sample can be 30 s old.
        refresh()
        send(SignalPlan.stopAll(pauseAllTargets(sparingFrontApp: sparingFrontApp)), target: "all apps")
    }

    func resumeAll() {
        refresh()
        send(SignalPlan.continueAll(groups), target: "all apps")
    }

    private func send(_ plan: SignalPlan, target: String) {
        lastError = nil
        // Started from a terminal (`swift run`), this process is a descendant of that terminal
        // and in its plan; stopping ourselves would leave the rest unsignalled and no way back.
        for process in plan.targets where process.pid != getpid() {
            guard let code = SystemProcessSource.send(plan.signal, to: process) else { continue }
            // Killing a parent can take its children down before their turn comes.
            if plan.signal == .kill && code == ESRCH { continue }
            let reason = String(cString: strerror(code))
            logger.error("kill(\(process.pid), \(plan.signal.number)) for \(target) failed: \(reason)")
            lastError = "Could not \(plan.signal.verb) \(target): \(reason)"
        }
        refresh()
    }
}

private extension SignalPlan.Signal {
    var verb: String {
        switch self {
        case .stop: "pause"
        case .continue: "resume"
        case .kill: "kill"
        }
    }
}
