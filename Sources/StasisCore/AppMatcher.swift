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

    /// Resolves a user-typed app reference. Exact bundle id, then exact name, then a unique name
    /// prefix, then a unique name substring; all case-insensitive. A unique prefix match wins even
    /// if the query also appears inside other names.
    public static func match(_ query: String, in groups: [AppGroup]) -> AppMatch {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return .notFound }

        if let exact = groups.first(where: {
            $0.app.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame
                || $0.app.name.caseInsensitiveCompare(query) == .orderedSame
        }) {
            return .found(exact)
        }
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
