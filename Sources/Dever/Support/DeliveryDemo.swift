import Foundation

/// Development aid: `DEVER_SNAPSHOT_DELIVERY=<scene>` fills the project page's Delivery panel
/// with a made-up project instead of the linked one, so every situation can be captured
/// whatever the real project holds. Scenes: `busy` (one issue in each situation), `grab`
/// (nothing of the viewer's left, one unassigned issue to take), `done` (everything merged),
/// `agent` (the viewer's issue in progress with no pull request yet: "Continue with" an agent).
extension DeliveryPlan {
    /// The made-up team of the demo's issues: the usual states, so Start and Move have somewhere to go.
    static var demoTeam: LinearTeamContext {
        func state(_ name: String, _ type: String, _ position: Double) -> LinearTeamContext.WorkflowState {
            .init(id: "demo-\(name)", name: name, type: type, color: "#888888", position: position)
        }
        return LinearTeamContext(states: [state("Backlog", "backlog", 0), state("Todo", "unstarted", 1), state("In Progress", "started", 2),
                                          state("In Review", "started", 3), state("Done", "completed", 4)], members: [])
    }

    /// The made-up issues of Canary's project, for the screens that list issues by project (the agents' board).
    static var canaryIssues: [LinearIssue] {
        guard let plan = snapshotDemo() else { return [] }
        return ([plan.start].compactMap { $0 } + plan.agents + plan.next + plan.others).map(\.issue) + plan.shipped.map(\.issue)
    }

    /// `agents` says, from the made-up issues, what their agents ask (made-up sessions and proposals).
    static func snapshotDemo(agents: ([LinearIssue]) -> [String: AgentAttention] = { _ in [:] }) -> DeliveryPlan? {
        guard let scene = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_DELIVERY"] else { return nil }
        return demo(scene, agents: agents)
    }

    private static func demo(_ scene: String, agents: ([LinearIssue]) -> [String: AgentAttention]) -> DeliveryPlan {
        let now = Date()
        let iso = ISO8601DateFormatter()
        let me = LinearIssue.Person(id: "me", name: "Sam Rivera", avatarUrl: nil)
        let ana = LinearIssue.Person(id: "ana", name: "Ana Costa", avatarUrl: nil)
        let leo = LinearIssue.Person(id: "leo", name: "Leo Brandt", avatarUrl: nil)
        func day(_ offset: Int) -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: now.addingTimeInterval(Double(offset) * 86_400))
        }
        func issue(_ n: Int, _ title: String, _ state: String, _ type: String, _ who: LinearIssue.Person?,
                   priority: Int = 3, due: Int? = nil, idle: Double = 1) -> LinearIssue {
            LinearIssue(id: "demo-\(n)", identifier: "APP-\(n)", title: title, url: "https://linear.app/demo/issue/APP-\(n)",
                        updatedAt: iso.string(from: now.addingTimeInterval(-idle * 86_400)),
                        state: .init(id: nil, name: state, type: type, color: nil), assignee: who,
                        branchName: "sam/app-\(n)", attachments: nil, priority: priority, dueDate: due.map(day),
                        labels: nil, archivedAt: nil, team: .init(id: "demo-team"))
        }
        func pull(_ n: Int, _ title: String, by author: String = "sam", idle: Double = 0.2, draft: Bool = false,
                  pipeline: ProjectSnapshot.PipelineState? = .passing, review: Review = .pending, asks: [String] = []) -> Pull {
            Pull(number: n, title: title, url: "https://github.com/demo/app/pull/\(n)", repository: "demo/app", draft: draft,
                 author: author, updatedAt: now.addingTimeInterval(-idle * 86_400), pipeline: pipeline,
                 runURL: "https://github.com/demo/app/actions", review: review, requested: asks)
        }
        func landed(_ n: Int, _ id: Int, daysAgo: Double) -> MergedPull {
            MergedPull(number: n, title: "Merged work", url: "https://github.com/demo/app/pull/\(n)", issue: "APP-\(id)",
                       mergedAt: now.addingTimeInterval(-daysAgo * 86_400))
        }
        var issues: [LinearIssue] = []
        var open: [String: [Pull]] = [:]
        var merged: [String: [MergedPull]] = [:]
        var blockers: [String: [String]] = [:]
        // Shipped: done, and merged while the ticket waits for QA.
        let shippedTitles = ["Sign-in with a magic link", "Empty state for the inbox", "Export a report as CSV",
                             "Keyboard shortcuts sheet", "Rate limit on the public API", "Dark theme for charts",
                             "Invite a teammate by email", "Audit log retention"]
        for (i, title) in shippedTitles.enumerated() {
            let qa = i < (scene == "done" ? 5 : 3)
            issues.append(issue(200 + i, title, qa ? "In Review" : "Done", qa ? "started" : "completed", i % 2 == 0 ? me : ana))
            merged["APP-\(200 + i)"] = [landed(900 + i, 200 + i, daysAgo: Double(i) + 0.4)]
        }
        if scene == "done" {
            return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: blockers,
                                viewer: .init(linearID: "me", linearName: me.name, githubLogin: "sam"), now: now)
        }
        if scene == "grab" {
            issues.append(issue(310, "Search results keep their scroll position", "In Review", "started", me))
            open["APP-310"] = [pull(941, "Keep scroll position", idle: 0.2)]
            issues.append(issue(311, "Bulk archive from the list", "Todo", "unstarted", nil, priority: 2, due: 4))
            issues.append(issue(312, "Webhook retries with backoff", "In Progress", "started", ana, idle: 2))
            return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: blockers,
                                viewer: .init(linearID: "me", linearName: me.name, githubLogin: "sam"), now: now)
        }
        if scene == "canary" {
            // Dever Canary: an agent waiting for an answer, one that finished with a pull request,
            // one at work on the issue to pick up, and the rest of a project around them.
            issues.append(issue(306, "Offline banner and retry", "In Progress", "started", me, priority: 2))
            issues.append(issue(311, "Export a report as CSV", "In Progress", "started", me))
            open["APP-311"] = [pull(961, "Export a report as CSV", idle: 0.05)]
            issues.append(issue(301, "Search indexes drafts, filtered by permission", "In Progress", "started", me, priority: 2))
            issues.append(issue(308, "Two-factor recovery codes", "Todo", "unstarted", me, priority: 2, due: 3))
            issues.append(issue(309, "Session timeout setting", "Todo", "unstarted", me, priority: 3))
            blockers["APP-309"] = ["APP-308"]
            issues.append(issue(303, "Notification digest, once a day", "In Review", "started", ana))
            open["APP-303"] = [pull(953, "Daily digest", by: "ana", asks: ["sam"])]
            issues.append(issue(320, "Billing page shows the next invoice", "In Progress", "started", leo, priority: 2))
            open["APP-320"] = [pull(960, "Next invoice", by: "leo", pipeline: .failing)]
            return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: blockers,
                                viewer: .init(linearID: "me", linearName: me.name, githubLogin: "sam"), agents: agents(issues), now: now)
        }
        if scene == "agent" {
            issues.append(issue(306, "Offline banner and retry", "In Progress", "started", me, priority: 2))
            issues.append(issue(308, "Two-factor recovery codes", "Todo", "unstarted", me, priority: 2, due: 3))
            issues.append(issue(321, "Changelog feed in the help menu", "In Progress", "started", ana, idle: 2))
            return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: blockers,
                                viewer: .init(linearID: "me", linearName: me.name, githubLogin: "sam"), agents: agents(issues), now: now)
        }
        issues.append(issue(301, "Search indexes drafts, filtered by permission", "In Progress", "started", me, priority: 2))
        open["APP-301"] = [pull(951, "Index drafts", pipeline: .failing)]
        issues.append(issue(302, "Onboarding checklist with progress", "In Review", "started", me))
        open["APP-302"] = [pull(952, "Onboarding checklist", review: .changesRequested)]
        issues.append(issue(303, "Notification digest, once a day", "In Review", "started", ana))
        open["APP-303"] = [pull(953, "Daily digest", by: "ana", asks: ["sam"])]
        issues.append(issue(304, "Avatar upload with cropping", "In Progress", "started", me))
        merged["APP-304"] = [landed(954, 304, daysAgo: 1)]
        issues.append(issue(305, "Saved filters on the board", "In Review", "started", me))
        open["APP-305"] = [pull(955, "Saved filters", review: .approved)]
        issues.append(issue(306, "Offline banner and retry", "In Progress", "started", me, idle: 9))
        issues.append(issue(307, "Comment mentions with autocomplete", "In Review", "started", me))
        open["APP-307"] = [pull(957, "Mentions", idle: 4)]
        issues.append(issue(308, "Two-factor recovery codes", "Todo", "unstarted", me, priority: 2, due: 3))
        issues.append(issue(309, "Session timeout setting", "Todo", "unstarted", me, priority: 3))
        blockers["APP-309"] = ["APP-308"]
        issues.append(issue(320, "Billing page shows the next invoice", "In Progress", "started", leo, priority: 2))
        open["APP-320"] = [pull(960, "Next invoice", by: "leo", pipeline: .failing)]
        issues.append(issue(321, "Changelog feed in the help menu", "In Progress", "started", ana, idle: 2))
        issues.append(issue(322, "Bulk archive from the list", "Todo", "unstarted", nil, priority: 4))
        return DeliveryPlan(issues: issues, open: open, merged: merged, blockers: blockers,
                            viewer: .init(linearID: "me", linearName: me.name, githubLogin: "sam"), now: now)
    }
}
