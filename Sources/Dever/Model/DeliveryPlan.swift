import Foundation

/// A project's issues from one developer's seat: what is theirs to move and in which order,
/// what waits on someone else, and what has shipped. Built from the same join as `Delivery`
/// (Linear state + linked pull requests), plus reviews, pipelines and blocking relations.
struct DeliveryPlan {
    /// Who is looking: their Linear user (assignee) and their GitHub login (author, reviewer).
    struct Viewer {
        var linearID: String?
        var linearName: String?
        var githubLogin: String?

        func owns(_ issue: LinearIssue) -> Bool {
            guard let person = issue.assignee else { return false }
            if let linearID, let id = person.id { return id == linearID }
            return linearName.map { $0 == person.name } ?? false
        }

        func isLogin(_ login: String) -> Bool {
            githubLogin.map { $0.caseInsensitiveCompare(login) == .orderedSame } ?? false
        }
    }

    /// Where an open issue stands, in the order it deserves a hand: unblock what is under way
    /// before starting something new.
    enum Situation: Int, CaseIterable {
        case ciFailed, changesRequested, reviewRequested, behind, readyToMerge, building, draft, waitingReview, todo, blocked

        var label: String {
            switch self {
            case .ciFailed: "CI failed"
            case .changesRequested: "Changes requested"
            case .reviewRequested: "Review requested"
            case .behind: "Merged, ticket not moved"
            case .readyToMerge: "Ready to merge"
            case .building: "In progress"
            case .draft: "Draft PR"
            case .waitingReview: "Waiting for review"
            case .todo: "To do"
            case .blocked: "Blocked"
            }
        }

        /// Whether the developer has a move to make; a review to wait for or a blocker is not one.
        var actionable: Bool { self != .waitingReview && self != .blocked }
    }

    /// A pull request's review outcome: the latest verdict of each reviewer.
    enum Review { case approved, changesRequested, pending }

    /// An open pull request matched to an issue.
    struct Pull: Hashable {
        var number: Int
        var title: String
        var url: String
        var repository: String
        var draft = false
        var author: String
        var updatedAt: Date?
        var pipeline: ProjectSnapshot.PipelineState?
        /// The latest run of the pull request's branch, where a failure is read.
        var runURL: String?
        var review: Review = .pending
        /// Logins whose review is asked for.
        var requested: [String] = []
    }

    /// One open issue.
    struct Item: Identifiable {
        var issue: LinearIssue
        var situation: Situation
        var pull: Pull?
        var merged: [MergedPull] = []
        /// Identifiers of the unfinished issues that block this one.
        var blockedBy: [String] = []
        /// How many unfinished issues wait on this one.
        var unblocks = 0
        /// Since when it has been in its situation (last activity), for the ones that wait.
        var since: Date?
        var stale = false
        var id: String { issue.id }

        /// Someone else's issue that is in trouble: shown even while the group is folded.
        var inTrouble: Bool { situation == .ciFailed || Self.isOverdue(issue.dueDate) }

        private static func isOverdue(_ day: String?) -> Bool {
            guard let day else { return false }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            guard let date = f.date(from: String(day.prefix(10))) else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        }
    }

    /// One issue whose code has landed: done, or merged and waiting for QA.
    struct Shipped: Identifiable {
        var issue: LinearIssue
        var merged: [MergedPull]
        /// Merged, but the ticket still sits in a review or QA state.
        var inQA: Bool
        var id: String { issue.id }
    }

    /// The one issue to pick up now; `startIsGrab` when it is an unassigned one to take.
    private(set) var start: Item?
    private(set) var startIsGrab = false
    /// The viewer's other open issues, in order.
    private(set) var next: [Item] = []
    private(set) var others: [Item] = []
    private(set) var shipped: [Shipped] = []
    /// How many open issues are the viewer's (the start pick included, unless it is a grab).
    private(set) var yours = 0
    private(set) var total = 0
    private(set) var lastMerged: Date?

    var left: Int { total - shipped.count }
    var inQA: Int { shipped.filter(\.inQA).count }
    /// Open issues with work under way, for the bar's middle segment.
    var moving: Int { ([start].compactMap { $0 } + next + others).filter { $0.situation != .todo && $0.situation != .blocked }.count }

    static let staleReview: TimeInterval = 3 * 86_400
    static let staleBuilding: TimeInterval = 7 * 86_400

    init() {}

    /// - Parameters:
    ///   - open: open pull requests by issue identifier.
    ///   - merged: merged pull requests by issue identifier.
    ///   - blockers: for an issue identifier, the unfinished issues that block it.
    init(issues: [LinearIssue], open: [String: [Pull]], merged: [String: [MergedPull]],
         blockers: [String: [String]], viewer: Viewer, now: Date = Date()) {
        var unblocks: [String: Int] = [:]
        for (_, list) in blockers { for id in list { unblocks[id, default: 0] += 1 } }
        var mine: [Item] = []
        var free: [Item] = []
        for issue in issues where issue.state.type != "canceled" {
            total += 1
            let landed = merged[issue.identifier] ?? []
            let pulls = open[issue.identifier] ?? []
            let review = Delivery.isReviewState(issue.state.name)
            if issue.state.type == "completed" || (!landed.isEmpty && review && pulls.isEmpty) {
                shipped.append(Shipped(issue: issue, merged: landed, inQA: issue.state.type != "completed"))
                continue
            }
            var item = Item(issue: issue, situation: .todo, merged: landed, unblocks: unblocks[issue.identifier] ?? 0)
            var isMine = viewer.owns(issue)
            let updated = Self.date(issue.updatedAt)
            if let asked = pulls.first(where: { p in !viewer.isLogin(p.author) && p.requested.contains(where: viewer.isLogin) }), !isMine {
                // A colleague's pull request on this project's issue, waiting for the viewer's review.
                item.pull = asked
                item.situation = .reviewRequested
                item.since = asked.updatedAt
                isMine = true
            } else if let pull = pulls.min(by: { Self.situation(of: $0).rawValue < Self.situation(of: $1).rawValue }) {
                item.pull = pull
                item.situation = Self.situation(of: pull)
                item.since = pull.updatedAt
                isMine = isMine || (issue.assignee == nil && viewer.isLogin(pull.author))
            } else if !landed.isEmpty {
                item.situation = .behind
            } else if review {
                item.situation = .waitingReview
                item.since = updated
            } else if issue.state.type == "started" {
                item.situation = .building
                item.since = updated
            } else if let by = blockers[issue.identifier], !by.isEmpty {
                item.situation = .blocked
                item.blockedBy = by
            }
            if let since = item.since {
                let age = now.timeIntervalSince(since)
                item.stale = (item.situation == .waitingReview && age > Self.staleReview)
                    || ((item.situation == .building || item.situation == .draft) && age > Self.staleBuilding)
            }
            if isMine { mine.append(item) } else { free.append(item) }
        }
        mine.sort(by: Self.before)
        free.sort(by: Self.before)
        yours = mine.count
        if let i = mine.firstIndex(where: { $0.situation.actionable }) {
            start = mine.remove(at: i)
        } else if let i = free.firstIndex(where: { $0.issue.assignee == nil && $0.situation == .todo }) {
            // Nothing of the viewer's to move: the most pressing issue nobody holds.
            start = free.remove(at: i)
            startIsGrab = true
        }
        next = mine
        others = free
        lastMerged = shipped.flatMap(\.merged).compactMap(\.mergedAt).max()
        shipped.sort {
            let a = $0.merged.compactMap(\.mergedAt).max(), b = $1.merged.compactMap(\.mergedAt).max()
            if a != b { return (a ?? .distantPast) > (b ?? .distantPast) }
            return $0.issue.updatedAt > $1.issue.updatedAt
        }
    }

    private static func situation(of pull: Pull) -> Situation {
        if pull.pipeline == .failing { return .ciFailed }
        if pull.review == .changesRequested { return .changesRequested }
        if pull.draft { return .draft }
        return pull.review == .approved ? .readyToMerge : .waitingReview
    }

    /// The situation's rank, moved up a notch by staleness or by issues waiting on this one.
    private static func rank(_ item: Item) -> Double {
        var rank: Double = switch item.situation {
        case .ciFailed: 0
        case .changesRequested: 1
        case .reviewRequested: 2
        case .behind: 3
        case .readyToMerge: 4
        case .building, .draft: 5
        case .waitingReview: 6
        case .todo: 7
        case .blocked: 9
        }
        if item.stale { rank -= 1.5 }
        if item.situation == .todo, item.unblocks > 0 { rank -= 0.5 }
        return rank
    }

    /// Rank, then Linear's priority (urgent first, none last), then the nearest due date.
    private static func before(_ a: Item, _ b: Item) -> Bool {
        let (ra, rb) = (rank(a), rank(b))
        if ra != rb { return ra < rb }
        func priority(_ i: Item) -> Int { (i.issue.priority ?? 0) == 0 ? 5 : i.issue.priority! }
        if priority(a) != priority(b) { return priority(a) < priority(b) }
        let (da, db) = (a.issue.dueDate ?? "9999", b.issue.dueDate ?? "9999")
        if da != db { return da < db }
        return a.issue.updatedAt > b.issue.updatedAt
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// The verdict of a pull request from each reviewer's latest opinion: one request for
    /// changes outweighs any approval.
    static func review(verdicts: [String]?) -> Review {
        let verdicts = verdicts ?? []
        if verdicts.contains("CHANGES_REQUESTED") { return .changesRequested }
        return verdicts.contains("APPROVED") ? .approved : .pending
    }
}
