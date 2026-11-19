import AppKit
import Foundation

/// The workspace view shared by the menu bar app and the CLI: which apps count, how they are
/// grouped with their processes, and which app the user is currently in.
public enum Workspace {
    /// Never listed: pausing Finder or Dock freezes the desktop, and a paused Raycast could not
    /// run the resume command.
    public static let systemExclusions: Set<String> = ["com.apple.finder", "com.apple.dock", "com.raycast.macos"]

    /// Posted by the CLI after it paused, resumed or killed so the menu bar icon updates at once
    /// instead of on its next background sample.
    public static let didChangeNotification = Notification.Name("dev.marstaj.Stasis.didChange")

    /// Dock-visible apps other than this process. The pid check matters when running outside a
    /// bundle, where there is no bundle id to exclude.
    public static func regularApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
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
            bundlePath: application.bundleURL?.path
        )
    }
}
