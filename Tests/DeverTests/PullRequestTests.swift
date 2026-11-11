import XCTest
@testable import Dever

final class PullRequestTests: XCTestCase {
    private struct Issue: IssueReference {
        var identifier: String
        var branchName: String?
        var attachments: Attachments?
    }

    private func pull(_ n: Int, title: String = "A change", ref: String = "some-branch", checks: String? = nil,
                      verdicts: [String]? = nil) -> GitHubPull {
        GitHubPull(id: n, number: n, title: title, html_url: "https://github.com/acme/app/pull/\(n)", draft: false,
                   user: .init(login: "ada"), updated_at: "2026-01-01T00:00:00Z", head: .init(ref: ref), merged_at: nil,
                   checks: checks, verdicts: verdicts)
    }

    func testChecksRollupMapsToPipelineState() {
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: "SUCCESS"), .passing)
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: "FAILURE"), .failing)
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: "ERROR"), .failing)
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: "PENDING"), .running)
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: "EXPECTED"), .running)
        XCTAssertEqual(ProjectSnapshot.PipelineState(checks: nil), .unknown)
    }

    func testProjectPipelineIsTheWorstOfItsPullRequests() {
        let issues = [Issue(identifier: "ENG-1"), Issue(identifier: "ENG-2"), Issue(identifier: "ENG-3")]
        let pulls = [pull(1, ref: "eng-1-a", checks: "SUCCESS"), pull(2, ref: "eng-2-b", checks: "PENDING"),
                     pull(3, ref: "other", checks: "FAILURE")]
        let scoped = ProjectPullRequests(pulls: pulls, issues: issues, wholeRepository: false)
        // #3 belongs to another project: its failure is not this project's.
        XCTAssertEqual(scoped.matches.map(\.pull.number), [1, 2])
        XCTAssertEqual(scoped.pipeline, .running)
        let whole = ProjectPullRequests(pulls: pulls, issues: issues, wholeRepository: true)
        XCTAssertEqual(whole.pipeline, .failing)
        XCTAssertEqual(ProjectPullRequests(pulls: [], issues: issues, wholeRepository: false).pipeline, .unknown)
    }

    func testMatchingByAttachmentBranchAndIdentifier() {
        let issues = [
            Issue(identifier: "ENG-1", attachments: .init(nodes: [.init(url: "https://github.com/acme/app/pull/10/")])),
            Issue(identifier: "ENG-2", branchName: "ada/eng-2-fix"),
            Issue(identifier: "ENG-3"),
        ]
        let pulls = [pull(10), pull(11, ref: "ada/eng-2-fix"), pull(12, title: "Fix the thing [ENG-3]"), pull(13)]
        let prs = ProjectPullRequests(pulls: pulls, issues: issues, wholeRepository: false)
        XCTAssertEqual(prs.matches.map(\.issue), ["ENG-1", "ENG-2", "ENG-3"])
        XCTAssertTrue(prs.scoped)
        // Without issues to match, every pull request is kept, unmatched.
        let all = ProjectPullRequests(pulls: pulls, issues: nil, wholeRepository: false)
        XCTAssertEqual(all.matches.count, 4)
        XCTAssertFalse(all.scoped)
    }

    func testReviewVerdicts() {
        XCTAssertEqual(DeliveryPlan.review(verdicts: nil), .pending)
        XCTAssertEqual(DeliveryPlan.review(verdicts: []), .pending)
        XCTAssertEqual(DeliveryPlan.review(verdicts: ["APPROVED"]), .approved)
        XCTAssertEqual(DeliveryPlan.review(verdicts: ["APPROVED", "CHANGES_REQUESTED"]), .changesRequested)
    }

    func testChecksURL() {
        XCTAssertEqual(pull(7).checksURL, "https://github.com/acme/app/pull/7/checks")
        XCTAssertEqual(pull(7).repository, "acme/app")
    }
}

final class ProjectPullsTests: XCTestCase {
    private struct Ref: IssueReference {
        var identifier: String
        var branchName: String?
        var attachments: Attachments?
    }

    func testAProjectThatFollowsItsIssuesWaitsForThem() {
        // Linear not connected, failing, or not linked on the shared repository: no issues.
        XCTAssertTrue(ProjectPulls.waitsForIssues(nil, wholeRepository: false))
        // A project that takes every pull request of its repositories needs no issues.
        XCTAssertFalse(ProjectPulls.waitsForIssues(nil, wholeRepository: true))
        XCTAssertFalse(ProjectPulls.waitsForIssues([Ref(identifier: "ENG-1")], wholeRepository: false))
        XCTAssertFalse(ProjectPulls.waitsForIssues([Ref](), wholeRepository: false))
    }

    private struct Issue: IssueReference {
        var identifier: String
        var branchName: String?
        var attachments: Attachments?
    }

    private func pull(_ n: Int, repo: String, ref: String, merged: String? = nil) -> GitHubPull {
        GitHubPull(id: n, number: n, title: "Change \(n)", html_url: "https://github.com/\(repo)/pull/\(n)", draft: false,
                   user: .init(login: "ada"), updated_at: "2026-01-01T00:00:00Z", head: .init(ref: ref), merged_at: merged)
    }

    private func repository(_ name: String, open: [GitHubPull], merged: [GitHubPull]) -> (name: String, data: GitHubStore.Repository) {
        (name, .init(state: .init(pulls: open), merged: merged))
    }

    func testTwoRepositoriesAddUpAndMergedAreNewestFirst() {
        let issues = [Issue(identifier: "ENG-1"), Issue(identifier: "ENG-2")]
        let a = repository("acme/app", open: [pull(1, repo: "acme/app", ref: "eng-1")],
                           merged: [pull(2, repo: "acme/app", ref: "eng-2", merged: "2026-01-02T00:00:00Z")])
        let b = repository("acme/api", open: [pull(1, repo: "acme/api", ref: "eng-2"), pull(9, repo: "acme/api", ref: "unrelated")],
                           merged: [pull(3, repo: "acme/api", ref: "eng-1", merged: "2026-01-05T00:00:00Z")])
        let pulls = ProjectPulls(repositories: [a, b], issues: issues, wholeRepository: false)
        XCTAssertTrue(pulls.scoped)
        XCTAssertEqual(pulls.open.map(\.pull.html_url), ["https://github.com/acme/app/pull/1", "https://github.com/acme/api/pull/1"])
        XCTAssertEqual(pulls.merged.map(\.number), [3, 2])
        XCTAssertEqual(pulls.merged.map(\.repository), ["acme/api", "acme/app"])
    }

    func testWholeRepositoryKeepsUnmatchedPullRequests() {
        let a = repository("acme/app", open: [pull(1, repo: "acme/app", ref: "eng-1"), pull(2, repo: "acme/app", ref: "misc")], merged: [])
        let whole = ProjectPulls(repositories: [a], issues: [Issue(identifier: "ENG-1")], wholeRepository: true)
        XCTAssertFalse(whole.scoped)
        XCTAssertEqual(whole.open.map(\.issue), ["ENG-1", nil])
        let noLinear = ProjectPulls(repositories: [a], issues: nil, wholeRepository: false)
        XCTAssertEqual(noLinear.open.count, 2)
    }

    func testNothingHeldIsEmpty() {
        let none = ProjectPulls(repositories: [], issues: nil, wholeRepository: false)
        XCTAssertTrue(none.open.isEmpty && none.merged.isEmpty && !none.scoped)
    }
}

@MainActor
final class GitHubStoreTests: XCTestCase {
    func testRevisionMovesWhenARepositoryIsDropped() {
        let store = GitHubStore()
        XCTAssertNil(store.repository("acme/app"))
        XCTAssertNil(store.fetchedAt("acme/app"))
        let before = store.revision
        store.reset()                       // nothing held: nothing to announce
        XCTAssertEqual(store.revision, before)
    }
}
