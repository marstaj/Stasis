import Foundation

/// UserDefaults keys read outside the SwiftUI view that sets them.
enum Preferences {
    /// Whether the menu bar icon carries the number of paused apps. On unless turned off.
    static let showPausedBadge = "showPausedBadge"
}
