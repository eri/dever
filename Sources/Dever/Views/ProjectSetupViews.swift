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

/// One question per screen, in the onboarding's frame: a name, then a Slack channel, a Linear
/// project and a GitHub repository picked from lists, then a recap to confirm. One project per
/// pass. Editing opens on the recap; each row opens its one step.
struct ProjectEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()

    @State var project: Project
    let isNew: Bool

    enum Step: Hashable { case name, slack, linear, github, preview, ready }
    @State private var step: Step
    /// The step the next editor opens on ("Add a preview" from the project page), consumed once.
    static var openAt: Step?

    /// What the pick means for a tool: an item id, `create`, or nothing.
    static let create = "__create__"
    @State private var slackPick: String?
    @State private var linearPick: String?
    @State private var newChannelName = ""
    @State private var privateChannel = false
    @State private var teamPick: String?
    @State private var saving = false
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
        // Snapshots: DEVER_SNAPSHOT_STEP=name|slack|linear|github|preview|ready opens that step.
        let snapshot = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_STEP"]
        let first: Step = switch snapshot {
        case "slack": .slack
        case "linear": .linear
        case "github": .github
        case "preview": .preview
        case "ready": .ready
        default: Self.openAt ?? (isNew ? .name : .ready)
        }
        Self.openAt = nil
        // Snapshots of the preview step need a repository to list pull requests of.
        if first == .preview, PreviewStore.simulation != nil, project.githubRepos.isEmpty {
            project.githubRepos = [PreviewStore.sampleRepo]
            project.previewRepository = PreviewStore.sampleRepo
            project.previewPullNumber = PreviewStore.samplePullNumber
        }
        _project = State(initialValue: project)
        _step = State(initialValue: first)
    }

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
            // One step fades out and the next rises in (`FadeSwap`); the marks slide with it.
            FadeSwap(value: step) { shown in
                switch shown {
                case .name: nameStep
                case .slack: slackStep
                case .linear: linearStep
                case .github: githubStep
                case .preview: previewStep
                case .ready: readyStep
                }
            }
        }
        .task {
            slackPick = project.slack?.id
            linearPick = project.linear?.id
            await catalog.load(app)
            teamPick = teamPick ?? catalog.teams.first?.id
            buildRows()
            suggest()
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_STEP"] != nil, project.name.isEmpty {
                project.name = "Checkout redesign"; suggest()
            }
        }
        .onChange(of: channelsNarrowed) { _, _ in buildRows() }
        .onChange(of: step) { _, _ in query = "" }
    }

    /// Every step change: the step fades out and the next rises in (`FadeSwap`); the marks slide.
    private func go(_ s: Step) { Motion.run(Motion.settle) { step = s } }

    private var backAction: (() -> Void)? {
        if !isNew { return step == .ready ? nil : { go(.ready) } }
        guard let i = path.firstIndex(of: step), i > 0 else { return nil }
        return { go(path[i - 1]) }
    }

    private func next() {
        if !isNew { go(.ready); return }
        guard let i = path.firstIndex(of: step), i + 1 < path.count else { go(.ready); return }
        go(path[i + 1])
    }

    // MARK: Steps

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepTitle(text: "Name your project")
            UnderlineField(placeholder: "e.g. Checkout redesign", text: $project.name, size: 24,
                           onSubmit: { if nameOK { suggest(); next() } })
                .frame(maxWidth: 360)
                .accessibilityLabel("Name in Dever")
            Button(isNew ? "Continue" : "Done") { suggest(); next() }
                .buttonStyle(PrimaryButton(size: .sheet))
                .keyboardShortcut(.defaultAction)
                .disabled(!nameOK)
        }
    }

    private var nameOK: Bool { !project.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var slackStep: some View {
        toolStep(.slack, title: "Slack channel", rows: channelRows, selection: $slackPick,
                 createTitle: "Create #\(suggestedChannel)",
                 more: channelsNarrowed && hiddenChannels > 0 ? { channelsNarrowed = false } : nil) {
            if slackPick == Self.create {
                SwitchRow(title: "Private channel", isOn: $privateChannel).frame(maxWidth: 420)
            }
        }
    }

    private var linearStep: some View {
        toolStep(.linear, title: "Linear project", rows: linearRows, selection: $linearPick,
                 createTitle: "Create \u{201C}\(project.name)\u{201D}", more: nil) {
            if linearPick == Self.create, catalog.teams.count > 1 {
                HStack(spacing: 12) {
                    FieldLabel(text: "Team")
                    SearchPicker(label: "Team", placeholder: "Pick a team",
                                 items: catalog.teams.map { PickerItem(id: $0.id, title: $0.name) },
                                 selection: $teamPick)
                        .frame(maxWidth: 240)
                }
            }
        }
    }

    /// Mixed mode: the workspace repository, or the project's own list (nil until chosen).
    private var ownRepositories: Binding<Bool> {
        Binding(get: { !(project.usesWorkspaceRepository ?? project.githubRepos.isEmpty) },
                set: { project.usesWorkspaceRepository = !$0 })
    }

    /// One or several repositories, ticked in a list; in mixed mode, first whether the project
    /// follows the workspace repository at all.
    private var githubStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(text: app.repositoryMode == .mixed ? "Repositories" : "GitHub repositories")
            if !app.isConnected(.github) {
                connectHint(.github)
            } else if catalog.loading {
                VStack(spacing: 6) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 44, radius: Soot.fieldRadius) } }
            } else {
                if app.repositoryMode == .mixed {
                    VStack(spacing: 6) {
                        PickRow(item: PickerItem(id: "workspace", title: "Use the workspace repository",
                                                 subtitle: app.workspaceRepository ?? "None picked yet in Settings"),
                                selected: !ownRepositories.wrappedValue) { ownRepositories.wrappedValue = false }
                        PickRow(item: PickerItem(id: "own", title: "Its own repositories",
                                                 subtitle: project.githubRepos.isEmpty ? "Pick one or several below"
                                                     : project.githubRepos.joined(separator: ", ")),
                                selected: ownRepositories.wrappedValue) { ownRepositories.wrappedValue = true }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Which repositories")
                }
                if app.repositoryMode == .perProject || ownRepositories.wrappedValue {
                    SootField(label: "", placeholder: "Search", text: $query, leadingSymbol: "magnifyingglass")
                        .accessibilityLabel("Search repositories")
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered(repoRows)) { item in
                                PickRow(item: item, selected: project.githubRepos.contains(item.id), multiple: true) {
                                    toggleRepository(item.id)
                                }
                            }
                            if filtered(repoRows).isEmpty && !query.isEmpty {
                                Text("No match for \u{201C}\(query)\u{201D}").font(.system(size: 13)).foregroundStyle(Soot.muted)
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if !project.githubRepos.isEmpty {
                        Text(Plural.text("^[\(project.githubRepos.count) repository](inflect: true) picked"))
                            .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    }
                }
                if !repos.isEmpty, app.repositoryMode == .perProject || ownRepositories.wrappedValue {
                    SwitchRow(title: "Count every pull request", detail: "Not only those linked to this project's issues",
                              isOn: Binding(get: { project.githubWholeRepo == true }, set: { project.githubWholeRepo = $0 }))
                        .frame(maxWidth: 420)
                }
            }
            HStack(spacing: 16) {
                Button(isNew ? "Continue" : "Done") { next() }
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.isConnected(.github) && !catalog.loading && repos.isEmpty)
                if app.isConnected(.github), app.repositoryMode == .perProject || ownRepositories.wrappedValue {
                    Button("Skip") { project.githubRepos = []; next() }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 14, weight: .medium)))
                }
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

    /// Which pull request's preview environment the project follows. Only with a repository;
    /// with several, each pull request says which one it is in.
    private var previewStep: some View {
        toolStep(.github, title: "Preview environment", rows: pullItems,
                 selection: Binding(get: { previewID },
                                    set: { id in
                                        let parts = id?.split(separator: "#", maxSplits: 1).map(String.init)
                                        project.previewRepository = parts?.first
                                        project.previewPullNumber = parts.flatMap { $0.count > 1 ? Int($0[1]) : nil }
                                        if project.previewPullNumber != nil { project.previewDismissed = nil } }),
                 createTitle: nil, more: nil,
                 loading: repos.contains { catalog.pulls[$0] == nil }) { EmptyView() }
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

    /// A tool's step: the title, a search, the list (with "Create …" first when it applies),
    /// then Continue and Skip. Not connected: one line and a way to Settings.
    private func toolStep<Extra: View>(_ service: ServiceKind, title: String, rows: [PickerItem],
                                       selection: Binding<String?>, createTitle: String?,
                                       more: (() -> Void)?, loading: Bool = false,
                                       @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(text: title)
            if !app.isConnected(service) {
                connectHint(service)
            } else if catalog.loading || loading {
                VStack(spacing: 6) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 44, radius: Soot.fieldRadius) } }
            } else {
                SootField(label: "", placeholder: "Search", text: $query, leadingSymbol: "magnifyingglass")
                    .accessibilityLabel("Search \(title.lowercased())")
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if let createTitle, query.isEmpty {
                            PickRow(item: PickerItem(id: Self.create, title: createTitle, symbol: "plus"),
                                    selected: selection.wrappedValue == Self.create) { selection.wrappedValue = Self.create }
                        }
                        ForEach(filtered(rows)) { item in
                            PickRow(item: item, selected: selection.wrappedValue == item.id) { selection.wrappedValue = item.id }
                        }
                        if filtered(rows).isEmpty && !query.isEmpty {
                            Text("No match for \u{201C}\(query)\u{201D}").font(.system(size: 13)).foregroundStyle(Soot.muted)
                                .padding(.vertical, 16)
                        }
                        if let more, query.isEmpty {
                            Button("Show every channel", action: more)
                                .buttonStyle(SecondaryButton())
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                extra()
            }
            HStack(spacing: 16) {
                Button(isNew ? "Continue" : "Done") { next() }
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.isConnected(service) && !catalog.loading && !loading && selection.wrappedValue == nil)
                if app.isConnected(service) {
                    Button("Skip") { selection.wrappedValue = nil; next() }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 14, weight: .medium)))
                }
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
                Button(saving ? "Saving…" : isNew ? "Create project" : "Save") { Task { await save() } }
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !nameOK)
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
        if app.repositoryMode == .mixed, !ownRepositories.wrappedValue {
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
                let members = ch.num_members.map { Plural.text("^[\($0) member](inflect: true)") }
                let subtitle = [ch.is_member == true ? "You're in it" : nil, members].compactMap { $0 }.joined(separator: " · ")
                return PickerItem(id: ch.id, title: "#\(ch.name)", subtitle: subtitle.isEmpty ? nil : subtitle,
                                  symbol: ch.is_private == true ? "lock" : nil)
            }
        linearRows = availableLinear.map {
            PickerItem(id: $0.id, title: $0.name, subtitle: $0.teams?.nodes.map(\.name).joined(separator: ", "))
        }
        repoRows = catalog.repos.map { PickerItem(id: $0.full_name, title: $0.full_name, subtitle: $0.private ? "Private" : "Public") }
    }

    /// Adding: a channel / Linear project with the project's name is picked; otherwise "Create".
    /// Editing never changes a pick on its own.
    private func suggest() {
        guard isNew, nameOK else { return }
        let expected = Naming.channelName(for: project.name, prefix: channelPrefix)
        if app.slack != nil, slackPick == nil || slackPick == Self.create {
            slackPick = availableChannels.first { $0.name == expected }?.id ?? Self.create
        }
        if app.linear != nil, linearPick == nil || linearPick == Self.create {
            linearPick = availableLinear.first { Naming.matches($0.name, project.name) }?.id ?? Self.create
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
