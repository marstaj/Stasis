import AppKit
import Foundation

/// The workspace view shared by the menu bar app and the CLI: which apps count, how they are
/// grouped with their processes, and which app the user is currently in.
public enum Workspace {
    /// Never listed: pausing Finder or Dock freezes the desktop, and Stasis is a menu bar app
    /// that would otherwise list itself when the CLI, a separate process, takes the snapshot.
    public static let systemExclusions: Set<String> = ["com.apple.finder", "com.apple.dock", "dev.marstaj.Stasis"]

    /// Posted by the CLI after it paused, resumed or killed so the menu bar icon updates at once
    /// instead of on its next background sample.
    public static let didChangeNotification = Notification.Name("dev.marstaj.Stasis.didChange")

    /// Dock apps plus third-party menu bar apps, other than this process. The pid check matters
    /// when running outside a bundle, where there is no bundle id to exclude.
    public static func listedApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != getpid() && (
                $0.activationPolicy == .regular
                    || ($0.activationPolicy == .accessory && isListedAccessoryBundle(path: $0.bundleURL?.path))
            )
        }
    }

    /// Whether a menu bar app (activation policy `.accessory`) is listed. Apple's agents all live
    /// under `/System`; everything else is the user's. Helpers that a listed app starts, or that
    /// live inside its bundle, pass here and are folded into that app by `ProcessGrouper`.
    static func isListedAccessoryBundle(path: String?) -> Bool {
        guard let path else { return false }
        return !path.hasPrefix("/System/")
    }

    public static func snapshot(
        of applications: [NSRunningApplication],
        includeUsage: Bool,
        excluding excludedBundleIdentifiers: Set<String> = systemExclusions
    ) -> [AppGroup] {
        ProcessGrouper.group(
            apps: applications.map(RunningApp.init),
            processes: SystemProcessSource.allProcesses(includeUsage: includeUsage),
            excludedBundleIdentifiers: excludedBundleIdentifiers
        )
    }

    /// The app the user is working in. Raycast is frontmost while running our commands, so an
    /// excluded or non-regular frontmost app defers to the one owning the menu bar.
    public static func foregroundApplicationPid(excluding excludedBundleIdentifiers: Set<String> = systemExclusions) -> pid_t? {
        if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
           !(front.bundleIdentifier.map(excludedBundleIdentifiers.contains) ?? false) {
            return front.processIdentifier
        }
        return NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
    }

    public static func postDidChange() {
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}

public extension RunningApp {
    init(_ application: NSRunningApplication) {
        self.init(
            pid: application.processIdentifier,
            name: (application.localizedName ?? application.bundleIdentifier ?? "pid \(application.processIdentifier)")
                .strippingControlCharacters,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.path,
            isUnresponsive: Responsiveness.isUnresponsive(pid: application.processIdentifier),
            hasDockIcon: application.activationPolicy == .regular
        )
    }
}
