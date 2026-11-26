import Foundation

/// The order of the app list in the popover, chosen by the user.
public enum AppSortOrder: String, CaseIterable, Sendable {
    case name, memory, cpu

    /// Memory and CPU sort largest first, apps without a CPU rate yet last; ties fall back to name.
    /// `pausedFirst` moves every app that is not running ahead of the rest, each part in this order.
    public func sorted(_ groups: [AppGroup], pausedFirst: Bool = false, cpuRate: (AppGroup) -> Double?) -> [AppGroup] {
        let sorted = ordered(groups, cpuRate: cpuRate)
        guard pausedFirst else { return sorted }
        return sorted.filter { $0.state != .running } + sorted.filter { $0.state == .running }
    }

    private func ordered(_ groups: [AppGroup], cpuRate: (AppGroup) -> Double?) -> [AppGroup] {
        func byName(_ lhs: AppGroup, _ rhs: AppGroup) -> Bool {
            let order = lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name)
            // The pid keeps two instances of one app from swapping places between refreshes.
            return order == .orderedSame ? lhs.app.pid < rhs.app.pid : order == .orderedAscending
        }
        switch self {
        case .name:
            return groups.sorted(by: byName)
        case .memory:
            return groups.sorted { lhs, rhs in
                lhs.totalResidentBytes != rhs.totalResidentBytes
                    ? lhs.totalResidentBytes > rhs.totalResidentBytes : byName(lhs, rhs)
            }
        case .cpu:
            let rates = Dictionary(groups.map { ($0.app.pid, cpuRate($0) ?? -1) }) { $1 }
            return groups.sorted { lhs, rhs in
                let (left, right) = (rates[lhs.app.pid]!, rates[rhs.app.pid]!)
                return left != right ? left > right : byName(lhs, rhs)
            }
        }
    }
}
