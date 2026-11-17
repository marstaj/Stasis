import Foundation
import Testing
@testable import StasisCore

private func proc(
    _ pid: pid_t, parent: pid_t = 1, path: String, stopped: Bool = false, bytes: UInt64 = 0
) -> ProcessRecord {
    ProcessRecord(
        pid: pid, parentPid: parent, name: (path as NSString).lastPathComponent,
        executablePath: path, isStopped: stopped, residentBytes: bytes
    )
}

private let brave = RunningApp(
    pid: 100, name: "Brave Browser", bundleIdentifier: "com.brave.Browser",
    bundlePath: "/Applications/Brave Browser.app"
)
private let studio = RunningApp(
    pid: 200, name: "Android Studio", bundleIdentifier: "com.google.android.studio",
    bundlePath: "/Applications/Android Studio.app"
)
private let terminal = RunningApp(
    pid: 300, name: "Terminal", bundleIdentifier: "com.apple.Terminal",
    bundlePath: "/System/Applications/Utilities/Terminal.app"
)

@Suite struct ProcessGrouperTests {
    @Test func claimsMainProcessBundleHelpersAndDescendants() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
            proc(101, parent: 100, path: "/Applications/Brave Browser.app/Contents/Frameworks/Helper"),
            proc(102, parent: 101, path: "/usr/bin/some-child-of-helper"),
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(201, parent: 1, path: "/Library/Java/bin/java"),  // detached gradle daemon
        ]
        let groups = ProcessGrouper.group(apps: [brave, studio], processes: processes)

        let bravePids = groups.first { $0.app.pid == 100 }!.processes.map(\.pid)
        let studioPids = groups.first { $0.app.pid == 200 }!.processes.map(\.pid)
        #expect(bravePids == [100, 101, 102])
        #expect(studioPids == [200])
    }

    @Test func claimsLaunchdReparentedHelperByBundlePath() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
            proc(103, parent: 1, path: "/Applications/Brave Browser.app/Contents/Frameworks/Helper"),
        ]
        let groups = ProcessGrouper.group(apps: [brave], processes: processes)
        #expect(groups[0].processes.map(\.pid) == [100, 103])
    }

    @Test func bundlePathMatchIsWholeDirectoryNotPrefix() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
            proc(104, parent: 1, path: "/Applications/Brave Browser.app-old/Contents/MacOS/Brave Browser"),
        ]
        let groups = ProcessGrouper.group(apps: [brave], processes: processes)
        #expect(groups[0].processes.map(\.pid) == [100])
    }

    @Test func childrenOfBundlePathClaimedHelperAreNotWalked() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
            proc(103, parent: 1, path: "/Applications/Brave Browser.app/Contents/Frameworks/Helper"),
            proc(105, parent: 103, path: "/usr/bin/some-child-of-helper"),
        ]
        let groups = ProcessGrouper.group(apps: [brave], processes: processes)
        #expect(groups[0].processes.map(\.pid) == [100, 103])
    }

    @Test func descendantWalkDoesNotCrossIntoAnotherApp() {
        // Android Studio launched from a Terminal shell is a descendant of Terminal.
        let processes = [
            proc(300, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            proc(301, parent: 300, path: "/bin/zsh"),
            proc(200, parent: 301, path: "/Applications/Android Studio.app/Contents/MacOS/studio"),
            proc(202, parent: 200, path: "/Applications/Android Studio.app/Contents/jbr/bin/java"),
        ]
        let groups = ProcessGrouper.group(apps: [terminal, studio], processes: processes)

        let terminalPids = groups.first { $0.app.pid == 300 }!.processes.map(\.pid)
        let studioPids = groups.first { $0.app.pid == 200 }!.processes.map(\.pid)
        #expect(terminalPids == [300, 301])
        #expect(studioPids == [200, 202])
    }

    @Test func dropsAppsWhoseMainProcessIsGone() {
        let groups = ProcessGrouper.group(apps: [brave], processes: [])
        #expect(groups.isEmpty)
    }

    @Test func excludesListedBundleIdentifiers() {
        let processes = [proc(300, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")]
        let groups = ProcessGrouper.group(
            apps: [terminal], processes: processes, excludedBundleIdentifiers: ["com.apple.Terminal"]
        )
        #expect(groups.isEmpty)
    }

    @Test func stateIsRunningPartialOrPaused() {
        func group(_ stopped: [Bool]) -> AppGroup {
            let processes = stopped.enumerated().map { i, s in
                proc(pid_t(100 + i), parent: i == 0 ? 1 : 100,
                     path: "/Applications/Brave Browser.app/Contents/MacOS/x", stopped: s)
            }
            return ProcessGrouper.group(apps: [brave], processes: processes)[0]
        }
        #expect(group([false, false]).state == .running)
        #expect(group([false, true]).state == .partiallyPaused)
        #expect(group([true, true]).state == .paused)
        #expect(group([false, true, true]).stoppedCount == 2)
    }

    @Test func sumsResidentMemoryAcrossProcesses() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser", bytes: 100),
            proc(101, parent: 100, path: "/Applications/Brave Browser.app/Contents/Frameworks/Helper", bytes: 50),
        ]
        let group = ProcessGrouper.group(apps: [brave], processes: processes)[0]
        #expect(group.totalResidentBytes == 150)
    }

    @Test func sortsPausedFirstThenPartialThenByMemoryDescending() {
        let processes = [
            proc(100, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser", bytes: 10),
            proc(200, path: "/Applications/Android Studio.app/Contents/MacOS/studio", stopped: true, bytes: 5),
            proc(300, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", bytes: 900),
            proc(301, parent: 300, path: "/bin/zsh", stopped: true, bytes: 1),
        ]
        let groups = ProcessGrouper.group(apps: [brave, studio, terminal], processes: processes)
        #expect(groups.map(\.app.pid) == [200, 300, 100])
    }
}

@Suite struct SignalPlanTests {
    private func group(stopped: [Bool]) -> AppGroup {
        let processes = stopped.enumerated().map { i, s in
            proc(pid_t(100 + i), parent: i == 0 ? 1 : 100,
                 path: "/Applications/Brave Browser.app/Contents/MacOS/x", stopped: s)
        }
        return ProcessGrouper.group(apps: [brave], processes: processes)[0]
    }

    @Test func togglingRunningAppStopsEveryProcess() {
        let plan = SignalPlan.toggle(group(stopped: [false, false]))
        #expect(plan.signal == .stop)
        #expect(plan.pids == [100, 101])
    }

    @Test func togglingPartiallyPausedAppContinuesEveryProcess() {
        let plan = SignalPlan.toggle(group(stopped: [false, true]))
        #expect(plan.signal == .continue)
        #expect(plan.pids == [100, 101])
    }

    @Test func togglingPausedAppContinuesEveryProcess() {
        let plan = SignalPlan.toggle(group(stopped: [true, true]))
        #expect(plan.signal == .continue)
        #expect(plan.pids == [100, 101])
    }

    @Test func togglingSingleProcessFlipsOnlyThatProcess() {
        let stopped = proc(5, path: "/x", stopped: true)
        let running = proc(6, path: "/x", stopped: false)
        #expect(SignalPlan.toggle(stopped) == SignalPlan(signal: .continue, pids: [5]))
        #expect(SignalPlan.toggle(running) == SignalPlan(signal: .stop, pids: [6]))
    }

    @Test func killingAppTargetsEveryProcessWhateverItsPauseState() {
        for stopped in [[false, false], [false, true], [true, true]] {
            let plan = SignalPlan.kill(group(stopped: stopped))
            #expect(plan.signal == .kill)
            #expect(plan.pids == [100, 101])
        }
    }

    @Test func killingSingleProcessTargetsOnlyThatProcess() {
        #expect(SignalPlan.kill(proc(5, path: "/x", stopped: true)) == SignalPlan(signal: .kill, pids: [5]))
        #expect(SignalPlan.Signal.kill.number == SIGKILL)
    }
}

@Suite struct CPUSamplerTests {
    @Test func rateIsCpuTimeDeltaOverWallClockDelta() {
        var sampler = CPUSampler()
        sampler.record([1: 1_000_000_000, 2: 0], atNanos: 10_000_000_000)
        let rates = sampler.record([1: 1_500_000_000, 2: 0], atNanos: 11_000_000_000)
        #expect(rates[1] == 50.0)
        #expect(rates[2] == 0.0)
    }

    @Test func firstSampleAndNewPidsHaveNoRate() {
        var sampler = CPUSampler()
        #expect(sampler.record([1: 5], atNanos: 100).isEmpty)
        let rates = sampler.record([1: 5, 2: 5], atNanos: 200)
        #expect(rates[1] == 0.0)
        #expect(rates[2] == nil)
    }

    @Test func cpuTimeGoingBackwardsMeansPidReuseAndYieldsZero() {
        var sampler = CPUSampler()
        sampler.record([1: 500], atNanos: 100)
        let rates = sampler.record([1: 10], atNanos: 200)
        #expect(rates[1] == 0.0)
    }

    @Test func nonAdvancingClockYieldsNoRates() {
        var sampler = CPUSampler()
        sampler.record([1: 5], atNanos: 100)
        #expect(sampler.record([1: 50], atNanos: 100).isEmpty)
        #expect(sampler.record([1: 50], atNanos: 90).isEmpty)
    }
}
