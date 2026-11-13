import AppKit
import StasisCore
import SwiftUI

@main
struct StasisApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self) private var controller

    var body: some Scene {
        // The app has no windows of its own; an empty Settings scene satisfies the App protocol.
        Settings { EmptyView() }
    }
}

/// Status item plus popover, instead of `MenuBarExtra(.window)`: that panel grows with its
/// content but never shrinks back, while an NSPopover follows the hosting controller's
/// preferred content size in both directions.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = ProcessMonitor()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: ContentView(monitor: monitor))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        observeIcon()

        // The CLI posts this after pausing or resuming; without it the icon lags up to 30 s.
        DistributedNotificationCenter.default().addObserver(
            forName: Workspace.didChangeNotification, object: nil, queue: .main
        ) { [monitor] _ in
            MainActor.assumeIsolated { monitor.refresh() }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Transient closing only sees clicks inside this app; clicks in other apps need a global monitor.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in self.popover.performClose(nil) }
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func observeIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: {
            Task { @MainActor in self.observeIcon() }
        }
    }

    private func updateIcon() {
        let name = monitor.anyPaused ? "pause.circle.fill" : "pause.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Stasis")
    }
}
