import AppKit
import Network

/// The moments someone looks at Dever again: the app comes forward, the Mac wakes, the network
/// returns. Each posts `.lookAgain`, and the screen in front refreshes what it shows if that is
/// older than half a minute, or whatever its age when a link to something Dever displays was
/// opened in another app meanwhile (docs/data-freshness.md, section 3.4).
@MainActor
final class LookAgain {
    static let shared = LookAgain()

    /// How old a screen's data may be before looking again refreshes it.
    static let tolerance: TimeInterval = 30

    /// A pull request, an issue, a message or a preview was opened outside Dever since the
    /// last look: it may have been acted on there.
    private(set) var dirty = false
    private var pending: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    private var online = true
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.post() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The network takes a moment to come back after a wake.
            Task { @MainActor in self?.post(after: 3) }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if reachable, !self.online { self.post(after: 1) }
                self.online = reachable
            }
        }
        monitor.start(queue: .global(qos: .utility))
        self.monitor = monitor
    }

    /// Remembers that `url` left for another app when it points at one of the tools.
    func openedExternally(_ url: URL) {
        guard let host = url.host()?.lowercased() else { return }
        let tools = ["github.com", "linear.app", "slack.com", PreviewTarget.domain]
        if tools.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { dirty = true }
    }

    /// Whether data fetched at `fetched` should be refreshed now that someone looks again.
    func isDue(_ fetched: Date?) -> Bool {
        dirty || fetched.map { Date().timeIntervalSince($0) > Self.tolerance } ?? true
    }

    /// One notification for events that arrive together (a wake is also an activation).
    private func post(after delay: TimeInterval = 0.3) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .lookAgain, object: nil)
            dirty = false
        }
    }
}

extension Notification.Name {
    /// Posted when the user looks at Dever again; screens refresh what `LookAgain.isDue` says.
    static let lookAgain = Notification.Name("dever.lookAgain")
}
