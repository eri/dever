import Foundation

// Finding the channel or Linear project that is "close" to a project name, so the editor can
// offer it before asking anything. Exact slug first, then one slug containing the other.

extension Naming {
    /// How close two names are once slugged: the same, one inside the other, or not close.
    enum Closeness: Int, Comparable {
        case none = 0, contains = 1, exact = 2
        static func < (a: Closeness, b: Closeness) -> Bool { a.rawValue < b.rawValue }
    }

    /// `candidate` compared to `name`, both reduced to slugs. A slug shorter than 3 characters
    /// never "contains": "ai" would match half the workspace.
    static func closeness(_ candidate: String, to name: String) -> Closeness {
        let a = slug(candidate), b = slug(name)
        guard !a.isEmpty, !b.isEmpty else { return .none }
        if a == b { return .exact }
        guard a.count >= 3, b.count >= 3 else { return .none }
        return a.contains(b) || b.contains(a) ? .contains : .none
    }

    /// The candidate closest to `name` (exact beats contains; among equals, the shortest), or nil.
    static func closest<T>(to name: String, in candidates: [T], key: (T) -> String) -> T? {
        var best: (item: T, closeness: Closeness, length: Int)?
        for item in candidates {
            let c = closeness(key(item), to: name)
            guard c > .none else { continue }
            let length = key(item).count
            if let b = best, (b.closeness > c) || (b.closeness == c && b.length <= length) { continue }
            best = (item, c, length)
        }
        return best?.item
    }

    /// The channel closest to a project name: its name without the prefix is compared, so
    /// `proj-checkout` is exact for "Checkout".
    static func closestChannel(to name: String, prefix: String, in channels: [SlackChannel]) -> SlackChannel? {
        closest(to: name, in: channels) { ch in
            prefix.isEmpty || !ch.name.hasPrefix(prefix) ? ch.name : String(ch.name.dropFirst(prefix.count))
        }
    }
}
