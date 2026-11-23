import XCTest
@testable import Dever

/// A project marked as done: when Dever proposes it, what the confirmation offers, what a done
/// project still reads, the mention exception, and reopening.
final class ProjectCompletionTests: XCTestCase {
    private func issue(_ n: Int, type: String, state: String? = nil) -> LinearIssue {
        LinearIssue(id: "i\(n)", identifier: "APP-\(n)", title: "Issue \(n)", url: "https://linear.app/demo/issue/APP-\(n)",
                    updatedAt: "2026-11-01T10:00:00.000Z",
                    state: .init(id: nil, name: state ?? (type == "completed" ? "Done" : type == "started" ? "In Progress" : "Todo"), type: type, color: nil),
                    assignee: nil, branchName: "sam/app-\(n)", attachments: nil, priority: nil, dueDate: nil, labels: nil, archivedAt: nil)
    }

    private func project(linear: Bool = true, slack: Bool = true) -> Project {
        Project(name: "Checkout", slack: slack ? .init(id: "C1", name: "proj-checkout") : nil,
                linear: linear ? .init(id: "L1", name: "Checkout", url: "https://linear.app/demo/project/checkout") : nil)
    }

    private let started = LinearProjectStatus(id: "s1", name: "In Progress", type: "started")
    private let completed = LinearProjectStatus(id: "s2", name: "Completed", type: "completed")

    // MARK: When Dever proposes

    func testEveryIssueShippedFollowsTheDeliveryPlan() {
        // Done, canceled (left out), and merged while the ticket waits in review: all shipped.
        let issues = [issue(1, type: "completed"), issue(2, type: "canceled"), issue(3, type: "started", state: "In Review")]
        XCTAssertTrue(ProjectCompletion.everyIssueShipped(issues: issues, openPR: [], mergedPR: ["APP-3"]))
        // The same answer as the plan the project page builds.
        let plan = ProjectCompletion.plan(issues: issues, openPR: [], mergedPR: ["APP-3"])
        XCTAssertEqual(plan.left, 0)
        XCTAssertEqual(plan.shipped.count, 2)
    }

    func testAnOpenIssueOrPullRequestIsNotShipped() {
        XCTAssertFalse(ProjectCompletion.everyIssueShipped(issues: [issue(1, type: "completed"), issue(2, type: "started")], openPR: [], mergedPR: []))
        // Merged once, but a pull request is open again on the ticket in review: not shipped.
        let review = [issue(1, type: "started", state: "In Review")]
        XCTAssertFalse(ProjectCompletion.everyIssueShipped(issues: review, openPR: ["APP-1"], mergedPR: ["APP-1"]))
        // Merged while the ticket still says in progress: the ticket is behind, not shipped.
        XCTAssertFalse(ProjectCompletion.everyIssueShipped(issues: [issue(1, type: "started")], openPR: [], mergedPR: ["APP-1"]))
    }

    func testAProjectWithNoIssueHasShippedNothing() {
        XCTAssertFalse(ProjectCompletion.everyIssueShipped(issues: [], openPR: [], mergedPR: []))
        XCTAssertFalse(ProjectCompletion.everyIssueShipped(issues: [issue(1, type: "canceled")], openPR: [], mergedPR: []))
    }

    func testProposesWhenEverythingShippedOrLinearSaysCompleted() {
        let p = project()
        XCTAssertEqual(ProjectCompletion.proposal(p, everyIssueShipped: true, issues: 8, linearStatus: started), .shipped(issues: 8))
        XCTAssertEqual(ProjectCompletion.proposal(p, everyIssueShipped: false, issues: 8, linearStatus: completed), .linearCompleted)
        XCTAssertNil(ProjectCompletion.proposal(p, everyIssueShipped: false, issues: 8, linearStatus: started))
        XCTAssertNil(ProjectCompletion.proposal(p, everyIssueShipped: false, issues: 8, linearStatus: nil))
    }

    func testNeverProposesWithoutLinearNorForADoneProject() {
        // No Linear project: by hand only.
        XCTAssertNil(ProjectCompletion.proposal(project(linear: false), everyIssueShipped: true, issues: 3, linearStatus: nil))
        var done = project()
        done.doneAt = Date()
        XCTAssertNil(ProjectCompletion.proposal(done, everyIssueShipped: true, issues: 3, linearStatus: completed))
    }

    func testNotYetSilencesTheProposalUntilTheProjectStopsQualifying() {
        var p = project()
        p.doneProposalDeclined = true
        XCTAssertNil(ProjectCompletion.proposal(p, everyIssueShipped: true, issues: 4, linearStatus: started))
        // Still qualifying: the answer is kept.
        XCTAssertFalse(ProjectCompletion.forgetsDecline(p, everyIssueShipped: true, issues: 4, linearStatus: started))
        // A new issue arrived: the answer has served, the next time is proposed again.
        XCTAssertTrue(ProjectCompletion.forgetsDecline(p, everyIssueShipped: false, issues: 5, linearStatus: started))
    }

    // MARK: The confirmation's lines

    private func preview(_ phase: PreviewStatus.Phase) -> PreviewStatus {
        PreviewStatus(phase: phase, pull: .init(number: 12, title: "Preview", url: URL(string: "https://github.com/demo/app/pull/12")!,
                                               author: "sam", state: .open, headRef: "feat/x", headSHA: "abc", baseRef: "main"))
    }

    func testStepsOfferLinearUnlessAlreadyCompleted() {
        let p = project()
        XCTAssertEqual(ProjectCompletion.steps(p, linearStatus: started, linearConnected: true, preview: nil, githubConnected: true).map(\.kind), [.linear])
        XCTAssertTrue(ProjectCompletion.steps(p, linearStatus: completed, linearConnected: true, preview: nil, githubConnected: true).isEmpty)
        // Not known: offered. Not connected, or no Linear project: nothing to move.
        XCTAssertEqual(ProjectCompletion.steps(p, linearStatus: nil, linearConnected: true, preview: nil, githubConnected: true).map(\.kind), [.linear])
        XCTAssertTrue(ProjectCompletion.steps(p, linearStatus: started, linearConnected: false, preview: nil, githubConnected: true).isEmpty)
        XCTAssertTrue(ProjectCompletion.steps(project(linear: false), linearStatus: nil, linearConnected: true, preview: nil, githubConnected: true).isEmpty)
    }

    func testStepsOfferThePreviewOnlyWhileItRuns() {
        var p = project()
        p.previewPullNumber = 12
        func kinds(_ phase: PreviewStatus.Phase) -> [ProjectCompletion.Step.Kind] {
            ProjectCompletion.steps(p, linearStatus: completed, linearConnected: true, preview: preview(phase), githubConnected: true).map(\.kind)
        }
        XCTAssertEqual(kinds(.live), [.preview])
        XCTAssertEqual(kinds(.deploying), [.preview])
        XCTAssertEqual(kinds(.failed), [.preview])
        XCTAssertTrue(kinds(.deleted).isEmpty)
        XCTAssertTrue(kinds(.notDeployed).isEmpty)
        XCTAssertTrue(kinds(.deleting).isEmpty)
        XCTAssertTrue(ProjectCompletion.steps(p, linearStatus: completed, linearConnected: true, preview: preview(.live), githubConnected: false).isEmpty)
    }

    // MARK: What a done project still reads

    func testADoneProjectLeavesTheCycleAndIsOnlyWatchedWithAChannel() {
        let active = project()
        var done = project(); done.doneAt = Date()
        var silent = project(slack: false); silent.doneAt = Date()
        let cycle = ProjectCompletion.cycle([active, done, silent])
        XCTAssertEqual(cycle.read.map(\.id), [active.id])
        XCTAssertEqual(cycle.watched.map(\.id), [done.id])
    }

    func testADoneProjectIsNotReadAgainByTheOverviewButAReopenedOneIs() {
        let before = project()
        var done = before; done.doneAt = Date()
        // Marked as done: nothing to read.
        XCTAssertTrue(OverviewStore.relinked(from: [before], to: [done]).isEmpty)
        // A done project whose links change is still not read.
        var relinked = done; relinked.slack = .init(id: "C9", name: "other")
        XCTAssertTrue(OverviewStore.relinked(from: [done], to: [relinked]).isEmpty)
        // Reopened: read at once, alone.
        XCTAssertEqual(OverviewStore.relinked(from: [done], to: [before]), [before.id])
    }

    func testTheWatchIsSlowAndSlowerOnLowPower() {
        let now = Date()
        XCTAssertTrue(ProjectCompletion.isWatchDue(last: nil, lowPower: false, now: now))
        XCTAssertFalse(ProjectCompletion.isWatchDue(last: now.addingTimeInterval(-300), lowPower: false, now: now))
        XCTAssertTrue(ProjectCompletion.isWatchDue(last: now.addingTimeInterval(-601), lowPower: false, now: now))
        XCTAssertFalse(ProjectCompletion.isWatchDue(last: now.addingTimeInterval(-601), lowPower: true, now: now))
    }

    // MARK: The mention exception

    func testTheWatchStartsWhenTheProjectWasMarkedDone() {
        var p = project()
        p.doneAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ProjectCompletion.watchCursor(p, seen: nil), "1700000000.000000")
        XCTAssertEqual(ProjectCompletion.watchCursor(p, seen: "1700000500.000100"), "1700000500.000100")
        XCTAssertNil(ProjectCompletion.watchCursor(project(), seen: nil))
    }

    func testOnlyAMessageFromSomeoneElseThatNamesYouCounts() {
        let messages = [
            SlackMessage(ts: "100.000001", user: "U2", text: "hello <@U1> can you look?"),
            SlackMessage(ts: "101.000001", user: "U2", text: "nothing for anyone"),
            SlackMessage(ts: "102.000001", user: "U1", text: "note to self <@U1>"),
            SlackMessage(ts: "103.000001", user: "U3", text: "<@U1> joined", subtype: "channel_join"),
            SlackMessage(ts: "104.000001", user: "B1", text: "deploy done <@U1>"),
            SlackMessage(ts: "90.000001", user: "U2", text: "before it was done <@U1>"),
            SlackMessage(ts: "105.000001", user: "U4", text: "and <@U1> again"),
        ]
        let found = ProjectCompletion.mentions(in: messages, me: "U1", after: "95.000000", bots: ["B1"])
        XCTAssertEqual(found.map(\.ts), ["105.000001", "100.000001"])
    }

    func testAMentionReadInSlackIsNoLongerWaiting() {
        let held = ["100.000001", "105.000001"]
        XCTAssertEqual(ProjectCompletion.unread(held, ts: { $0 }, lastRead: "100.000001"), ["105.000001"])
        XCTAssertEqual(ProjectCompletion.unread(held, ts: { $0 }, lastRead: nil), held)
        XCTAssertTrue(ProjectCompletion.unread(held, ts: { $0 }, lastRead: "200.000000").isEmpty)
    }

    // MARK: The model, marking and reopening

    func testProjectsSavedBeforeDoneStillLoad() throws {
        let old = #"[{"id":"00000000-0000-0000-0000-000000000001","name":"Checkout","githubRepos":[],"createdAt":0}]"#
        let list = try JSONDecoder().decode([Project].self, from: Data(old.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertNil(list[0].doneAt)
        XCTAssertFalse(list[0].isDone)
    }

    func testTheDoneDateAndThePreviousLinearStatusSurviveSaving() throws {
        var p = project()
        p.doneAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        p.linearStatusBeforeDone = started
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.doneAt, p.doneAt)
        XCTAssertEqual(back.linearStatusBeforeDone, started)
        XCTAssertTrue(back.isDone)
    }

    func testMarkingDoneAndReopeningPutsTheProjectBackAsItWas() {
        var p = project()
        p.favorite = true
        let other = Project(name: "Billing")
        let at = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var marked = p
        marked.markDone(at: at, previousLinearStatus: started)
        XCTAssertEqual([marked, other].active.map(\.id), [other.id])
        XCTAssertEqual([marked, other].done.map(\.id), [p.id])
        XCTAssertEqual(marked.doneAt, at)
        XCTAssertEqual(marked.linearStatusBeforeDone, started)
        // The links are kept: it is archived, not forgotten.
        XCTAssertEqual(marked.slack, p.slack)
        XCTAssertEqual(marked.linear, p.linear)
        var back = marked
        back.reopen()
        XCTAssertEqual([back, other].active.count, 2)
        XCTAssertNil(back.doneAt)
        XCTAssertNil(back.linearStatusBeforeDone)
        XCTAssertEqual(back.slack, p.slack)
        // Reopened while Linear may still say Completed: not proposed again at once.
        XCTAssertEqual(back.doneProposalDeclined, true)
        XCTAssertNil(ProjectCompletion.proposal(back, everyIssueShipped: true, issues: 3, linearStatus: completed))
    }

    func testTheDoneListIsLatestFirst() {
        var a = project(), b = project()
        a.doneAt = Date(timeIntervalSinceReferenceDate: 100)
        b.doneAt = Date(timeIntervalSinceReferenceDate: 200)
        XCTAssertEqual([a, b].done.map(\.id), [b.id, a.id])
    }

    // MARK: Elsewhere

    func testALeftoverWorktreeOfADoneProjectCanGoUnlessWorkIsLeftInIt() {
        let clean = AgentWorktreeEntry(path: URL(fileURLWithPath: "/tmp/w/a"), clone: URL(fileURLWithPath: "/tmp/c"),
                                       repository: "demo/app", branch: "sam/app-1", dirty: false)
        XCTAssertEqual(clean.standing(sessions: [], mergedBranches: [], doneBranches: ["sam/app-1"]), .leftover)
        XCTAssertEqual(clean.standing(sessions: [], mergedBranches: [], doneBranches: []), .notMerged)
        XCTAssertEqual(clean.standing(sessions: [], mergedBranches: ["sam/app-1"], doneBranches: ["sam/app-1"]), .removable)
        var dirty = clean; dirty.dirty = true
        XCTAssertEqual(dirty.standing(sessions: [], mergedBranches: [], doneBranches: ["sam/app-1"]), .uncommitted)
    }

    func testAnAgentIsToldTheProjectIsDone() {
        XCTAssertNil(ProjectCompletion.agentNote(project()))
        var p = project()
        p.doneAt = Date(timeIntervalSince1970: 1_700_000_000)
        let note = ProjectCompletion.agentNote(p)
        XCTAssertEqual(note?.contains("marked as done in Dever on 2023-11-14"), true)
    }

    func testTheDoneLabelSaysTheYearOnlyWhenItIsNotThisOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 11, day: 12))!
        XCTAssertFalse(ProjectCompletion.doneLabel(thisYear, now: now, calendar: calendar).contains("2026"))
        XCTAssertTrue(ProjectCompletion.doneLabel(lastYear, now: now, calendar: calendar).contains("2025"))
    }
}
