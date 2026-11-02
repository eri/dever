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

    init(pulls: [GitHubPull], issues: [IssueReference]?, wholeRepository: Bool) {
        guard let issues, !wholeRepository else {
            matches = pulls.map { Match(pull: $0, issue: nil) }
            scoped = false
            return
        }
        scoped = true

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
            return nil
        }
    }

    /// Pipeline state of the project's PR branches: the latest run of each branch counts.
    func pipeline(from runs: [GitHubRun]) -> (state: ProjectSnapshot.PipelineState, latest: [GitHubRun]) {
        let wanted = branches
        var seen = Set<String>()
        // Runs come newest first, so the first run per branch is its latest.
        let latest = runs.filter { run in
            guard let branch = run.head_branch, wanted.contains(branch), !seen.contains(branch) else { return false }
            seen.insert(branch)
            return true
        }
        let states = latest.map(ProjectSnapshot.PipelineState.init(run:))
        let state: ProjectSnapshot.PipelineState =
            states.contains(.failing) ? .failing
            : states.contains(.running) ? .running
            : states.contains(.passing) ? .passing
            : .unknown
        return (state, latest)
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

extension ProjectSnapshot.PipelineState {
    init(run: GitHubRun) {
        if run.status != "completed" {
            self = .running
        } else {
            self = run.conclusion == "success" ? .passing : .failing
        }
    }
}

/// A merged pull request of the project, from GitHub's recent history or, for older
/// ones, from the links Linear attached to the project's issues.
struct MergedPull: Identifiable {
    var number: Int
    var title: String?
    var url: String
    var issue: String?
    var mergedAt: Date?
    var id: Int { number }

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
