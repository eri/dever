import XCTest
@testable import Dever

final class RefreshCadenceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    func testBudgetsOfTheScreenInFront() {
        XCTAssertEqual(RefreshCadence.interval(.slackNew), 20)
        XCTAssertEqual(RefreshCadence.interval(.slackPage), 60)
        XCTAssertEqual(RefreshCadence.interval(.linear), 60)
        XCTAssertEqual(RefreshCadence.interval(.github), 60)
        XCTAssertEqual(RefreshCadence.interval(.preview), 60)
    }

    func testWhatIsInFlightIsReadFaster() {
        XCTAssertEqual(RefreshCadence.interval(.checks, inFlight: true), 15)
        XCTAssertEqual(RefreshCadence.interval(.preview, inFlight: true), 15)
        // No check running: nothing to poll, however long ago the last read was.
        XCTAssertNil(RefreshCadence.interval(.checks))
        XCTAssertFalse(RefreshCadence.isDue(.checks, last: nil, now: t0))
        XCTAssertFalse(RefreshCadence.isDue(.checks, last: t0, now: t0.addingTimeInterval(3_600)))
        XCTAssertTrue(RefreshCadence.isDue(.checks, last: t0, inFlight: true, now: t0.addingTimeInterval(15)))
    }

    func testDueOnceTheBudgetHasPassed() {
        XCTAssertTrue(RefreshCadence.isDue(.github, last: nil, now: t0))
        XCTAssertFalse(RefreshCadence.isDue(.github, last: t0, now: t0.addingTimeInterval(59)))
        XCTAssertTrue(RefreshCadence.isDue(.github, last: t0, now: t0.addingTimeInterval(60)))
        XCTAssertFalse(RefreshCadence.isDue(.slackNew, last: t0, now: t0.addingTimeInterval(19)))
        XCTAssertTrue(RefreshCadence.isDue(.slackNew, last: t0, now: t0.addingTimeInterval(20)))
    }

    func testAFailingToolIsAskedLessAndLessOften() {
        XCTAssertEqual(RefreshCadence.wait(20, failures: 0), 20)
        XCTAssertEqual(RefreshCadence.wait(20, failures: 1), 40)
        XCTAssertEqual(RefreshCadence.wait(20, failures: 2), 80)
        XCTAssertEqual(RefreshCadence.wait(20, failures: 3), 160)
        XCTAssertEqual(RefreshCadence.wait(20, failures: 4), 300)      // capped at five minutes
        XCTAssertEqual(RefreshCadence.wait(20, failures: 500), 300)
        XCTAssertEqual(RefreshCadence.wait(60, failures: 1), 120)
        // Never sooner than the interval itself.
        XCTAssertEqual(RefreshCadence.wait(600, failures: 3), 600)
        XCTAssertFalse(RefreshCadence.isDue(.slackNew, last: t0, failures: 2, now: t0.addingTimeInterval(79)))
        XCTAssertTrue(RefreshCadence.isDue(.slackNew, last: t0, failures: 2, now: t0.addingTimeInterval(80)))
    }

    func testTheBackgroundCycleSetsItself() {
        // Two minutes: how late an alert may be while Dever is behind another app.
        XCTAssertEqual(RefreshCadence.background(projects: 0, lowPower: false), 120)
        XCTAssertEqual(RefreshCadence.background(projects: 4, lowPower: false), 120)
        XCTAssertEqual(RefreshCadence.background(projects: 20, lowPower: false), 120)
        // Many projects: three Slack calls each a cycle stay under 30 a minute.
        XCTAssertEqual(RefreshCadence.background(projects: 40, lowPower: false), 240)
        XCTAssertEqual(RefreshCadence.background(projects: 100, lowPower: false), 600)
        for projects in [1, 20, 40, 100, 400] {
            let perMinute = Double(projects * 3) / (RefreshCadence.background(projects: projects, lowPower: false) / 60)
            XCTAssertLessThanOrEqual(perMinute, 30)
        }
        // Low Power Mode: ten minutes at least.
        XCTAssertEqual(RefreshCadence.background(projects: 4, lowPower: true), 600)
        XCTAssertEqual(RefreshCadence.background(projects: 100, lowPower: true), 1_800)
    }

    func testEachKindBelongsToItsTool() {
        XCTAssertEqual(RefreshCadence.Kind.slackNew.service, .slack)
        XCTAssertEqual(RefreshCadence.Kind.slackPage.service, .slack)
        XCTAssertEqual(RefreshCadence.Kind.linear.service, .linear)
        XCTAssertEqual(RefreshCadence.Kind.github.service, .github)
        XCTAssertEqual(RefreshCadence.Kind.checks.service, .github)
        XCTAssertEqual(RefreshCadence.Kind.preview.service, .github)
    }

    /// One visible project for an hour, nothing failing, a check running the whole time:
    /// the request counts the budgets add up to stay far from the tools' limits.
    func testAnHourOfPollingStaysWellUnderTheLimits() {
        func reads(_ kind: RefreshCadence.Kind, inFlight: Bool = false) -> Int {
            RefreshCadence.interval(kind, inFlight: inFlight).map { Int(3_600 / $0) } ?? 0
        }
        let slack = reads(.slackNew) * 2 + reads(.slackPage) * 2          // history + cursor each
        let linear = reads(.linear) * 2                                    // delta + blockers
        let github = reads(.github) * 3 + reads(.checks, inFlight: true)   // open (cost 3 points) + checks
        XCTAssertLessThan(slack / 60, 50)          // Tier 3: about 50 a minute
        XCTAssertLessThan(linear, 1_200)           // per hour
        XCTAssertLessThan(github * 3, 5_000)       // GraphQL points per hour, counted generously
    }
}

final class RateLimitTests: XCTestCase {
    func testARateLimitSaysHowLongItWaits() {
        let error = AppError.rateLimited(.slack, retryAfter: 12.2)
        XCTAssertEqual(error.errorDescription, "Slack asked Dever to slow down. Trying again in 13 s.")
        // It is a failure a retry clears: what was on screen stays.
        XCTAssertTrue(ServiceState(error).isTransient)
    }
}
