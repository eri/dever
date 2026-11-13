import XCTest
@testable import Dever

final class PeopleMatchTests: XCTestCase {
    private let photo = URL(string: "https://example.com/a.png")!

    func testMatchesByEmailIgnoringCaseAndSpaces() {
        let slack = PeopleMatch.slackPhotos([SlackUser(id: "U1", name: "Alex", avatar: photo, isBot: false, email: " Alex@Example.com ")])
        XCTAssertEqual(PeopleMatch.photo(linearID: "L1", linearEmails: ["L1": "alex@example.com"], slackPhotos: slack), photo)
    }

    func testSameNameDifferentEmailDoesNotMatch() {
        let slack = PeopleMatch.slackPhotos([SlackUser(id: "U1", name: "Alex", avatar: photo, isBot: false, email: "alex@other.com")])
        XCTAssertNil(PeopleMatch.photo(linearID: "L1", linearEmails: ["L1": "alex@example.com"], slackPhotos: slack))
    }

    func testBotsAndMissingDataNeverMatch() {
        let slack = PeopleMatch.slackPhotos([
            SlackUser(id: "B1", name: "Bot", avatar: photo, isBot: true, email: "bot@example.com"),
            SlackUser(id: "U2", name: "No picture", avatar: nil, isBot: false, email: "np@example.com"),
            SlackUser(id: "U3", name: "No email", avatar: photo, isBot: false),
        ])
        XCTAssertTrue(slack.isEmpty)
        XCTAssertNil(PeopleMatch.photo(linearID: nil, linearEmails: [:], slackPhotos: slack))
        XCTAssertNil(PeopleMatch.photo(linearID: "L9", linearEmails: [:], slackPhotos: ["a@b.c": photo]))
    }
}
