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

/// One question per screen, in the onboarding's frame. Adding: how to start, a name, then
/// Slack, Linear and GitHub. Editing: a hub of what is linked; each row opens its one step.
struct ProjectEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()

    @State var project: Project
    let isNew: Bool

    enum Step: Hashable { case start, pick(ImportSheet.Source), name, slack, linear, github, preview, hub }
    @State private var step: Step
    /// The step the next editor opens on ("Add a preview" from the project page), consumed once.
    static var openAt: Step?

    enum Mode: Hashable { case undecided, none, existing, create }
    @State private var slackMode: Mode = .undecided
    @State private var linearMode: Mode = .undecided
    @State private var newChannelName = ""
    @State private var privateChannel = false
    @State private var slackPick: String?
    @State private var linearPick: String?
    @State private var teamPick: String?
    @State private var saving = false
    @State private var error: String?

    init(project: Project = Project(name: ""), isNew: Bool = true) {
        var project = project
        self.isNew = isNew
        // Snapshots: DEVER_SNAPSHOT_STEP=name|slack|linear|github|preview opens that step.
        let snapshot = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_STEP"]
        let first: Step = switch snapshot {
        case "name": .name
        case "slack": .slack
        case "linear": .linear
        case "github": .github
        case "preview": .preview
        default: Self.openAt ?? (isNew ? .start : .hub)
        }
        Self.openAt = nil
        _step = State(initialValue: first)
        // Snapshots of the preview step need a repository to list pull requests of.
        if first == .preview, PreviewStore.simulation != nil, project.githubRepo == nil {
            project.githubRepo = PreviewStore.sampleRepo
            project.previewPullNumber = PreviewStore.samplePullNumber
        }
        _project = State(initialValue: project)
    }

    /// The adding path, for the marks at the bottom; the preview step exists once a repository is linked.
    private var path: [Step] { [.start, .name, .slack, .linear, .github] + (project.githubRepo != nil ? [.preview] : []) }

    var body: some View {
        Group {
            switch step {
            case .start: startStep
            case .pick(let source): ImportSheet(source: source, back: { step = .start })
            case .name: nameStep
            case .slack: slackStep
            case .linear: linearStep
            case .github: githubStep
            case .preview: previewStep
            case .hub: hubStep
            }
        }
        .task {
            slackMode = project.slack != nil ? .existing : (app.slack == nil ? .none : (isNew ? .undecided : .none))
            linearMode = project.linear != nil ? .existing : (app.linear == nil ? .none : (isNew ? .undecided : .none))
            slackPick = project.slack?.id
            linearPick = project.linear?.id
            await catalog.load(app)
            teamPick = teamPick ?? catalog.teams.first?.id
            autoMatch()
            // Snapshots: DEVER_SNAPSHOT_CHOICE=create shows the "create" tile open.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_CHOICE"] == "create" {
                project.name = "Checkout redesign"; slackMode = .create; linearMode = .create
            }
        }
        .onChange(of: project.name) { _, _ in autoMatch() }
    }

    // MARK: Steps

    private func frame<C: View>(_ step: Step, back: (() -> Void)?, @ViewBuilder content: @escaping () -> C) -> some View {
        StepSheet(step: isNew ? path.firstIndex(of: step) : nil, count: isNew ? path.count : 0,
                  back: back, close: { dismiss() }, content: content)
    }

    private var startStep: some View {
        frame(.start, back: nil) {
            VStack(alignment: .leading, spacing: 28) {
                StepTitle(text: "Add a project")
                VStack(spacing: 8) {
                    OptionRow(icon: AnyView(BrandLogo(service: .slack, size: 20)),
                              title: "From Slack channels",
                              detail: app.slack == nil ? "Connect Slack first"
                                  : channelPrefix.isEmpty ? "Pick channels" : "Channels starting with \(channelPrefix)",
                              recommended: app.slack != nil, enabled: app.slack != nil) { step = .pick(.slack) }
                    OptionRow(icon: AnyView(BrandLogo(service: .linear, size: 20).foregroundStyle(Soot.ink)),
                              title: "From Linear projects",
                              detail: app.linear == nil ? "Connect Linear first" : "Pick projects",
                              recommended: false, enabled: app.linear != nil) { step = .pick(.linear) }
                    OptionRow(icon: AnyView(Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)),
                              title: "From scratch", detail: "Name it, then link its tools",
                              recommended: app.slack == nil, enabled: true) { step = .name }
                }
                .frame(maxWidth: 420)
            }
        }
    }

    private var nameStep: some View {
        frame(.name, back: isNew ? { step = .start } : { step = .hub }) {
            VStack(alignment: .leading, spacing: 28) {
                StepTitle(text: "Name your project")
                UnderlineField(placeholder: "e.g. Checkout redesign", text: $project.name, size: 24,
                               onSubmit: { if nameOK { step = isNew ? .slack : .hub } })
                    .frame(maxWidth: 360)
                    .accessibilityLabel("Name in Dever")
                Button(isNew ? "Continue" : "Done") { step = isNew ? .slack : .hub }
                    .buttonStyle(LimeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameOK)
            }
        }
    }

    private var nameOK: Bool { !project.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var slackStep: some View {
        frame(.slack, back: { step = isNew ? .name : .hub }) {
            VStack(alignment: .leading, spacing: 28) {
                StepTitle(text: "Slack channel")
                if app.slack == nil {
                    connectHint(.slack)
                } else if catalog.loading {
                    VStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Skeleton(height: 48, radius: Soot.fieldRadius) } }
                        .frame(maxWidth: 420)
                } else {
                    VStack(spacing: 6) {
                        ChoiceCard(title: "Create #\(newChannelName.isEmpty ? suggestedChannel : newChannelName)",
                                   tag: "Recommended", selected: slackMode == .create, select: { slackMode = .create }) {
                            SootField(label: "Name", placeholder: suggestedChannel, text: $newChannelName)
                                .accessibilityLabel("New channel name")
                            SwitchRow(title: "Private", isOn: $privateChannel)
                        }
                        ChoiceCard(title: "Use an existing channel", selected: slackMode == .existing,
                                   select: { slackMode = .existing }) {
                            SearchPicker(label: "Slack channel", placeholder: "Pick a channel",
                                         items: channelItems, selection: $slackPick)
                        }
                        ChoiceCard(title: "Not now", selected: slackMode == .none, select: { slackMode = .none })
                    }
                    .frame(maxWidth: 420)
                }
                nextButton(ok: slackOK) { step = isNew ? .linear : .hub }
            }
        }
    }

    private var slackOK: Bool {
        app.slack == nil || slackMode == .create || slackMode == .none || (slackMode == .existing && slackPick != nil)
    }

    private var linearStep: some View {
        frame(.linear, back: { step = isNew ? .slack : .hub }) {
            VStack(alignment: .leading, spacing: 28) {
                StepTitle(text: "Linear project")
                if app.linear == nil {
                    connectHint(.linear)
                } else if catalog.loading {
                    VStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Skeleton(height: 48, radius: Soot.fieldRadius) } }
                        .frame(maxWidth: 420)
                } else {
                    VStack(spacing: 6) {
                        ChoiceCard(title: "Create \u{201C}\(project.name)\u{201D}", tag: "Recommended",
                                   selected: linearMode == .create, select: { linearMode = .create }) {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldLabel(text: "Team")
                                SearchPicker(label: "Team", placeholder: "Pick a team",
                                             items: catalog.teams.map { PickerItem(id: $0.id, title: $0.name) },
                                             selection: $teamPick)
                            }
                        }
                        ChoiceCard(title: "Use an existing project", selected: linearMode == .existing,
                                   select: { linearMode = .existing }) {
                            SearchPicker(label: "Linear project", placeholder: "Pick a project",
                                         items: availableLinear.map {
                                             PickerItem(id: $0.id, title: $0.name,
                                                        subtitle: $0.teams?.nodes.map(\.name).joined(separator: ", "))
                                         },
                                         selection: $linearPick)
                        }
                        ChoiceCard(title: "Not now", selected: linearMode == .none, select: { linearMode = .none })
                    }
                    .frame(maxWidth: 420)
                }
                nextButton(ok: linearOK) { step = isNew ? .github : .hub }
            }
        }
    }

    private var linearOK: Bool {
        app.linear == nil || linearMode == .none || (linearMode == .existing && linearPick != nil)
            || (linearMode == .create && teamPick != nil)
    }

    private var githubStep: some View {
        frame(.github, back: { step = isNew ? .linear : .hub }) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    StepTitle(text: "GitHub repository")
                    Text("Optional").font(.system(size: 14)).foregroundStyle(Soot.muted)
                }
                if app.github == nil {
                    connectHint(.github)
                } else if catalog.loading {
                    Skeleton(height: Soot.fieldHeight, radius: Soot.fieldRadius).frame(maxWidth: 420)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        SearchPicker(label: "GitHub repository", placeholder: "Pick a repository",
                                     actions: [PickerItem(id: Self.noneItem, title: "Not linked", symbol: "minus.circle")],
                                     items: catalog.repos.map {
                                         PickerItem(id: $0.full_name, title: $0.full_name, subtitle: $0.private ? "Private" : "Public")
                                     },
                                     selection: Binding<String?>(
                                        get: { project.githubRepo ?? Self.noneItem },
                                        set: { project.githubRepo = ($0 == Self.noneItem) ? nil : $0 }))
                        if project.githubRepo != nil {
                            SwitchRow(title: "Count every pull request",
                                      detail: "Not only those linked to this project's issues",
                                      isOn: Binding(get: { project.githubWholeRepo == true },
                                                    set: { project.githubWholeRepo = $0 }))
                        }
                    }
                    .frame(maxWidth: 420)
                }
                if isNew && project.githubRepo == nil { finishRow } else { nextButton(ok: true) { step = isNew ? .preview : .hub } }
            }
        }
    }

    /// Which pull request's preview environment the project follows. Only with a repository.
    private var previewStep: some View {
        frame(.preview, back: { step = isNew ? .github : .hub }) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    StepTitle(text: "Preview environment")
                    Text("Optional · the preview of one pull request, deployed and followed from the project page")
                        .font(.system(size: 14)).foregroundStyle(Soot.muted).fixedSize(horizontal: false, vertical: true)
                }
                if app.github == nil {
                    connectHint(.github)
                } else if let repo = project.githubRepo, catalog.pulls[repo] == nil {
                    Skeleton(height: Soot.fieldHeight, radius: Soot.fieldRadius).frame(maxWidth: 420)
                } else {
                    SearchPicker(label: "Pull request", placeholder: "Pick a pull request",
                                 actions: [PickerItem(id: Self.noneItem, title: "No preview", symbol: "minus.circle")],
                                 items: pullItems,
                                 selection: Binding<String?>(
                                    get: { project.previewPullNumber.map(String.init) ?? Self.noneItem },
                                    set: { project.previewPullNumber = $0.flatMap(Int.init) }))
                        .frame(maxWidth: 420)
                }
                if isNew { finishRow } else { nextButton(ok: true) { step = .hub } }
            }
        }
        .task(id: project.githubRepo) {
            if let repo = project.githubRepo, app.github != nil { await catalog.loadPulls(repo, app) }
        }
    }

    /// The repository's open pull requests, the project's own (citing one of its issues) first,
    /// then by number, newest first; the one already linked stays listed even when closed.
    private var pullItems: [PickerItem] {
        guard let repo = project.githubRepo else { return [] }
        let pulls = catalog.pulls[repo] ?? []
        let identifiers = project.linear.map { Set(IssueStore.shared.issues(project: $0.id).map(\.identifier)) } ?? []
        func isMine(_ p: GitHubPull) -> Bool {
            identifiers.contains { p.title.localizedCaseInsensitiveContains($0) || p.head.ref.localizedCaseInsensitiveContains($0) }
        }
        var items = pulls
            .sorted { (isMine($0) ? 0 : 1, -$0.number) < (isMine($1) ? 0 : 1, -$1.number) }
            .map { p in
                PickerItem(id: String(p.number), title: "#\(p.number) \(PullTitle.split(p.title).title)",
                           subtitle: [isMine(p) ? "This project" : nil, p.draft == true ? "Draft" : nil, p.user.login].compactMap { $0 }.joined(separator: " · "),
                           symbol: p.draft == true ? "pencil.line" : "arrow.triangle.pull")
            }
        if let n = project.previewPullNumber, !pulls.contains(where: { $0.number == n }) {
            items.insert(PickerItem(id: String(n), title: "#\(n)", subtitle: "Not open any more", symbol: "arrow.triangle.pull"), at: 0)
        }
        return items
    }

    /// Editing: what is linked, one row each; a row opens its step.
    private var hubStep: some View {
        frame(.hub, back: nil) {
            VStack(alignment: .leading, spacing: 28) {
                StepTitle(text: "Edit project")
                VStack(spacing: 8) {
                    hubRow(icon: AnyView(Image(systemName: "textformat").font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)),
                           title: "Name", value: project.name) { step = .name }
                    hubRow(icon: AnyView(BrandLogo(service: .slack, size: 18)), title: "Slack",
                           value: slackSummary) { step = .slack }
                    hubRow(icon: AnyView(BrandLogo(service: .linear, size: 18).foregroundStyle(Soot.ink)), title: "Linear",
                           value: linearSummary) { step = .linear }
                    hubRow(icon: AnyView(BrandLogo(service: .github, size: 18).foregroundStyle(Soot.ink)), title: "GitHub",
                           value: project.githubRepo ?? "Not linked") { step = .github }
                    if project.githubRepo != nil {
                        hubRow(icon: AnyView(Image(systemName: "globe").font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)),
                               title: "Preview", value: project.previewPullNumber.map { "Pull request #\($0)" } ?? "No preview") { step = .preview }
                    }
                }
                .frame(maxWidth: 420)
                finishRow
            }
        }
    }

    private func hubRow(icon: AnyView, title: String, value: String, open: @escaping () -> Void) -> some View {
        OptionRow(icon: icon, title: title, detail: value, recommended: false, enabled: true, action: open)
    }

    private var slackSummary: String {
        switch slackMode {
        case .create: "Create #\(newChannelName.isEmpty ? suggestedChannel : newChannelName)"
        case .existing: catalog.channels.first { $0.id == slackPick }.map { "#\($0.name)" } ?? project.slack.map { "#\($0.name)" } ?? "Pick a channel"
        case .none, .undecided: "Not linked"
        }
    }

    private var linearSummary: String {
        switch linearMode {
        case .create: "Create \u{201C}\(project.name)\u{201D}"
        case .existing: catalog.linearProjects.first { $0.id == linearPick }?.name ?? project.linear?.name ?? "Pick a project"
        case .none, .undecided: "Not linked"
        }
    }

    /// The last step's button, with what it will do outside Dever beside it.
    private var finishRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button(saving ? "Saving…" : isNew ? "Create project" : "Save") { Task { await save() } }
                    .buttonStyle(LimeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !nameOK || !slackOK || !linearOK)
                if !consequence.isEmpty {
                    Text(consequence).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(2)
                }
            }
            ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
        }
    }

    private func nextButton(ok: Bool, go: @escaping () -> Void) -> some View {
        Button(isNew ? "Continue" : "Done", action: go)
            .buttonStyle(LimeButton())
            .keyboardShortcut(.defaultAction)
            .disabled(!ok)
    }

    private func connectHint(_ service: ServiceKind) -> some View {
        Button {
            dismiss()
            NotificationCenter.default.post(name: .showScreen, object: SidebarItem.settings)
        } label: {
            HStack(spacing: 6) { Text("Connect \(service.label) in Settings"); Image(systemName: "arrow.up.right") }
                .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Soot.lime)
        .modifier(FocusOutline(radius: 6))
    }

    // MARK: Data

    private static let noneItem = "__none__"

    private var suggestedChannel: String {
        Naming.channelName(for: project.name.isEmpty ? "project" : project.name, prefix: channelPrefix)
    }

    /// Channels you're in first, then the rest, each with its member count.
    private var channelItems: [PickerItem] {
        availableChannels
            .sorted { ($0.is_member == true ? 0 : 1, $0.name) < ($1.is_member == true ? 0 : 1, $1.name) }
            .map { ch in
                let members = ch.num_members.map { Plural.text("^[\($0) member](inflect: true)") }
                let subtitle = [ch.is_member == true ? "You're in it" : nil, members].compactMap { $0 }.joined(separator: " · ")
                return PickerItem(id: ch.id, title: "#\(ch.name)", subtitle: subtitle.isEmpty ? nil : subtitle,
                                  symbol: ch.is_private == true ? "lock" : nil)
            }
    }

    private var availableChannels: [SlackChannel] {
        let taken = app.linkedSlackIDs.subtracting([project.slack?.id].compactMap { $0 })
        return catalog.channels.filter { !taken.contains($0.id) }
    }

    private var availableLinear: [LinearProject] {
        let taken = app.linkedLinearIDs.subtracting([project.linear?.id].compactMap { $0 })
        return catalog.linearProjects.filter { !taken.contains($0.id) }
    }

    /// If a matching channel / Linear project already exists, suggest it instead of creating a duplicate.
    private func autoMatch() {
        guard !project.name.isEmpty else { return }
        let expected = Naming.channelName(for: project.name, prefix: channelPrefix)
        if project.slack == nil, let ch = availableChannels.first(where: { $0.name == expected }) {
            slackMode = .existing; slackPick = ch.id
        }
        if project.linear == nil, let lp = availableLinear.first(where: { Naming.matches($0.name, project.name) }) {
            linearMode = .existing; linearPick = lp.id
        }
    }

    /// What saving will do outside Dever, stated before the user commits.
    private var consequence: String {
        var parts: [String] = []
        if slackMode == .create {
            let name = newChannelName.isEmpty ? Naming.channelName(for: project.name, prefix: channelPrefix) : newChannelName
            parts.append("creates #\(name) in Slack")
        }
        if linearMode == .create, let team = catalog.teams.first(where: { $0.id == teamPick }) {
            parts.append("creates a Linear project in \(team.name)")
        }
        guard !parts.isEmpty, nameOK else { return "" }
        return parts.joined(separator: " and ").prefix(1).uppercased() + parts.joined(separator: " and ").dropFirst() + "."
    }

    private func save() async {
        error = nil
        saving = true
        defer { saving = false }
        do {
            var p = project
            p.name = p.name.trimmingCharacters(in: .whitespaces)
            switch slackMode {
            case .create:
                let name = newChannelName.isEmpty ? Naming.channelName(for: p.name, prefix: channelPrefix) : newChannelName
                let ch = try await app.withSlack { try await $0.createChannel(name: name, isPrivate: privateChannel) }
                p.slack = .init(id: ch.id, name: ch.name)
            case .existing:
                if let id = slackPick, let ch = catalog.channels.first(where: { $0.id == id }) {
                    p.slack = .init(id: ch.id, name: ch.name)
                }
            case .none, .undecided:
                p.slack = nil
            }
            switch linearMode {
            case .create:
                guard let team = teamPick else { throw AppError.message("Pick a Linear team") }
                let lp = try await app.withLinear { try await $0.createProject(name: p.name, teamIDs: [team]) }
                p.linear = .init(id: lp.id, name: lp.name, url: lp.url)
            case .existing:
                if let id = linearPick, let lp = catalog.linearProjects.first(where: { $0.id == id }) {
                    p.linear = .init(id: lp.id, name: lp.name, url: lp.url)
                }
            case .none, .undecided:
                p.linear = nil
            }
            if p.githubRepo == nil { p.previewPullNumber = nil }
            if p.previewPullNumber != project.previewPullNumber || p.githubRepo != project.githubRepo { PreviewStore.shared.forget(p.id) }
            app.upsert(p)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
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
        /// Why the row was hidden while narrowed; shown quietly on hover.
        var aside: String? = nil
    }

    private var isNarrowed: Bool { source == .slack && narrowed && search.isEmpty }

    private var candidates: [Candidate] {
        let rows: [Candidate]
        switch source {
        case .slack:
            rows = catalog.channels
                .filter { !app.linkedSlackIDs.contains($0.id) }
                .filter { !isNarrowed || fitsPrefix($0) && $0.is_member == true }
                .map { ch in
                    let name = Naming.projectName(fromChannel: ch.name, prefix: channelPrefix)
                    let aside = ch.is_member != true ? "You're not in this channel yet"
                              : !fitsPrefix(ch) ? "Doesn't start with \(channelPrefix)" : nil
                    return Candidate(id: ch.id, title: "#\(ch.name)", projectName: name,
                                     match: linearMatch(for: name)?.name, aside: aside)
                }
        case .linear:
            rows = catalog.linearProjects
                .filter { !app.linkedLinearIDs.contains($0.id) }
                .map { lp in
                    Candidate(id: lp.id, title: lp.name, projectName: lp.name,
                              match: slackMatch(for: lp.name).map { "#\($0.name)" })
                }
        }
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
                StepTitle(text: source == .slack ? "Pick channels" : "Pick projects")
                SootField(label: "", placeholder: "Search", text: $search, leadingSymbol: "magnifyingglass")
                    .accessibilityLabel(source == .slack ? "Search channels" : "Search projects")
                ForEach(catalog.errors, id: \.self) { ErrorLabel($0) }
                ScrollView { list }
                    .frame(maxHeight: .infinity)
                footer
            }
        }
        .task { await catalog.load(app) }
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
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
            } else if !search.isEmpty {
                Button("Clear search") { search = "" }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
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
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                .frame(minHeight: 28)
                .modifier(FocusOutline(radius: 6))
            }
            if hiddenCount > 0 {
                Button("Find more channels") { narrowed = false }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                    .frame(minHeight: 28)
                    .modifier(FocusOutline(radius: 6))
                    .help(Plural.text("^[\(hiddenCount) more channel](inflect: true) you're not in or without the prefix"))
            }
            Spacer()
            Button(selection.isEmpty ? "Add" : "Add ^[\(selection.count) project](inflect: true)") { importSelected() }
                .buttonStyle(LimeButton())
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

    private func importSelected() {
        for id in selection {
            switch source {
            case .slack:
                guard let ch = catalog.channels.first(where: { $0.id == id }) else { continue }
                let name = Naming.projectName(fromChannel: ch.name, prefix: channelPrefix)
                var p = Project(name: name, slack: .init(id: ch.id, name: ch.name))
                if let lp = linearMatch(for: name) { p.linear = .init(id: lp.id, name: lp.name, url: lp.url) }
                app.upsert(p)
            case .linear:
                guard let lp = catalog.linearProjects.first(where: { $0.id == id }) else { continue }
                var p = Project(name: lp.name, linear: .init(id: lp.id, name: lp.name, url: lp.url))
                if let ch = slackMatch(for: lp.name) { p.slack = .init(id: ch.id, name: ch.name) }
                app.upsert(p)
            }
        }
        dismiss()
    }
}

/// One channel or project to pick; hovering a row that was hidden while narrowed says why.
private struct ImportRow: View {
    let candidate: ImportSheet.Candidate
    let counterpart: ServiceKind
    let on: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let c = candidate
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    if hovering, let aside = c.aside {
                        Text(aside).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    } else if c.projectName != c.title {
                        Text(c.projectName).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
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
            .contentShape(RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .modifier(FocusOutline(radius: Soot.fieldRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(c.aside ?? "")
    }
}
