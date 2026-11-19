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
    private let updates = UpdateChecker()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: ContentView(monitor: monitor, updates: updates))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        observeIcon()

        // The CLI posts this after pausing, resuming or killing; without it the icon lags up to 30 s.
        DistributedNotificationCenter.default().addObserver(
            forName: Workspace.didChangeNotification, object: nil, queue: .main
        ) { [monitor] _ in
            MainActor.assumeIsolated { monitor.refreshSoon() }
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        monitor.refresh()

        let menu = NSMenu()
        menu.autoenablesItems = false
        if let front = monitor.frontApp {
            let pauseOthers = menu.addItem(
                withTitle: "Pause All Except \(front.name)", action: #selector(pauseAllExceptFrontApp), keyEquivalent: ""
            )
            pauseOthers.target = self
            pauseOthers.isEnabled = !monitor.pauseAllTargets(sparingFrontApp: true).isEmpty
        }
        let pause = menu.addItem(withTitle: "Pause All", action: #selector(pauseAll), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = !monitor.pauseAllTargets(sparingFrontApp: false).isEmpty
        let resume = menu.addItem(withTitle: "Resume All", action: #selector(resumeAll), keyEquivalent: "")
        resume.target = self
        resume.isEnabled = monitor.anyPaused
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stasis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // A permanently assigned menu would take over left-click too; attached only for this
        // click, the status item still positions and highlights it. Tracking blocks until it closes.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func pauseAllExceptFrontApp() { monitor.pauseAll(sparingFrontApp: true) }

    @objc private func pauseAll() { monitor.pauseAll(sparingFrontApp: false) }

    @objc private func resumeAll() { monitor.resumeAll() }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Otherwise the first click only makes the popover key and the row's tap gesture never sees it.
            popover.contentViewController?.view.window?.makeKey()
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
