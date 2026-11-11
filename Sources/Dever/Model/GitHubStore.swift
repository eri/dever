import Foundation

/// What Dever knows of each repository, one copy for the app: the Overview and every project
/// page that follows the repository read the same pull requests, checked at the same moment.
/// Which of them belong to a project is worked out by the reader (`ProjectPullRequests`).
@MainActor
final class GitHubStore: ObservableObject {
    static let shared = GitHubStore()

    struct Repository {
        /// Open pull requests with their checks and reviews, and the default branch.
        var state: GitHubRepositoryState
        /// Pull requests merged recently, newest first.
        var merged: [GitHubPull]
    }

    /// Moves each time a repository's entry changes; readers that derive from the store watch it.
    @Published private(set) var revision = 0
    private let cache = ResourceCache<String, Repository>()

    init() {
        cache.onChange = { [weak self] in self?.revision += 1 }
    }

    func repository(_ repo: String) -> Repository? { cache.value(repo) }
    /// When the repository was last read with success.
    func fetchedAt(_ repo: String) -> Date? { cache.fetchedAt(repo) }
    /// Why its latest refresh failed, if it did.
    func failure(_ repo: String) -> Error? { cache.failure(repo) }

    /// The repository, read again unless it was read within `maxAge` (two requests, sent
    /// together). Readers asking at the same moment share them.
    func load(_ repo: String, client: GitHubClient, maxAge: TimeInterval) async throws -> Repository {
        try await cache.value(repo, maxAge: maxAge) {
            async let merged = client.mergedPulls(repo)
            let state = try await client.repository(repo)
            return Repository(state: state, merged: try await merged)
        }
    }

    /// Reads the checks of the pull requests `numbers` again and puts them on the pull
    /// requests held: what a screen asks every few seconds while checks are running. True
    /// when one of them is no longer open (merged or closed): the repository is then marked
    /// to be read in full.
    @discardableResult
    func refreshChecks(_ repo: String, numbers: [Int], client: GitHubClient) async throws -> Bool {
        let found = try await client.checks(repo, numbers: numbers)
        let changed = cache.value(repo)?.state.pulls.contains { pull in
            found[pull.number].map { $0.checks != pull.checks } ?? false
        } ?? false
        if changed {
            cache.update(repo) { held in
                for i in held.state.pulls.indices {
                    if let now = found[held.state.pulls[i].number] { held.state.pulls[i].checks = now.checks }
                }
            }
        }
        let gone = found.values.contains { !$0.open }
        if gone { cache.invalidate(repo) }
        return gone
    }

    /// A pull request of `repo` was opened on GitHub: the next reader fetches whatever its age.
    func invalidate(_ repo: String) { cache.invalidate(repo) }

    /// Another account, or none: nothing of the previous one stays.
    func reset() { cache.removeAll() }
}
