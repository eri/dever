import XCTest
@testable import Dever

final class OnboardingIntelligenceTests: XCTestCase {
    typealias Stage = OnboardingView.Stage

    func testTheStageIsOfferedWhereTheModelRunsNowOrAfterAFix() {
        let features: [IntelligenceFeature] = [.messageSummary]
        XCTAssertTrue(Stage.offersIntelligence(.available, features: features))
        XCTAssertTrue(Stage.offersIntelligence(.notReady, features: features))
        XCTAssertTrue(Stage.offersIntelligence(.off, features: features))
        XCTAssertFalse(Stage.offersIntelligence(.unsupported, features: features))
        XCTAssertFalse(Stage.offersIntelligence(.available, features: []))
    }

    func testAnUnsupportedMacHasNeitherTheStageNorItsMark() {
        XCTAssertEqual(Stage.flow(intelligence: true), [.name, .connect, .repositories, .channels, .intelligence, .project])
        XCTAssertEqual(Stage.flow(intelligence: false), [.name, .connect, .repositories, .channels, .project])
        XCTAssertEqual(Stage.intelligence.resolved(intelligence: false), .project)
        XCTAssertEqual(Stage.intelligence.resolved(intelligence: true), .intelligence)
        XCTAssertEqual(Stage.channels.resolved(intelligence: false), .channels)
    }

    func testTheStagePresentsOnlyWhatIsBuilt() {
        XCTAssertFalse(OnboardingIntelligence.features.isEmpty)
        XCTAssertTrue(OnboardingIntelligence.features.allSatisfy(IntelligenceFeature.built.contains))
    }

    @MainActor
    func testTheSwitchWritesTheKeySettingsReadsAndDropsWhatWasWritten() async {
        let name = "onboarding-intelligence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = IntelligenceStore()
        let subject = IntelligenceStore.Subject(feature: .messageSummary, id: "C1/1.000000")
        store.want(subject, version: "v") { GeneratedText(sentences: [.init(text: "A sentence.")]) }
        await store.settle()
        XCTAssertNotNil(store.text(subject))

        XCTAssertTrue(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
        IntelligencePreferences.set(.messageSummary, on: false, defaults: defaults, store: store)
        XCTAssertFalse(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
        XCTAssertNil(store.text(subject))
        IntelligencePreferences.set(.messageSummary, on: true, defaults: defaults, store: store)
        XCTAssertTrue(IntelligencePreferences.isOn(.messageSummary, defaults: defaults))
    }
}
