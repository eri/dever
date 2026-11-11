import XCTest
@testable import Dever

final class OverviewRowTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T12:00:00Z")!

    private func issue(_ identifier: String, _ type: String, name: String? = nil) -> LinearIssue {
        LinearIssue(id: "id-" + identifier, identifier: identifier, title: "Issue " + identifier,
                    url: "https://linear.app/acme/issue/" + identifier, updatedAt: "2026-03-01T00:00:00.000Z",
                    state: .init(id: type, name: name ?? type, type: type, color: nil))
    }

    private func pull(_ n: Int, ref: String, checks: String? = nil, updated: String = "2026-03-10T10:00:00Z",
                      merged: String? = nil, draft: Bool = false, reviewers: [String] = [], author: String = "ada") -> GitHubPull {
        GitHubPull(id: n, number: n, title: "Change \(n)", html_url: "https://github.com/acme/app/pull/\(n)", draft: draft,
                   user: .init(login: author), updated_at: updated, head: .init(ref: ref), merged_at: merged,
                   requested_reviewers: reviewers.map { .init(login: $0) }, checks: checks)
    }

    private func repository(open: [GitHubPull], merged: [GitHubPull] = [], branch: String? = "main", branchChecks: String? = nil)
        -> GitHubStore.Repository {
        .init(state: .init(pulls: open, defaultBranch: branch, defaultBranchChecks: branchChecks), merged: merged)
    }

    // MARK: Linear

    func testLinearCountsLeaveCanceledOut() {
        let issues = [issue("ENG-1", "completed"), issue("ENG-2", "started"), issue("ENG-3", "unstarted"),
                      issue("ENG-4", "backlog"), issue("ENG-5", "canceled")]
        let facts = LinearProjectFacts(lead: "Ada", team: "Platform", targetDate: now)
        let stats = ProjectSnapshot.LinearStats(issues: issues, facts: facts)
        XCTAssertEqual([stats.total, stats.done, stats.inProgress, stats.todo], [4, 1, 1, 2])
        XCTAssertEqual(stats.lead, "Ada")
        XCTAssertEqual(stats.team, "Platform")
        XCTAssertEqual(stats.targetDate, now)
        XCTAssertEqual(stats.progress, 0.25)
    }

    func testRecountKeepsTheProjectFacts() {
        var stats = ProjectSnapshot.LinearStats(issues: [issue("ENG-1", "started")], facts: .init(lead: "Ada", team: "Platform"))
        // The issue was moved to done in Delivery: the row follows without a request.
        stats.count([issue("ENG-1", "completed")])
        XCTAssertEqual([stats.total, stats.done, stats.inProgress], [1, 1, 0])
        XCTAssertEqual(stats.lead, "Ada")
    }

    func testMoreThan250IssuesAreAllCounted() {
        let issues = (1...400).map { issue("ENG-\($0)", $0 % 2 == 0 ? "completed" : "started") }
        let stats = ProjectSnapshot.LinearStats(issues: issues, facts: nil)
        XCTAssertEqual(stats.total, 400)
        XCTAssertEqual(stats.done, 200)
    }

    // MARK: GitHub, scoped to the project's issues

    func testScopedRepositoryCountsOnlyTheProjectsPullRequests() {
        let issues = [issue("ENG-1", "started"), issue("ENG-2", "started"), issue("ENG-3", "started", name: "In Review"),
                      issue("ENG-4", "completed")]
        let repo = repository(
            open: [pull(1, ref: "eng-1-a", checks: "SUCCESS"), pull(2, ref: "other-team", checks: "FAILURE")],
            merged: [pull(3, ref: "eng-2-b", merged: "2026-03-09T09:00:00Z", author: "grace"),
                     pull(4, ref: "eng-3-c", merged: "2026-03-08T09:00:00Z"),
                     pull(5, ref: "eng-4-d", merged: "2026-03-01T09:00:00Z"),
                     pull(6, ref: "other-team-2", merged: "2026-03-10T09:00:00Z")],
            branchChecks: "FAILURE")
        let stats = ProjectSnapshot.GitHubStats(repository: repo, issues: issues, wholeRepository: false, login: "ada", now: now)
        XCTAssertTrue(stats.scoped)
        XCTAssertEqual(stats.openPRs, 1)
        // Another project's failing pull request and the default branch do not count here.
        XCTAssertEqual(stats.pipeline, .passing)
        XCTAssertNil(stats.branch)
        XCTAssertEqual(stats.openPRIssues, ["ENG-1"])
        XCTAssertEqual(stats.mergedPRIssues, ["ENG-2", "ENG-3", "ENG-4"])
        // Merged while still "in progress": ENG-2. In review (ENG-3) and done (ENG-4) are fine.
        XCTAssertEqual(stats.mergedButOpen, ["ENG-2"])
        XCTAssertEqual(stats.lastMerged?.number, 3)
        XCTAssertEqual(stats.lastMerged?.author, "grace")
    }

    func testAFailingCheckOnAProjectPullRequestFailsItsPipeline() {
        let issues = [issue("ENG-1", "started"), issue("ENG-2", "started")]
        let repo = repository(open: [pull(1, ref: "eng-1", checks: "SUCCESS"), pull(2, ref: "eng-2", checks: "FAILURE")])
        let stats = ProjectSnapshot.GitHubStats.project(repositories: [("acme/app", repo)], issues: issues,
                                                        wholeRepository: false, login: nil, now: now)
        XCTAssertEqual(stats.pipeline, .failing)
        XCTAssertEqual(stats.repositories, ["acme/app"])
        XCTAssertEqual(stats.failingRepositories, ["acme/app"])
    }

    func testReviewRequestsAndTheLongestWait() {
        let issues = [issue("ENG-1", "started"), issue("ENG-2", "started"), issue("ENG-3", "started")]
        let repo = repository(open: [
            pull(1, ref: "eng-1", updated: "2026-03-10T08:00:00Z", reviewers: ["Ada"]),
            pull(2, ref: "eng-2", updated: "2026-03-01T08:00:00Z", reviewers: ["grace"]),
            pull(3, ref: "eng-3", updated: "2026-02-20T08:00:00Z", draft: true, reviewers: ["grace"]),
        ])
        let stats = ProjectSnapshot.GitHubStats(repository: repo, issues: issues, wholeRepository: false, login: "ada", now: now)
        // The login is matched whatever its case; the request names its issue.
        XCTAssertEqual(stats.reviewRequests.map(\.number), [1])
        XCTAssertEqual(stats.reviewRequests.first?.issue, "ENG-1")
        // Past three days with a reviewer asked: #2. The draft does not wait for anyone.
        XCTAssertEqual(stats.longWait?.number, 2)
        let nobody = ProjectSnapshot.GitHubStats(repository: repo, issues: issues, wholeRepository: false, login: nil, now: now)
        XCTAssertTrue(nobody.reviewRequests.isEmpty)
    }

    // MARK: GitHub, the whole repository

    func testWholeRepositoryReadsTheDefaultBranch() {
        let repo = repository(open: [pull(1, ref: "a", checks: "FAILURE"), pull(2, ref: "b")],
                              merged: [pull(3, ref: "c", merged: "2026-03-09T09:00:00Z")], branch: "main", branchChecks: "SUCCESS")
        let noLinear = ProjectSnapshot.GitHubStats(repository: repo, issues: nil, wholeRepository: false, login: nil, now: now)
        XCTAssertFalse(noLinear.scoped)
        XCTAssertEqual(noLinear.openPRs, 2)
        XCTAssertEqual(noLinear.pipeline, .passing)
        XCTAssertEqual(noLinear.branch, "main")
        XCTAssertTrue(noLinear.mergedButOpen.isEmpty)
        XCTAssertEqual(noLinear.lastMerged?.number, 3)
        let whole = ProjectSnapshot.GitHubStats(repository: repo, issues: [issue("ENG-1", "started")], wholeRepository: true,
                                                login: nil, now: now)
        XCTAssertFalse(whole.scoped)
        XCTAssertEqual(whole.openPRs, 2)
        XCTAssertEqual(whole.pipeline, .passing)
    }

    func testSeveralRepositoriesAddUpAndTheWorstPipelineWins() {
        let issues = [issue("ENG-1", "started"), issue("ENG-2", "started")]
        let app = repository(open: [pull(1, ref: "eng-1", checks: "SUCCESS")])
        let api = repository(open: [pull(1, ref: "eng-2", checks: "FAILURE")])
        let stats = ProjectSnapshot.GitHubStats.project(repositories: [("acme/app", app), ("acme/api", api)], issues: issues,
                                                        wholeRepository: false, login: nil, now: now)
        XCTAssertEqual(stats.openPRs, 2)
        XCTAssertEqual(stats.pipeline, .failing)
        XCTAssertEqual(stats.repositories, ["acme/app", "acme/api"])
        XCTAssertEqual(stats.failingRepositories, ["acme/api"])
        XCTAssertEqual(stats.openPRIssues, ["ENG-1", "ENG-2"])
    }

    // MARK: Delivery

    func testDeliveryJoinsIssuesWithTheirPullRequests() {
        let issues = [issue("ENG-1", "completed"), issue("ENG-2", "started"), issue("ENG-3", "started"),
                      issue("ENG-4", "started"), issue("ENG-5", "unstarted"), issue("ENG-6", "canceled")]
        var github = ProjectSnapshot.GitHubStats()
        github.openPRIssues = ["ENG-3"]
        github.mergedPRIssues = ["ENG-2"]
        let delivery = Delivery(issues: issues, github: github)
        XCTAssertEqual([delivery.done, delivery.merged, delivery.review, delivery.building, delivery.todo], [1, 1, 1, 1, 1])
        XCTAssertEqual(delivery.total, 5)
        XCTAssertEqual(delivery.shipped, 2)
        // Without GitHub, Linear's states alone decide.
        let alone = Delivery(issues: issues, github: nil)
        XCTAssertEqual([alone.done, alone.merged, alone.review, alone.building, alone.todo], [1, 0, 0, 3, 1])
    }

    func testMovingAnIssueToDoneShipsItOnTheRow() {
        var issues = [issue("ENG-1", "started"), issue("ENG-2", "unstarted")]
        XCTAssertEqual(Delivery(issues: issues, github: nil).shipped, 0)
        issues[0].state = .init(id: "done", name: "Done", type: "completed", color: nil)
        let delivery = Delivery(issues: issues, github: nil)
        XCTAssertEqual(delivery.shipped, 1)
        XCTAssertEqual(delivery.total, 2)
    }
}
