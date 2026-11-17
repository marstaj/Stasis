import Foundation
import Testing
@testable import StasisCore

private func group(_ pid: pid_t, _ name: String, bytes: UInt64 = 0, stopped: Bool = false) -> AppGroup {
    AppGroup(
        app: RunningApp(pid: pid, name: name, bundleIdentifier: nil, bundlePath: nil),
        processes: [
            ProcessRecord(
                pid: pid, parentPid: 1, name: name, executablePath: "/\(name)",
                isStopped: stopped, residentBytes: bytes
            )
        ]
    )
}

@Suite struct AppSortOrderTests {
    @Test func nameSortsCaseInsensitivelyAndIgnoresPauseState() {
        let groups = [group(1, "zed", stopped: true), group(2, "Brave"), group(3, "android Studio")]
        let sorted = AppSortOrder.name.sorted(groups) { _ in nil }
        #expect(sorted.map(\.app.pid) == [3, 2, 1])
    }

    @Test func sameNamedAppsKeepPidOrder() {
        let groups = [group(9, "Chrome"), group(4, "Chrome")]
        #expect(AppSortOrder.name.sorted(groups) { _ in nil }.map(\.app.pid) == [4, 9])
    }

    @Test func memorySortsLargestFirstWithNameBreakingTies() {
        let groups = [group(1, "Zed", bytes: 5), group(2, "Brave", bytes: 5), group(3, "Terminal", bytes: 900)]
        let sorted = AppSortOrder.memory.sorted(groups) { _ in nil }
        #expect(sorted.map(\.app.pid) == [3, 2, 1])
    }

    @Test func cpuSortsHighestFirstWithUnsampledAppsLast() {
        let groups = [group(1, "Idle"), group(2, "Unsampled"), group(3, "Busy"), group(4, "Also Unsampled")]
        let rates: [pid_t: Double] = [1: 0, 3: 42.5]
        let sorted = AppSortOrder.cpu.sorted(groups) { rates[$0.app.pid] }
        #expect(sorted.map(\.app.pid) == [3, 1, 4, 2])
    }
}
