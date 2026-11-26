import Foundation

/// Which apps the popover lists, chosen by the user. An app that hides its Dock icon when its
/// window closes (Granola) moves between Dock and Menu Bar with it.
public enum AppFilter: String, CaseIterable, Sendable {
    case all, dock, menuBar

    public func includes(_ app: RunningApp) -> Bool {
        switch self {
        case .all: true
        case .dock: app.hasDockIcon
        case .menuBar: !app.hasDockIcon
        }
    }

    public func filtered(_ groups: [AppGroup]) -> [AppGroup] {
        groups.filter { includes($0.app) }
    }

    /// Paused, partially paused or not-responding apps this filter leaves out. The menu bar icon
    /// counts them, so the popover has to say why it shows nothing paused.
    public func hiddenNotRunning(in groups: [AppGroup]) -> [AppGroup] {
        groups.filter { !includes($0.app) && $0.state != .running }
    }

    /// The filter that lists exactly what this one hides; nil for `.all`, which hides nothing.
    public var complement: AppFilter? {
        switch self {
        case .all: nil
        case .dock: .menuBar
        case .menuBar: .dock
        }
    }
}
