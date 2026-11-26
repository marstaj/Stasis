import AppKit
import StasisCore
import SwiftUI
import os

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
        UserDefaults.standard.register(defaults: [Preferences.showPausedBadge: true])
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
        // The popover's badge checkbox writes through @AppStorage, which Observation does not see.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }

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
        let count = monitor.pausedCount
        let icon = count > 0 ? pausedIcon : idleIcon
        if UserDefaults.standard.bool(forKey: Preferences.showPausedBadge),
           let text = PausedBadge.text(forPausedCount: count), let icon {
            statusItem?.button?.image = Self.badged(icon, text: text, pausedCount: count)
        } else {
            statusItem?.button?.image = icon
        }
    }

    /// The icon with `text` in a pill on its top-right corner. The canvas is exactly the square
    /// item's width with the icon where the button centres it unbadged, and the pill is pinned to
    /// the right edge, so a longer count grows over the icon instead of widening the item. The
    /// digits and a ring around the pill are cut out of the template rather than coloured, so
    /// macOS still tints the whole image.
    private static func badged(_ icon: NSImage, text: String, pausedCount: Int) -> NSImage {
        // Condensed keeps two digits from covering most of the icon.
        let font = NSFont.systemFont(ofSize: 7.5, weight: .bold, width: .condensed)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let pillHeight: CGFloat = 9
        let pillWidth = max(pillHeight, textWidth + 3.5)
        let iconSize = icon.size
        let side = NSStatusBar.system.thickness
        let pill = NSRect(x: side - pillWidth, y: iconSize.height - pillHeight, width: pillWidth, height: pillHeight)
        let image = NSImage(size: NSSize(width: side, height: iconSize.height), flipped: false) { _ in
            icon.draw(in: NSRect(origin: NSPoint(x: (side - iconSize.width) / 2, y: 0), size: iconSize))
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A clear ring keeps the pill from merging into the icon underneath.
            let ring = pill.insetBy(dx: -1.5, dy: -1.5)
            context.setBlendMode(.destinationOut)
            NSBezierPath(roundedRect: ring, xRadius: ring.height / 2, yRadius: ring.height / 2).fill()
            context.setBlendMode(.normal)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
            context.setBlendMode(.destinationOut)
            let baseline = pill.midY - font.capHeight / 2
            (text as NSString).draw(at: NSPoint(x: pill.midX - textWidth / 2, y: baseline + font.descender), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Stasis, \(pausedCount) paused"
        return image
    }

    private lazy var idleIcon = Self.menuBarIcon("MenuBarIdle", fallbackSymbol: "pause.circle")
    private lazy var pausedIcon = Self.menuBarIcon("MenuBarPaused", fallbackSymbol: "pause.circle.fill")

    /// The SVGs are copied into the bundle by the Makefile, so `swift run` has none and gets the symbol.
    private static func menuBarIcon(_ name: String, fallbackSymbol: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"), let image = NSImage(contentsOf: url) else {
            Logger(subsystem: "dev.marstaj.Stasis", category: "status-item")
                .error("Menu bar icon \(name).svg is missing or unreadable; using \(fallbackSymbol)")
            return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: "Stasis")
        }
        // Tinted by macOS for light, dark and highlighted menu bars.
        image.isTemplate = true
        image.accessibilityDescription = "Stasis"
        return image
    }
}
