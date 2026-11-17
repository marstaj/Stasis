import Foundation

/// A dotted numeric version such as `1.2.3` or the release tag `v1.2.3`. Components compare as
/// numbers and missing ones count as zero, so `1.10` is newer than `1.9` and `1.0` equals `1.0.0`.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    private let components: [Int]

    /// Nil for anything that is not purely dotted numbers, such as a pre-release tag.
    public init?(_ string: String) {
        let parts = (string.hasPrefix("v") ? string.dropFirst() : Substring(string))
            .split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
        }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let (left, right) = (lhs.component(index), rhs.component(index))
            if left != right { return left < right }
        }
        return false
    }

    private func component(_ index: Int) -> Int { index < components.count ? components[index] : 0 }
}
