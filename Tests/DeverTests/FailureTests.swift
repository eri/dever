import XCTest
@testable import Dever

private final class LogModel: LanguageModel, @unchecked Sendable {
    var availability: IntelligenceAvailability = .available
    var contextSize = 4096
    var answer = FailureAnswer(stated: true, line: "", sentence: "")
    private let lock = NSLock()
    private(set) var prompts: [String] = []

    func tokenCount(_ text: String) async -> Int { TextBudget.estimate(text) }
    func respond(instructions: String, prompt: String, maximumTokens: Int?) async throws -> String { "" }
    func summarise(instructions: String, prompt: String) async throws -> MessageSummaryAnswer { .init(kind: "Update", summary: "") }
    func explainFailure(instructions: String, prompt: String) async throws -> FailureAnswer {
        lock.withLock { prompts.append(prompt) }
        return answer
    }
}

final class PipelineLogTests: XCTestCase {
    private let typeError = "src/ExportButton.tsx:42:27 - error TS2345: Argument of type 'string | undefined' is not assignable to parameter of type 'string'."

    private func excerpt(_ output: [String], errors: [String] = ["Process completed with exit code 1."], command: String = "npm run build") -> PipelineLog.Excerpt {
        PipelineLog.excerpt(PipelineLog.lines(actionsLog(command: command, output: output, errors: errors), cut: false))!
    }

    func testLinesLoseTheRunnersTimeAndColours() {
        let raw = Data("half a line\n2026-11-03T09:14:02.1234567Z \u{1B}[31mFAIL\u{1B}[0m tests/a.spec.ts\n2026-11-03T09:14:03.0000000Z done".utf8)
        XCTAssertEqual(PipelineLog.lines(raw, cut: true), ["FAIL tests/a.spec.ts", "done"])
        XCTAssertEqual(PipelineLog.lines(raw, cut: false).first, "half a line")
    }

    func testTheExcerptIsTheFailedStepAlone() {
        let e = excerpt(["> tsc --noEmit", "", typeError])
        XCTAssertEqual(e.command, "npm run build")
        XCTAssertEqual(e.output, ["> tsc --noEmit", typeError], "no header, no environment, no clean-up, no earlier step")
        XCTAssertEqual(e.errors, ["Process completed with exit code 1."])
    }

    func testSeveralRunnerErrorsAreKeptTogether() {
        let e = excerpt(["✓ 7 downloads a book"], errors: ["The operation was canceled.", "The job has exceeded the maximum execution time of 30 minutes."])
        XCTAssertEqual(e.errors.count, 2)
        XCTAssertTrue(PipelineLog.statesAnError(e), "the runner's own error says why")
    }

    func testATailWithoutTheStepsHeaderStillGivesItsOutput() {
        let lines = ["still compiling", typeError, "##[error]Process completed with exit code 2.", "Post job cleanup."]
        let e = PipelineLog.excerpt(lines)
        XCTAssertNil(e?.command)
        XCTAssertEqual(e?.output, ["still compiling", typeError])
    }

    func testNoErrorFromTheRunnerIsNoExcerpt() {
        XCTAssertNil(PipelineLog.excerpt(["all good", "Post job cleanup."]))
        XCTAssertNil(PipelineLog.excerpt(["Post job cleanup.", "##[error]a clean-up step failed"]), "what fails after the job is not the failure")
    }

    func testAStepThatOnlyExitsStatesNoError() {
        XCTAssertFalse(PipelineLog.statesAnError(excerpt(["Uploading 214 files", "Waiting for environment to become ready", "Waiting for environment to become ready"])))
        XCTAssertFalse(PipelineLog.statesAnError(excerpt(["$ prettier --write .", "diff --git a/docs/guide.md b/docs/guide.md", "-Run  the installer", "+Run the installer"])))
        XCTAssertFalse(PipelineLog.statesAnError(excerpt(["src/main.c:14:9: warning: unused variable 'n'", "npm warn deprecated glob@7.2.3"], errors: ["Process completed with exit code 137."])))
        XCTAssertFalse(PipelineLog.statesAnError(excerpt(["12 passed, 0 failed", "Found 0 errors. Watching for file changes."])))
    }

    func testALineThatReportsWhatWentWrongStatesIt() {
        for line in [typeError, "npm error code ECONNRESET", "FAILED tests/test_billing.py::test_invoice_total - assert 19.97 == 19.98",
                     "Test Case '-[ReaderTests.StreakTests testAcrossTimeZones]' failed (0.012 seconds).", "fatal: unable to access the repository",
                     "Timeout waiting for browser logs.", "sh: 1: eslint: not found", "panic: runtime error: index out of range"] {
            XCTAssertTrue(PipelineLog.statesAnError(excerpt([line])), line)
        }
    }

    func testTheExitCodeIsNeverTheReason() {
        XCTAssertTrue(PipelineLog.isExitCode("Process completed with exit code 1."))
        XCTAssertTrue(PipelineLog.isExitCode("Error: Process completed with exit code 137"))
        XCTAssertFalse(PipelineLog.isExitCode("npm error code ECONNRESET"))
    }
}

final class FailureExplanationTests: XCTestCase {
    private let error = "npm error network request to https://registry.npmjs.org/@typescript-eslint%2fparser failed, reason: read ECONNRESET"
    private var excerpt: PipelineLog.Excerpt {
        .init(command: "npm ci", output: ["npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported", error],
              errors: ["Process completed with exit code 1."])
    }
    private func shown(line: String, sentence: String = "The request to the npm registry failed with ECONNRESET.", stated: Bool = true) -> String? {
        FailureExplanation.sentence(from: .init(stated: stated, line: line, sentence: sentence), excerpt: excerpt)
    }

    func testASentenceThatRestsOnALineOfTheLogIsShown() {
        XCTAssertEqual(shown(line: error), "The request to the npm registry failed with ECONNRESET.")
        XCTAssertNotNil(shown(line: "npm error network request to https://registry.npmjs.org/@typescript-eslint/parser failed, reason: read ECONNRESET"),
                        "the model tidies what it copies")
        XCTAssertEqual(shown(line: error, sentence: "`npm ci` lost the network."), "Npm ci lost the network.")
    }

    func testAnAnswerThatCannotBeCheckedIsNotShown() {
        XCTAssertNil(shown(line: error, stated: false), "the model says the log does not state it")
        XCTAssertNil(shown(line: "error: the disk is full"), "a line that is not in the log")
        XCTAssertNil(shown(line: "Process completed with exit code 1."), "the exit code says nothing")
        XCTAssertNil(shown(line: "npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported"), "a warning is not the cause")
        XCTAssertNil(shown(line: ""), "no line at all")
        XCTAssertNil(shown(line: error, sentence: ""), "no sentence")
        XCTAssertNil(shown(line: error, sentence: String(repeating: "word ", count: 80)), "one sentence far too long")
    }

    func testOnlyWholeSentencesUnderTheLimit() {
        let long = "The request failed. " + String(repeating: "More and more words about it ", count: 10) + "end."
        XCTAssertEqual(shown(line: error, sentence: long), "The request failed.")
    }

    func testThePromptKeepsTheNewestOutputThatFits() async {
        let many = PipelineLog.Excerpt(command: "swift test", output: (1...200).map { "line \($0) of the output" }, errors: ["Process completed with exit code 1."])
        let prompt = await FailureExplanation.prompt(job: "test", step: "Run tests", excerpt: many, room: 200) { TextBudget.estimate($0) }
        XCTAssertEqual(prompt?.hasPrefix("Job: test\nStep: Run tests\nCommand: swift test\nLog:\n"), true)
        XCTAssertEqual(prompt?.contains("line 200 of the output"), true)
        XCTAssertEqual(prompt?.contains("line 1 of the output\n"), false)
        XCTAssertEqual(prompt?.hasSuffix("Error: Process completed with exit code 1."), true)
        XCTAssertLessThanOrEqual(TextBudget.estimate(prompt ?? ""), 220)
        let none = await FailureExplanation.prompt(job: "test", step: nil, excerpt: many, room: 5) { TextBudget.estimate($0) }
        XCTAssertNil(none, "not even the head fits")
    }

    func testTheModelIsNotAskedWhenTheLogStatesNoError() async throws {
        let model = LogModel()
        let quiet = PipelineLog.Excerpt(command: "./deploy.sh", output: ["Waiting for environment to become ready"], errors: ["Process completed with exit code 1."])
        let sentence = try await FailureExplanation.write(job: "deploy", step: nil, excerpt: quiet, with: Intelligence(model: model))
        XCTAssertNil(sentence)
        XCTAssertTrue(model.prompts.isEmpty)
    }

    func testTheModelIsAskedOnceWithTheStepAndItsAnswerChecked() async throws {
        let model = LogModel()
        model.answer = .init(stated: true, line: error, sentence: "The request to the npm registry failed.")
        let sentence = try await FailureExplanation.write(job: "lint", step: "Install", excerpt: excerpt, with: Intelligence(model: model))
        XCTAssertEqual(sentence, "The request to the npm registry failed.")
        XCTAssertEqual(model.prompts.count, 1)
        XCTAssertEqual(model.prompts.first?.hasPrefix("Job: lint\nStep: Install\nCommand: npm ci\n"), true)
        model.answer = .init(stated: true, line: "error: invented", sentence: "Something else failed.")
        let invented = try await FailureExplanation.write(job: "lint", step: "Install", excerpt: excerpt, with: Intelligence(model: model))
        XCTAssertNil(invented)
    }
}

@MainActor
final class FailureStoreTests: XCTestCase {
    private let key = FailureStore.Key(repository: "owner/app", number: 12)
    private let job = GitHubFailedCheck(name: "test (macos-15)", url: "https://github.com/owner/app/actions/runs/1/job/7", jobID: 7, step: "Run tests",
                                        completedAt: Date(timeIntervalSince1970: 1_000))
    private let log = actionsLog(command: "swift test", output: ["error: testStreak failed: 3 is not equal to 4"])

    /// Counts what is read and answers what the test set.
    private final class Calls: @unchecked Sendable {
        var failed = 0, log = 0, write = 0
        var checks: Result<GitHubFailedChecks, Error> = .success(.init(sha: "abc", failed: []))
        var data: Result<Data, Error> = .success(Data())
        var sentence: Result<String?, Error> = .success("testStreak failed: 3 is not equal to 4.")
        var reads: FailureStore.Reads {
            .init(failed: { _, _ in self.failed += 1; return try self.checks.get() },
                  log: { _, _ in self.log += 1; return (try self.data.get(), false) },
                  write: { _, _, _ in self.write += 1; return try self.sentence.get() })
        }
    }

    private func make(_ checks: [GitHubFailedCheck]? = nil) -> (FailureStore, Calls) {
        let store = FailureStore()
        store.isOn = { true }
        let calls = Calls()
        calls.checks = .success(.init(sha: "abc", failed: checks ?? [job]))
        calls.data = .success(log)
        return (store, calls)
    }

    private func outcome(_ store: FailureStore) -> FailureStore.Outcome? {
        if case .explained(let e) = store.entry(key) { return e.outcome }
        return nil
    }

    func testNothingIsReadBeforeSomeoneAsks() {
        let (store, calls) = make()
        XCTAssertNil(store.entry(key))
        XCTAssertEqual(calls.failed + calls.log + calls.write, 0)
    }

    func testAskingReadsTheChecksThenTheLogThenWritesOnce() async {
        let (store, calls) = make()
        store.explain(key, reads: calls.reads)
        XCTAssertEqual(store.entry(key), .loading)
        await store.settle()
        XCTAssertEqual(store.entry(key), .explained(.init(check: job, failed: [job], sha: "abc", outcome: .sentence("testStreak failed: 3 is not equal to 4."))))
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual([calls.failed, calls.log, calls.write], [1, 1, 1], "kept for the run: asking again reads nothing")
    }

    func testANewRunDropsWhatWasSaidOfTheOldOne() async {
        let (store, calls) = make()
        store.explain(key, reads: calls.reads)
        await store.settle()
        store.keep("owner/other", failing: [])
        XCTAssertNotNil(store.entry(key), "another repository's checks say nothing of this one")
        store.keep("owner/app", failing: [12, 40])
        XCTAssertNotNil(store.entry(key), "still failing")
        store.keep("owner/app", failing: [40])
        XCTAssertNil(store.entry(key), "its checks run again or pass: the explanation was of a run that is gone")
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(calls.failed, 2)
    }

    func testTheFirstFailedJobIsExplainedAndTheOthersCounted() async {
        let later = GitHubFailedCheck(name: "e2e", url: "u", jobID: 9, step: nil, completedAt: Date(timeIntervalSince1970: 2_000))
        let status = GitHubFailedCheck(name: "deploy/preview", url: "u", jobID: nil, step: nil, completedAt: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(GitHubFailedChecks(sha: "a", failed: [later, status, job]).first, job, "the Actions job that failed first")
        XCTAssertEqual(GitHubFailedChecks(sha: "a", failed: [status]).first, status)
        let (store, calls) = make([later, status, job])
        store.explain(key, reads: calls.reads)
        await store.settle()
        guard case .explained(let e) = store.entry(key) else { return XCTFail() }
        XCTAssertEqual(e.check, job)
        XCTAssertEqual(e.failed, [job, later, status], "the explained job first")
    }

    func testALogThatStatesNoErrorSaysSoWithoutTheModel() async {
        let (store, calls) = make()
        calls.data = .success(actionsLog(command: "./deploy.sh", output: ["Waiting for environment to become ready"]))
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .doesNotSay)
        XCTAssertEqual(calls.write, 0)
        calls.data = .success(Data("no marker at all".utf8))
        store.drop(key)
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .doesNotSay)
    }

    func testTheModelFailingOrUnsureIsSilence() async {
        let (store, calls) = make()
        calls.sentence = .success(nil)
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .silent)
        store.drop(key)
        calls.sentence = .failure(IntelligenceError.unavailable)
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .silent, "the job and the log link stay, with no sentence and no error")
    }

    func testACheckFromAnotherServiceHasNoLogToRead() async {
        let (store, calls) = make([GitHubFailedCheck(name: "deploy/preview", url: "https://example.com/deploy", jobID: nil, step: nil, completedAt: nil)])
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .noLog)
        XCTAssertEqual(calls.log, 0)
    }

    func testALogThatCannotBeReadKeepsTheJobAndItsLink() async {
        let (store, calls) = make()
        calls.data = .failure(GitHubLogError.unavailable(403))
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .unreadable)
        XCTAssertEqual(calls.write, 0)
    }

    func testNoFailedCheckAnyMoreIsSaidAndTriedAgainOnTheNextAsk() async {
        let (store, calls) = make([])
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(store.entry(key), .problem(.moved))
        calls.checks = .success(.init(sha: "def", failed: [job]))
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(outcome(store), .sentence("testStreak failed: 3 is not equal to 4."))
    }

    func testEachFailureOfTheReadIsNamed() async {
        let cases: [(Error, FailureStore.Problem)] = [
            (AppError.rateLimited(.github, retryAfter: 60), .rateLimited), (AppError.unauthorized(.github), .unauthorized),
            (AppError.notConnected(.github), .unauthorized), (URLError(.notConnectedToInternet), .offline), (AppError.message("GitHub 502"), .failed),
        ]
        for (error, problem) in cases {
            let (store, calls) = make()
            calls.checks = .failure(error)
            store.explain(key, reads: calls.reads)
            await store.settle()
            XCTAssertEqual(store.entry(key), .problem(problem))
            XCTAssertEqual(calls.log, 0)
        }
        let (store, calls) = make()
        calls.data = .failure(AppError.rateLimited(.github, retryAfter: 60))
        store.explain(key, reads: calls.reads)
        await store.settle()
        XCTAssertEqual(store.entry(key), .problem(.rateLimited), "a limit met on the log is a problem, not a silence")
    }

    func testSwitchedOffNothingIsReadAndNothingStays() async {
        let (store, calls) = make()
        store.explain(key, reads: calls.reads)
        await store.settle()
        store.isOn = { false }
        store.explain(key, reads: calls.reads)
        XCTAssertNil(store.entry(key))
        store.isOn = { true }
        store.explain(key, reads: calls.reads)
        await store.settle()
        store.reset()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(calls.failed, 2)
    }

    func testAPullRequestsAddressGivesItsRepositoryAndNumber() {
        XCTAssertEqual(PullFailure.key(url: "https://github.com/owner/app/pull/12"), key)
        XCTAssertEqual(PullFailure.key(url: "https://github.com/owner/app/pull/12/checks"), key)
        XCTAssertNil(PullFailure.key(url: "https://github.com/owner/app/issues/12"))
        XCTAssertNil(PullFailure.key(url: "https://example.com/owner/app/pull/12"))
        XCTAssertNil(PullFailure.key(url: "not a url"))
    }

    func testAnOldReadIsNotDrawnAsCurrent() {
        let now = Date()
        XCTAssertFalse(PullFailure.isStale(now.addingTimeInterval(-90), now: now))
        XCTAssertTrue(PullFailure.isStale(now.addingTimeInterval(-121), now: now))
    }

    func testTheFeatureIsBuiltWithItsSwitch() {
        XCTAssertTrue(IntelligenceFeature.built.contains(.explainFailure))
        XCTAssertEqual(IntelligenceFeature.explainFailure.group, .pipelines)
    }
}

extension RealModelTests {
    /// The whole chain on a real pull request: `DEVER_TEST_GITHUB_PULL=owner/name#12` with a
    /// token in `DEVER_TEST_GITHUB_TOKEN`, and the real model. Prints what Dever would show.
    @MainActor
    func testWhyARealPullRequestFailed() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DEVER_TEST_REAL_MODEL"] == "1", let target = env["DEVER_TEST_GITHUB_PULL"], let token = env["DEVER_TEST_GITHUB_TOKEN"],
              let hash = target.firstIndex(of: "#"), let number = Int(target[target.index(after: hash)...]) else {
            throw XCTSkip("needs the system model, a pull request and a token")
        }
        let key = FailureStore.Key(repository: String(target[..<hash]), number: number)
        let client = GitHubClient(token: token)
        let checks = try await client.failedChecks(key.repository, number: key.number)
        print("real: \(checks.failed.count) failed checks on \(checks.sha.prefix(7)): \(checks.failed.map { "\($0.name) [\($0.step ?? "-")] job \($0.jobID.map(String.init) ?? "none")" })")
        for check in checks.failed {
            guard let job = check.jobID else { continue }
            let start = Date()
            let log = try await client.jobLogTail(key.repository, jobID: job, bytes: PipelineLog.tailBytes)
            let read = Date().timeIntervalSince(start)
            guard let excerpt = PipelineLog.excerpt(PipelineLog.lines(log.data, cut: log.cut)) else { print("real: \(check.name): no error marker"); continue }
            let sentence = try? await FailureExplanation.write(job: check.name, step: check.step, excerpt: excerpt)
            print("real: \(check.name) › \(check.step ?? "-"): \(log.data.count) bytes\(log.cut ? " (tail)" : "") in \(String(format: "%.1f", read)) s, \(excerpt.output.count) lines, states an error \(PipelineLog.statesAnError(excerpt)), then \(String(format: "%.1f", Date().timeIntervalSince(start) - read)) s | SHOWN: \(sentence.flatMap { $0 } ?? "The log does not say why.")")
        }
        let store = FailureStore()
        store.isOn = { true }
        store.explain(key, reads: .live(client))
        await store.settle()
        print("real store: \(String(describing: store.entry(key)))")
    }
}
