/// The count drawn on the menu bar icon while apps are paused, partially paused or not responding.
public enum PausedBadge {
    /// Nil when nothing is paused, so the icon shows no badge.
    public static func text(forPausedCount count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1...99: String(count)
        default: "99+"
        }
    }
}
