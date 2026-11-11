import SwiftUI

/// One project. Its question: what is left to ship, and what needs closing?
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    let project: Project
    let edit: () -> Void

    @ObservedObject private var issueStore = IssueStore.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var slackStore = SlackStore.shared
    @ObservedObject private var intelligence = IntelligenceStore.shared
    @ObservedObject private var intelligenceStatus = IntelligenceStatus.shared
    /// What the catch-up of the rail is written from; nil when there is none to write.
    @State private var catchUp: CatchUp.Input?
    @State private var shownMessages = 8
    @State private var loadingEarlier = false
    @State private var slackExpanded = false
    /// The room is built once, after the panel's first growth, then kept (see `toggleSlackWide`).
    @State private var roomMounted = false
    @State private var roomMount: Task<Void, Never>?
    @State private var slackFocus: String?
    /// Slack's read cursor for the channel (nil until known) and the newest message that has
    /// been on screen in the room: one timestamp each, nothing else is remembered.
    @State private var markTask: Task<Void, Never>?
    @State private var previewFile: SlackFile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The project's pull requests, worked out from `GitHubStore` each time it or the issues
    /// change (`derivePulls`): the matching is too much to redo on every render.
    @State private var pulls: [ProjectPullRequests.Match] = []
    @State private var pullsScoped = false
    @State private var merged: [MergedPull] = []
    /// Why a panel has nothing: not connected, token rejected, offline, or a failure.
    @State private var states: [ServiceKind: ServiceState] = [:]
    /// When each service last loaded on this page, for the failure rows.
    @State private var lastLoaded: [ServiceKind: Date] = [:]
    @StateObject private var flow = ConnectFlow()
    /// A refresh that failed while its panel had something to show: the panel keeps it and
    /// the line under the title says how old it is.
    @State private var refreshFailed: [ServiceKind: ServiceState] = [:]
    @State private var loading = false
    @State private var loaded = false
    /// A load is running (asked for, or the quiet one that keeps the page current).
    @State private var inFlight = false
    @State private var lastLoad: Date?
    /// When each kind of data was last read by the page's own cadence, and how many reads
    /// in a row each tool has failed (its next one waits longer).
    @State private var polled: [RefreshCadence.Kind: Date] = [:]
    @State private var pollFailures: [ServiceKind: Int] = [:]
    /// The clock the age line is read against, moved by the page's own tick.
    @State private var now = Date()
    @State private var expanded: Set<String> = []

    private var status: ProjectStatus { project.status(store.snapshots[project.id]) }

    /// Opens the project editor on one of its steps: "Link Linear" lands on the Linear picker.
    private func link(_ step: ProjectEditorSheet.Step) {
        ProjectEditorSheet.openAt = step
        edit()
    }

    /// The linked tools with no token: one missing gets its invitation inside its panel,
    /// several get one section at the top and quiet placeholders in the panels.
    private var missing: [ServiceKind] { app.missingServices(for: project) }
    private var linkedServices: [ServiceKind] {
        [project.slack != nil ? .slack : nil, project.linear != nil ? .linear : nil, repos.isEmpty ? nil : .github]
            .compactMap { $0 }
    }
    /// The repositories the project follows under the workspace's repository mode.
    private var repos: [String] { app.repositories(for: project) }
    /// Rows name their repository once the project follows more than one.
    private var labelsRepository: Bool { repos.count > 1 }
    /// Reloads when a token arrives or the project's links change (the editor's Save), so a
    /// panel fills in without leaving the page.
    private var connectionKey: String {
        "\(app.slack != nil)-\(app.linear != nil)-\(app.github != nil)"
            + "-\(project.slack?.id ?? "")-\(project.linear?.id ?? "")-\(repos.joined(separator: ","))"
    }

    // The conversation lives in `SlackStore`, by channel: the page keeps only what is about
    // the page (how many messages are shown, the open room, the focus).
    private var channel: SlackStore.Channel? { project.slack.flatMap { slackStore.channels[$0.id] } }
    /// Newest first.
    private var messages: [SlackMessage] { channel?.messages ?? [] }
    private var hasEarlier: Bool { channel?.hasEarlier ?? false }
    /// Slack's read cursor for the channel (nil until known) and the newest message that has
    /// been on screen in the room.
    private var lastRead: String? { channel?.lastRead }
    private var seenUpTo: String? { channel?.seenUpTo }
    private var users: [String: SlackUser] { slackStore.users }
    private var customEmoji: [String: URL] { slackStore.customEmoji }
    /// Names of channels linked from the messages, for "Estelle in #other-channel".
    private var linkedChannels: [String: String] { slackStore.channelNames }
    /// The Slack panel has something to show: the page loaded, or the store holds the channel.
    private var slackLoaded: Bool { loaded || channel?.fetchedAt != nil }

    private var issues: [LinearIssue] { project.linear.map { issueStore.issues(project: $0.id) } ?? [] }

    var body: some View {
        GeometryReader { geo in
            // The same two columns as the skeleton, loaded or not: the work on the left,
            // the conversation alongside it. Below ~1000px they stack.
            let twoColumns = geo.size.width >= 1000
            // In the wide view the page stops scrolling: the messages scroll inside their
            // panel and the thread pane stays put beside them. Same ScrollView either way,
            // so the panel's state (open thread, draft) survives the switch.
            // The Slack panel's content width in each layout, so the messages are laid out at
            // their final width while the panel grows or shrinks around them (no reflow).
            let railWidth = twoColumns ? min(420, geo.size.width * 0.34) : geo.size.width - 56
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    titleRow
                    if !agedData.isEmpty {
                        AgeNotice(items: agedData, refreshing: inFlight, retry: { Task { await load(quiet: true) } })
                            .padding(.top, -12)
                            .transition(.opacity)
                    }
                    if missing.count > 1 {
                        ConnectSection(project: project, services: linkedServices, flow: flow)
                    }
                    // The Slack panel keeps one place in the hierarchy whichever layout is on,
                    // so open threads and a half-written reply survive a switch to the wide view.
                    // Opening the room: the work column slides out to the left as the panel
                    // grows over its place (one spring, ~350 ms); the reverse on the way back.
                    // The work column is never torn down either: while the room is open it stays
                    // laid out at its width under the panel, faded and slid 40 pt aside, so Back
                    // only animates it back instead of rebuilding every row.
                    if twoColumns {
                        let workWidth = max(0, geo.size.width - 56 - railWidth - 16)
                        ZStack(alignment: .topTrailing) {
                            workColumn
                                .frame(width: workWidth, alignment: .topLeading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .frame(height: slackExpanded ? 0 : nil, alignment: .top)
                                .opacity(slackExpanded ? 0 : 1)
                                .offset(x: slackExpanded && !reduceMotion ? -40 : 0)
                                .allowsHitTesting(!slackExpanded)
                                .accessibilityHidden(slackExpanded)
                            slackPanel(railWidth: railWidth - 40, wideWidth: geo.size.width - 56 - 40)
                                .frame(width: slackExpanded ? geo.size.width - 56 : railWidth)
                                .frame(maxHeight: slackExpanded ? .infinity : nil, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            if !slackExpanded {
                                workColumn.transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(y: -24)))
                            }
                            slackPanel(railWidth: railWidth - 40, wideWidth: geo.size.width - 56 - 40)
                                .frame(maxHeight: slackExpanded ? .infinity : nil, alignment: .top)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(width: geo.size.width, height: slackExpanded ? geo.size.height : nil, alignment: .topLeading)
            }
            .scrollDisabled(slackExpanded)
        }
        .background(Soot.ground)
        .modifier(FilePreviewHost(preview: $previewFile))
        .navigationTitle(project.name)
        .windowTitleHidden()
        // What the stores already hold shows at once: no skeleton for a project seen before.
        .onAppear {
            if derivePulls() { lastLoaded[.github] = githubReadAt }
            if let at = channel?.fetchedAt { lastLoaded[.slack] = at }
        }
        // The repository was read again, here or by the Overview's cycle: the page follows.
        .onChange(of: github.revision) { _, _ in
            guard derivePulls(), let at = githubReadAt else { return }
            lastLoaded[.github] = at
            if !repos.contains(where: { github.failure($0) != nil }) { refreshFailed[.github] = nil }
        }
        .task {
            // Back from an issue page with data read a moment ago: nothing to fetch.
            if LookAgain.shared.isDue(lastLoad) { await load(quiet: loaded) }
            await land()
            await keepCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lookAgain)) { _ in
            now = Date()
            if LookAgain.shared.isDue(lastLoad) { Task { await load(quiet: true) } }
        }
        .sheet(isPresented: $flow.githubSheet) { GitHubLoginSheet() }
        .onChange(of: catchUpTrigger, initial: true) { _, _ in
            refreshCatchUp()
            refreshMessageSummaries()
        }
        // Another channel: the messages and the read cursor of the previous one do not carry over.
        .onChange(of: project.slack?.id) { _, _ in
            shownMessages = 8
            lastLoaded[.slack] = channel?.fetchedAt
        }
        .onChange(of: connectionKey) { _, _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSlackWide)) { _ in toggleSlackWide() }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstIssue)) { _ in
            let plan = self.plan
            if let first = plan.start?.issue ?? plan.next.first?.issue ?? plan.others.first?.issue ?? plan.shipped.first?.issue {
                NotificationCenter.default.post(name: .openIssue, object: IssueRoute(project: project, issue: first))
            }
        }
    }

    private var workColumn: some View {
        VStack(spacing: 16) {
            // Skeletons dissolve into the loaded panels; the panels resize in the same 200 ms.
            // Scoped to `loaded`, so nothing else on the page animates with it.
            // The preview first: it is the thing to open or to deploy, and it stays one or two lines.
            if app.showsPreview(project) {
                PreviewPanel(project: project, missing: missing, flow: flow,
                             addPreview: { link(.preview) },
                             dismiss: {
                                 var p = project
                                 p.previewDismissed = true
                                 app.upsert(p)
                             })
            }
            workPanel
        }
        .motion(Motion.ui, fade: true, value: loaded)
    }

    // MARK: Title row

    /// The page's toolbar: name and status, the linked tools as chips, and on the right the
    /// two actions on the project itself. Its height does not depend on what has loaded.
    private var titleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.name).font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                        .foregroundStyle(Soot.ink)
                        .lineLimit(1)
                        .help(project.name)
                        .accessibilityAddTraits(.isHeader)
                    if status == .loading { Skeleton(width: 72, height: 20, radius: 4).transition(.opacity) }
                    else { StatusBadge(status: status).transition(.opacity) }
                }
                .motion(Motion.ui, fade: true, value: status == .loading)
                linkRow
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button { Task { await load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ToolbarButton(busy: loading))
                .disabled(loading)
                .help("Refresh this project (⌘R)")
                .accessibilityLabel("Refresh this project")
                .accessibilityValue(loading ? "Refreshing" : "")
                .keyboardShortcut("r")
                Button(action: edit) {
                    Label("Edit project", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(ToolbarButton())
                .help("Change the name and linked tools (⌘E)")
                .accessibilityLabel("Edit project")
                .keyboardShortcut("e")
            }
            .fixedSize()
            .padding(.top, 4)
        }
    }

    private var slackURL: URL? {
        guard let channel = project.slack, let slack = app.slack else { return nil }
        return URL(string: "https://\(slack.domain).slack.com/archives/\(channel.id)")
    }

    /// The linked tools, each a chip that opens it. A tool linked but not reachable (no
    /// Slack domain yet) keeps its chip, so the row reads the same in every state.
    private var linkRow: some View {
        HStack(spacing: 4) {
            if let channel = project.slack {
                ToolChip(service: .slack, text: "#\(channel.name)", url: slackURL)
            }
            if let linear = project.linear {
                ToolChip(service: .linear, text: linear.name, url: URL(string: linear.url))
            }
            ForEach(repos, id: \.self) { repo in
                ToolChip(service: .github, text: repo, url: URL(string: "https://github.com/\(repo)"))
            }
            if !project.isComplete {
                Button { link(project.slack == nil ? .slack : .linear) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("Link a tool")
                    }
                }
                .buttonStyle(TertiaryButton(lift: Soot.surface, font: .system(size: 13, weight: .medium)))
                .help("Link a Slack channel, a Linear project or a GitHub repository")
            }
        }
        .padding(.leading, -8)
        .frame(height: 28)
    }

    // MARK: Work (the signature block)

    private var linearURL: URL? { project.linear.flatMap { URL(string: $0.url) } }
    /// The open pull requests of the project's repositories on GitHub: one repository's page,
    /// or a search across several.
    private var pullsURL: URL? {
        if repos.count == 1, let repo = repos.first { return URL(string: "https://github.com/\(repo)/pulls") }
        let query = (["is:pr", "is:open"] + repos.map { "repo:\($0)" }).joined(separator: "+")
        return URL(string: "https://github.com/pulls?q=\(query)")
    }

    /// The project's issues from the viewer's seat: what to pick up, what waits, what shipped.
    private var plan: DeliveryPlan {
        if let demo = DeliveryPlan.snapshotDemo { return demo }
        let open = Dictionary(grouping: pulls.filter { $0.issue != nil }, by: { $0.issue! }).mapValues { matches in
            matches.map { m in
                DeliveryPlan.Pull(number: m.pull.number, title: m.pull.title, url: m.pull.html_url,
                                         repository: m.pull.repository, draft: m.pull.draft == true, author: m.pull.user.login,
                                         updatedAt: DeliveryPlan.date(m.pull.updated_at),
                                         pipeline: pipeline(of: m.pull), runURL: m.pull.checksURL,
                                         review: DeliveryPlan.review(verdicts: m.pull.verdicts),
                                         requested: m.pull.requested_reviewers?.map(\.login) ?? [])
            }
        }
        return DeliveryPlan(issues: issues, open: open,
                            merged: Dictionary(grouping: merged.filter { $0.issue != nil }, by: { $0.issue! }),
                            blockers: project.linear.flatMap { issueStore.blockers[$0.id] } ?? [:],
                            viewer: .init(linearID: issueStore.viewerID, linearName: app.linear?.account.userName,
                                          githubLogin: app.github?.login))
    }

    /// Pull requests of the repository that no issue of the project cites (whole-repository
    /// projects, or a project with no Linear): they keep their own list under the issues.
    private var unlinkedOpen: [ProjectPullRequests.Match] { pulls.filter { $0.issue == nil } }
    private var unlinkedMerged: [MergedPull] { merged.filter { $0.issue == nil } }

    /// The state of the pull request's own checks; nil when its head commit has none.
    private func pipeline(of pull: GitHubPull) -> ProjectSnapshot.PipelineState? {
        pull.checks == nil ? nil : ProjectSnapshot.PipelineState(checks: pull.checks)
    }

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if project.linear != nil, connectsLinearInHeader {
                // Not connected: the header is the invitation, as in the Preview panel. Nothing
                // under it, and no pull requests either when they are matched through the issues.
                PanelHeader(service: .linear, title: "Delivery", subtitle: ConnectPitch.line(.linear, for: project)) {
                    ConnectControl(service: .linear, flow: flow)
                }
            } else if project.linear != nil {
                PanelHeader(service: .linear, title: "Delivery", subtitle: "What is left, and where to start",
                            link: linearURL, linkHelp: "Open the project in Linear")
            } else {
                PanelHeader(service: .github, title: "Pull requests",
                            subtitle: repos.isEmpty ? "No repository yet" : repos.joined(separator: " · "),
                            link: repos.isEmpty ? nil : pullsURL, linkHelp: "Open the pull requests on GitHub")
            }
            if project.linear == nil && repos.isEmpty {
                PanelEmpty(service: .linear, line: "Link a tool to see the work here",
                           primary: ("Link Linear", { link(.linear) }),
                           quiet: app.repositoryMode == .single ? nil : ("Link a repository", { link(.github) }),
                           primaryHelp: "Pick the Linear project whose issues this project tracks",
                           quietHelp: "Pick the GitHub repositories this project follows")
            } else if !workLoaded, states[.linear] == nil, states[.github] == nil {
                workSkeleton
            } else {
                if project.linear != nil { linearPart }
                if !repos.isEmpty {
                    githubPart
                } else if app.repositoryMode != .single, states[.linear] == nil {
                    PanelEmpty(service: .github, line: "Link a repository to see its pull requests",
                               primary: ("Link a repository", { link(.github) }),
                               primaryHelp: "Pick the GitHub repositories this project follows")
                }
            }
        }
        // Skeleton, invitation and content hand over with a dissolve, on load and when the
        // editor links the missing tool.
        .motion(Motion.ui, fade: true, value: workLoaded)
        .motion(Motion.ui, fade: true, value: project.linear == nil)
        .motion(Motion.ui, fade: true, value: repos.isEmpty)
        .sootPanel()
    }

    /// Linear is the only tool missing: its invitation sits in the panel's header.
    private var connectsLinearInHeader: Bool { states[.linear] == .notConnected && missing.count <= 1 }

    /// What is left, where to start, then the rest: see `DeliveryBoard`.
    @ViewBuilder
    private var linearPart: some View {
        if states[.linear] == .notConnected {
            if missing.count > 1 {
                ConnectPlaceholder(service: .linear, widths: [90, 320, 220, 280])
            } else if let error = flow.error, error.service == .linear {
                ErrorLabel(error.message)
            }
        } else if let state = states[.linear] {
            failure(.linear, state)
        } else {
            let plan = self.plan
            if plan.total == 0 {
                QuietEmpty(symbol: "tray", text: "No issues in this project yet")
            } else {
                DeliveryBoard(plan: plan, project: project, labelsRepository: labelsRepository)
            }
        }
    }

    /// Pull requests, with their states inside the panel: an invitation to connect, a failure,
    /// or the ones no issue cites.
    @ViewBuilder
    private var githubPart: some View {
        if states[.github] == .notConnected {
            if missing.count > 1 {
                ConnectPlaceholder(service: .github, widths: [300, 240, 280])
            } else {
                ConnectPanelBody(service: .github, project: project, flow: flow)
            }
        } else if let state = states[.github] {
            failure(.github, state, compact: project.linear != nil && states[.linear] != nil)
        } else if app.pullsNeedLinear(project) {
            // The shared repository's pull requests belong to every project: only the project's
            // own issues tell which are its own.
            PanelEmpty(service: .linear, line: "Link a Linear project to see its pull requests",
                       primary: ("Link Linear", { link(.linear) }),
                       primaryHelp: "\(app.workspaceRepository.map(GitHubRepository.short) ?? "The repository") is shared with other projects: its pull requests are matched to the project's issues")
        } else if !unlinkedOpen.isEmpty || !unlinkedMerged.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if project.linear != nil {
                    Text(states[.linear] == nil ? "Pull requests without an issue" : "Pull requests")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                let rows: [UnlinkedPull] = unlinkedOpen.map { .open($0) } + unlinkedMerged.map { .merged($0) }
                ForEach(capped(rows, key: "unlinked")) { row in
                    // Rows revealed by "Show all" fade in with the list's growth.
                    Group {
                    switch row {
                    case .open(let m):
                        pullRow(kind: m.pull.draft == true ? .draft : .open, pipeline: pipeline(of: m.pull), title: m.pull.title,
                                number: m.pull.number, repository: m.pull.repository, url: m.pull.html_url, trailing: m.pull.user.login)
                    case .merged(let m):
                        pullRow(kind: .merged, pipeline: nil, title: m.title ?? "Pull request #\(m.number)", number: m.number,
                                repository: m.repository, url: m.url, trailing: m.mergedAt.map { $0.formatted(.relative(presentation: .named)) })
                    }
                    }
                    .transition(.opacity)
                }
                showAll(rows.count, key: "unlinked")
            }
        } else if project.linear == nil {
            QuietEmpty(symbol: "arrow.triangle.pull", text: "No pull requests")
        }
    }

    private enum UnlinkedPull: Identifiable {
        case open(ProjectPullRequests.Match), merged(MergedPull)
        var id: String {
            switch self {
            case .open(let m): "open-\(m.pull.html_url)"
            case .merged(let m): "merged-\(m.url)"
            }
        }
    }

    /// Two lines for a pull request on its own: what changed, then number and kind.
    private func pullRow(kind: PullChip.Kind, pipeline: ProjectSnapshot.PipelineState?, title: String, number: Int,
                         repository: String, url: String, trailing: String?) -> some View {
        let parts = PullTitle.split(title)
        let (symbol, tint, word): (String, Color, String) = switch kind {
        case .merged: ("arrow.triangle.merge", Theme.chart1, "merged")
        case .open: ("arrow.triangle.pull", Theme.chart2, "open")
        case .draft: ("pencil.line", Soot.muted, "draft")
        }
        return TileRow(url: URL(string: url)) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1).help(title)
                HStack(spacing: 6) {
                    if labelsRepository { Text(GitHubRepository.short(repository)); Text("·") }
                    Text(verbatim: "#\(number)")
                    Text("·"); Text(word)
                    if let kind = parts.kind { Text("·"); Text(kind) }
                }
                .font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            Spacer(minLength: 12)
            if let pipeline { PipelineGlyph(state: pipeline) }
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(Soot.muted).frame(minWidth: 70, alignment: .trailing)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens on GitHub")
    }

    /// Rows of the same shape as the list, while it loads.
    private var workSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            if project.linear != nil {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Skeleton(width: 70, height: 34); Skeleton(width: 80); Spacer(); Skeleton(width: 110)
                }
                Skeleton(height: 6, radius: 3)
                Skeleton(height: 92, radius: 10)
            }
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 12) {
                        Skeleton(width: 16, height: 16, radius: 8)
                        Skeleton(width: 64, height: 20, radius: 5)
                        // Flexible, so a narrow column never pushes the row past the panel's edge.
                        Skeleton(height: 12).frame(maxWidth: [280, 220, 320][i])
                        Spacer(minLength: 12)
                        Skeleton(width: 66, height: 26, radius: 13)
                        Skeleton(width: 22, height: 22, radius: 11)
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading the project's work")
    }

    // MARK: Slack

    /// The panel in both layouts. `railWidth` and `wideWidth` are the content widths of each,
    /// so the messages keep their final layout while the panel's frame animates between the two.
    private func slackPanel(railWidth: CGFloat, wideWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(service: .slack, title: project.slack.map { "#\($0.name)" } ?? "Slack", subtitle: slackSubtitle,
                        link: slackExpanded ? slackURL : nil, linkHelp: "Open the channel in Slack",
                        leading: {
                if slackExpanded {
                    // The way back sits where a back control is looked for: leading, before the title.
                    Button { toggleSlackWide() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, 10).frame(height: 30)
                    }
                    .buttonStyle(ChipButton(fill: Soot.surface))
                    .help("Back to the project (⌘⇧E)")
                    .accessibilityLabel("Back to the project")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .transition(.opacity)
                    Rectangle().fill(Soot.line).frame(width: 1, height: 22).transition(.opacity)
                }
            }, accessory: { EmptyView() }, trailing: {
                if project.slack != nil, !slackExpanded, slackLoaded, lastRead != nil, !railPlan.caughtUp, railPlan.unread > 0 {
                    Button("Mark as read") { markAllRead() }
                        .buttonStyle(TertiaryButton(tint: .muted, font: .system(size: 12, weight: .semibold)))
                        .help("Mark the whole channel as read, in Slack too")
                        .transition(.opacity)
                }
                if project.slack != nil, !slackExpanded {
                    Button { toggleSlackWide() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(IconButton(fill: Soot.ground))
                    .help("Read the conversation full width (⌘⇧E)")
                    .accessibilityLabel("Read the conversation full width")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .transition(.opacity)
                }
            })
            if project.slack == nil {
                PanelEmpty(service: .slack, line: "Link a channel to read it here",
                           primary: ("Link Slack", { link(.slack) }),
                           primaryHelp: "Pick the Slack channel this project follows")
            } else if states[.slack] == .notConnected {
                if missing.count > 1 {
                    ConnectPlaceholder(service: .slack, widths: [120, 260, 96, 220])
                } else {
                    ConnectPanelBody(service: .slack, project: project, flow: flow)
                }
            } else if let state = states[.slack] {
                failure(.slack, state)
            } else if !slackLoaded {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Skeleton(width: [120, 96, 140][i], height: 14)
                            Skeleton(height: 12)
                            Skeleton(width: [220, 160, 260][i], height: 12)
                        }
                    }
                }
                .transition(.opacity)
                .accessibilityElement()
                .accessibilityLabel("Loading messages")
            } else if messages.isEmpty {
                QuietEmpty(symbol: "bubble.left", text: "No messages yet")
            } else {
                if !slackExpanded { IntelligenceInvitation() }
                if !slackExpanded, let subject = catchUpSubject, catchUp != nil,
                   intelligence.text(subject) != nil || intelligence.isWriting(subject) {
                    GeneratedBlock(text: intelligence.text(subject), writing: intelligence.isWriting(subject),
                                   open: { openInRoom($0) })
                        .padding(.bottom, 14)
                        .overlay(alignment: .bottom) { Rectangle().fill(Soot.line).frame(height: 1) }
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
                SlackThreadView(messages: messages, users: users, domain: app.slack?.domain,
                                channelID: project.slack?.id, channelName: project.slack?.name, otherChannels: linkedChannels,
                                shown: shownMessages, railMessages: railPlan.messages, readUpTo: lastRead,
                                railCaughtUp: railPlan.caughtUp,
                                onSeen: { seen($0) }, roomMounted: roomMounted,
                                hasEarlier: hasEarlier, loadingEarlier: loadingEarlier,
                                wide: slackExpanded, widths: (rail: railWidth, wide: wideWidth),
                                focus: slackFocus, customEmoji: customEmoji,
                                showEarlier: { Task { await showEarlier() } },
                                openWide: slackExpanded ? nil : { m in
                                    slackFocus = m.ts
                                    toggleSlackWide()
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        if slackFocus == m.ts { Motion.run(Motion.ui, fade: true) { slackFocus = nil } }
                                    }
                                },
                                expand: slackExpanded ? nil : { toggleSlackWide() },
                                actions: slackActions)
                    .transition(.opacity)
            }
        }
        .motion(Motion.ui, fade: true, value: loaded)
        .motion(Motion.ui, fade: true, value: project.slack == nil)
        .sootPanel()
        // The panel's own frame is the mask of the move: nothing of the room shows outside it.
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Capped lists

    private static let cap = 6

    private func capped<T>(_ list: [T], key: String) -> [T] {
        expanded.contains(key) ? list : Array(list.prefix(Self.cap))
    }

    @ViewBuilder
    private func showAll(_ count: Int, key: String) -> some View {
        if count > Self.cap {
            ShowAllButton(count: count, expanded: Binding(
                get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }))
        }
    }

    // MARK: Loading

    /// The failure row of a panel, with the time of the last good load when there was one.
    private func failure(_ service: ServiceKind, _ state: ServiceState, compact: Bool = false) -> some View {
        let snapshot = store.snapshots[project.id]
        let fromSnapshot: Date? = switch service {
        case .slack: snapshot?.slack != nil ? snapshot?.updatedAt : nil
        case .linear: snapshot?.linear != nil ? snapshot?.updatedAt : nil
        case .github: snapshot?.github != nil ? snapshot?.updatedAt : nil
        }
        return ServiceFailureRow(service: service, state: state, lastLoaded: lastLoaded[service] ?? fromSnapshot,
                                 retry: { Task { await load(force: true) } }, flow: flow, compact: compact)
    }

    /// A click on the Overview's "waiting for you" line leaves where to land: a Slack message
    /// opens the reading room on it, a pull request opens the page of the issue it belongs to.
    private func land() async {
        guard let target = ProjectFocus.take(for: project.id) else { return }
        switch target {
        case .slack(let ts):
            guard project.slack != nil else { return }
            // An unread message older than the loaded page: bring the earlier pages in first.
            var tries = 0
            while !messages.contains(where: { SlackTS.isAtOrBefore($0.ts, ts) }), hasEarlier, tries < 4 {
                await showEarlier()
                tries += 1
            }
            slackFocus = ts
            if !slackExpanded { toggleSlackWide() }
            // You opened it on purpose: it is read, and so is what came before it.
            seen(ts)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if slackFocus == ts { Motion.run(Motion.ui, fade: true) { slackFocus = nil } }
        case .pull(let identifier, _):
            guard let identifier, let issue = issues.first(where: { $0.identifier == identifier }) else { return }
            NotificationCenter.default.post(name: .openIssue, object: IssueRoute(project: project, issue: issue))
        }
    }

    /// How old pull requests and their checks may get on screen before the page says so:
    /// twice their budget of a minute, and a little for the refresh itself.
    private static let agedAfter: TimeInterval = 150

    /// What the page shows that is not current: a tool whose refresh failed, and GitHub once
    /// its checks are old enough to mislead (the page was left open in the background).
    private var agedData: [AgeNotice.Item] {
        var out: [AgeNotice.Item] = []
        for service in ServiceKind.allCases {
            guard let since = lastLoaded[service], states[service] == nil else { continue }
            if let failure = refreshFailed[service] {
                out.append(.init(service: service, since: since, failure: failure))
            } else if service == .github, !repos.isEmpty, now.timeIntervalSince(since) > Self.agedAfter {
                out.append(.init(service: service, since: since))
            }
        }
        return out
    }

    /// The project's open pull requests whose checks are running, by repository.
    private var checksRunning: [String: [Int]] {
        Dictionary(grouping: pulls.filter { ["PENDING", "EXPECTED"].contains($0.pull.checks ?? "") }, by: { $0.pull.repository })
            .mapValues { $0.map(\.pull.number) }
    }

    /// The preview is deploying, updating or deleting, and nothing else is watching it (a
    /// command posted from here has its own watch).
    private var previewMoving: Bool {
        PreviewStore.shared.state(for: project)?.status?.phase.busy == true && PreviewStore.shared.awaiting[project.id] == nil
    }

    private func isDue(_ kind: RefreshCadence.Kind) -> Bool {
        let inFlight = kind == .checks ? !checksRunning.isEmpty : kind == .preview ? previewMoving : false
        return RefreshCadence.isDue(kind, last: polled[kind], inFlight: inFlight, failures: pollFailures[kind.service] ?? 0)
    }

    /// While the page is open and Dever in front, each kind of data is read again at its own
    /// pace, in place (`RefreshCadence`): new messages every 20 s, running checks and a moving
    /// preview every 15 s, the rest every minute. The tick also moves the age line.
    private func keepCurrent() async {
        guard Snapshotter.directory == nil else { return }
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            ticks += 1
            if ticks % 4 == 0 { now = Date() }
            guard NSApp.isActive, !inFlight else { continue }
            for kind in RefreshCadence.Kind.allCases where isDue(kind) {
                guard !Task.isCancelled, !inFlight else { break }
                await poll(kind)
                polled[kind] = Date()
            }
        }
    }

    private func poll(_ kind: RefreshCadence.Kind) async {
        switch kind {
        case .slackNew:
            guard let id = project.slack?.id, states[.slack] != .notConnected else { return }
            do {
                try await slackStore.poll(id, app: app)
                succeeded(.slack)
            } catch { failed(.slack, error) }
        case .slackPage:
            await loadSlack()
            polled[.slackNew] = Date()
        case .linear:
            await loadLinear(force: false)
            derivePulls()
        case .github:
            await loadGitHub()
        case .checks:
            guard let client = try? app.githubClient() else { return }
            for (repo, numbers) in checksRunning {
                do {
                    // One of them merged or closed: the repository is read in full on the next tick.
                    if try await github.refreshChecks(repo, numbers: numbers, client: client) { polled[.github] = nil }
                } catch { failed(.github, error) }
            }
        case .preview:
            await PreviewStore.shared.load(project, app: app, force: previewMoving)
        }
    }

    /// - Parameter quiet: a refresh nobody asked for: the Refresh button stays still and a
    ///   panel that failed before keeps its row until the tool answers.
    private func load(force: Bool = false, quiet: Bool = false) async {
        if !quiet { loading = true }
        guard !inFlight else { return }
        inFlight = true
        defer {
            inFlight = false; loading = false; loaded = true; lastLoad = Date(); now = Date()
            for kind in RefreshCadence.Kind.allCases { polled[kind] = Date() }
        }
        for service in ServiceKind.allCases {
            // A tool without a token is an invitation, not a call that fails.
            if missing.contains(service) { states[service] = .notConnected }
            else if !quiet || states[service] == .notConnected { states[service] = nil }
        }
        async let s: Void = loadSlack()
        async let preview: Void = PreviewStore.shared.load(project, app: app, force: force)
        // GitHub needs the Linear issues to tell which pull requests belong to the project.
        await loadLinear(force: force)
        await loadGitHub(force: force)
        await s
        await preview
    }

    private func succeeded(_ service: ServiceKind) {
        lastLoaded[service] = Date()
        states[service] = nil
        refreshFailed[service] = nil
        pollFailures[service] = nil
    }

    /// A failed refresh keeps what the panel shows and says so under the title; only a panel
    /// with nothing to show, or a rejected token, becomes the failure row.
    private func failed(_ service: ServiceKind, _ error: Error) {
        guard let state = app.failure(error, service) else { return }
        pollFailures[service, default: 0] += 1
        if lastLoaded[service] != nil, state.isTransient {
            refreshFailed[service] = state
            states[service] = nil
        } else {
            states[service] = state
        }
    }

    private func loadLinear(force: Bool) async {
        guard let id = project.linear?.id, states[.linear] != .notConnected else { return }
        do {
            _ = try await issueStore.load(project: id, force: force, app: app)
            succeeded(.linear)
            await issueStore.loadPlanContext(project: id, app: app)
        } catch { failed(.linear, error) }
    }

    private func loadSlack() async {
        guard let id = project.slack?.id, states[.slack] != .notConnected else { return }
        do {
            try await slackStore.load(id, app: app)
            succeeded(.slack)
            let authors = Set(messages.prefix(shownMessages).compactMap(\.user)).compactMap { users[$0] }
            Task.detached(priority: .utility) { await SlackMediaCache.shared.prefetchAvatars(authors) }
        } catch { failed(.slack, error) }
    }

    /// Reveals already loaded messages first; fetches an earlier page only when those run out.
    private func showEarlier() async {
        if messages.count > shownMessages { shownMessages += 10; return }
        guard let id = project.slack?.id, !messages.isEmpty, !loadingEarlier else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        do {
            try await slackStore.loadEarlier(id, app: app)
            shownMessages += 10
        } catch { app.report(error) }
    }

    /// What the rail shows. With Slack's read cursor: the unread messages (up to eight) and
    /// the threads with new replies; all caught up, only the last message, dimmed. Without a
    /// cursor yet: this week's messages, at most six, or the last one if the week was quiet.
    private var railPlan: (messages: [SlackMessage], unread: Int, caughtUp: Bool, quietSince: Date?) {
        if let lastRead {
            let unread = messages.filter { !SlackTS.isAtOrBefore($0.ts, lastRead) }
            let threads = messages.filter { m in
                SlackTS.isAtOrBefore(m.ts, lastRead) && (m.latest_reply.map { !SlackTS.isAtOrBefore($0, lastRead) } ?? false)
            }
            let picked = Array((unread.prefix(8) + threads.prefix(3)).sorted { $0.ts > $1.ts })
            if picked.isEmpty { return (Array(messages.prefix(1)), 0, true, nil) }
            return (picked, unread.count + threads.count, false, nil)
        }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let recent = messages.prefix { $0.date >= weekAgo }.count   // newest first
        if recent == 0 { return (Array(messages.prefix(1)), 0, false, messages.first?.date) }
        return (Array(messages.prefix(min(recent, 6))), recent, false, nil)
    }

    // MARK: Catch-up (docs/on-device-ai.md, 5.1)

    private var catchUpSubject: IntelligenceStore.Subject? {
        project.slack.map { .init(feature: .catchUp, id: $0.id) }
    }

    /// The oldest unread message the Overview counted, unless it stopped counting (200 and more).
    private var countedFirstUnread: String? {
        guard let slack = store.snapshots[project.id]?.slack, !slack.unreadCapped else { return nil }
        return slack.firstUnreadTS
    }

    /// Changes when the unread messages, the cursor or the model's readiness do.
    private var catchUpTrigger: String {
        "\(project.slack?.id ?? "")|\(lastRead ?? "")|\(messages.first?.ts ?? "")|\(messages.count)|\(intelligenceStatus.offers(.catchUp))|\(countedFirstUnread ?? "")|\(intelligenceStatus.offers(.messageSummary))|\(users.count)"
    }

    /// Asks the store for a catch-up of the unread messages when there are enough of them, and
    /// drops the previous one when there is nothing left to catch up on. No network request.
    private func refreshCatchUp() {
        guard let subject = catchUpSubject else { catchUp = nil; return }
        if !intelligenceStatus.offers(.catchUp) {
            CatchUp.log.notice("catch-up: not offered, model \(intelligenceStatus.availability.rawValue, privacy: .public), switch \(IntelligencePreferences.isOn(.catchUp))")
        }
        let input = !intelligenceStatus.offers(.catchUp) ? nil : CatchUp.input(
            messages: messages, lastRead: lastRead, hasEarlier: hasEarlier, firstUnread: countedFirstUnread,
            users: users, me: app.slack?.userID,
            languageCode: { IntelligencePreferences.language(forSummaryOf: $0) })
        catchUp = input
        if let input {
            intelligence.want(subject, version: input.version) { try await CatchUp.write(input) }
        } else {
            intelligence.drop(subject)
        }
    }

    /// Asks for the summary of each long message the rail shows, the newest first: what is seen
    /// first is written first. One at a time, behind the catch-up. No network request.
    private func refreshMessageSummaries() {
        guard let channel = project.slack?.id, intelligenceStatus.offers(.messageSummary) else { return }
        for message in railPlan.messages {
            guard let input = MessageSummary.input(message, users: users,
                                                   languageCode: { IntelligencePreferences.language(forSummaryOf: $0) }) else { continue }
            intelligence.want(MessageSummary.subject(channel: channel, ts: message.ts), version: input.version) {
                try await MessageSummary.write(input)
            }
        }
    }

    /// Opens the room on a message and lights it for two seconds.
    private func openInRoom(_ ts: String) {
        slackFocus = ts
        if !slackExpanded { toggleSlackWide() }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if slackFocus == ts { Motion.run(Motion.ui, fade: true) { slackFocus = nil } }
        }
    }

    private var slackSubtitle: String {
        if project.slack == nil { return "No channel yet" }
        if slackExpanded { return "Conversation" }
        if !loaded { return "Latest messages" }
        let plan = railPlan
        if plan.caughtUp { return "Nothing new" }
        if let since = plan.quietSince {
            return "Quiet since \(since.formatted(.relative(presentation: .named)))"
        }
        if lastRead != nil { return plan.unread == 1 ? "1 unread" : "\(plan.unread) unread" }
        return plan.unread == 1 ? "1 message this week" : "\(plan.unread) messages this week"
    }

    /// A message stayed on screen in the room: remember the newest such, and after three quiet
    /// seconds move Slack's cursor there. Closing the room sends it at once.
    private func seen(_ ts: String) {
        guard let id = project.slack?.id, slackStore.seen(id, ts) else { return }
        markTask?.cancel()
        markTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { await pushCursor() }
        }
    }

    /// Moves the read cursor to the newest seen message, if it is past the current one.
    private func pushCursor() async {
        guard let id = project.slack?.id, let seen = channel?.cursorToPush else { return }
        Motion.run(Motion.ui, fade: true) { slackStore.setLastRead(id, seen) }
        do {
            try await app.withSlack { try await $0.markRead(id, ts: seen) }
            // The Overview's "for you" follows at once, without a refresh.
            store.slackRead(project.id, upTo: seen)
        } catch { app.report(error) }
    }

    /// "Mark as read" in the rail: the cursor goes to the latest message.
    private func markAllRead() {
        guard let id = project.slack?.id, let target = channel?.readAllTarget else { return }
        _ = slackStore.seen(id, target)
        Task { await pushCursor() }
    }

    /// Rail to room and back: one spring (~350 ms, ease-out, no overshoot). The panel's frame
    /// grows in place while the work column slides out of its way; inside, the rail's messages
    /// dissolve into the room's, each laid out at its own final width. Instant under Reduce Motion.
    ///
    /// The click only moves frames and opacities. The room's messages are built once, after the
    /// first growth has settled (a skeleton of the room until then), and kept: later opens and
    /// every close only fade it, so the movement starts on the next frame instead of waiting for
    /// thirty messages to lay out or tear down.
    private func toggleSlackWide() {
        let opening = !slackExpanded
        if !opening { markTask?.cancel(); Task { await pushCursor() } }
        Motion.run(Motion.move) {
            slackExpanded = opening
            if opening { shownMessages = max(shownMessages, 30) }
        }
        guard opening, !roomMounted, roomMount == nil else { return }
        roomMount = Task { @MainActor in
            defer { roomMount = nil }
            try? await Task.sleep(nanoseconds: Motion.reduced ? 16_000_000 : 380_000_000)
            guard !Task.isCancelled, slackExpanded else { return }
            Motion.run(Motion.ui, fade: true) { roomMounted = true }
        }
    }

    /// A reply and a reaction change what they touch: the thread is read again by its pane
    /// (its parent's count follows), the reaction is applied to its message. The channel is
    /// not read again for either.
    private var slackActions: SlackMessageActions {
        SlackMessageActions(
            reply: { m, draft in
                guard let id = project.slack?.id else { return }
                try await app.withSlack { try await $0.reply(id, threadTS: m.ts, text: draft.text, blocks: draft.blocks) }
            },
            react: { m, name, on in
                guard let id = project.slack?.id else { return }
                try await app.withSlack { try await $0.react(id, ts: m.ts, name: name, on: on) }
                slackStore.react(id, ts: m.ts, name: name, on: on, user: app.slack?.userID)
            },
            replies: { m in
                guard let id = project.slack?.id else { return [] }
                return try await slackStore.thread(id, parent: m.ts, app: app)
            },
            cachedReplies: { m in
                project.slack.flatMap { slackStore.cachedThread($0.id, parent: m.ts) }
            })
    }

    /// The work panel has what it needs: the page loaded, or the stores already hold the
    /// project's issues and repositories from an earlier visit or the Overview's cycle.
    private var workLoaded: Bool {
        if loaded { return true }
        let issuesHeld = project.linear.map { issueStore.projects[$0.id] != nil } ?? true
        let reposHeld = repos.allSatisfy { github.repository($0) != nil }
        return issuesHeld && reposHeld && !(project.linear == nil && repos.isEmpty)
    }

    /// The issues the project's pull requests are matched against; nil without a Linear
    /// project, or while Linear cannot be read.
    private var issueRefs: [IssueReference]? {
        project.linear == nil || states[.linear] != nil ? nil : issues
    }

    /// When the least recently read of the project's repositories was read.
    private var githubReadAt: Date? { repos.compactMap { github.fetchedAt($0) }.min() }

    /// Works the project's pull requests out of what `GitHubStore` holds. False while one of
    /// its repositories has not been read yet (nothing is changed then).
    @discardableResult
    private func derivePulls() -> Bool {
        let repos = self.repos
        guard !repos.isEmpty, app.github != nil else { return false }
        let refs = issueRefs
        var derived = ProjectPulls()
        // A project that follows its issues (always so on the shared repository): without
        // issues to match, none of the repository's pull requests is known to be its own.
        if ProjectPulls.waitsForIssues(refs, wholeRepository: app.showsWholeRepository(project)) {
            derived.scoped = true
        } else {
            var held: [(name: String, data: GitHubStore.Repository)] = []
            for repo in repos {
                guard let data = github.repository(repo) else { return false }
                held.append((repo, data))
            }
            derived = ProjectPulls(repositories: held, issues: refs, wholeRepository: app.showsWholeRepository(project))
        }
        pulls = derived.open
        pullsScoped = derived.scoped
        merged = derived.merged
        for m in merged {
            issueStore.pullsByURL[m.url] = .init(number: m.number, title: m.title ?? "", state: .merged, issue: m.issue, date: m.mergedAt)
        }
        let iso = ISO8601DateFormatter()
        for p in pulls {
            issueStore.pullsByURL[p.pull.html_url] = .init(number: p.pull.number, title: p.pull.title,
                                                           state: p.pull.draft == true ? .draft : .open, issue: p.issue,
                                                           date: iso.date(from: p.pull.updated_at), author: p.pull.user.login)
        }
        return true
    }

    /// Reads the project's repositories through `GitHubStore` (shared with the Overview: one
    /// read within 20 s serves both), then works its pull requests out.
    private func loadGitHub(force: Bool = false) async {
        let repos = self.repos
        guard !repos.isEmpty, states[.github] != .notConnected else { return }
        do {
            let client = try app.githubClient()
            if !ProjectPulls.waitsForIssues(issueRefs, wholeRepository: app.showsWholeRepository(project)) {
                // One repository after the other: a project rarely follows more than a few.
                for repo in repos { _ = try await github.load(repo, client: client, maxAge: force ? 0 : RepoCache.maxAge) }
            }
            derivePulls()
            succeeded(.github)
            app.succeeded(.github)
        } catch { failed(.github, error) }
    }
}
