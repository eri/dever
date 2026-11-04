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

// MARK: - New / edit project

struct ProjectEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @StateObject private var catalog = Catalog()

    @State var project: Project
    var isNew: Bool

    enum SlackMode: Hashable { case none, existing, create }
    enum LinearMode: Hashable { case none, existing, create }
    @State private var slackMode: SlackMode = .create
    @State private var linearMode: LinearMode = .create
    @State private var newChannelName = ""
    @State private var privateChannel = false
    @State private var slackPick: String?
    @State private var linearPick: String?
    @State private var teamPick: String?
    @State private var saving = false
    @State private var error: String?
    @State private var nameError: String?

    init(project: Project = Project(name: ""), isNew: Bool = true) {
        _project = State(initialValue: project)
        self.isNew = isNew
    }

    var body: some View {
        SheetScaffold(width: 640) {
            VStack(alignment: .leading, spacing: 8) {
                SheetTitle(title: isNew ? "New project" : "Edit project",
                           mark: { ActionIcon(symbol: isNew ? "plus" : "pencil") }, close: { dismiss() })
                Text("A Dever project follows one Slack channel and one Linear project.")
                    .font(.system(size: 14)).foregroundStyle(Soot.muted)
            }
        } content: {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    SootField(label: "Name in Dever", placeholder: "e.g. Checkout redesign", text: $project.name)
                    if let nameError { ErrorLabel(nameError) }
                }
                // One section per tool: its name, then the one choice, then what that choice needs.
                slackSection
                Rectangle().fill(Soot.line).frame(height: 1)
                linearSection
                Rectangle().fill(Soot.line).frame(height: 1)
                githubSection
                ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
            }
        } footer: {
            HStack(spacing: 12) {
                Text(saving ? "Saving…" : consequence)
                    .font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(2)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButton())
                Button(isNew ? "Create project" : "Save") { Task { await save() } }
                    .buttonStyle(LimeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // New projects default to creating what's missing; edits never create anything implicitly.
            let defaultMode: SlackMode = isNew ? .create : .none
            slackMode = project.slack != nil ? .existing : (app.slack == nil ? .none : defaultMode)
            linearMode = project.linear != nil ? .existing : (app.linear == nil ? .none : (isNew ? .create : .none))
            slackPick = project.slack?.id
            linearPick = project.linear?.id
            await catalog.load(app)
            teamPick = teamPick ?? catalog.teams.first?.id
            autoMatch()
        }
        .onChange(of: project.name) { _, _ in autoMatch() }
    }

    private static let newItem = "__new__"
    private static let noneItem = "__none__"

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

    /// A tool's section: logo and name, then its control (or why there is none), then extras.
    private func toolSection<Control: View, Extra: View>(_ service: ServiceKind, title: String,
                                                         @ViewBuilder control: () -> Control,
                                                         @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: title) { BrandLogo(service: service, size: 18).foregroundStyle(Soot.ink) }
            if app.isConnected(service) {
                if catalog.loading {
                    Skeleton(height: Soot.fieldHeight, radius: Soot.fieldRadius)
                } else {
                    control().labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button {
                    dismiss()
                    NotificationCenter.default.post(name: .showScreen, object: SidebarItem.settings)
                } label: {
                    HStack(spacing: 6) { Text("Connect \(service.label)"); Image(systemName: "arrow.up.right") }
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Soot.lime)
                .help("Opens Settings, where you can connect \(service.label)")
                .modifier(FocusOutline(radius: 6))
            }
            extra()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var slackSection: some View {
        toolSection(.slack, title: "Slack channel") {
            SearchPicker(label: "Slack channel", placeholder: "Not linked",
                         actions: [PickerItem(id: Self.noneItem, title: "Not linked", symbol: "minus.circle"),
                                   PickerItem(id: Self.newItem, title: "New channel…", symbol: "plus")],
                         items: channelItems,
                         selection: Binding<String?>(
                            get: { slackMode == .create ? Self.newItem : slackMode == .existing ? slackPick : Self.noneItem },
                            set: { v in
                                switch v {
                                case Self.newItem?: slackMode = .create
                                case Self.noneItem?, nil: slackMode = .none
                                case let id?: slackMode = .existing; slackPick = id
                                }
                            }))
        } extra: {
            if slackMode == .create && app.slack != nil {
                VStack(alignment: .leading, spacing: 16) {
                    SootField(label: "Channel name",
                              placeholder: Naming.channelName(for: project.name.isEmpty ? "project" : project.name,
                                                              prefix: channelPrefix),
                              text: $newChannelName)
                        .accessibilityLabel("New channel name")
                    SwitchRow(title: "Private channel", detail: "Only invited people can see it", isOn: $privateChannel)
                }
                .padding(.top, 6)
            }
        }
    }

    private var linearSection: some View {
        toolSection(.linear, title: "Linear project") {
            SearchPicker(label: "Linear project", placeholder: "Not linked",
                         actions: [PickerItem(id: Self.noneItem, title: "Not linked", symbol: "minus.circle"),
                                   PickerItem(id: Self.newItem, title: "New project…", symbol: "plus")],
                         items: availableLinear.map {
                             PickerItem(id: $0.id, title: $0.name,
                                        subtitle: $0.teams?.nodes.map(\.name).joined(separator: ", "))
                         },
                         selection: Binding<String?>(
                            get: { linearMode == .create ? Self.newItem : linearMode == .existing ? linearPick : Self.noneItem },
                            set: { v in
                                switch v {
                                case Self.newItem?: linearMode = .create
                                case Self.noneItem?, nil: linearMode = .none
                                case let id?: linearMode = .existing; linearPick = id
                                }
                            }))
        } extra: {
            if linearMode == .create && app.linear != nil && !catalog.loading {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "In team")
                    SearchPicker(label: "Team", placeholder: "Pick a team",
                                 items: catalog.teams.map { PickerItem(id: $0.id, title: $0.name) },
                                 selection: $teamPick)
                }
                .padding(.top, 6)
            }
        }
    }

    private var githubSection: some View {
        toolSection(.github, title: "GitHub repository") {
            SearchPicker(label: "GitHub repository", placeholder: "Not linked",
                         actions: [PickerItem(id: Self.noneItem, title: "Not linked", symbol: "minus.circle")],
                         items: catalog.repos.map {
                             PickerItem(id: $0.full_name, title: $0.full_name, subtitle: $0.private ? "Private" : "Public")
                         },
                         selection: Binding<String?>(
                            get: { project.githubRepo ?? Self.noneItem },
                            set: { project.githubRepo = ($0 == Self.noneItem) ? nil : $0 }))
        } extra: {
            if project.githubRepo != nil && app.github != nil {
                SwitchRow(title: "Count every pull request",
                          detail: "Not only those linked to this project's issues",
                          isOn: Binding(get: { project.githubWholeRepo == true },
                                        set: { project.githubWholeRepo = $0 }))
                    .padding(.top, 6)
            }
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
        if slackMode == .existing && slackPick == nil {
            error = "Pick a Slack channel, or choose Later."
            return
        }
        if linearMode == .existing && linearPick == nil {
            error = "Pick a Linear project, or choose Later."
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
            case .none:
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
            case .none:
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
        SheetScaffold(width: 680, height: 660) {
            VStack(alignment: .leading, spacing: 24) {
                SheetTitle(title: source == .slack ? "Import channels" : "Import projects", mark: {
                    ActionIcon(symbol: "square.and.arrow.down")
                }, close: { dismiss() })
                VStack(alignment: .leading, spacing: 14) {
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
                        .padding(.horizontal, 18).frame(height: 60)
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
            HStack(spacing: 14) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    if c.projectName != c.title {
                        Text(c.projectName).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    BrandLogo(service: counterpart, size: 13)
                        .foregroundStyle(c.match == nil ? Soot.muted : Soot.ink)
                        .opacity(c.match == nil ? 0.5 : 1)
                    Text(c.match ?? "No match").font(.system(size: 13))
                        .foregroundStyle(c.match == nil ? Soot.muted : Soot.ink).lineLimit(1)
                }
                .help(c.match == nil ? "Link it later from the project" : "Linked automatically")
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
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
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
            if source == .slack && search.isEmpty && (onlyPrefixed || onlyMine) {
                Button("Show all channels") { onlyPrefixed = false; onlyMine = false }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.lime)
            } else if !search.isEmpty {
                Button("Clear search") { search = "" }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.lime)
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
                .buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                .frame(minHeight: 32)
                .modifier(FocusOutline(radius: 6))
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(QuietButton())
            Button("Import ^[\(selection.count) project](inflect: true)") { importSelected() }
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Soot.limeInk : Soot.ink)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(on ? Soot.lime : Soot.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Soot.edge))
            .contentShape(Capsule())
            .modifier(FocusOutline(radius: 16))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
