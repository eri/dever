import SwiftUI

/// Reference data loaded once per sheet (channels, Linear projects, teams, repos).
@MainActor
final class Catalog: ObservableObject {
    @Published var channels: [SlackChannel] = []
    @Published var linearProjects: [LinearProject] = []
    @Published var teams: [LinearTeam] = []
    @Published var repos: [GitHubRepo] = []
    /// Open pull requests of the repositories the Preview step looked at.
    @Published var pulls: [String: [GitHubPull]] = [:]
    @Published var loadingPulls = false
    @Published var loading = false
    @Published var errors: [String] = []

    /// Loads a repository's open pull requests once per sheet.
    func loadPulls(_ repo: String, _ app: AppState) async {
        guard pulls[repo] == nil, !loadingPulls else { return }
        if PreviewStore.simulation != nil { pulls[repo] = PreviewStore.samplePulls; return }
        loadingPulls = true
        defer { loadingPulls = false }
        do { pulls[repo] = try await app.githubClient().pulls(repo) } catch { errors.append(error.localizedDescription) }
    }

    func load(_ app: AppState) async {
        loading = true
        defer { loading = false }
        errors = []
        async let ch: [SlackChannel] = app.slack == nil ? [] : app.withSlack { try await $0.channels() }
        async let lp: [LinearProject] = app.linear == nil ? [] : app.withLinear { try await $0.projects() }
        async let tm: [LinearTeam] = app.linear == nil ? [] : app.withLinear { try await $0.teams() }
        async let rp: [GitHubRepo] = app.github == nil ? [] : app.githubClient().repos()
        do { channels = try await ch } catch { errors.append(error.localizedDescription) }
        do { linearProjects = try await lp } catch { errors.append(error.localizedDescription) }
        do { teams = try await tm } catch { errors.append(error.localizedDescription) }
        do { repos = try await rp } catch { errors.append(error.localizedDescription) }
    }
}

// MARK: - Add / edit project

/// One question per screen, in the onboarding's frame: a name, then for Slack, Linear, the
/// repositories and the preview a question first (pictures to choose from) and the detail on
/// the page after it, then a recap. One project per pass. Editing opens on the recap; each
/// row opens its question.
struct ProjectEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()

    @State var project: Project
    let isNew: Bool

    enum Step: Hashable { case name, slack, linear, github, preview, ready }
    /// A step's question, then what the answer needs (a name, a list).
    enum Phase: Hashable { case ask, detail }
    struct Page: Hashable { var step: Step; var phase: Phase = .ask }
    @State private var page: Page
    /// The step the next editor opens on ("Add a preview" from the project page), consumed once.
    static var openAt: Step?

    /// The answer to a tool's question.
    enum Choice: Hashable { case found, create, existing, workspace, own, yes, no }
    @State private var slackChoice: Choice = .create
    @State private var linearChoice: Choice = .create
    @State private var githubChoice: Choice = .workspace
    @State private var previewChoice: Choice = .no

    /// What the pick means for a tool: an item id, `create`, or nothing.
    static let create = "__create__"
    @State private var slackPick: String?
    @State private var linearPick: String?
    @State private var newChannelName = ""
    @State private var privateChannel = false
    @State private var teamPick: String?
    @State private var saving = false
    @State private var confirmingRemove = false
    @State private var error: String?

    // Lists are built once per load, not on every keystroke.
    @State private var channelRows: [PickerItem] = []
    @State private var linearRows: [PickerItem] = []
    @State private var repoRows: [PickerItem] = []
    @State private var channelsNarrowed = true
    @State private var query = ""

    init(project: Project = Project(name: ""), isNew: Bool = true) {
        var project = project
        self.isNew = isNew
        // Snapshots: DEVER_SNAPSHOT_STEP=name|slack|linear|github|preview|ready opens that step,
        // DEVER_SNAPSHOT_PHASE=detail its second page.
        let env = ProcessInfo.processInfo.environment
        let step: Step = switch env["DEVER_SNAPSHOT_STEP"] {
        case "slack": .slack
        case "linear": .linear
        case "github": .github
        case "preview": .preview
        case "ready": .ready
        default: Self.openAt ?? (isNew ? .name : .ready)
        }
        Self.openAt = nil
        // Snapshots of the preview step need a repository to list pull requests of.
        if step == .preview, PreviewStore.simulation != nil, project.githubRepos.isEmpty {
            project.githubRepos = [PreviewStore.sampleRepo]
            project.previewRepository = PreviewStore.sampleRepo
            project.previewPullNumber = PreviewStore.samplePullNumber
        }
        _project = State(initialValue: project)
        _page = State(initialValue: Page(step: step, phase: env["DEVER_SNAPSHOT_PHASE"] == "detail" ? .detail : .ask))
    }

    private var step: Step { page.step }

    /// The adding path: the repository step only where the mode lets a project choose, the
    /// preview step once the project follows a repository.
    private var path: [Step] {
        [.name, .slack, .linear] + (app.repositoryMode == .single ? [] : [.github]) + (repos.isEmpty ? [] : [.preview]) + [.ready]
    }

    /// The repositories the project follows, as edited so far, under the workspace's mode.
    private var repos: [String] { app.repositories(for: project) }

    var body: some View {
        StepSheet(step: isNew ? path.firstIndex(of: step) : nil, count: isNew ? path.count : 0,
                  back: backAction, close: { dismiss() }) {
            // One page fades out and the next rises in (`FadeSwap`); the marks slide with it.
            FadeSwap(value: page) { shown in
                switch (shown.step, shown.phase) {
                case (.name, _): nameStep
                case (.slack, .ask): slackAsk
                case (.slack, .detail): slackDetail
                case (.linear, .ask): linearAsk
                case (.linear, .detail): linearDetail
                case (.github, .ask): githubAsk
                case (.github, .detail): githubDetail
                case (.preview, .ask): previewAsk
                case (.preview, .detail): previewDetail
                case (.ready, _): readyStep
                }
            }
        }
        .task {
            slackPick = project.slack?.id
            linearPick = project.linear?.id
            githubChoice = ownRepositories ? .own : .workspace
            previewChoice = project.previewPullNumber != nil ? .yes : .no
            await catalog.load(app)
            teamPick = teamPick ?? catalog.teams.first?.id
            buildRows()
            let env = ProcessInfo.processInfo.environment
            if env["DEVER_SNAPSHOT_STEP"] != nil, project.name.isEmpty {
                // DEVER_SNAPSHOT_DETECT=1 names the project after a channel, so one is found.
                let sample = env["DEVER_SNAPSHOT_DETECT"] == "1"
                    ? availableChannels.first { fitsPrefix($0) }.map { Naming.projectName(fromChannel: $0.name, prefix: channelPrefix) }
                    : nil
                project.name = sample ?? "Checkout redesign"
            }
            suggest()
            if let want = env["DEVER_SNAPSHOT_CHOICE"].flatMap(Self.snapshotChoice) {
                slackChoice = want; linearChoice = want; answer(.slack, want); answer(.linear, want)
            }
        }
        .onChange(of: channelsNarrowed) { _, _ in buildRows() }
        .onChange(of: page) { _, _ in query = "" }
        .confirmationDialog("Remove \u{201C}\(project.name)\u{201D} from Dever?", isPresented: $confirmingRemove) {
            Button("Remove project", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dever stops tracking it. The Slack channel and the Linear project are not changed.")
        }
    }

    /// Leaves the project's page first, so nothing is left showing a project that is gone.
    private func remove() {
        NotificationCenter.default.post(name: .showScreen, object: SidebarItem.overview)
        app.delete(project)
        dismiss()
    }

    private static func snapshotChoice(_ raw: String) -> Choice? {
        switch raw { case "create": .create; case "existing": .existing; case "found": .found; default: nil }
    }

    /// Every page change: the page fades out and the next rises in (`FadeSwap`); the marks slide.
    private func go(_ p: Page) { Motion.run(Motion.settle) { page = p } }
    private func go(_ s: Step) { go(Page(step: s)) }

    private var backAction: (() -> Void)? {
        if page.phase == .detail { return { go(Page(step: step)) } }
        if !isNew { return step == .ready ? nil : { go(.ready) } }
        guard let i = path.firstIndex(of: step), i > 0 else { return nil }
        return { go(path[i - 1]) }
    }

    /// On to the next step (editing: back to the recap).
    private func next() {
        if !isNew { go(.ready); return }
        guard let i = path.firstIndex(of: step), i + 1 < path.count else { go(.ready); return }
        go(path[i + 1])
    }

    /// From a question to its detail page.
    private func detail() { go(Page(step: step, phase: .detail)) }

    // MARK: Name

    private var nameStep: some View {
        StepPage(title: "Name your project") {
            UnderlineField(placeholder: "e.g. Checkout redesign", text: $project.name, size: 24,
                           onSubmit: { if nameOK { suggest(); next() } })
                .frame(maxWidth: 360)
                .accessibilityLabel("Name in Dever")
        } buttons: {
            Button(isNew ? "Continue" : "Done") { suggest(); next() }
                .buttonStyle(PrimaryButton(size: .sheet))
                .keyboardShortcut(.defaultAction)
                .disabled(!nameOK)
        }
    }

    private var nameOK: Bool { !project.name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Slack

    /// The channel named like the project, if there is one.
    private var foundChannel: SlackChannel? {
        guard nameOK else { return nil }
        return Naming.closestChannel(to: project.name, prefix: channelPrefix, in: availableChannels)
    }

    private var slackAsk: some View {
        askPage(.slack, title: "Which Slack channel?", choice: $slackChoice,
                found: foundChannel.map { ("#\($0.name)", $0.num_members.map { Plural.text("^[\($0) member](inflect: true)") }) },
                createDetail: "#\(suggestedChannel)", nothing: "No channel named like \u{201C}\(project.name)\u{201D} yet",
                skip: "No channel for now")
    }

    @ViewBuilder
    private var slackDetail: some View {
        if slackChoice == .create {
            StepPage(title: "Name the channel") {
                VStack(alignment: .leading, spacing: 20) {
                    SootField(label: "Channel", placeholder: suggestedChannel, text: $newChannelName,
                              onSubmit: { next() })
                        .accessibilityLabel("New channel name")
                    SwitchRow(title: "Private channel", detail: "Only invited people can see it", isOn: $privateChannel)
                }
                .frame(maxWidth: 420)
            } buttons: {
                continueButton(ok: true)
            }
        } else {
            listPage(title: "Pick the channel", rows: channelRows, selection: $slackPick,
                     more: channelsNarrowed && hiddenChannels > 0 ? { channelsNarrowed = false } : nil)
        }
    }

    // MARK: Linear

    private var foundLinear: LinearProject? {
        guard nameOK else { return nil }
        return Naming.closest(to: project.name, in: availableLinear) { $0.name }
    }

    private var linearAsk: some View {
        askPage(.linear, title: "Which Linear project?", choice: $linearChoice,
                found: foundLinear.map { ($0.name, $0.teams?.nodes.map(\.name).joined(separator: ", ")) },
                createDetail: "\u{201C}\(project.name)\u{201D}", nothing: "No project named like \u{201C}\(project.name)\u{201D} yet",
                skip: "No Linear project for now")
    }

    @ViewBuilder
    private var linearDetail: some View {
        if linearChoice == .create {
            listPage(title: "In which team?", rows: catalog.teams.map { PickerItem(id: $0.id, title: $0.name) },
                     selection: $teamPick, more: nil, search: false)
        } else {
            listPage(title: "Pick the project", rows: linearRows, selection: $linearPick, more: nil)
        }
    }

    // MARK: Repositories

    /// Mixed mode: the project's own list rather than the workspace repository.
    private var ownRepositories: Bool { !(project.usesWorkspaceRepository ?? project.githubRepos.isEmpty) }

    /// Mixed mode only: the workspace repository, or the project's own.
    private var githubAsk: some View {
        StepPage(title: "Where is the code?") {
            if !app.isConnected(.github) {
                connectHint(.github)
            } else {
                ChoiceTiles {
                    ChoiceTile(thumb: .found, title: "Shared repository",
                               detail: app.workspaceRepository.map(GitHubRepository.short) ?? "Not picked in Settings yet",
                               tag: "Recommended",
                               selected: githubChoice == .workspace) { choose(.github, .workspace) }
                    ChoiceTile(thumb: .existing, title: "Separate repository",
                               detail: project.githubRepos.isEmpty ? "One or several" : Plural.text("^[\(project.githubRepos.count) repository](inflect: true)"),
                               selected: githubChoice == .own) { choose(.github, .own) }
                }
            }
        } buttons: {
            continueButton(ok: !app.isConnected(.github) || githubChoice == .own || app.workspaceRepository != nil) {
                if app.isConnected(.github) && githubChoice == .own { detail() } else { next() }
            }
        }
    }

    /// The project's own repositories, ticked in a list; the whole step where every project has its own.
    private var githubDetail: some View {
        StepPage(title: app.repositoryMode == .mixed ? "Which repositories?" : "Which repositories?") {
            if !app.isConnected(.github) {
                connectHint(.github)
            } else if catalog.loading {
                skeletonRows
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    searchField("Search repositories")
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered(repoRows)) { item in
                                PickRow(item: item, selected: project.githubRepos.contains(item.id), multiple: true) {
                                    toggleRepository(item.id)
                                }
                            }
                            noMatch(repoRows)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if !project.githubRepos.isEmpty {
                        SwitchRow(title: "Count every pull request", detail: "Not only those linked to this project's issues",
                                  isOn: Binding(get: { project.githubWholeRepo == true }, set: { project.githubWholeRepo = $0 }))
                            .frame(maxWidth: 420)
                    }
                }
            }
        } buttons: {
            continueButton(ok: !app.isConnected(.github) || catalog.loading || !project.githubRepos.isEmpty)
            if app.isConnected(.github) {
                skipButton("No repository for now") { project.githubRepos = []; next() }
            }
        }
    }

    private func toggleRepository(_ repo: String) {
        if let i = project.githubRepos.firstIndex(of: repo) {
            project.githubRepos.remove(at: i)
        } else {
            project.githubRepos.append(repo)
        }
        if app.repositoryMode == .mixed { project.usesWorkspaceRepository = false }
    }

    // MARK: Preview

    /// Some projects have no preview environment: ask before listing pull requests.
    private var previewAsk: some View {
        StepPage(title: "Is there a preview environment?") {
            ChoiceTiles {
                ChoiceTile(thumb: .symbol("globe"), title: "Yes", detail: "One pull request's preview",
                           selected: previewChoice == .yes) { choose(.preview, .yes) }
                ChoiceTile(thumb: .none, title: "No", detail: "Not for this project",
                           selected: previewChoice == .no) { choose(.preview, .no) }
            }
        } buttons: {
            continueButton(ok: true) {
                if previewChoice == .yes {
                    detail()
                } else {
                    project.previewPullNumber = nil; project.previewRepository = nil; project.previewDismissed = true
                    next()
                }
            }
        }
    }

    /// Which pull request's preview environment the project follows; with several
    /// repositories, each pull request says which one it is in.
    private var previewDetail: some View {
        listPage(title: "Which pull request?", rows: pullItems,
                 selection: Binding(get: { previewID },
                                    set: { id in
                                        let parts = id?.split(separator: "#", maxSplits: 1).map(String.init)
                                        project.previewRepository = parts?.first
                                        project.previewPullNumber = parts.flatMap { $0.count > 1 ? Int($0[1]) : nil }
                                        if project.previewPullNumber != nil { project.previewDismissed = nil } }),
                 more: nil, loading: repos.contains { catalog.pulls[$0] == nil })
            .task(id: repos) {
                guard app.github != nil else { return }
                for repo in repos { await catalog.loadPulls(repo, app) }
            }
    }

    /// `owner/name#number` of the preview pull request.
    private var previewID: String? {
        guard let n = project.previewPullNumber, let repo = app.previewRepository(for: project) else { return nil }
        return "\(repo)#\(n)"
    }

    /// The repositories' open pull requests, the project's own (citing one of its issues) first,
    /// then by number, newest first; the one already linked stays listed even when closed.
    private var pullItems: [PickerItem] {
        let repos = self.repos
        guard !repos.isEmpty else { return [] }
        let several = repos.count > 1
        let identifiers = project.linear.map { Set(IssueStore.shared.issues(project: $0.id).map(\.identifier)) } ?? []
        func isMine(_ p: GitHubPull) -> Bool {
            identifiers.contains { p.title.localizedCaseInsensitiveContains($0) || p.head.ref.localizedCaseInsensitiveContains($0) }
        }
        let pulls = repos.flatMap { repo in (catalog.pulls[repo] ?? []).map { (repo, $0) } }
        var items = pulls
            .sorted { (isMine($0.1) ? 0 : 1, -$0.1.number) < (isMine($1.1) ? 0 : 1, -$1.1.number) }
            .map { repo, p in
                PickerItem(id: "\(repo)#\(p.number)", title: "#\(p.number) \(PullTitle.split(p.title).title)",
                           subtitle: [several ? GitHubRepository.short(repo) : nil, isMine(p) ? "This project" : nil,
                                      p.draft == true ? "Draft" : nil, p.user.login].compactMap { $0 }.joined(separator: " · "),
                           symbol: p.draft == true ? "pencil.line" : "arrow.triangle.pull")
            }
        if let id = previewID, !items.contains(where: { $0.id == id }), let n = project.previewPullNumber {
            items.insert(PickerItem(id: id, title: "#\(n)", subtitle: "Not open any more", symbol: "arrow.triangle.pull"), at: 0)
        }
        return items
    }

    // MARK: Pages shared by the tools

    /// A tool's question: the match found (Recommended), create, or pick an existing one; a
    /// quiet line when nothing close exists. Not connected: one line and a way to Settings.
    private func askPage(_ service: ServiceKind, title: String, choice: Binding<Choice>,
                         found: (title: String, detail: String?)?, createDetail: String,
                         nothing: String, skip: String) -> some View {
        StepPage(title: title) {
            if !app.isConnected(service) {
                connectHint(service)
            } else if catalog.loading {
                skeletonTiles
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ChoiceTiles {
                        if let found {
                            ChoiceTile(thumb: .found, title: found.title, detail: found.detail, tag: "Recommended",
                                       selected: choice.wrappedValue == .found) { choose(service == .slack ? .slack : .linear, .found) }
                        }
                        ChoiceTile(thumb: .create, title: "Create one", detail: createDetail,
                                   tag: found == nil ? "Recommended" : nil,
                                   selected: choice.wrappedValue == .create) { choose(service == .slack ? .slack : .linear, .create) }
                        ChoiceTile(thumb: .existing, title: "Pick an existing one",
                                   selected: choice.wrappedValue == .existing) { choose(service == .slack ? .slack : .linear, .existing) }
                    }
                    if found == nil {
                        Label(nothing, systemImage: "magnifyingglass")
                            .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    }
                }
            }
        } buttons: {
            continueButton(ok: !app.isConnected(service) || !catalog.loading) {
                guard app.isConnected(service) else { return next() }
                switch choice.wrappedValue {
                case .found: next()
                case .create where service == .linear && catalog.teams.count <= 1: next()
                default: detail()
                }
            }
            if app.isConnected(service) {
                skipButton(skip) { answer(service == .slack ? .slack : .linear, .no); next() }
            }
        }
    }

    /// A tile chosen: the ring moves and the pick follows.
    private func choose(_ step: Step, _ choice: Choice) {
        Motion.run(Motion.settle) {
            switch step {
            case .slack: slackChoice = choice
            case .linear: linearChoice = choice
            case .github: githubChoice = choice
            case .preview: previewChoice = choice
            default: break
            }
        }
        answer(step, choice)
    }

    /// What a choice means for the pick that is saved.
    private func answer(_ step: Step, _ choice: Choice) {
        switch (step, choice) {
        case (.slack, .found): slackPick = foundChannel?.id
        case (.slack, .create): slackPick = Self.create
        case (.slack, .existing): if slackPick == Self.create || slackPick == foundChannel?.id { slackPick = nil }
        case (.slack, .no): slackPick = nil; slackChoice = .existing
        case (.linear, .found): linearPick = foundLinear?.id
        case (.linear, .create): linearPick = Self.create
        case (.linear, .existing): if linearPick == Self.create || linearPick == foundLinear?.id { linearPick = nil }
        case (.linear, .no): linearPick = nil; linearChoice = .existing
        case (.github, .workspace): project.usesWorkspaceRepository = true
        case (.github, .own): project.usesWorkspaceRepository = false
        default: break
        }
    }

    /// A list to pick one thing from: a search, light rows under hairlines, "show every" at the end.
    private func listPage(title: String, rows: [PickerItem], selection: Binding<String?>,
                          more: (() -> Void)?, loading: Bool = false, search: Bool = true) -> some View {
        StepPage(title: title) {
            if catalog.loading || loading {
                skeletonRows
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if search { searchField("Search") }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered(rows)) { item in
                                ListRow(item: item, selected: selection.wrappedValue == item.id) {
                                    Motion.run(Motion.ui) { selection.wrappedValue = item.id }
                                }
                            }
                            noMatch(rows)
                            if let more, query.isEmpty {
                                Button("Show every channel", action: more)
                                    .buttonStyle(TertiaryButton(tint: .lime, lift: Soot.surface, font: .system(size: 13, weight: .semibold)))
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: 440)
            }
        } buttons: {
            continueButton(ok: catalog.loading || loading || selection.wrappedValue != nil)
        }
    }

    private func continueButton(ok: Bool, action: (() -> Void)? = nil) -> some View {
        Button(isNew ? "Continue" : "Done") { (action ?? next)() }
            .buttonStyle(PrimaryButton(size: .sheet))
            .keyboardShortcut(.defaultAction)
            .disabled(!ok)
    }

    private func skipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 14, weight: .medium)))
    }

    private func searchField(_ label: String) -> some View {
        SootField(label: "", placeholder: "Search", text: $query, leadingSymbol: "magnifyingglass")
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private func noMatch(_ rows: [PickerItem]) -> some View {
        if filtered(rows).isEmpty {
            Text(query.isEmpty ? "Nothing to pick from yet" : "No match for \u{201C}\(query)\u{201D}")
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.vertical, 16)
        }
    }

    private var skeletonRows: some View {
        VStack(spacing: 6) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 44, radius: Soot.fieldRadius) } }
    }

    private var skeletonTiles: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 10) {
                    Skeleton(width: 116, height: 76, radius: 8)
                    Skeleton(width: 80, height: 10)
                }
                .frame(width: 148)
                .padding(.vertical, 10)
            }
        }
    }

    private func filtered(_ rows: [PickerItem]) -> [PickerItem] {
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// The recap: one row per thing, each opening its step; then the one button.
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(text: isNew ? "Ready?" : "Edit project")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    recapRow(icon: AnyView(Image(systemName: "textformat").font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)),
                             tool: "Name", state: .set(project.name)) { go(.name) }
                    FieldLabel(text: "Tools").padding(.top, 12).padding(.bottom, 4)
                    recapRow(icon: AnyView(BrandLogo(service: .slack, size: 18)), tool: "Slack", state: slackState) { go(.slack) }
                    recapRow(icon: AnyView(BrandLogo(service: .linear, size: 18).foregroundStyle(Soot.ink)), tool: "Linear",
                             state: linearState) { go(.linear) }
                    if app.repositoryMode != .single {
                        recapRow(icon: AnyView(BrandLogo(service: .github, size: 18).foregroundStyle(Soot.ink)), tool: "GitHub",
                                 state: githubState) { go(.github) }
                    }
                    if !repos.isEmpty {
                        recapRow(icon: AnyView(Image(systemName: "globe").font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)),
                                 tool: "Preview",
                                 state: project.previewPullNumber.map { .set("Pull request #\($0)") }
                                    ?? .unset(project.previewDismissed == true ? "Not needed" : "Not linked")) { go(.preview) }
                    }
                }
                .frame(maxWidth: 440)
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Button(saving ? "Saving…" : isNew ? "Create project" : "Save") { Task { await save() } }
                        .buttonStyle(PrimaryButton(size: .sheet))
                        .keyboardShortcut(.defaultAction)
                        .disabled(saving || !nameOK)
                    if !isNew {
                        Spacer(minLength: 0)
                        // The same question as the rail's "Remove from Dever", asked from the sheet.
                        Button { confirmingRemove = true } label: {
                            Label("Remove project", systemImage: "trash")
                        }
                        // A quiet text link: removing is rare, so it does not compete with Save.
                        .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 14, weight: .medium)))
                        .disabled(saving)
                        .accessibilityHint("Asks before removing the project from Dever")
                    }
                }
                ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
            }
        }
    }

    /// What a recap row shows: linked to something, about to create it, or nothing yet.
    enum RecapState {
        case set(String), create(String), unset(String)
    }

    /// A recap line: the tool, what it is linked to underneath, and a clear mark of set or not.
    /// Set: the value in ink and a lime check. Not set: a quiet line and a lime "Link".
    private func recapRow(icon: AnyView, tool: String, state: RecapState, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                icon.frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                    switch state {
                    case .set(let value):
                        Text(value).font(.system(size: 12)).foregroundStyle(Soot.ink).lineLimit(1).truncationMode(.middle)
                    case .create(let value):
                        Text(value).font(.system(size: 12)).foregroundStyle(Soot.lime).lineLimit(1).truncationMode(.middle)
                    case .unset(let hint):
                        Text(hint).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                switch state {
                case .set:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Soot.lime)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                case .create:
                    Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundStyle(Soot.lime)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                case .unset:
                    Text("Link").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
            }
            .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
        .accessibilityLabel({
            switch state {
            case .set(let v): "\(tool): \(v)"
            case .create(let v): "\(tool): \(v)"
            case .unset(let h): "\(tool): \(h)"
            }
        }())
    }

    private var slackState: RecapState {
        switch slackPick {
        case Self.create?: .create("Create #\(suggestedChannel)")
        case let id?: (catalog.channels.first { $0.id == id }.map { "#\($0.name)" } ?? project.slack.map { "#\($0.name)" })
            .map { .set($0) } ?? .unset("Not linked")
        case nil: .unset("Not linked")
        }
    }

    private var linearState: RecapState {
        switch linearPick {
        case Self.create?: .create("Create \u{201C}\(project.name)\u{201D}")
        case let id?: (catalog.linearProjects.first { $0.id == id }?.name ?? project.linear?.name).map { .set($0) } ?? .unset("Not linked")
        case nil: .unset("Not linked")
        }
    }

    private var githubState: RecapState {
        if app.repositoryMode == .mixed, !ownRepositories {
            return app.workspaceRepository.map { .set("Workspace · \($0)") } ?? .unset("Workspace repository, not set")
        }
        return repos.isEmpty ? .unset("Not linked") : .set(repos.joined(separator: ", "))
    }

    private func connectHint(_ service: ServiceKind) -> some View {
        Button {
            dismiss()
            NotificationCenter.default.post(name: .showScreen, object: SidebarItem.settings)
        } label: {
            HStack(spacing: 4) { Text("Connect \(service.label) in Settings"); Image(systemName: "arrow.right") }
            }
            .buttonStyle(TertiaryButton(lift: Soot.surface, font: .system(size: 14, weight: .semibold)))
            .padding(.leading, -8)
    }

    // MARK: Data

    private var suggestedChannel: String {
        newChannelName.isEmpty ? Naming.channelName(for: project.name.isEmpty ? "project" : project.name, prefix: channelPrefix)
                               : newChannelName
    }

    private func fitsPrefix(_ ch: SlackChannel) -> Bool { channelPrefix.isEmpty || ch.name.hasPrefix(channelPrefix) }

    private var availableChannels: [SlackChannel] {
        let taken = app.linkedSlackIDs.subtracting([project.slack?.id].compactMap { $0 })
        return catalog.channels.filter { !taken.contains($0.id) }
    }

    private var hiddenChannels: Int {
        availableChannels.filter { !(fitsPrefix($0) && $0.is_member == true) }.count
    }

    private var availableLinear: [LinearProject] {
        let taken = app.linkedLinearIDs.subtracting([project.linear?.id].compactMap { $0 })
        return catalog.linearProjects.filter { !taken.contains($0.id) }
    }

    /// Channels you're in first, then the rest; narrowed to the likely ones until "Show every channel".
    private func buildRows() {
        channelRows = availableChannels
            .filter { !channelsNarrowed || (fitsPrefix($0) && $0.is_member == true) || $0.id == project.slack?.id }
            .sorted { ($0.is_member == true ? 0 : 1, $0.name) < ($1.is_member == true ? 0 : 1, $1.name) }
            .map { ch in
                PickerItem(id: ch.id, title: "#\(ch.name)",
                           subtitle: ch.is_member == true ? nil : "Not in it",
                           symbol: ch.is_private == true ? "lock" : nil,
                           aside: ch.num_members.map { Plural.text("^[\($0) member](inflect: true)") })
            }
        linearRows = availableLinear.map {
            PickerItem(id: $0.id, title: $0.name, subtitle: $0.teams?.nodes.map(\.name).joined(separator: ", "))
        }
        repoRows = catalog.repos.map { PickerItem(id: $0.full_name, title: $0.full_name, subtitle: $0.private ? "Private" : "Public") }
    }

    /// Adding: the channel / Linear project named like the project is offered first; without
    /// one, "Create" is. Editing keeps what is linked and only sets the question's answer.
    private func suggest() {
        guard nameOK else { return }
        if app.slack != nil {
            if let linked = project.slack?.id, !isNew {
                slackChoice = linked == foundChannel?.id ? .found : .existing
            } else if slackPick == nil || slackPick == Self.create || slackPick == foundChannel?.id {
                slackChoice = foundChannel != nil ? .found : .create
                slackPick = foundChannel?.id ?? Self.create
            }
        }
        if app.linear != nil {
            if let linked = project.linear?.id, !isNew {
                linearChoice = linked == foundLinear?.id ? .found : .existing
            } else if linearPick == nil || linearPick == Self.create || linearPick == foundLinear?.id {
                linearChoice = foundLinear != nil ? .found : .create
                linearPick = foundLinear?.id ?? Self.create
            }
        }
    }

    private func save() async {
        error = nil
        saving = true
        defer { saving = false }
        do {
            var p = project
            p.name = p.name.trimmingCharacters(in: .whitespaces)
            switch slackPick {
            case Self.create?:
                let ch = try await app.withSlack { try await $0.createChannel(name: suggestedChannel, isPrivate: privateChannel) }
                p.slack = .init(id: ch.id, name: ch.name)
            case let id?:
                if let ch = catalog.channels.first(where: { $0.id == id }) { p.slack = .init(id: ch.id, name: ch.name) }
            case nil:
                p.slack = nil
            }
            switch linearPick {
            case Self.create?:
                guard let team = teamPick else { throw AppError.message("Pick a Linear team") }
                let lp = try await app.withLinear { try await $0.createProject(name: p.name, teamIDs: [team]) }
                p.linear = .init(id: lp.id, name: lp.name, url: lp.url)
            case let id?:
                if let lp = catalog.linearProjects.first(where: { $0.id == id }) { p.linear = .init(id: lp.id, name: lp.name, url: lp.url) }
            case nil:
                p.linear = nil
            }
            if app.previewRepository(for: p) == nil { p.previewPullNumber = nil; p.previewRepository = nil }
            if p.previewPullNumber != nil, p.previewRepository == nil { p.previewRepository = app.previewRepository(for: p) }
            if p.previewPullNumber != project.previewPullNumber || p.previewRepository != project.previewRepository { PreviewStore.shared.forget(p.id) }
            app.upsert(p)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One choice in a step's list: a ring, the title, one quiet line; lime edge when picked.
private struct PickRow: View {
    let item: PickerItem
    let selected: Bool
    /// A tick box rather than a radio ring: several rows can be on at once.
    var multiple = false
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                CheckCircle(on: selected, square: multiple)
                if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(symbol == "plus" ? Soot.lime : Soot.muted).frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius).strokeBorder(selected ? Soot.lime : .clear, lineWidth: 1.5))
            }
            .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One line to pick, under a hairline: a ring, the name, a quiet note, a figure on the right.
/// Lighter than `PickRow`: no card, so a long list breathes.
private struct ListRow: View {
    let item: PickerItem
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                CheckCircle(on: selected)
                if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted).frame(width: 14)
                }
                Text(item.title).font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Soot.ink).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer(minLength: 12)
                if let aside = item.aside {
                    Text(aside).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Soot.line).frame(height: 1).padding(.leading, 42) }
        }
        .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
        .accessibilityLabel([item.title, item.subtitle, item.aside].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Import

struct ImportSheet: View {
    enum Source: String, Identifiable { case slack, linear; var id: String { rawValue } }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()
    let source: Source
    /// From the guided "Add a project" sheet: a way back to its first step.
    var back: (() -> Void)? = nil
    @State private var selection = Set<String>()
    /// Channels start narrowed to the likely ones (your channels, with the prefix); searching
    /// or "Find more channels" widens to every channel.
    @State private var narrowed = true
    @State private var search = ""

    struct Candidate: Identifiable {
        var id: String
        var title: String
        var projectName: String
        var match: String?
        /// A repository named like the project, where the mode lets a project have its own.
        var repo: String?
    }

    private var isNarrowed: Bool { source == .slack && narrowed && search.isEmpty }

    /// Built once per load and per narrowing; matching every row against the other tool is
    /// too slow to redo on each keystroke.
    @State private var rows: [Candidate] = []

    private func buildRows() {
        switch source {
        case .slack:
            rows = catalog.channels
                .filter { !app.linkedSlackIDs.contains($0.id) }
                .filter { !isNarrowed || fitsPrefix($0) && $0.is_member == true }
                .map { ch in
                    let name = Naming.projectName(fromChannel: ch.name, prefix: channelPrefix)
                    return Candidate(id: ch.id, title: "#\(ch.name)", projectName: name,
                                     match: linearMatch(for: name)?.name, repo: repoMatch(for: name))
                }
        case .linear:
            rows = catalog.linearProjects
                .filter { !app.linkedLinearIDs.contains($0.id) }
                .map { lp in
                    Candidate(id: lp.id, title: lp.name, projectName: lp.name,
                              match: slackMatch(for: lp.name).map { "#\($0.name)" }, repo: repoMatch(for: lp.name))
                }
        }
    }

    private var candidates: [Candidate] {
        guard !search.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func fitsPrefix(_ ch: SlackChannel) -> Bool { channelPrefix.isEmpty || ch.name.hasPrefix(channelPrefix) }

    /// Channels hidden by the narrowing, so "Find more" says how many.
    private var hiddenCount: Int {
        guard isNarrowed else { return 0 }
        return catalog.channels.filter { !app.linkedSlackIDs.contains($0.id) && !(fitsPrefix($0) && $0.is_member == true) }.count
    }

    /// The other side of each pair: Linear for channels, Slack for Linear projects.
    private var counterpart: ServiceKind { source == .slack ? .linear : .slack }

    var body: some View {
        StepSheet(back: back, close: { dismiss() }) {
            VStack(alignment: .leading, spacing: 20) {
                StepTitle(text: source == .slack ? "Add many from Slack" : "Add many from Linear")
                SootField(label: "", placeholder: "Search", text: $search, leadingSymbol: "magnifyingglass")
                    .accessibilityLabel(source == .slack ? "Search channels" : "Search projects")
                ForEach(catalog.errors, id: \.self) { ErrorLabel($0) }
                ScrollView { list }
                    .frame(maxHeight: .infinity)
                footer
            }
        }
        .task { await catalog.load(app); buildRows() }
        .onChange(of: isNarrowed) { _, _ in buildRows() }
    }

    @ViewBuilder
    private var list: some View {
        LazyVStack(spacing: 8) {
                if catalog.loading {
                    ForEach(0..<6, id: \.self) { i in
                        HStack(spacing: 12) {
                            Skeleton(width: 18, height: 18, radius: 9)
                            Skeleton(width: [160, 120, 190, 140, 170, 130][i], height: 12)
                            Spacer()
                            Skeleton(width: 110, height: 12)
                        }
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                    }
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    ForEach(candidates) { c in ImportRow(candidate: c, counterpart: counterpart,
                                                        on: selection.contains(c.id)) { toggle(c.id) } }
                }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(search.isEmpty ? (source == .slack ? "No channel to import" : "No project to import")
                                : "No result for \u{201C}\(search)\u{201D}")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)
            if isNarrowed {
                Button("Find more channels") { narrowed = false }
                    .buttonStyle(TertiaryButton(lift: Soot.surface))
                } else if !search.isEmpty {
                    Button("Clear search") { search = "" }
                        .buttonStyle(TertiaryButton(lift: Soot.surface))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var footer: some View {
        HStack(spacing: 20) {
            if !candidates.isEmpty {
                Button(selection.count == candidates.count ? "Select none" : "Select all") {
                    selection = selection.count == candidates.count ? [] : Set(candidates.map(\.id))
                }
                .buttonStyle(TertiaryButton(lift: Soot.surface))
                .padding(.leading, -8)
                }
                if hiddenCount > 0 {
                    Button("Find more channels") { narrowed = false }
                        .buttonStyle(SecondaryButton())
                    .help(Plural.text("^[\(hiddenCount) more channel](inflect: true) you're not in or without the prefix"))
            }
            Spacer()
            Button(selection.isEmpty ? "Add" : "Add ^[\(selection.count) project](inflect: true)") { importSelected() }
                .buttonStyle(PrimaryButton(size: .sheet))
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
        }
    }

    private func linearMatch(for name: String) -> LinearProject? {
        catalog.linearProjects.first { !app.linkedLinearIDs.contains($0.id) && Naming.matches($0.name, name) }
    }

    private func slackMatch(for name: String) -> SlackChannel? {
        let expected = Naming.channelName(for: name, prefix: channelPrefix)
        return catalog.channels.first { !app.linkedSlackIDs.contains($0.id) && $0.name == expected }
    }

    /// In `perProject` and `mixed` modes, a repository whose name is the project's; `single`
    /// mode needs none, the workspace repository is followed.
    private func repoMatch(for name: String) -> String? {
        guard app.repositoryMode != .single else { return nil }
        return catalog.repos.first { Naming.matches(GitHubRepository.short($0.full_name), name) }?.full_name
    }

    private func importSelected() {
        for id in selection {
            switch source {
            case .slack:
                guard let ch = catalog.channels.first(where: { $0.id == id }) else { continue }
                let name = Naming.projectName(fromChannel: ch.name, prefix: channelPrefix)
                var p = Project(name: name, slack: .init(id: ch.id, name: ch.name))
                if let lp = linearMatch(for: name) { p.linear = .init(id: lp.id, name: lp.name, url: lp.url) }
                if let repo = repoMatch(for: name) { p.githubRepos = [repo]; p.usesWorkspaceRepository = false }
                app.upsert(p)
            case .linear:
                guard let lp = catalog.linearProjects.first(where: { $0.id == id }) else { continue }
                var p = Project(name: lp.name, linear: .init(id: lp.id, name: lp.name, url: lp.url))
                if let ch = slackMatch(for: lp.name) { p.slack = .init(id: ch.id, name: ch.name) }
                if let repo = repoMatch(for: lp.name) { p.githubRepos = [repo]; p.usesWorkspaceRepository = false }
                app.upsert(p)
            }
        }
        dismiss()
    }
}

/// One channel or project to pick.
private struct ImportRow: View {
    let candidate: ImportSheet.Candidate
    let counterpart: ServiceKind
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        let c = candidate
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    if c.projectName != c.title {
                        Text(c.projectName).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if let repo = c.repo {
                    HStack(spacing: 6) {
                        BrandLogo(service: .github, size: 12).foregroundStyle(Soot.ink)
                        Text(GitHubRepository.short(repo)).font(.system(size: 12)).foregroundStyle(Soot.ink).lineLimit(1)
                    }
                    .help("Repository \(repo), linked automatically")
                }
                HStack(spacing: 6) {
                    BrandLogo(service: counterpart, size: 12)
                        .foregroundStyle(c.match == nil ? Soot.muted : Soot.ink)
                        .opacity(c.match == nil ? 0.5 : 1)
                    Text(c.match ?? "No match").font(.system(size: 12))
                        .foregroundStyle(c.match == nil ? Soot.muted : Soot.ink).lineLimit(1)
                }
                .help(c.match == nil ? "Link it later from the project" : "Linked automatically")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
                .strokeBorder(on ? Soot.lime : .clear, lineWidth: 1.5))
            }
            .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
