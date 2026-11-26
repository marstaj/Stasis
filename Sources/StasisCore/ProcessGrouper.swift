import Foundation

public enum ProcessGrouper {
    /// Assigns processes to the apps they belong to. Each process is claimed by at most one app:
    /// app main processes first, then descendants by parent pid, then anything whose executable
    /// lives inside the app bundle (helpers that reparented to launchd). Apps whose main process
    /// is missing from the table have exited and are dropped. A menu bar app descended from
    /// another listed app or inside its bundle is that app's helper (an IDE's embedded browser, a
    /// login item) and gets no row.
    public static func group(
        apps: [RunningApp],
        processes: [ProcessRecord],
        excludedBundleIdentifiers: Set<String> = []
    ) -> [AppGroup] {
        let byPid = Dictionary(processes.map { ($0.pid, $0) }) { $1 }
        let childrenByParent = Dictionary(grouping: processes, by: \.parentPid)
        var apps = apps.filter { app in
            byPid[app.pid] != nil && !(app.bundleIdentifier.map(excludedBundleIdentifiers.contains) ?? false)
        }
        let appPids = Set(apps.map(\.pid))
        let bundlePrefixes = apps.compactMap(\.bundlePath).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        apps.removeAll { app in
            guard !app.hasDockIcon else { return false }
            if let path = app.bundlePath, bundlePrefixes.contains(where: path.hasPrefix) { return true }
            var pid = byPid[app.pid]!.parentPid
            while pid > 1, let parent = byPid[pid] {
                if appPids.contains(pid) { return true }
                pid = parent.parentPid
            }
            return false
        }

        // Claiming every main process up front keeps a descendant walk from swallowing another
        // app, e.g. an app launched from a Terminal shell.
        var claimed = Set(apps.map(\.pid))
        var members = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, [ProcessRecord]()) })

        for app in apps {
            var queue = [app.pid]
            while let pid = queue.popLast() {
                for child in childrenByParent[pid] ?? [] where claimed.insert(child.pid).inserted {
                    members[app.pid]!.append(child)
                    queue.append(child.pid)
                }
            }
        }

        for app in apps {
            guard let bundlePath = app.bundlePath else { continue }
            let prefix = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
            for process in processes
            where process.executablePath.hasPrefix(prefix) && claimed.insert(process.pid).inserted {
                members[app.pid]!.append(process)
            }
        }

        return apps.map { app in
            AppGroup(app: app, processes: [byPid[app.pid]!] + members[app.pid]!.sorted { $0.pid < $1.pid })
        }
        .sorted { lhs, rhs in
            if lhs.state != rhs.state { return lhs.state.sortRank < rhs.state.sortRank }
            if lhs.totalResidentBytes != rhs.totalResidentBytes { return lhs.totalResidentBytes > rhs.totalResidentBytes }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }
}

private extension PauseState {
    var sortRank: Int {
        switch self {
        case .notResponding: 0
        case .paused: 1
        case .partiallyPaused: 2
        case .running: 3
        }
    }
}
