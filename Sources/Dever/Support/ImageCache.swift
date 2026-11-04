import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Pictures fetched once and kept in memory and on disk under Application Support/Dever,
/// keyed by URL. Decoding is downsampled to the pixels the view shows and happens off the
/// main thread. Private hosts (`uploads.linear.app`) are fetched through a token the caller
/// supplies per request, so the cache itself knows nothing about accounts.
///
/// Folders are shared with the Slack media cache (`avatars/` for people, `files/` for the
/// rest); keys carry a source prefix so the two never collide.
actor ImageCache {
    static let shared = ImageCache()

    enum Kind: String { case avatars, files }

    /// Adds credentials to a request for hosts that need them; nil leaves it anonymous.
    typealias Authorizer = @Sendable (inout URLRequest) -> Void

    private let memory = NSCache<NSString, CGImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let concurrency = 4
    private let root: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        for kind in [Kind.avatars, .files] {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(kind.rawValue, isDirectory: true),
                                                     withIntermediateDirectories: true)
        }
        return dir
    }()

    init() { memory.countLimit = 400 }

    /// The picture at `url`, at most `maxPixels` on its long side.
    /// - Parameter source: a short prefix naming who the picture belongs to ("linear").
    func image(_ url: URL, kind: Kind, source: String, maxPixels: Int, authorize: Authorizer? = nil) async -> CGImage? {
        let key = "\(source)-\(Self.hash(url))"
        let memoryKey = "\(key)@\(maxPixels)" as NSString
        if let hit = memory.object(forKey: memoryKey) { return hit }
        if let task = inFlight[key] { return await task.value }
        let file = root.appendingPathComponent(kind.rawValue, isDirectory: true).appendingPathComponent(key)
        let task = Task<CGImage?, Never> {
            if let data = try? Data(contentsOf: file), let decoded = Self.decode(data, maxPixels: maxPixels) { return decoded }
            await self.acquire()
            defer { Task { await self.release() } }
            guard let data = try? await Self.fetch(url, authorize: authorize),
                  let decoded = Self.decode(data, maxPixels: maxPixels) else { return nil }
            try? data.write(to: file, options: .atomic)
            return decoded
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: memoryKey) }
        return result
    }

    private static func fetch(_ url: URL, authorize: Authorizer?) async throws -> Data {
        var req = URLRequest(url: url)
        authorize?(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200, !(http?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/html") else {
            throw AppError.message("Image: not available (\(http?.statusCode ?? 0))")
        }
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
        SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func acquire() async {
        if running < concurrency { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}
