import Foundation
import Testing
@testable import StasisCore

private func group(_ pid: pid_t, _ name: String, bundleId: String, stopped: [Bool] = [false]) -> AppGroup {
    let app = RunningApp(pid: pid, name: name, bundleIdentifier: bundleId, bundlePath: "/Applications/\(name).app")
    let processes = stopped.enumerated().map { i, s in
        ProcessRecord(pid: pid + pid_t(i), parentPid: i == 0 ? 1 : pid, name: name,
                      executablePath: "/Applications/\(name).app/x", isStopped: s, residentBytes: 0)
    }
    return AppGroup(app: app, processes: processes)
}

private let brave = group(100, "Brave Browser", bundleId: "com.brave.Browser")
private let studio = group(200, "Android Studio", bundleId: "com.google.android.studio")
private let slack = group(300, "Slack", bundleId: "com.tinyspeck.slackmacgap")
private let smartGit = group(400, "SmartGit", bundleId: "com.syntevo.smartgit")
private let all = [brave, studio, slack, smartGit]

@Suite struct AppMatcherTests {
    @Test func exactBundleIdentifierWinsRegardlessOfCase() {
        #expect(AppMatcher.match("COM.BRAVE.browser", in: all) == .found(brave))
    }

    @Test func exactNameWinsOverPrefixOfAnotherApp() {
        let slackish = group(500, "Slack Helper", bundleId: "x.helper")
        #expect(AppMatcher.match("slack", in: all + [slackish]) == .found(slack))
    }

    @Test func uniquePrefixMatches() {
        #expect(AppMatcher.match("bra", in: all) == .found(brave))
    }

    @Test func uniquePrefixWinsOverAmbiguousSubstring() {
        let translator = group(1000, "Translator", bundleId: "x.translator")
        #expect(AppMatcher.match("sla", in: [slack, translator]) == .found(slack))
    }

    @Test func severalPrefixMatchesAreAmbiguous() {
        let slash = group(600, "Slash", bundleId: "x.slash")
        let slashdot = group(700, "Slashdot Reader", bundleId: "x.slashdot")
        #expect(AppMatcher.match("Sla", in: [slack, slash]) == .ambiguous([slack, slash]))
        #expect(AppMatcher.match("Slas", in: [slash, slashdot]) == .ambiguous([slash, slashdot]))
        #expect(AppMatcher.match("Slash", in: [slash, slashdot]) == .found(slash))  // exact beats prefix
    }

    @Test func substringFallsBackWhenNoPrefixMatches() {
        #expect(AppMatcher.match("studio", in: all) == .found(studio))
        #expect(AppMatcher.match("git", in: all) == .found(smartGit))
    }

    @Test func shortQueriesOnlyMatchExactly() {
        #expect(AppMatcher.match("a", in: all) == .notFound)
        #expect(AppMatcher.match("an", in: all) == .notFound)
        #expect(AppMatcher.match("Go", in: [group(700, "Go", bundleId: "x.go")]) == .found(group(700, "Go", bundleId: "x.go")))
    }

    @Test func emptyAndUnknownQueriesAreNotFound() {
        #expect(AppMatcher.match("", in: all) == .notFound)
        #expect(AppMatcher.match("   ", in: all) == .notFound)
        #expect(AppMatcher.match("xcode", in: all) == .notFound)
    }
}

@Suite struct BulkSignalPlanTests {
    @Test func stopAllSkipsFullyPausedApps() {
        let paused = group(800, "Paused", bundleId: "x.paused", stopped: [true, true])
        let partial = group(900, "Partial", bundleId: "x.partial", stopped: [false, true])
        let plan = SignalPlan.stopAll([brave, paused, partial])
        #expect(plan.signal == .stop)
        #expect(plan.pids == [100, 900, 901])
    }

    @Test func continueAllSkipsRunningApps() {
        let paused = group(800, "Paused", bundleId: "x.paused", stopped: [true, true])
        let partial = group(900, "Partial", bundleId: "x.partial", stopped: [false, true])
        let plan = SignalPlan.continueAll([brave, paused, partial])
        #expect(plan.signal == .continue)
        #expect(plan.pids == [800, 801, 900, 901])
    }
}

@Suite struct AppSummaryTests {
    @Test func jsonFieldNamesAreTheRaycastContract() throws {
        let partial = group(900, "Partial", bundleId: "x.partial", stopped: [false, true])
        let data = try JSONEncoder().encode(AppSummary(partial, includeProcesses: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "pid", "name", "bundleIdentifier", "bundlePath", "state", "residentBytes",
            "processCount", "pausedCount", "processes",
        ])
        #expect(object["state"] as? String == "partial")
        #expect(object["pausedCount"] as? Int == 1)
        let processes = try #require(object["processes"] as? [[String: Any]])
        #expect(Set(processes[0].keys) == ["pid", "name", "paused", "residentBytes"])
    }

    @Test func processesAreOmittedUnlessRequested() throws {
        let data = try JSONEncoder().encode(AppSummary(brave, includeProcesses: false))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["processes"] == nil)
        #expect(object["state"] as? String == "running")
    }
}
