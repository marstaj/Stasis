import Foundation

public enum AppMatch: Sendable, Hashable {
    case found(AppGroup)
    case notFound
    case ambiguous([AppGroup])
}

public enum AppMatcher {
    /// Prefix and substring matching need at least this many characters; `stasis pause a` must
    /// not pause whichever app happens to start with "a".
    public static let minimumPartialQueryLength = 3

    /// Resolves a user-typed app reference. The app's pid, then exact bundle id, then exact name,
    /// then a unique name prefix, then a unique name substring; all case-insensitive. A unique
    /// prefix match wins even if the query also appears inside other names.
    ///
    /// Each exact tier is tried on every app before the next one, so an app cannot take another's
    /// place by using its bundle id as a name. Only the pid tells two instances of one app apart.
    public static func match(_ query: String, in groups: [AppGroup]) -> AppMatch {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return .notFound }

        let exact = pid_t(query).flatMap { pid in groups.first { $0.app.pid == pid } }
            ?? groups.first { $0.app.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame }
            ?? groups.first { $0.app.name.caseInsensitiveCompare(query) == .orderedSame }
        if let exact { return .found(exact) }
        // A number is taken as a pid. If no app has it any more (a stale list), it must not go on
        // to match an app that merely has those digits in its name.
        guard pid_t(query) == nil else { return .notFound }
        guard query.count >= minimumPartialQueryLength else { return .notFound }

        for predicate in [
            { (name: String) in name.range(of: query, options: [.caseInsensitive, .anchored]) != nil },
            { (name: String) in name.range(of: query, options: .caseInsensitive) != nil },
        ] {
            let candidates = groups.filter { predicate($0.app.name) }
            switch candidates.count {
            case 0: continue
            case 1: return .found(candidates[0])
            default: return .ambiguous(candidates)
            }
        }
        return .notFound
    }
}
