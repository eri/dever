import Foundation

/// Remote things kept for the session, by key: the value, when it was last read with success,
/// and whether the latest refresh failed. Concurrent readers of one key share one request, a
/// failed refresh keeps the value, and a value is served without a request while it is
/// younger than what the reader accepts (docs/data-freshness.md, section 3.1).
///
/// The stores (`GitHubStore`, …) each hold one and publish its changes.
@MainActor
final class ResourceCache<Key: Hashable, Value> {
    struct Entry {
        var value: Value
        /// The last successful read.
        var fetchedAt: Date
        /// Why the latest refresh did not go through; nil once one does.
        var failure: Error?
        /// Something may have changed it elsewhere: the next reader fetches whatever its age.
        var dirty = false
    }

    private(set) var entries: [Key: Entry] = [:]
    private var loads: [Key: Task<Value, Error>] = [:]
    /// Called after an entry changed (a read landed, a refresh failed, a local update).
    var onChange: (() -> Void)?
    /// The clock, replaceable in tests.
    var now: () -> Date = Date.init

    func value(_ key: Key) -> Value? { entries[key]?.value }
    func fetchedAt(_ key: Key) -> Date? { entries[key]?.fetchedAt }
    func failure(_ key: Key) -> Error? { entries[key]?.failure }

    /// Whether `key` can be served as it is to a reader that accepts values up to `maxAge` old.
    func isFresh(_ key: Key, maxAge: TimeInterval) -> Bool {
        guard let entry = entries[key], !entry.dirty else { return false }
        return now().timeIntervalSince(entry.fetchedAt) <= maxAge
    }

    /// The value for `key`: the one held when it is fresh enough, otherwise fetched. A fetch
    /// already running for the key is joined, not repeated. When the fetch fails the held
    /// value stays, marked with the failure, and the error is thrown.
    func value(_ key: Key, maxAge: TimeInterval, fetch: @escaping () async throws -> Value) async throws -> Value {
        if isFresh(key, maxAge: maxAge), let held = entries[key]?.value { return held }
        if let running = loads[key] { return try await running.value }
        let task = Task { try await fetch() }
        loads[key] = task
        do {
            let value = try await task.value
            loads[key] = nil
            entries[key] = Entry(value: value, fetchedAt: now())
            onChange?()
            return value
        } catch {
            loads[key] = nil
            if entries[key] != nil {
                entries[key]?.failure = error
                onChange?()
            }
            throw error
        }
    }

    /// Changes the held value in place (an optimistic write, or the server's answer to one).
    func update(_ key: Key, _ change: (inout Value) -> Void) {
        guard var entry = entries[key] else { return }
        change(&entry.value)
        entries[key] = entry
        onChange?()
    }

    /// The value may have changed elsewhere: it stays on screen, and the next reader fetches.
    func invalidate(_ key: Key) {
        guard entries[key] != nil else { return }
        entries[key]?.dirty = true
    }

    func remove(_ key: Key) {
        guard entries.removeValue(forKey: key) != nil else { return }
        onChange?()
    }

    func removeAll() {
        guard !entries.isEmpty else { return }
        entries = [:]
        onChange?()
    }
}
