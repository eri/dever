import Foundation
import SwiftUI

// A project the user marked as done: when Dever proposes it, what marking it does in the tools,
// and what a done project still reads. Pure: the stores and the screens come through here, so
// the Overview row, the project page and the confirmation cannot disagree.
//
// One word everywhere: "Done". "Mark as done", the "Done" list, "Reopen project". A done
// project is kept and readable; "Remove from Dever" forgets it.

/// A Linear project's status (Linear's `ProjectStatus`): its own name in the workspace, and
/// the type that says what it means.
struct LinearProjectStatus: Codable, Hashable {
    var id: String
    var name: String
    /// backlog, planned, started, paused, completed or canceled.
    var type: String

    var isCompleted: Bool { type == "completed" }
}

enum ProjectCompletion {
    // MARK: When Dever proposes

    /// Why Dever proposes to mark a project as done. It never does it by itself.
    enum Reason: Equatable {
        /// Every issue of the project has shipped, by the delivery rules (`DeliveryPlan`).
        case shipped(issues: Int)
        /// Its Linear project is Completed.
        case linearCompleted

        var line: String {
            switch self {
            case .shipped(let n): n == 1 ? "Its one issue has shipped" : "All \(n) issues have shipped"
            case .linearCompleted: "Completed in Linear"
            }
        }
    }

    /// Every issue has shipped, as the Delivery panel counts it: the plan's own rules, not a
    /// second reading of the states. A project with no issue has shipped nothing.
    static func everyIssueShipped(_ plan: DeliveryPlan) -> Bool {
        plan.total > 0 && plan.left == 0
    }

    /// The same answer where only the issues and which of them have an open or a merged pull
    /// request are known (the Overview's row): a plan is built from them, so the rules stay
    /// `DeliveryPlan`'s.
    static func everyIssueShipped(issues: [LinearIssue], openPR: Set<String>, mergedPR: Set<String>) -> Bool {
        everyIssueShipped(plan(issues: issues, openPR: openPR, mergedPR: mergedPR))
    }

    static func plan(issues: [LinearIssue], openPR: Set<String>, mergedPR: Set<String>) -> DeliveryPlan {
        var open: [String: [DeliveryPlan.Pull]] = [:]
        for id in openPR { open[id] = [.init(number: 0, title: "", url: "", repository: "", author: "")] }
        var merged: [String: [MergedPull]] = [:]
        for id in mergedPR { merged[id] = [MergedPull(number: 0, title: nil, url: "", issue: id, mergedAt: nil)] }
        return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: [:], viewer: .init())
    }

    /// Whether the project is one Dever would propose to mark as done, whatever the user said
    /// of the proposal: it has a Linear project, and that project is Completed or every issue
    /// has shipped. A project without Linear is marked by hand only.
    static func qualifies(_ project: Project, everyIssueShipped: Bool, issues: Int, linearStatus: LinearProjectStatus?) -> Reason? {
        guard !project.isDone, project.linear != nil else { return nil }
        if linearStatus?.isCompleted == true { return .linearCompleted }
        if everyIssueShipped, issues > 0 { return .shipped(issues: issues) }
        return nil
    }

    /// What Dever proposes: `qualifies`, unless the user answered "Not yet" (or reopened the
    /// project) while it qualified. The answer is forgotten once the project stops qualifying
    /// (`forgetsDecline`), so the next time everything has shipped it is proposed again.
    static func proposal(_ project: Project, everyIssueShipped: Bool, issues: Int, linearStatus: LinearProjectStatus?) -> Reason? {
        guard project.doneProposalDeclined != true else { return nil }
        return qualifies(project, everyIssueShipped: everyIssueShipped, issues: issues, linearStatus: linearStatus)
    }

    /// The user's "Not yet" has served: the project no longer qualifies.
    static func forgetsDecline(_ project: Project, everyIssueShipped: Bool, issues: Int, linearStatus: LinearProjectStatus?) -> Bool {
        project.doneProposalDeclined == true && !project.isDone
            && qualifies(project, everyIssueShipped: everyIssueShipped, issues: issues, linearStatus: linearStatus) == nil
    }

    // MARK: What marking it does in the tools

    /// One thing Dever does in a tool when the project is marked as done. Each is a line of
    /// the confirmation, ticked by default, that the user can untick.
    struct Step: Identifiable, Equatable {
        enum Kind: String, CaseIterable { case linear, preview }
        var kind: Kind
        var title: String
        var detail: String
        var id: String { kind.rawValue }
    }

    /// A preview environment that still runs, or is on its way to: live, deploying, updating.
    /// A failed deploy may have left hosts up, so it counts too.
    static func previewRuns(_ phase: PreviewStatus.Phase?) -> Bool {
        switch phase {
        case .live, .deploying, .updating, .failed: true
        case .notDeployed, .deleting, .deleted, nil: false
        }
    }

    /// The lines of the confirmation. Nothing in Slack (the channel is not archived) and
    /// nothing on GitHub beyond the preview's delete command.
    /// - Parameters:
    ///   - linearStatus: the Linear project's status as last read; nil when it is not known,
    ///     in which case the move is offered (Linear ignores a move to the same status).
    ///   - preview: the project's preview as `PreviewStore` holds it.
    static func steps(_ project: Project, linearStatus: LinearProjectStatus?, linearConnected: Bool,
                      preview: PreviewStatus?, githubConnected: Bool) -> [Step] {
        var out: [Step] = []
        if project.linear != nil, linearConnected, linearStatus?.isCompleted != true {
            out.append(.init(kind: .linear, title: "Move the Linear project to Completed",
                             detail: linearStatus.map { "Now \($0.name)" } ?? "In Linear"))
        }
        if let number = project.previewPullNumber, githubConnected, previewRuns(preview?.phase) {
            out.append(.init(kind: .preview, title: "Delete the preview of #\(number)",
                             detail: "Posts /delete-preview on the pull request"))
        }
        return out
    }

    // MARK: What a done project still reads

    /// The projects a refresh cycle reads, and the ones it only watches for a mention.
    /// A done project is in neither the cycle nor the alerts; with a Slack channel it is
    /// watched, slowly, for a message that names the user.
    static func cycle(_ projects: [Project]) -> (read: [Project], watched: [Project]) {
        (projects.filter { !$0.isDone }, projects.filter { $0.isDone && $0.slack != nil })
    }

    /// How far apart two looks at the done projects' channels are: ten minutes, half an hour
    /// in Low Power Mode. One `conversations.history` per done project each time, from the
    /// newest message already seen: an answer with nothing new is about 0.2 kB.
    static func watchInterval(lowPower: Bool) -> TimeInterval { lowPower ? 1800 : 600 }

    static func isWatchDue(last: Date?, lowPower: Bool, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= watchInterval(lowPower: lowPower)
    }

    /// Where the watch of a project starts: the newest message it has seen, else the moment
    /// the project was marked as done. What was said before that was said to an open project.
    static func watchCursor(_ project: Project, seen: String?) -> String? {
        if let seen { return seen }
        return project.doneAt.map { String(format: "%.6f", $0.timeIntervalSince1970) }
    }

    /// The messages that name the user among those that arrived: written by someone else,
    /// by a person (not a join, a rename, a bot), after `cursor`. Newest first.
    static func mentions(in messages: [SlackMessage], me: String, after cursor: String?, bots: Set<String> = []) -> [SlackMessage] {
        messages.filter { m in
            guard let user = m.user, user != me, !bots.contains(user) else { return false }
            guard [nil, "thread_broadcast", "file_share"].contains(m.subtype) else { return false }
            if let cursor, SlackTS.isAtOrBefore(m.ts, cursor) { return false }
            return (m.text ?? "").contains("<@\(me)>")
        }
        .sorted { (Double($0.ts) ?? 0) > (Double($1.ts) ?? 0) }
    }

    /// The mentions still unread once Slack's own read cursor is known: reading the message in
    /// Slack, or in Dever, clears it here too.
    static func unread<M>(_ mentions: [M], ts: (M) -> String, lastRead: String?) -> [M] {
        guard let lastRead else { return mentions }
        return mentions.filter { !SlackTS.isAtOrBefore(ts($0), lastRead) }
    }

    // MARK: Words

    /// "Done 12 Nov", with the year once it is not this one.
    static func doneLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let format: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
        return "Done \(date.formatted(format))"
    }

    /// What a coding agent is told of an issue whose project is done.
    static func agentNote(_ project: Project) -> String? {
        guard let at = project.doneAt else { return nil }
        let day = at.formatted(.iso8601.year().month().day())
        return "Note: the project \u{201C}\(project.name)\u{201D} was marked as done in Dever on \(day). Dever no longer refreshes it: what follows is as it was last read."
    }
}
