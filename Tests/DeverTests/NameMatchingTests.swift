import XCTest
@testable import Dever

final class NameMatchingTests: XCTestCase {
    func testExactBeatsContains() {
        let names = ["Checkout redesign v2", "Checkout redesign", "Billing"]
        XCTAssertEqual(Naming.closest(to: "checkout-redesign", in: names) { $0 }, "Checkout redesign")
    }

    func testContainsWhenNoExact() {
        let names = ["Mobile app", "Checkout redesign v2"]
        XCTAssertEqual(Naming.closest(to: "Checkout", in: names) { $0 }, "Checkout redesign v2")
    }

    func testShortSlugsNeverContain() {
        XCTAssertNil(Naming.closest(to: "AI", in: ["Mail", "Trains"]) { $0 })
        XCTAssertEqual(Naming.closest(to: "AI", in: ["Mail", "ai"]) { $0 }, "ai")
    }

    func testNothingCloseIsNil() {
        XCTAssertNil(Naming.closest(to: "Checkout", in: ["Billing", "Mobile app"]) { $0 })
    }

    func testChannelPrefixIsIgnored() {
        let channels = [SlackChannel(id: "1", name: "proj-checkout", is_private: nil, is_member: true, num_members: nil),
                        SlackChannel(id: "2", name: "random", is_private: nil, is_member: true, num_members: nil)]
        XCTAssertEqual(Naming.closestChannel(to: "Checkout", prefix: "proj-", in: channels)?.id, "1")
        XCTAssertNil(Naming.closestChannel(to: "Random stuff", prefix: "proj-", in: [channels[0]]))
    }
}
