import Foundation

/// Narrows a repository's pull requests and pipeline runs down to one project,
/// using the project's Linear issues. Needed when several projects share a
/// repository (monorepo): a PR belongs to the project when Linear attached it to
/// one of the project's issues, when its branch is the issue's suggested branch,
/// or when its branch or title mentions an issue identifier such as `ENG-123`.
struct ProjectPullRequests {
    struct Match: Identifiable {
        var pull: GitHubPull
        /// Identifier of the Linear issue the PR was matched to (nil when unscoped).
        var issue: String?
        var id: Int { pull.id }
    }

    var matches: [Match]
    /// True when the list is limited to the project's issues, false for the whole repository.
    var scoped: Bool

    var branches: Set<String> { Set(matches.map(\.pull.head.ref)) }

    /// A whole-repository project keeps every pull request, matched to an issue where one
    /// cites it (so its row can still show the PR) and unmatched otherwise.
    init(pulls: [GitHubPull], issues: [IssueReference]?, wholeRepository: Bool) {
        guard let issues else {
            matches = pulls.map { Match(pull: $0, issue: nil) }
            scoped = false
            return
        }
        scoped = !wholeRepository

        var byIdentifier: [String: String] = [:]
        var byBranch: [String: String] = [:]
        var byURL: [String: String] = [:]
        for issue in issues {
            byIdentifier[issue.identifier.lowercased()] = issue.identifier
            if let branch = issue.branchName?.lowercased(), !branch.isEmpty { byBranch[branch] = issue.identifier }
            for node in issue.attachments?.nodes ?? [] { byURL[Self.normalized(node.url)] = issue.identifier }
        }

        matches = pulls.compactMap { pull in
            if let id = byURL[Self.normalized(pull.html_url)] ?? byBranch[pull.head.ref.lowercased()] {
                return Match(pull: pull, issue: id)
            }
            for token in Self.identifierTokens(in: pull.head.ref + " " + pull.title) {
                if let id = byIdentifier[token] { return Match(pull: pull, issue: id) }
            }
            return wholeRepository ? Match(pull: pull, issue: nil) : nil
        }
    }

    /// Pipeline state of the project's pull requests: the worst of their checks.
    var pipeline: ProjectSnapshot.PipelineState {
        ProjectSnapshot.PipelineState.worst(matches.map { ProjectSnapshot.PipelineState(checks: $0.pull.checks) })
    }

    /// Pull requests of `repo` that Linear attached to the issues, by number. Covers PRs
    /// merged long ago, beyond what the GitHub scan of recent pull requests reaches.
    static func linkedPullRequests(in repo: String, issues: [IssueReference]) -> [(number: Int, url: String, issue: String)] {
        let prefix = "https://github.com/\(repo.lowercased())/pull/"
        var seen = Set<Int>()
        var out: [(number: Int, url: String, issue: String)] = []
        for issue in issues {
            for node in issue.attachments?.nodes ?? [] {
                let url = node.url.lowercased()
                guard url.hasPrefix(prefix),
                      let number = Int(url.dropFirst(prefix.count).prefix { $0.isNumber }),
                      seen.insert(number).inserted else { continue }
                out.append((number, node.url, issue.identifier))
            }
        }
        return out.sorted { $0.number > $1.number }
    }

    private static func normalized(_ url: String) -> String {
        url.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static let identifierPattern = try! NSRegularExpression(pattern: "[a-z][a-z0-9]*-[0-9]+", options: [.caseInsensitive])

    private static func identifierTokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return identifierPattern.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { text[$0].lowercased() }
        }
    }
}

extension GitHubPull {
    /// `owner/name`, read off the pull request's own URL.
    var repository: String { GitHubRepository.name(fromURL: html_url) }
}

/// A repository name as GitHub writes it, `owner/name`.
enum GitHubRepository {
    static func name(fromURL url: String) -> String {
        let parts = url.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // https: / github.com / owner / name / pull / N
        guard let host = parts.firstIndex(where: { $0.contains("github.com") }), parts.count > host + 2 else { return "" }
        return parts[host + 1] + "/" + parts[host + 2]
    }

    /// The part after the slash: what a row shows when every repository shares an owner.
    static func short(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
}

extension ProjectSnapshot.PipelineState {
    /// From GitHub's rollup of a commit's checks; nil (no checks at all) is unknown.
    init(checks: String?) {
        switch checks {
        case "SUCCESS": self = .passing
        case "FAILURE", "ERROR": self = .failing
        case "PENDING", "EXPECTED": self = .running
        default: self = .unknown
        }
    }
}

extension GitHubPull {
    /// Where the pull request's checks are listed on GitHub.
    var checksURL: String { html_url + "/checks" }
}

/// A merged pull request of the project, from GitHub's recent history or, for older
/// ones, from the links Linear attached to the project's issues.
struct MergedPull: Identifiable {
    var number: Int
    var title: String?
    var url: String
    var issue: String?
    var mergedAt: Date?
    var id: String { url }
    var repository: String { GitHubRepository.name(fromURL: url) }

    static func list(repo: String, recentlyMerged: [GitHubPull], issues: [IssueReference]?,
                     wholeRepository: Bool, open: Set<Int>) -> [MergedPull] {
        let matched = ProjectPullRequests(pulls: recentlyMerged, issues: issues, wholeRepository: wholeRepository)
        let iso = ISO8601DateFormatter()
        var items = matched.matches.map {
            MergedPull(number: $0.pull.number, title: $0.pull.title, url: $0.pull.html_url,
                       issue: $0.issue, mergedAt: $0.pull.merged_at.flatMap(iso.date(from:)))
        }
        guard matched.scoped, let issues else { return items }
        // Older PRs Linear knows about, minus those already listed or still open.
        let known = Set(items.map(\.number)).union(open)
        items += ProjectPullRequests.linkedPullRequests(in: repo, issues: issues)
            .filter { !known.contains($0.number) }
            .map { MergedPull(number: $0.number, title: nil, url: $0.url, issue: $0.issue, mergedAt: nil) }
        return items
    }
}

/// A project's pull requests across its repositories, worked out from what `GitHubStore`
/// holds for each: the open ones matched to its issues, the merged ones, newest first.
struct ProjectPulls {
    var open: [ProjectPullRequests.Match] = []
    var merged: [MergedPull] = []
    /// True when the lists are limited to the project's Linear issues.
    var scoped = false

    init() {}

    init(repositories: [(name: String, data: GitHubStore.Repository)], issues: [IssueReference]?, wholeRepository: Bool) {
        for (name, data) in repositories {
            let prs = ProjectPullRequests(pulls: data.state.pulls, issues: issues, wholeRepository: wholeRepository)
            open += prs.matches
            scoped = scoped || prs.scoped
            merged += MergedPull.list(repo: name, recentlyMerged: data.merged, issues: issues,
                                      wholeRepository: wholeRepository, open: Set(prs.matches.map(\.pull.number)))
        }
        merged.sort { ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast) }
    }
}
