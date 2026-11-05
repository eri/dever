import SwiftUI

/// Reference data loaded once per sheet (channels, Linear projects, teams, repos).
@MainActor
final class Catalog: ObservableObject {
    @Published var channels: [SlackChannel] = []
    @Published var linearProjects: [LinearProject] = []
    @Published var teams: [LinearTeam] = []
    @Published var repos: [GitHubRepo] = []
    @Published var loading = false
    @Published var errors: [String] = []

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

/// Adding a project is guided: first how to start (from Slack, from Linear, from scratch),
/// then that one step. Editing opens the form directly.
struct ProjectEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    var isNew: Bool

    enum Step: Hashable { case start, pick(ImportSheet.Source), form }
    @State private var step: Step

    init(project: Project = Project(name: ""), isNew: Bool = true) {
        _project = State(initialValue: project)
        self.isNew = isNew
        // Snapshots: DEVER_SNAPSHOT_STEP=form opens the form straight away.
        let snapshotForm = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_STEP"] == "form"
        _step = State(initialValue: isNew && !snapshotForm ? .start : .form)
    }

    var body: some View {
        switch step {
        case .start:
            StartStep(choose: { step = $0 }, close: { dismiss() })
        case .pick(let source):
            ImportSheet(source: source, back: { step = .start })
        case .form:
            ProjectForm(project: project, isNew: isNew, back: isNew ? { step = .start } : nil)
        }
    }
}

/// "How do you want to start?": one recommended path first, the others under it, as in onboarding.
private struct StartStep: View {
    @EnvironmentObject var app: AppState
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    let choose: (ProjectEditorSheet.Step) -> Void
    let close: () -> Void

    var body: some View {
        SheetScaffold(width: 520) {
            VStack(alignment: .leading, spacing: 8) {
                SheetTitle(title: "Add a project", mark: { ActionIcon(symbol: "plus") }, close: close)
                Text("A project follows one Slack channel and one Linear project. Start from what you already have, or from nothing.")
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } content: {
            VStack(spacing: 8) {
                OptionRow(icon: AnyView(BrandLogo(service: .slack, size: 20)),
                          title: "From Slack channels",
                          detail: app.slack == nil ? "Connect Slack first"
                              : channelPrefix.isEmpty ? "Pick channels; Dever links matching Linear projects"
                              : "Starts with \(channelPrefix); matching Linear projects are linked",
                          recommended: app.slack != nil, enabled: app.slack != nil) { choose(.pick(.slack)) }
                OptionRow(icon: AnyView(BrandLogo(service: .linear, size: 20).foregroundStyle(Soot.ink)),
                          title: "From Linear projects",
                          detail: app.linear == nil ? "Connect Linear first" : "Pick projects; Dever links matching channels",
                          recommended: false, enabled: app.linear != nil) { choose(.pick(.linear)) }
                OptionRow(icon: AnyView(Image(systemName: "sparkles").font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)),
                          title: "From scratch",
                          detail: "Name it; create or pick its channel and project",
                          recommended: app.slack == nil, enabled: true) { choose(.form) }
            }
        }
    }
}

/// The form: a name, then for each tool a choice (create, use existing, skip) with what it needs.
private struct ProjectForm: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()

    @State var project: Project
    let isNew: Bool
    var back: (() -> Void)? = nil

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
    @State private var nameError: String?

    var body: some View {
        SheetScaffold(width: 560, height: 640) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let back { BackButton(action: back) }
                    SheetTitle(title: isNew ? "New project" : "Edit project",
                               mark: { if back == nil { ActionIcon(symbol: "pencil") } }, close: { dismiss() })
                }
                Text(isNew ? "Name it, then decide what to do for each tool."
                           : "Change what this project follows.")
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
            }
        } content: {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    SootField(label: "Name in Dever", placeholder: "e.g. Checkout redesign", text: $project.name)
                    if let nameError { ErrorLabel(nameError) }
                }
                slackSection
                linearSection
                githubSection
                ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
            }
        } footer: {
            HStack(spacing: 12) {
                Text(saving ? "Saving…" : consequence)
                    .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(2)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButton())
                Button(isNew ? "Create project" : "Save") { Task { await save() } }
                    .buttonStyle(LimeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
        }
        .task {
            // Editing shows what is linked; adding asks. A connected tool with nothing linked is a question.
            slackMode = project.slack != nil ? .existing : (app.slack == nil ? .none : (isNew ? .undecided : .none))
            linearMode = project.linear != nil ? .existing : (app.linear == nil ? .none : (isNew ? .undecided : .none))
            slackPick = project.slack?.id
            linearPick = project.linear?.id
            await catalog.load(app)
            teamPick = teamPick ?? catalog.teams.first?.id
            autoMatch()
            // Snapshots: DEVER_SNAPSHOT_CHOICE=create shows both "create" tiles open.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_CHOICE"] == "create" {
                project.name = "Checkout redesign"; slackMode = .create; linearMode = .create
            }
        }
        .onChange(of: project.name) { _, _ in autoMatch() }
    }

    // MARK: Sections

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

    /// A tool's section: its name, then the choice tiles (or a way to connect it).
    private func toolSection<Choices: View>(_ service: ServiceKind, title: String,
                                            @ViewBuilder choices: () -> Choices) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title) { BrandLogo(service: service, size: 16).foregroundStyle(Soot.ink) }
            if app.isConnected(service) {
                if catalog.loading {
                    Skeleton(height: 48, radius: Soot.fieldRadius)
                } else {
                    VStack(spacing: 6) { choices() }
                }
            } else {
                Button {
                    dismiss()
                    NotificationCenter.default.post(name: .showScreen, object: SidebarItem.settings)
                } label: {
                    HStack(spacing: 6) { Text("Connect \(service.label)"); Image(systemName: "arrow.up.right") }
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Soot.lime)
                .help("Opens Settings, where you can connect \(service.label)")
                .modifier(FocusOutline(radius: 6))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var slackSection: some View {
        toolSection(.slack, title: "Slack channel") {
            ChoiceCard(title: project.name.isEmpty && newChannelName.isEmpty ? "Create a channel named after it"
                                : "Create #\(newChannelName.isEmpty ? suggestedChannel : newChannelName)",
                       detail: "A new channel in your workspace", tag: isNew ? "Recommended" : nil,
                       selected: slackMode == .create, select: { slackMode = .create }) {
                SootField(label: "Channel name", placeholder: suggestedChannel, text: $newChannelName)
                    .accessibilityLabel("New channel name")
                SwitchRow(title: "Private channel", detail: "Only invited people can see it", isOn: $privateChannel)
            }
            ChoiceCard(title: "Use an existing channel", detail: channelDetail,
                       selected: slackMode == .existing, select: { slackMode = .existing }) {
                SearchPicker(label: "Slack channel", placeholder: "Pick a channel",
                             items: channelItems, selection: $slackPick)
            }
            ChoiceCard(title: "No channel for now", selected: slackMode == .none, select: { slackMode = .none })
        }
    }

    private var channelDetail: String? {
        guard slackMode != .existing, let id = slackPick,
              let ch = catalog.channels.first(where: { $0.id == id }) else { return nil }
        return "#\(ch.name)"
    }

    private var linearSection: some View {
        toolSection(.linear, title: "Linear project") {
            ChoiceCard(title: project.name.isEmpty ? "Create a Linear project with this name"
                                : "Create \u{201C}\(project.name)\u{201D} in Linear",
                       detail: "A new project with the same name", tag: isNew ? "Recommended" : nil,
                       selected: linearMode == .create, select: { linearMode = .create }) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "In team")
                    SearchPicker(label: "Team", placeholder: "Pick a team",
                                 items: catalog.teams.map { PickerItem(id: $0.id, title: $0.name) },
                                 selection: $teamPick)
                }
            }
            ChoiceCard(title: "Use an existing project", detail: linearDetail,
                       selected: linearMode == .existing, select: { linearMode = .existing }) {
                SearchPicker(label: "Linear project", placeholder: "Pick a project",
                             items: availableLinear.map {
                                 PickerItem(id: $0.id, title: $0.name,
                                            subtitle: $0.teams?.nodes.map(\.name).joined(separator: ", "))
                             },
                             selection: $linearPick)
            }
            ChoiceCard(title: "No Linear project for now", selected: linearMode == .none, select: { linearMode = .none })
        }
    }

    private var linearDetail: String? {
        guard linearMode != .existing, let id = linearPick,
              let lp = catalog.linearProjects.first(where: { $0.id == id }) else { return nil }
        return lp.name
    }

    private var githubSection: some View {
        toolSection(.github, title: "GitHub repository") {
            VStack(alignment: .leading, spacing: 12) {
                SearchPicker(label: "GitHub repository", placeholder: "Not linked",
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
        }
    }

    private static let noneItem = "__none__"

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
            parts.append("create #\(name) in Slack")
        }
        if linearMode == .create, let team = catalog.teams.first(where: { $0.id == teamPick }) {
            parts.append("create a Linear project in \(team.name)")
        }
        guard !parts.isEmpty, !project.name.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return "Will " + parts.joined(separator: " and ") + "."
    }

    private func save() async {
        error = nil
        nameError = nil
        guard !project.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            nameError = "Enter a project name."
            return
        }
        if slackMode == .undecided && app.slack != nil {
            error = "Choose what to do for Slack."
            return
        }
        if linearMode == .undecided && app.linear != nil {
            error = "Choose what to do for Linear."
            return
        }
        if slackMode == .existing && slackPick == nil {
            error = "Pick a Slack channel, or choose \u{201C}No channel for now\u{201D}."
            return
        }
        if linearMode == .existing && linearPick == nil {
            error = "Pick a Linear project, or choose \u{201C}No Linear project for now\u{201D}."
            return
        }
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
    @State private var onlyPrefixed = true
    @State private var onlyMine = true
    @State private var search = ""

    private struct Candidate: Identifiable {
        var id: String
        var title: String
        var projectName: String
        var match: String?
    }

    private var candidates: [Candidate] {
        let rows: [Candidate]
        switch source {
        case .slack:
            rows = catalog.channels
                .filter { !app.linkedSlackIDs.contains($0.id) }
                .filter { !onlyPrefixed || channelPrefix.isEmpty || $0.name.hasPrefix(channelPrefix) }
                .filter { !onlyMine || $0.is_member == true }
                .map { ch in
                    let name = Naming.projectName(fromChannel: ch.name, prefix: channelPrefix)
                    return Candidate(id: ch.id, title: "#\(ch.name)", projectName: name,
                                     match: linearMatch(for: name)?.name)
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

    /// The other side of each pair: Linear for channels, Slack for Linear projects.
    private var counterpart: ServiceKind { source == .slack ? .linear : .slack }

    var body: some View {
        SheetScaffold(width: 600, height: 620) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        if let back { BackButton(action: back) }
                        SheetTitle(title: source == .slack ? "From Slack channels" : "From Linear projects",
                                   mark: { if back == nil { ActionIcon(symbol: "plus") } }, close: { dismiss() })
                    }
                    Text(source == .slack ? "Each channel becomes a project. A Linear project with the same name is linked."
                                          : "Each Linear project becomes a project. A channel with the same name is linked.")
                        .font(.system(size: 13)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SootField(label: source == .slack ? "Search channels" : "Search projects",
                              placeholder: source == .slack ? "Channel name" : "Project name",
                              text: $search, leadingSymbol: "magnifyingglass")
                    if source == .slack {
                        HStack(spacing: 10) {
                            if !channelPrefix.isEmpty {
                                FilterChip(label: "Starts with \(channelPrefix)", on: $onlyPrefixed)
                                    .help("Only channels starting with \(channelPrefix)")
                            }
                            FilterChip(label: "I'm in", on: $onlyMine)
                                .help("Only channels you're a member of")
                        }
                    }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(catalog.errors, id: \.self) { ErrorLabel($0) }
                list
            }
        } footer: {
            footer
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
                    ForEach(candidates) { c in row(c) }
                }
        }
    }

    private func row(_ c: Candidate) -> some View {
        let on = selection.contains(c.id)
        return Button {
            if on { selection.remove(c.id) } else { selection.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    if c.projectName != c.title {
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
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(search.isEmpty ? (source == .slack ? "No channel to import" : "No project to import")
                                : "No result for \u{201C}\(search)\u{201D}")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)
            if source == .slack && search.isEmpty && (onlyPrefixed || onlyMine) {
                Button("Show all channels") { onlyPrefixed = false; onlyMine = false }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
            } else if !search.isEmpty {
                Button("Clear search") { search = "" }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !candidates.isEmpty {
                Button(selection.count == candidates.count ? "Select none" : "Select all") {
                    selection = selection.count == candidates.count ? [] : Set(candidates.map(\.id))
                }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                .frame(minHeight: 28)
                .modifier(FocusOutline(radius: 6))
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(QuietButton())
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

/// A filter that can be switched off: lime when on.
private struct FilterChip: View {
    let label: String
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? Soot.limeInk : Soot.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(on ? Soot.lime : Soot.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Soot.edge))
            .contentShape(Capsule())
            .modifier(FocusOutline(radius: 14))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
