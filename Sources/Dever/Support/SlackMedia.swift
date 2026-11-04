import AppKit
import CryptoKit
import Foundation
import ImageIO

/// Pictures Slack messages need (avatars, thumbnails, link previews), fetched once and kept
/// in memory and on disk under Application Support/Dever. Decoding happens here, off the
/// main thread, downsampled to the size the row shows, so scrolling never decodes a 4000px
/// photo. Requests for one key are shared, and at most four downloads run at a time.
actor SlackMediaCache {
    static let shared = SlackMediaCache()

    enum Kind: String { case avatars, files }

    private let memory = NSCache<NSString, CGImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private let gate = Semaphore(limit: 4)
    /// Avatars (small, long-lived) under Application Support; thumbnails and originals under
    /// Caches, which macOS may clear and which `purge()` keeps under 200 MB and two weeks.
    private let root: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(Kind.avatars.rawValue, isDirectory: true),
                                                 withIntermediateDirectories: true)
        return dir
    }()
    static let cachesRoot: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        for sub in ["files", "originals"] {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        return dir
    }()

    init() {
        memory.countLimit = 600
        Task.detached(priority: .background) { SlackMediaCache.purge() }
    }

    /// Oldest first, drop what is older than 14 days, then what exceeds 200 MB.
    static func purge(maxBytes: Int = 200 * 1024 * 1024, maxAge: TimeInterval = 14 * 86_400) {
        let fm = FileManager.default
        var entries: [(url: URL, size: Int, date: Date)] = []
        for sub in ["files", "originals"] {
            let dir = cachesRoot.appendingPathComponent(sub, isDirectory: true)
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey])) ?? [] {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
                entries.append((url, values?.fileSize ?? 0, values?.contentAccessDate ?? values?.contentModificationDate ?? .distantPast))
            }
        }
        entries.sort { $0.date < $1.date }
        var total = entries.reduce(0) { $0 + $1.size }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for e in entries where e.date < cutoff || total > maxBytes {
            try? fm.removeItem(at: e.url)
            total -= e.size
        }
    }

    /// The avatar of `user`, keyed by user id so a picture is fetched once per person.
    /// The URL's hash in the key makes a changed picture a new file.
    func avatar(for user: SlackUser, pixels: Int = 72) async -> CGImage? {
        guard let url = user.avatar else { return nil }
        return await image(url: url, kind: .avatars, key: "\(user.id)-\(Self.hash(url))", maxPixels: pixels, client: nil)
    }

    /// A Slack-hosted thumbnail (`thumb_360` …), downloaded with the token through `client`.
    func thumbnail(_ url: URL, fileID: String, variant: String, maxPixels: Int, client: SlackClient) async -> CGImage? {
        await image(url: url, kind: .files, key: "\(fileID)-\(variant)", maxPixels: maxPixels, client: client)
    }

    /// A public picture (an unfurl's thumbnail), fetched without credentials.
    func publicImage(_ url: URL, maxPixels: Int) async -> CGImage? {
        await image(url: url, kind: .files, key: "u-\(Self.hash(url))", maxPixels: maxPixels, client: nil)
    }

    /// Warms the cache for a set of users in the background, four at a time.
    func prefetchAvatars(_ users: [SlackUser]) async {
        await withTaskGroup(of: Void.self) { group in
            for user in users where user.avatar != nil {
                group.addTask { _ = await self.avatar(for: user) }
            }
        }
    }

    private func image(url: URL, kind: Kind, key: String, maxPixels: Int, client: SlackClient?) async -> CGImage? {
        let memoryKey = "\(key)@\(maxPixels)" as NSString
        if let hit = memory.object(forKey: memoryKey) { return hit }
        if let running = inFlight[key] { return await running.value }
        let file = (kind == .avatars ? root : Self.cachesRoot).appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(Self.safe(key))
        let task = Task<CGImage?, Never> {
            if let data = try? Data(contentsOf: file), let decoded = Self.decode(data, maxPixels: maxPixels) {
                return decoded
            }
            await gate.wait()
            defer { Task { await gate.signal() } }
            guard let data = try? await Self.fetch(url, client: client), let decoded = Self.decode(data, maxPixels: maxPixels) else {
                return nil
            }
            try? data.write(to: file, options: .atomic)
            return decoded
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: memoryKey) }
        return result
    }

    private static func fetch(_ url: URL, client: SlackClient?) async throws -> Data {
        if let client { return try await client.download(url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("Image: not available") }
        return data
    }

    /// Decoded and downsampled in one step: ImageIO never materialises the full-size bitmap.
    private static func decode(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func hash(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func safe(_ key: String) -> String {
        String(key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    /// A counting semaphore for structured concurrency.
    private actor Semaphore {
        private let limit: Int
        private var running = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []
        init(limit: Int) { self.limit = limit }
        func wait() async {
            if running < limit { running += 1; return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func signal() {
            if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
        }
    }
}

/// The workspace's members, fetched with one `users.list` and kept for a quarter of an hour
/// (the method is Tier 2: 20 calls a minute). A copy on disk gives names when offline.
actor SlackDirectory {
    static let shared = SlackDirectory()
    private var cached: (team: String, users: [String: SlackUser], at: Date)?
    private var loading: Task<[String: SlackUser], Error>?
    private let ttl: TimeInterval = 15 * 60

    func users(team: String, via client: SlackClient) async throws -> [String: SlackUser] {
        if let cached, cached.team == team, Date().timeIntervalSince(cached.at) < ttl { return cached.users }
        if let loading { return try await loading.value }
        let task = Task<[String: SlackUser], Error> {
            do {
                let users = try await client.users()
                try? JSONEncoder().encode(users).write(to: Self.file(team), options: .atomic)
                return users
            } catch {
                if let data = try? Data(contentsOf: Self.file(team)),
                   let stored = try? JSONDecoder().decode([String: SlackUser].self, from: data) { return stored }
                throw error
            }
        }
        loading = task
        defer { loading = nil }
        let users = try await task.value
        cached = (team, users, Date())
        return users
    }

    private var emojiCache: (team: String, emoji: [String: URL], at: Date)?
    private var emojiLoading: Task<[String: URL], Error>?

    /// The team's custom emoji, one `emoji.list` an hour; a disk copy for offline and for
    /// tokens without `emoji:read` (then the last known set, or none).
    func customEmoji(team: String, via client: SlackClient) async -> [String: URL] {
        if let emojiCache, emojiCache.team == team, Date().timeIntervalSince(emojiCache.at) < 3600 { return emojiCache.emoji }
        if let emojiLoading { return (try? await emojiLoading.value) ?? [:] }
        let file = Self.file(team).deletingLastPathComponent().appendingPathComponent("emoji-\(team).json")
        let task = Task<[String: URL], Error> {
            do {
                let emoji = try await client.customEmoji()
                try? JSONEncoder().encode(emoji).write(to: file, options: .atomic)
                return emoji
            } catch {
                return (try? JSONDecoder().decode([String: URL].self, from: Data(contentsOf: file))) ?? [:]
            }
        }
        emojiLoading = task
        defer { emojiLoading = nil }
        let emoji = (try? await task.value) ?? [:]
        emojiCache = (team, emoji, Date())
        return emoji
    }

    private static func file(_ team: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
            .appendingPathComponent("users-\(team).json")
    }
}

extension SlackMediaCache {
    /// The whole file, downloaded once with the token into the purgeable cache (see `purge`).
    func localFile(for file: SlackFile, client: SlackClient) async throws -> URL {
        guard let urlString = file.url_private, let url = URL(string: urlString) else { throw AppError.message("File: no download URL") }
        let dir = Self.cachesRoot.appendingPathComponent("originals", isDirectory: true)
        let ext = (file.name as NSString?)?.pathExtension ?? ""
        let name = Self.safe(file.id) + (ext.isEmpty ? "" : "." + ext)
        let target = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let data = try await client.download(url)
        try data.write(to: target, options: .atomic)
        return target
    }
}
