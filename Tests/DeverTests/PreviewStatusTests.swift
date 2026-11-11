import XCTest
@testable import Dever

/// A live preview is called live only when every probed host answers.
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
}
