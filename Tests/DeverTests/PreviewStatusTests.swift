import XCTest
@testable import Dever

/// A live preview is called live only when every probed host answers.
@MainActor
final class PreviewStatusTests: XCTestCase {
    private func status(_ phase: PreviewStatus.Phase, _ targets: [PreviewTarget: Bool?]) -> PreviewStatus {
        let pull = PreviewStatus.Pull(number: 1, title: "A change", url: URL(string: "https://example.com/pull/1")!,
                                      author: "someone", state: .open, headRef: "some-branch")
        return PreviewStatus(phase: phase, pull: pull, targets: targets)
    }

    func testEveryHostUpIsLive() {
        let s = status(.live, [.app: true, .api: true])
        XCTAssertEqual(s.health, .up)
        XCTAssertEqual(s.word, "Live")
    }

    func testOneHostDownIsPartlyDown() {
        let s = status(.live, [.app: true, .api: true, .bo: false])
        XCTAssertEqual(s.health, .partlyDown)
        XCTAssertEqual(s.word, "Partly down")
    }

    func testEveryHostDownIsDown() {
        let s = status(.live, [.app: false, .api: false])
        XCTAssertEqual(s.health, .down)
        XCTAssertEqual(s.word, "Down")
    }

    func testUnprobedHostsStayLive() {
        let s = status(.live, [.app: nil, .api: nil])
        XCTAssertEqual(s.health, .checking)
        XCTAssertEqual(s.word, "Live")
    }

    func testAProbedHostDownCountsBesideUnprobedOnes() {
        XCTAssertEqual(status(.live, [.app: nil, .bo: false, .api: true]).health, .partlyDown)
    }

    func testOtherPhasesKeepTheirWord() {
        XCTAssertEqual(status(.deploying, [.app: false]).word, "Deploying")
        XCTAssertEqual(status(.failed, [:]).word, "Failed")
    }

    // MARK: Following the pull request

    private let deployed = ISO8601DateFormatter().date(from: "2026-03-02T10:00:00Z")!

    private func run(_ sha: String, at: String, event: String = "pull_request", conclusion: String = "success") -> GitHubRun {
        GitHubRun(id: abs(sha.hashValue), name: "Preview update", head_branch: "feat/thing", status: "completed", conclusion: conclusion,
                  html_url: "https://github.com/acme/app/actions/runs/1", created_at: at, event: event, head_sha: sha)
    }

    func testAnUpdateThatSucceededForTheHeadFollows() {
        let runs = [run("aaa", at: "2026-03-03T09:00:00Z"), run("bbb", at: "2026-03-04T09:00:00Z")]
        XCTAssertEqual(PreviewStore.tracking(head: "bbb", headCommittedAt: nil, runs: runs, deployedAt: deployed), .following)
        XCTAssertFalse(PreviewStore.needsHeadDate(head: "bbb", runs: runs, deployedAt: deployed))
    }

    func testTheLastUpdateOnAnOlderCommitIsBehindAndNamesIt() {
        // The head moved to ccc and no workflow ran for it (a pull request in conflict).
        let runs = [run("aaa", at: "2026-03-03T09:00:00Z"), run("bbb", at: "2026-03-04T09:00:00Z")]
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: nil, runs: runs, deployedAt: deployed), .behind(served: "bbb"))
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: nil, runs: runs, deployedAt: nil), .behind(served: "bbb"))
        XCTAssertFalse(PreviewStore.needsHeadDate(head: "ccc", runs: runs, deployedAt: deployed))
    }

    func testAFailedOrCommentRunDeploysNothing() {
        // A failed update of the head, and an issue_comment run (its commit is the default branch's).
        let runs = [run("ccc", at: "2026-03-05T09:00:00Z", conclusion: "failure"),
                    run("ccc", at: "2026-03-05T10:00:00Z", event: "issue_comment"),
                    run("bbb", at: "2026-03-04T09:00:00Z")]
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: nil, runs: runs, deployedAt: deployed), .behind(served: "bbb"))
    }

    func testAHeadMadeAfterTheLastDeployIsBehind() {
        // Deployed by /preview, no update since: only the head commit's date can tell.
        XCTAssertTrue(PreviewStore.needsHeadDate(head: "ccc", runs: [], deployedAt: deployed))
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: deployed.addingTimeInterval(3600), runs: [], deployedAt: deployed),
                       .behind(served: nil))
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: deployed.addingTimeInterval(-3600), runs: [], deployedAt: deployed),
                       .following)
        // A /preview posted after the last update redeployed the head of that moment.
        let old = [run("aaa", at: "2026-03-01T09:00:00Z")]
        XCTAssertTrue(PreviewStore.needsHeadDate(head: "ccc", runs: old, deployedAt: deployed))
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: deployed.addingTimeInterval(-60), runs: old, deployedAt: deployed),
                       .following)
    }

    func testNothingKnownIsNotCalledBehind() {
        XCTAssertEqual(PreviewStore.tracking(head: "ccc", headCommittedAt: nil, runs: [], deployedAt: nil), .following)
        XCTAssertFalse(PreviewStore.needsHeadDate(head: "ccc", runs: [], deployedAt: nil))
    }

    func testConflictIsReadFromGitHubsTwoFields() {
        XCTAssertEqual(PreviewStore.conflict(mergeable: false, state: "dirty"), true)
        XCTAssertEqual(PreviewStore.conflict(mergeable: nil, state: "dirty"), true)
        XCTAssertEqual(PreviewStore.conflict(mergeable: true, state: "clean"), false)
        XCTAssertEqual(PreviewStore.conflict(mergeable: true, state: "blocked"), false)
        XCTAssertNil(PreviewStore.conflict(mergeable: nil, state: "unknown"))
        XCTAssertNil(PreviewStore.conflict(mergeable: nil, state: nil))
    }

    func testALivePreviewThatDoesNotFollowIsNotCalledLive() {
        var s = status(.live, [.app: true, .api: true])
        s.pull.headSHA = "9f3c2e7a41d0"; s.pull.baseRef = "main"
        XCTAssertNil(s.drift)
        XCTAssertEqual(s.word, "Live")

        s.tracking = .behind(served: "4b81d6f02c9e")
        XCTAssertEqual(s.drift, .behind)
        XCTAssertEqual(s.word, "Live, behind the pull request")
        XCTAssertEqual(s.compactWord, "Live, behind")
        XCTAssertEqual(s.driftReason, "The preview serves 4b81d6f, the pull request is at 9f3c2e7. No update ran for it.")

        s.conflict = true
        XCTAssertEqual(s.drift, .behind)
        XCTAssertTrue(s.driftReason?.hasPrefix("Won't redeploy: the pull request conflicts with main") == true)

        s.tracking = .following
        XCTAssertEqual(s.drift, .wontRedeploy)
        XCTAssertEqual(s.word, "Live, won't redeploy")

        // A host that does not answer is said first; a merged pull request has nothing to follow.
        s.targets[.api] = false
        XCTAssertEqual(s.word, "Partly down")
        s.pull.state = .merged
        XCTAssertNil(s.drift)
        var failed = status(.failed, [:]); failed.conflict = true
        XCTAssertNil(failed.drift)
    }

    func testTheLastPreviewCommandDatesTheDeploy() {
        func comment(_ id: Int, _ body: String, _ at: String) -> GitHubComment {
            GitHubComment(id: id, body: body, user: .init(login: "ada"), created_at: at, html_url: "https://github.com/acme/app/pull/1#c\(id)")
        }
        let pull = PreviewStatus.Pull(number: 1, title: "A change", url: URL(string: "https://github.com/acme/app/pull/1")!,
                                      author: "ada", state: .open, headRef: "feat/thing")
        let s = PreviewStore.derive(from: [comment(1, "/preview", "2026-03-02T10:00:00Z"),
                                           comment(2, "## Environnement de preview déployé", "2026-03-02T10:12:00Z"),
                                           comment(3, "/delete-preview --dry", "2026-03-03T10:00:00Z")], pull: pull)
        XCTAssertEqual(s.deployedAt, deployed)
        XCTAssertEqual(pull.conflictsURL.absoluteString, "https://github.com/acme/app/pull/1/conflicts")
    }
}
