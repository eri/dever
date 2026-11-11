import XCTest
@testable import Dever

/// Which projects the Overview reads again when the list of projects changes.
final class OverviewRelinkTests: XCTestCase {
    private func project(_ name: String, linear: String? = nil, slack: String? = nil, repos: [String] = []) -> Project {
        var p = Project(name: name)
        p.linear = linear.map { .init(id: $0, name: name, url: "https://example.com/\($0)") }
        p.slack = slack.map { .init(id: $0, name: name) }
        p.githubRepos = repos
        return p
    }

    func testAProjectThatGainsALinearProjectIsReadAgain() {
        let a = project("Checkout"), b = project("Billing", linear: "L1")
        var linked = a
        linked.linear = .init(id: "L2", name: "Checkout", url: "https://example.com/L2")
        XCTAssertEqual(OverviewStore.relinked(from: [a, b], to: [linked, b]), [a.id])
    }

    func testAChannelOrARepositoryChangeIsReadAgain() {
        let a = project("Checkout", slack: "C1"), b = project("Billing", repos: ["acme/app"])
        var a2 = a, b2 = b
        a2.slack = .init(id: "C2", name: "checkout")
        b2.githubRepos = ["acme/app", "acme/api"]
        XCTAssertEqual(Set(OverviewStore.relinked(from: [a, b], to: [a2, b2])), [a.id, b.id])
    }

    func testANewProjectIsRead() {
        let a = project("Checkout"), new = project("Search", linear: "L3")
        XCTAssertEqual(OverviewStore.relinked(from: [a], to: [a, new]), [new.id])
    }

    func testARenameAPreviewOrARemovalReadsNothing() {
        let a = project("Checkout", linear: "L1"), b = project("Billing")
        var renamed = a
        renamed.name = "Checkout v2"
        renamed.previewPullNumber = 12
        renamed.favorite = true
        XCTAssertEqual(OverviewStore.relinked(from: [a, b], to: [renamed]), [])
    }
}
