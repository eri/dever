import XCTest
@testable import Dever

/// How Intelligence is presented: where "Beta" is said, and where the coming model is announced.
final class IntelligenceOutlookTests: XCTestCase {
    func testEveryFeatureIsBetaSoThePageSaysItOnce() {
        XCTAssertTrue(IntelligenceFeature.allCases.allSatisfy { $0.maturity == .beta })
        XCTAssertEqual(IntelligenceFeature.betaMark(among: IntelligenceFeature.built), .page)
        XCTAssertEqual(IntelligenceFeature.betaMark(among: IntelligenceFeature.allCases), .page)
    }

    func testNoFeatureShownMeansNoBetaMark() {
        XCTAssertEqual(IntelligenceFeature.betaMark(among: [IntelligenceFeature]()), .none)
    }

    func testTheAnnouncementIsMadeOnlyWhereTheRecommendationReaches() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertTrue(LocalModelOutlook.announced(memory: 16 * gb, appleSilicon: true))
        XCTAssertTrue(LocalModelOutlook.announced(memory: 32 * gb, appleSilicon: true))
        XCTAssertFalse(LocalModelOutlook.announced(memory: 8 * gb, appleSilicon: true))
        XCTAssertFalse(LocalModelOutlook.announced(memory: 64 * gb, appleSilicon: false))
    }

    func testSettingsPageExistsForAFeatureOrForTheAnnouncement() {
        // A Mac that runs Apple's model, or could: the page, with or without the announcement.
        for state in [IntelligenceAvailability.available, .off, .notReady] {
            XCTAssertTrue(LocalModelOutlook.settingsPage(availability: state, anyFeature: true, announced: false))
        }
        // A Mac that never will: the page only for the announcement.
        XCTAssertTrue(LocalModelOutlook.settingsPage(availability: .unsupported, anyFeature: true, announced: true))
        XCTAssertFalse(LocalModelOutlook.settingsPage(availability: .unsupported, anyFeature: true, announced: false))
        // No feature built and nothing announced: no page.
        XCTAssertFalse(LocalModelOutlook.settingsPage(availability: .available, anyFeature: false, announced: false))
    }

    func testTheAnnouncementNamesNoModelSizeOrDate() {
        let words = ([LocalModelOutlook.title, LocalModelOutlook.reason(today: true), LocalModelOutlook.reason(today: false)]
            + LocalModelOutlook.terms + LocalModelOutlook.Promise.allCases.map(\.rawValue)).joined(separator: " ").lowercased()
        for banned in ["gb", "gemma", "qwen", "mlx", "larger", "bigger", "202", "billion"] {
            XCTAssertFalse(words.contains(banned), "the announcement says \(banned)")
        }
        // A Mac without Apple's model is not told Dever shortens messages there today.
        XCTAssertFalse(LocalModelOutlook.reason(today: false).contains("Today"))
    }
}
