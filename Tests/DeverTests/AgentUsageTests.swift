import XCTest
@testable import Dever

final class AgentUsageTests: XCTestCase {
    private let zone = TimeZone(identifier: "UTC")!
    /// 2026-11-13 12:00 UTC, a Friday.
    private let now = Date(timeIntervalSince1970: 1_794_571_200)

    private func answer(primary: String? = #"{"usedPercent": 38, "windowDurationMins": 300, "resetsAt": 1794579000}"#,
                        secondary: String? = #"{"usedPercent": 20, "windowDurationMins": 10080, "resetsAt": 1794916800}"#,
                        credits: String = #"{"hasCredits": false, "unlimited": false, "balance": null}"#,
                        reached: String = "null", allowed: Bool = true) -> Data {
        Data("""
        {"ordinaryUsageAllowed": \(allowed), "accountId": "someone",
         "rateLimits": {"limitId": "codex", "primary": \(primary ?? "null"), "secondary": \(secondary ?? "null"),
                        "credits": \(credits), "planType": "team", "rateLimitReachedType": \(reached)}}
        """.utf8)
    }

    func testBothWindowsAreReadAndSaidWithTheirResets() throws {
        let usage = try AgentUsage.codex(result: answer(), at: now)
        XCTAssertEqual(usage.windows.map(\.minutes), [300, 10_080])
        XCTAssertEqual(usage.plan, "team")
        XCTAssertFalse(usage.limitReached)
        XCTAssertEqual(usage.line(at: now, zone: zone), "62% of the 5-hour window left, resets 14:10 · week 80% left")
        XCTAssertEqual(usage.short(at: now, zone: zone), "62% left · resets 14:10")
        XCTAssertFalse(usage.tight(at: now))
    }

    func testAnOldReadingSaysItsAge() throws {
        let usage = try AgentUsage.codex(result: answer(), at: now)
        let later = now.addingTimeInterval(20 * 60)
        XCTAssertEqual(usage.short(at: later, zone: zone), "62% left · resets 14:10 · read 20 min ago")
        XCTAssertEqual(usage.short(at: now.addingTimeInterval(299), zone: zone), "62% left · resets 14:10")
    }

    func testAWindowThatResetIsNoLongerSaid() throws {
        let usage = try AgentUsage.codex(result: answer(), at: now)
        // After the five-hour window reset, only the week still stands (another day: named).
        let afterShort = now.addingTimeInterval(3 * 3600)
        XCTAssertEqual(usage.live(at: afterShort).map(\.minutes), [10_080])
        XCTAssertEqual(usage.line(at: afterShort, zone: zone), "80% of the week left, resets Tue 12:00 · read 3 h ago")
        // After both: nothing can be said.
        let afterAll = now.addingTimeInterval(5 * 86_400)
        XCTAssertTrue(usage.lapsed(at: afterAll))
        XCTAssertEqual(usage.short(at: afterAll, zone: zone), "Usage unknown since its window reset")
        XCTAssertFalse(usage.tight(at: afterAll))
    }

    func testALimitReachedOrNearlyIsTight() throws {
        let reached = try AgentUsage.codex(result: answer(reached: "\"rate_limit_reached\""), at: now)
        XCTAssertTrue(reached.limitReached)
        XCTAssertEqual(reached.short(at: now, zone: zone), "Limit reached · resets 14:10")
        XCTAssertTrue(reached.tight(at: now))
        XCTAssertTrue(try AgentUsage.codex(result: answer(allowed: false), at: now).limitReached)
        let nearly = try AgentUsage.codex(result: answer(primary: #"{"usedPercent": 93.4, "windowDurationMins": 300, "resetsAt": 1794579000}"#), at: now)
        XCTAssertEqual(nearly.windows[0].leftPercent, 7)
        XCTAssertTrue(nearly.tight(at: now))
    }

    func testPlansWithoutAWindowSayWhatTheyHave() throws {
        // No five-hour limit: the week is the sentence.
        let weekly = try AgentUsage.codex(result: answer(primary: nil), at: now)
        XCTAssertEqual(weekly.line(at: now, zone: zone), "80% of the week left, resets Tue 12:00")
        // Credits only.
        let credits = try AgentUsage.codex(result: answer(primary: nil, secondary: nil,
                                                          credits: #"{"hasCredits": true, "unlimited": false, "balance": "12.50"}"#), at: now)
        XCTAssertEqual(credits.line(at: now, zone: zone), "Credits: 12.50")
        XCTAssertFalse(credits.lapsed(at: now.addingTimeInterval(86_400 * 30)))
        let unlimited = try AgentUsage.codex(result: answer(primary: nil, secondary: nil,
                                                            credits: #"{"hasCredits": true, "unlimited": true, "balance": null}"#), at: now)
        XCTAssertEqual(unlimited.short(at: now, zone: zone), "No fixed limit")
        XCTAssertThrowsError(try AgentUsage.codex(result: Data("{}".utf8), at: now))
    }

    func testAnApiKeyLoginIsNotAFailure() {
        XCTAssertEqual(CodexUsageError.from(message: "chatgpt authentication required to read rate limits"), .noPlan)
        XCTAssertEqual(CodexUsageError.from(message: "boom"), .failed("boom"))
        // An expired sign-in says what to do in one sentence; the tool's words wait under "Details".
        let expired = CodexUsageError.from(message: #"GET https://example.com/usage failed: 401 Unauthorized; {"code": "token_expired"}"#)
        guard case .signInExpired = expired else { return XCTFail("not read as an expired sign-in") }
        XCTAssertEqual(expired.localizedDescription, "Codex's sign-in has expired: open Codex to sign in again")
        XCTAssertTrue(expired.detail?.contains("token_expired") == true)
        XCTAssertEqual(CodexUsageError.failed("boom").localizedDescription, "Codex could not say what is left")
        XCTAssertNil(CodexUsageError.noPlan.detail)
        XCTAssertTrue(AgentTool.codex.usageIsReadable)
        XCTAssertFalse(AgentTool.claudeCode.usageIsReadable)
        XCTAssertNil(CodexUsageReader.binary(app: URL(fileURLWithPath: "/nowhere/Nothing.app"))
            .flatMap { $0.path.hasPrefix("/nowhere") ? $0 : nil })
    }

    func testTheAgentWithTheMostUsageLeftIsPickedOnlyFromWhatIsKnown() throws {
        func entry(_ short: Double, _ week: Double = 0, reached: Bool = false) -> AgentUsageEntry {
            .init(usage: AgentUsage(windows: [.init(usedPercent: short, minutes: 300, resetsAt: now.addingTimeInterval(3600)),
                                              .init(usedPercent: week, minutes: 10_080, resetsAt: now.addingTimeInterval(86_400))],
                                    plan: nil, limitReached: reached, readAt: now))
        }
        // The tightest window counts: 62% of five hours but 30% of the week is 30% left.
        XCTAssertEqual(AgentRecommendation.left(entry(38, 70).usage, at: now), 30)
        XCTAssertEqual(AgentRecommendation.left(entry(38, reached: true).usage, at: now), 0)
        XCTAssertNil(AgentRecommendation.left(nil, at: now))
        XCTAssertNil(AgentRecommendation.left(entry(38).usage, at: now.addingTimeInterval(5 * 86_400)))

        // One tool readable with room: it is picked, on its own figure.
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(38)], at: now, fallback: .claudeCode), .init(tool: .codex, reason: "62% left"))
        // Nearly out: the tool whose usage is unknown is taken, and the reason says why.
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(95)], at: now, fallback: .claudeCode),
                       .init(tool: .claudeCode, reason: "Codex is nearly out"))
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(10, reached: true)], at: now, fallback: .codex).tool, .claudeCode)
        // Nothing known: the agent used last, and it says so.
        XCTAssertEqual(AgentRecommendation.pick([:], at: now, fallback: .codex), .init(tool: .codex, reason: "usage not known yet"))
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(38)], at: now.addingTimeInterval(5 * 86_400), fallback: .claudeCode).tool, .claudeCode)
        // Both known: the one with more room; a tie goes to the agent used last.
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(38), .claudeCode: entry(20)], at: now, fallback: .codex), .init(tool: .claudeCode, reason: "80% left"))
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(50), .claudeCode: entry(50)], at: now, fallback: .codex).tool, .codex)
        XCTAssertEqual(AgentRecommendation.pick([.codex: entry(99), .claudeCode: entry(100)], at: now, fallback: .codex),
                       .init(tool: .codex, reason: "1% left"))
        XCTAssertEqual(AgentChoice(stored: AgentChoice.mostLeft.stored), .mostLeft)
    }
}
