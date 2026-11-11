import Foundation

// The summaries of long messages, kept between launches so that a message that has not changed
// is not summarised again (docs/on-device-ai.md, rule 3 and 5.7). The one generated text that
// reaches the disk, and only for as long as it is of use: a summary goes when its message is
// read, when it is older than the limit, and when "Long messages" is switched off. The file
// stays on this Mac, readable by the user alone.

struct SummaryCache {
    struct Record: Codable, Equatable {
        /// The input the summary was made from: an edited message is another version.
        var version: String
        var kind: String?
        /// Nil: the model had nothing to show for this version, and is not asked again.
        var sentence: String?
        var written: Date

        var text: GeneratedText? {
            sentence.map { GeneratedText(sentences: [.init(text: $0)], kind: kind) }
        }
    }

    /// By message: "channel/ts", the id of `MessageSummary.subject`.
    private(set) var records: [String: Record] = [:]
    /// Nil keeps everything in memory (tests, captures).
    let url: URL?

    /// The file in the app's own folder.
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("message-summaries.json")
    }

    /// How long an unread summary is kept: the days after which Settings calls a channel quiet.
    static var maxAge: TimeInterval { Double(Preferences.quietAfterDays) * 86_400 }

    init(url: URL?, now: Date = Date(), maxAge: TimeInterval = SummaryCache.maxAge) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        records = saved
        prune(now: now, maxAge: maxAge)
    }

    /// What was written for this message, if it was written from the same input.
    func record(_ id: String, version: String) -> Record? {
        records[id].flatMap { $0.version == version ? $0 : nil }
    }

    mutating func save(_ id: String, version: String, text: GeneratedText?, now: Date = Date()) {
        records[id] = Record(version: version, kind: text?.kind,
                             sentence: text?.sentences.map(\.text).joined(separator: " "), written: now)
        write()
    }

    /// The messages of `channel` up to `ts` have been read: their summaries have served.
    mutating func dropRead(channel: String, upTo ts: String) {
        let prefix = channel + "/"
        let before = records.count
        records = records.filter { id, _ in
            !(id.hasPrefix(prefix) && SummaryCache.isAtOrBefore(String(id.dropFirst(prefix.count)), ts))
        }
        if records.count != before { write() }
    }

    /// Nothing stays longer than `maxAge`, read or not.
    mutating func prune(now: Date = Date(), maxAge: TimeInterval = SummaryCache.maxAge) {
        let before = records.count
        records = records.filter { now.timeIntervalSince($0.value.written) <= maxAge }
        if records.count != before { write() }
    }

    mutating func removeAll() {
        guard !records.isEmpty else { return }
        records = [:]
        write()
    }

    static func isAtOrBefore(_ a: String, _ b: String) -> Bool { (Double(a) ?? 0) <= (Double(b) ?? 0) }

    private func write() {
        guard let url else { return }
        guard !records.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
