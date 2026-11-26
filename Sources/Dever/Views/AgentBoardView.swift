import SwiftUI

/// Every agent session Dever hears on this Mac, across projects: what waits for you first, each
/// tied to its issue. Under them, the worktrees Dever made, with the ones that can go. The board
/// lists and opens; it starts and steers nothing.
struct AgentBoardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var agents = AgentStore.shared
    @ObservedObject private var issues = IssueStore.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var proposals = ProposalStore.shared
    @State private var worktrees: [AgentWorktreeEntry]?
    @State private var removing: String?
    @State private var problem: String?

    private var groups: [AgentBoard.Group] {
        // Active projects first; the sessions left on a done project come after them.
        AgentBoard.groups(sessions: Array(agents.sessions.values), projects: app.activeProjects + app.doneProjects) { project in
            // Canary's project lists its made-up issues.
            if Canary.isOn, project.id == Canary.projectID { return DeliveryPlan.canaryIssues }
            return project.linear.map { issues.issues(project: $0.id) } ?? []
        }
    }
    private var followed: Bool { AgentTool.allCases.contains(where: AgentPreferences.followed) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Agents").font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("What your coding agents are doing on this Mac. What waits for you comes first.")
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    .padding(.top, 4).padding(.bottom, 24)
                if groups.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in section(group) }
                    }
                }
                worktreeSection
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Soot.ground)
        .navigationTitle("Agents")
        .windowTitleHidden()
        .task { await scan() }
    }

    @ViewBuilder private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuietEmpty(symbol: followed ? "moon.zzz" : "antenna.radiowaves.left.and.right.slash",
                       text: followed ? "No session open right now" : "Dever follows no agent yet")
            if !followed {
                Button("Follow an agent in Settings") {
                    openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .showSettingsSection, object: SettingsView.Section.agents.rawValue)
                    }
                }
                .buttonStyle(SecondaryButton())
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func section(_ group: AgentBoard.Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.project?.name ?? "Other folders").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                // A session left open on a project marked as done: nothing waits there any more.
                if group.project?.isDone == true {
                    Pill(text: "Done", tone: .neutral)
                    Text("Left over: close the session when you no longer need it")
                        .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 6) {
                        if let issue = row.issue, let project = group.project {
                            NavigationLink(value: IssueRoute(project: project, issue: issue)) {
                                HStack(spacing: 8) {
                                    IDPill(text: issue.identifier)
                                    Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Soot.ink).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                            }
                            .buttonStyle(RowButton(lift: .ground, radius: 8))
                            .padding(.horizontal, -8)
                            .accessibilityHint("Opens the issue")
                        } else {
                            // No issue of a followed project has this branch: the folder says where it is.
                            HStack(spacing: 8) {
                                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Soot.muted).accessibilityHidden(true)
                                Text(verbatim: row.session.cwd.map { ($0 as NSString).lastPathComponent } ?? "Unknown folder")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                                if let branch = row.session.branch {
                                    Text(verbatim: branch).font(.system(size: 12, design: .monospaced)).foregroundStyle(Soot.muted).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        AgentSessionLine(session: row.session, lift: Soot.ground,
                                         hasProposal: row.issue.map { proposals.proposal(for: $0.identifier) != nil } ?? false)
                        if let issue = row.issue, let proposal = proposals.proposal(for: issue.identifier) {
                            Text(proposal.summary).font(.system(size: 13)).foregroundStyle(Soot.ink.opacity(0.85))
                                .lineLimit(2).padding(.leading, 23)
                        }
                    }
                    .padding(.vertical, 12)
                    if index < group.rows.count - 1 { Rectangle().fill(Soot.line).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Worktrees

    /// Branches whose pull request is merged, per repository, as GitHub was last read.
    private func merged(_ repository: String) -> Set<String> {
        let known = github.repository(repository) ?? app.projects.flatMap { app.repositories(for: $0) }
            .first { $0.lowercased() == repository.lowercased() }.flatMap { github.repository($0) }
        return Set((known?.merged ?? []).map { $0.head.ref.lowercased() })
    }

    /// The branches of the issues of done projects, as far as their issues are held.
    private var doneBranches: Set<String> {
        Set(app.doneProjects.flatMap { p in p.linear.map { issues.issues(project: $0.id) } ?? [] }
            .compactMap { $0.branchName?.lowercased() }.filter { !$0.isEmpty })
    }

    @ViewBuilder private var worktreeSection: some View {
        if let worktrees, !worktrees.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Worktrees").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                    .padding(.top, 32)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, entry in
                        let standing = entry.standing(sessions: Array(agents.sessions.values), mergedBranches: merged(entry.repository),
                                                      doneBranches: doneBranches)
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Soot.muted).frame(width: 18).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: entry.branch ?? entry.path.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Soot.ink).lineLimit(1)
                                Text(verbatim: "\(entry.repository) · \((entry.path.path as NSString).abbreviatingWithTildeInPath)")
                                    .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            switch standing {
                            case .removable:
                                Button(removing == entry.id ? "Removing…" : "Remove") { remove(entry) }
                                    .buttonStyle(DestructiveButton())
                                    .disabled(removing != nil)
                                    .help("Its pull request is merged and nothing is left in it. The branch stays.")
                                    .accessibilityLabel("Remove the worktree of \(entry.branch ?? entry.path.lastPathComponent)")
                            case .leftover:
                                Text("Project done").font(.system(size: 13)).foregroundStyle(Soot.muted)
                                Button(removing == entry.id ? "Removing…" : "Remove") { remove(entry) }
                                    .buttonStyle(DestructiveButton())
                                    .disabled(removing != nil)
                                    .help("Its project is marked as done and nothing uncommitted is left in it. The branch stays.")
                                    .accessibilityLabel("Remove the worktree of \(entry.branch ?? entry.path.lastPathComponent), left from a done project")
                            case .inUse(let tool):
                                Text("\(tool.label) is in it").font(.system(size: 13)).foregroundStyle(Soot.muted)
                            case .uncommitted:
                                Text("Uncommitted work").font(.system(size: 13)).foregroundStyle(Theme.chart3)
                            case .notMerged:
                                Text("Not merged").font(.system(size: 13)).foregroundStyle(Soot.muted)
                            }
                        }
                        .frame(minHeight: 56)
                        .accessibilityElement(children: .combine)
                        if index < worktrees.count - 1 { Rectangle().fill(Soot.line).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
                Text(problem ?? "Made by Dever beside your clones. One can go once its pull request is merged and nothing uncommitted is left in it.")
                    .font(.system(size: 12)).foregroundStyle(problem == nil ? Soot.muted : Theme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scan() async {
        let clones = AgentPreferences.clones
        worktrees = await Task.detached(priority: .utility) { AgentWorktrees.scan(clones: clones) }.value
        // Done projects are no longer read behind the scenes: with worktrees to judge, their
        // issues are read once here (an hour at most apart), to know which branches were theirs.
        guard worktrees?.isEmpty == false, Snapshotter.directory == nil else { return }
        for project in app.doneProjects {
            if let linear = project.linear?.id { _ = try? await issues.load(project: linear, maxAge: 3600, app: app) }
        }
    }

    private func remove(_ entry: AgentWorktreeEntry) {
        removing = entry.id
        problem = nil
        Task {
            do {
                try await Task.detached { try AgentWorktrees.remove(entry) }.value
            } catch {
                problem = "Not removed: \(error.localizedDescription)"
            }
            removing = nil
            await scan()
        }
    }
}
