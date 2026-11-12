import XCTest
@testable import Dever

/// The page the browser shows after a sign-in says what actually happened.
final class OAuthPageTests: XCTestCase {
    func testThePathNamesTheTool() {
        XCTAssertEqual(OAuthPage.service(path: "/linear/callback"), "Linear")
        XCTAssertEqual(OAuthPage.service(path: "/slack/callback"), "Slack")
        XCTAssertEqual(OAuthPage.service(path: "/github/callback"), "GitHub")
        XCTAssertNil(OAuthPage.service(path: "/favicon.ico"))
    }

    func testAnErrorFromTheProviderIsNotASignIn() {
        XCTAssertEqual(OAuthPage.outcome(matches: true, query: ["code": "abc", "state": "s"]), .signedIn)
        XCTAssertEqual(OAuthPage.outcome(matches: true, query: ["error": "access_denied"]), .refused)
        XCTAssertEqual(OAuthPage.outcome(matches: false, query: ["code": "abc"]), .notFound)
    }

    func testThePageSaysWhatHappenedAndKeepsNothingInTheAddressBar() {
        let ok = OAuthPage.html(service: "Linear", outcome: .signedIn)
        XCTAssertTrue(ok.contains("Linear is signed in"))
        XCTAssertTrue(ok.contains("Keychain"))
        XCTAssertTrue(ok.contains("history.replaceState"))
        XCTAssertFalse(ok.contains("http://") || ok.contains("https://"), "the page loads nothing from the network")

        let refused = OAuthPage.html(service: "Slack", outcome: .refused)
        XCTAssertTrue(refused.contains("Slack was not connected"))
        XCTAssertFalse(refused.contains("Keychain"))
    }
}
