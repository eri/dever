import Foundation

// The parts of a project's Overview row that are worked out, not fetched: from the project's
// issues (`IssueStore`) and its repositories (`GitHubStore`). The refresh cycle and the
// between-cycles follow-up (`OverviewStore.rederive`) both come through here, so a row and
// the project page it opens cannot disagree (docs/data-freshness.md, section 3.1).

/// What Linear says of the project itself, beside its issues.
struct LinearProjectFacts: Equatable {
    var lead: String?
    /// The Linear team the project belongs to (the first, when it spans several).
    var team: String?
    var targetDate: Date?
}

extension ProjectSnapshot.LinearStats {
    init(issues: [LinearIssue], facts: LinearProjectFacts?) {
        self.init()
        count(issues)
        lead = facts?.lead
        team = facts?.team
        targetDate = facts?.targetDate
    }

    /// Counts the issues again; canceled ones are left out. The project's own facts stay.
    mutating func count(_ issues: [LinearIssue]) {
        total = 0; done = 0; inProgress = 0; todo = 0
        for issue in issues {
            switch issue.state.type {
            case "canceled": continue
            case "completed": done += 1
            case "started": inProgress += 1
            default: todo += 1
            }
            total += 1
        }
    }
}

extension ProjectSnapshot.GitHubStats {
    /// One repository's numbers for a project.
    /// - Parameters:
    ///   - issues: the project's issues, which decide which pull requests are its own; nil
    ///     without a Linear project.
    ///   - login: the viewer's GitHub login, for the reviews asked of them.
    init(repository: GitHubStore.Repository, issues: [LinearIssue]?, wholeRepository: Bool, login: String?, now: Date = Date()) {
        self.init()
        let prs = ProjectPullRequests(pulls: repository.state.pulls, issues: issues, wholeRepository: wholeRepository)
        let merged = ProjectPullRequests(pulls: repository.merged, issues: issues, wholeRepository: wholeRepository)
        openPRs = prs.matches.count

        // What waits for you or holds the project back: the pull requests whose review is
        // asked of you, the one waiting longest, and the latest merge.
        let me = login?.lowercased()
        for m in prs.matches {
            let pull = m.pull
            let updated = Self.iso(pull.updated_at) ?? now
            let reviewers = pull.requested_reviewers ?? []
            if let me, reviewers.contains(where: { $0.login.lowercased() == me }) {
                reviewRequests.append(.init(number: pull.number, title: pull.title, url: pull.html_url, issue: m.issue, date: updated))
            }
            if pull.draft != true, !reviewers.isEmpty, now.timeIntervalSince(updated) > 3 * 86_400,
               updated < (longWait?.since ?? .distantFuture) {
                longWait = (pull.number, updated)
            }
        }
        // The merges of this project only (the same matching as the open ones).
        if let last = merged.matches.compactMap({ m in m.pull.merged_at.flatMap(Self.iso).map { (m.pull, $0) } }).max(by: { $0.1 < $1.1 }) {
            lastMerged = (last.0.number, last.0.user.login, last.1)
        }

        if prs.scoped, let issues {
            let mergedIDs = Set(ProjectPullRequests(pulls: repository.merged, issues: issues, wholeRepository: false)
                .matches.compactMap(\.issue))
            pipeline = prs.pipeline
            scoped = true
            // Merged in code while the ticket still says "in progress" (review states are fine).
            mergedButOpen = issues.filter {
                Delivery.isBehind(stateType: $0.state.type, stateName: $0.state.name, merged: mergedIDs.contains($0.identifier))
            }.map(\.identifier).sorted()
            openPRIssues = Set(prs.matches.compactMap(\.issue))
            mergedPRIssues = mergedIDs
        } else {
            // Unscoped: the health of the default branch, not of whichever branch ran last.
            pipeline = .init(checks: repository.state.defaultBranchChecks)
            branch = repository.state.defaultBranch
        }
    }

    /// A project's numbers across the repositories it follows.
    static func project(repositories: [(name: String, data: GitHubStore.Repository)], issues: [LinearIssue]?,
                        wholeRepository: Bool, login: String?, now: Date = Date()) -> Self {
        let parts = repositories.map { (repo: $0.name, stats: Self(repository: $0.data, issues: issues,
                                                                 wholeRepository: wholeRepository, login: login, now: now)) }
        var combined = Self.combined(parts)
        combined.repositories = repositories.map(\.name)
        if parts.count == 1, combined.pipeline == .failing { combined.failingRepositories = combined.repositories }
        return combined
    }

    private static func iso(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}

extension Delivery {
    /// The project's issues by stage, joined with what GitHub says of their pull requests.
    init(issues: [LinearIssue], github: ProjectSnapshot.GitHubStats?) {
        self.init(issues: issues.map { ($0.identifier, $0.state.type, $0.state.name) },
                  openPR: github?.openPRIssues ?? [], mergedPR: github?.mergedPRIssues ?? [])
    }
}
