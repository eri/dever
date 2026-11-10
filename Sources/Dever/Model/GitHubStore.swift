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

    /// A pull request of `repo` was opened on GitHub: the next reader fetches whatever its age.
    func invalidate(_ repo: String) { cache.invalidate(repo) }

    /// Another account, or none: nothing of the previous one stays.
    func reset() { cache.removeAll() }
}
