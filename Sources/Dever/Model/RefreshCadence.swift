import Foundation

/// How often each kind of data is read again while its screen is in front and Dever is the
/// active app: the freshness budgets of docs/data-freshness.md, section 4. Fast for what is
/// in flight (a running check, a deploying preview) and for the open channel, a minute for
/// the rest, and slower each time a tool fails to answer.
enum RefreshCadence {
    enum Kind: CaseIterable {
        /// Messages that arrived since the newest one held, and the read cursor: two small requests.
        case slackNew
        /// The channel's latest page again: edits, reactions and reply counts of what is on screen.
        case slackPage
        /// The project's issues changed since the last read.
        case linear
        /// The repositories' open and merged pull requests.
        case github
        /// The checks of the pull requests whose checks are running, and nothing else.
        case checks
        case preview

        var service: ServiceKind {
            switch self {
            case .slackNew, .slackPage: .slack
            case .linear: .linear
            case .github, .checks, .preview: .github
            }
        }
    }

    /// Seconds between two reads of `kind`; nil when there is nothing to read (no check is
    /// running). `inFlight`: something of that kind is moving right now.
    static func interval(_ kind: Kind, inFlight: Bool = false) -> TimeInterval? {
        switch kind {
        case .slackNew: 20
        case .slackPage, .linear, .github: 60
        case .checks: inFlight ? 15 : nil
        case .preview: inFlight ? 15 : 60
        }
    }

    /// The Overview's cycle while the Overview is the screen in front (Settings › Refresh in
    /// the background every, when that is shorter).
    static let overviewInFront: TimeInterval = 60

    /// A tool that keeps failing is asked less and less often, up to this.
    static let longestWait: TimeInterval = 300

    /// The wait before the next read after `failures` failed ones in a row: twice as long
    /// each time, never shorter than the interval nor longer than five minutes.
    static func wait(_ interval: TimeInterval, failures: Int) -> TimeInterval {
        guard failures > 0 else { return interval }
        return max(interval, min(longestWait, interval * pow(2, Double(min(failures, 10)))))
    }

    /// Whether `kind`, last read at `last`, is to be read again at `now`.
    static func isDue(_ kind: Kind, last: Date?, inFlight: Bool = false, failures: Int = 0, now: Date = Date()) -> Bool {
        guard let interval = interval(kind, inFlight: inFlight) else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= wait(interval, failures: failures)
    }
}
