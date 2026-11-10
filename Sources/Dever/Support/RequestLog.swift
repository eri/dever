import Foundation

/// Development aid: `DEVER_TRACE_REQUESTS=1` prints one line per request to stderr (service,
/// endpoint, status, size, duration) with the running count and bytes since launch, so the cost
/// of a refresh is measured rather than estimated (docs/data-freshness.md).
enum RequestLog {
    static let enabled = ProcessInfo.processInfo.environment["DEVER_TRACE_REQUESTS"] == "1"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var total = 0

    static func record(_ service: String, _ endpoint: String, status: Int, bytes: Int, since started: Date) {
        guard enabled else { return }
        lock.lock()
        count += 1
        total += bytes
        let (n, sum) = (count, total)
        lock.unlock()
        // Query strings carry cursors and ids, never a token; the path alone names the endpoint.
        let name = endpoint.split(separator: "?").first.map(String.init) ?? endpoint
        let line = String(format: "[requests] #%d %@ %@ %d %.1f KB %.2f s (total %.1f KB)\n",
                          n, service, name, status, Double(bytes) / 1024, Date().timeIntervalSince(started), Double(sum) / 1024)
        FileHandle.standardError.write(Data(line.utf8))
    }
}
