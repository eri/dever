import Combine
import Foundation

/// Why a pull request's pipeline failed, for the whole app's lifetime and in memory only: the
/// failed job as GitHub names it and one generated sentence (docs/on-device-ai.md, 5.6).
/// Nothing is read before someone asks; an answer is kept for as long as that run is the pull
/// request's failure, and dropped when its checks move on.
@MainActor
final class FailureStore: ObservableObject {
    static let shared = FailureStore(following: true)

    struct Key: Hashable, Sendable {
        var repository: String
        var number: Int
    }

    /// What can be said of the failed job once GitHub has named it.
    enum Outcome: Equatable {
        /// The log is being read and the sentence written: a skeleton line.
        case writing
        /// What went wrong, written by the model from a line of the log.
        case sentence(String)
        /// The step failed without a line that says why. Fixed words, never a guess.
        case doesNotSay
        /// The model had nothing to give (refused, failed, not sure): no sentence, no message.
        case silent
        /// A check another service reports: there is no log to read here.
        case noLog
        /// The log exists on GitHub but cannot be read from here: expired, or not allowed.
        case unreadable
    }

    struct Explanation: Equatable {
        /// The failed job, raw: its name, its step, when it ended, its page.
        var check: GitHubFailedCheck
        /// How many other checks of the same commit failed.
        var others: Int
        /// The commit the run was for.
        var sha: String
        var outcome: Outcome
    }

    /// Why nothing could be read. The red state stays GitHub's; this only says what Dever lacks.
    enum Problem: Equatable {
        case offline, rateLimited, unauthorized, failed
        /// GitHub no longer reports a failed check on the pull request's latest commit.
        case moved

        var text: String {
            switch self {
            case .offline: "Couldn't reach GitHub."
            case .rateLimited: "GitHub asks for fewer requests. Try again in a minute."
            case .unauthorized: "GitHub needs reconnecting."
            case .failed: "Couldn't read the checks."
            case .moved: "No failed check on the latest commit."
            }
        }
    }

    enum Entry: Equatable {
        case loading
        case explained(Explanation)
        case problem(Problem)
    }

    /// What the store needs from outside, so tests run without GitHub and without the model.
    struct Reads: Sendable {
        var failed: @Sendable (_ repository: String, _ number: Int) async throws -> GitHubFailedChecks
        var log: @Sendable (_ repository: String, _ jobID: Int) async throws -> (data: Data, cut: Bool)
        var write: @Sendable (_ job: String, _ step: String?, _ excerpt: PipelineLog.Excerpt) async throws -> String?

        static func live(_ client: GitHubClient) -> Reads {
            Reads(failed: { try await client.failedChecks($0, number: $1) },
                  log: { try await client.jobLogTail($0, jobID: $1, bytes: PipelineLog.tailBytes) },
                  write: { try await FailureExplanation.write(job: $0, step: $1, excerpt: $2) })
        }
    }

    @Published private(set) var entries: [Key: Entry] = [:]
    private var tasks: [Key: Task<Void, Never>] = [:]
    private var following: AnyCancellable?

    /// Whether the feature is switched on; replaced in tests.
    var isOn: () -> Bool = { IntelligencePreferences.isOn(.explainFailure) }

    init(following: Bool = false) {
        guard following else { return }
        // A pull request whose checks are no longer failing has nothing left to explain.
        self.following = GitHubStore.shared.$revision.sink { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    func entry(_ key: Key) -> Entry? { entries[key] }

    /// Someone asked why: reads the failed checks, then the end of the first failed job's log,
    /// then asks the model. Does nothing while an answer is there or on its way; a problem is
    /// tried again.
    func explain(_ key: Key, reads: Reads) {
        guard isOn() else { return drop(key) }
        switch entries[key] {
        case .loading, .explained: return
        case .problem, nil: break
        }
        // Captures: a made-up answer, no network and no model.
        if IntelligenceStatus.snapshotOverride != nil {
            entries[key] = .explained(Self.sample)
            return
        }
        entries[key] = .loading
        tasks[key] = Task { [weak self] in
            await self?.run(key, reads: reads)
            self?.tasks[key] = nil
        }
    }

    private func run(_ key: Key, reads: Reads) async {
        func set(_ entry: Entry) { if !Task.isCancelled, entries[key] != nil { entries[key] = entry } }
        let checks: GitHubFailedChecks
        do {
            checks = try await reads.failed(key.repository, key.number)
        } catch {
            return set(.problem(Self.problem(error)))
        }
        guard let check = checks.first else {
            // The store's copy is behind GitHub: have it read again.
            GitHubStore.shared.invalidate(key.repository)
            return set(.problem(.moved))
        }
        var explanation = Explanation(check: check, others: checks.failed.count - 1, sha: checks.sha, outcome: .writing)
        guard let job = check.jobID else {
            explanation.outcome = .noLog
            return set(.explained(explanation))
        }
        // The job's name shows at once; the sentence follows.
        set(.explained(explanation))
        do {
            let log = try await reads.log(key.repository, job)
            guard let excerpt = PipelineLog.excerpt(PipelineLog.lines(log.data, cut: log.cut)) else {
                explanation.outcome = .doesNotSay
                return set(.explained(explanation))
            }
            guard PipelineLog.statesAnError(excerpt) else {
                explanation.outcome = .doesNotSay
                return set(.explained(explanation))
            }
            let sentence = try? await reads.write(check.name, check.step, excerpt)
            explanation.outcome = sentence.flatMap { $0 }.map(Outcome.sentence) ?? .silent
        } catch is GitHubLogError {
            explanation.outcome = .unreadable
        } catch {
            return set(.problem(Self.problem(error)))
        }
        set(.explained(explanation))
    }

    private static func problem(_ error: Error) -> Problem {
        switch error {
        case AppError.unauthorized, AppError.notConnected: .unauthorized
        case AppError.rateLimited: .rateLimited
        case is URLError: .offline
        default: .failed
        }
    }

    /// The pull requests of `repository` whose checks fail now are `failing`: what was said of
    /// any other is about a run that has been replaced.
    func keep(_ repository: String, failing: Set<Int>) {
        for key in entries.keys where key.repository == repository && !failing.contains(key.number) { drop(key) }
    }

    private func reconcile() {
        for repository in Set(entries.keys.map(\.repository)) {
            guard let held = GitHubStore.shared.repository(repository) else { continue }
            keep(repository, failing: Set(held.state.pulls.filter { ProjectSnapshot.PipelineState(checks: $0.checks) == .failing }.map(\.number)))
        }
    }

    func drop(_ key: Key) {
        tasks.removeValue(forKey: key)?.cancel()
        entries[key] = nil
    }

    /// The switch was turned off, or another account: nothing stays.
    func reset() {
        for key in Array(entries.keys) { drop(key) }
    }

    /// Waits for whatever is being read or written; tests only.
    func settle() async {
        for task in tasks.values { await task.value }
    }

    /// A made-up answer for captures (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static let sample = Explanation(
        check: .init(name: "test (macos-15)", url: "https://github.com/demo/app/actions/runs/1/job/2", jobID: 2,
                     step: "Run tests", completedAt: Date().addingTimeInterval(-12 * 60)),
        others: 1, sha: "0000000",
        outcome: .sentence("testStreakAcrossTimeZoneChange failed: 3 is not equal to 4, the streak should count the day in the new time zone."))
}
