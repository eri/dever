import Foundation

/// Development aid: `DEVER_SNAPSHOT_OVERVIEW_DEMO=busy|quiet` (with `DEVER_SNAPSHOT_DIR`) runs the
/// Overview on made-up projects instead of the linked ones, so what waits for you, an all-quiet
/// list and an incomplete project can be captured whatever the real workspace holds. Nothing is
/// saved: snapshot runs never write the projects back.
enum OverviewDemo {
    @MainActor static var scene: (projects: [Project], snapshots: [UUID: ProjectSnapshot])? {
        guard Snapshotter.directory != nil,
              let raw = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_OVERVIEW_DEMO"] else { return nil }
        return make(busy: raw != "quiet")
    }

    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    private static func make(busy: Bool) -> (projects: [Project], snapshots: [UUID: ProjectSnapshot]) {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func ts(_ minutes: Double) -> String { String(format: "%.6f", ago(minutes).timeIntervalSince1970) }
        func project(_ n: Int, _ name: String, linear: Bool = true, pinned: Bool = false) -> Project {
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            var p = Project(id: id(n), name: name,
                            slack: .init(id: "C\(n)", name: "proj-\(slug)"),
                            linear: linear ? .init(id: "L\(n)", name: name, url: "https://linear.app/demo/project/\(slug)") : nil)
            p.favorite = pinned ? true : nil
            return p
        }
        func delivery(done: Int, total: Int) -> Delivery {
            Delivery(issues: (0..<total).map { ("APP-\($0)", $0 < done ? "completed" : "started", $0 < done ? "Done" : "In Progress") },
                     openPR: [], mergedPR: [])
        }
        func linear(done: Int, total: Int) -> ProjectSnapshot.LinearStats {
            var l = ProjectSnapshot.LinearStats()
            l.total = total; l.done = done; l.inProgress = total - done
            return l
        }

        let checkout = project(1, "Checkout", pinned: true)
        let billing = project(2, "Billing")
        let onboarding = project(3, "Onboarding")
        let search = project(4, "Search")
        let leaderboard = project(5, "Leaderboard", linear: false)

        var snapshots: [UUID: ProjectSnapshot] = [:]

        var s = ProjectSnapshot()
        s.linear = linear(done: 15, total: 16)
        s.delivery = delivery(done: 15, total: 16)
        s.slack = .init(messagesThisWeek: 42, lastActivity: ago(10), lastAuthor: "Léa", unread: busy ? 7 : 0,
                        firstUnreadTS: busy ? ts(55) : nil, lastUnreadAt: busy ? ago(10) : nil,
                        mentions: busy ? [.init(ts: ts(40), author: "Léa", text: "can you check the staging build?", date: ago(40))] : [])
        var g = ProjectSnapshot.GitHubStats(openPRs: 3, pipeline: .passing)
        if busy {
            g.reviewRequests = [
                .init(number: 4871, title: "Tip preview width", url: "https://github.com/demo/app/pull/4871", issue: "APP-12", date: ago(120)),
                .init(number: 4866, title: "Receipt totals in the summary", url: "https://github.com/demo/app/pull/4866", issue: "APP-9", date: ago(300)),
            ]
        }
        s.github = g
        snapshots[checkout.id] = s

        s = ProjectSnapshot()
        s.linear = linear(done: 6, total: 11)
        s.delivery = delivery(done: 6, total: 11)
        s.slack = .init(messagesThisWeek: 12, lastActivity: ago(25), lastAuthor: "Ana", unread: busy ? 1 : 0,
                        firstUnreadTS: busy ? ts(25) : nil, lastUnreadAt: busy ? ago(25) : nil,
                        mentions: busy ? [.init(ts: ts(25), author: "Ana", text: "the invoice export fails on Safari, any idea?", date: ago(25))] : [])
        g = ProjectSnapshot.GitHubStats(openPRs: 2, pipeline: .failing)
        g.failingRepositories = ["demo/billing"]
        s.github = g
        snapshots[billing.id] = s

        s = ProjectSnapshot()
        s.linear = linear(done: 8, total: 8)
        s.delivery = delivery(done: 8, total: 8)
        s.slack = .init(messagesThisWeek: 0, lastActivity: ago(6 * 24 * 60), lastAuthor: "Marco", unread: 0)
        g = ProjectSnapshot.GitHubStats(openPRs: 0, pipeline: .passing)
        g.lastMerged = (212, "sam", ago(3 * 24 * 60))
        s.github = g
        snapshots[onboarding.id] = s

        s = ProjectSnapshot()
        s.linear = linear(done: 3, total: 9)
        s.delivery = delivery(done: 3, total: 9)
        s.slack = .init(messagesThisWeek: 4, lastActivity: ago(26 * 60), lastAuthor: "Ana", unread: 0)
        g = ProjectSnapshot.GitHubStats(openPRs: 1, pipeline: .passing)
        g.longWait = (318, ago(4 * 24 * 60))
        s.github = g
        snapshots[search.id] = s

        s = ProjectSnapshot()
        s.slack = .init(messagesThisWeek: 2, lastActivity: ago(23 * 60), lastAuthor: "Marco", unread: busy ? 2 : 0,
                        firstUnreadTS: busy ? ts(23 * 60) : nil, lastUnreadAt: busy ? ago(23 * 60) : nil)
        snapshots[leaderboard.id] = s

        return ([checkout, billing, onboarding, search, leaderboard], snapshots)
    }
}
