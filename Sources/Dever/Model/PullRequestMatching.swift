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
