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
        VStack(alignment: .leading, spacing: 24) {
            SheetTitle(title: isNew ? "New project" : "Edit project", mark: { DeverMark().frame(width: 22, height: 22) },
                       close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        UnderlineField(placeholder: "Project name", text: $project.name, size: 22)
                            .accessibilityLabel("Project name")
                        if let nameError { ErrorLabel(nameError) }
                    }
                    slackSection
                    linearSection
                    githubSection
                    ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
                }
                .padding(.bottom, 8)
            }
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
        .sootSheet(width: 560, height: 640)
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

    /// One service block: its logo and name, its choice of mode, then the one field that mode needs.
    private func block<Content: View>(_ service: ServiceKind, optional: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BrandLogo(service: service, size: 18).foregroundStyle(Soot.ink)
                Text(service.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(Soot.ink)
                if optional { Text("Optional").font(.system(size: 13)).foregroundStyle(Soot.muted) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
    }

    private func notConnected(_ service: ServiceKind) -> some View {
        Text("Not connected — connect \(service.label) in Accounts.").font(.system(size: 13)).foregroundStyle(Soot.muted)
    }

    private var slackSection: some View {
        block(.slack) {
            if app.slack == nil {
                notConnected(.slack)
            } else {
                ChipPicker(options: [("New channel", SlackMode.create), ("Existing", .existing), ("Later", .none)],
                           selection: $slackMode)
                switch slackMode {
                case .create:
                    HStack(spacing: 12) {
                        UnderlineField(placeholder: "#" + Naming.channelName(for: project.name.isEmpty ? "project" : project.name,
                                                                          prefix: channelPrefix),
                                       text: $newChannelName, size: 15)
                        Toggle("Private", isOn: $privateChannel).toggleStyle(.switch).tint(Soot.lime).fixedSize()
                    }
                case .existing:
                    if catalog.loading {
                        Skeleton(width: 200, height: 14)
                    } else {
                        Picker("Channel", selection: $slackPick) {
                            Text("Choose a channel").tag(String?.none)
                            ForEach(availableChannels) { Text("#\($0.name)").tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280, alignment: .leading)
                    }
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private var linearSection: some View {
        block(.linear) {
            if app.linear == nil {
                notConnected(.linear)
            } else {
                ChipPicker(options: [("New project", LinearMode.create), ("Existing", .existing), ("Later", .none)],
                           selection: $linearMode)
                switch linearMode {
                case .create:
                    if catalog.loading {
                        Skeleton(width: 180, height: 14)
                    } else {
                        Picker("Team", selection: $teamPick) {
                            ForEach(catalog.teams) { Text("\($0.name) team").tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                case .existing:
                    if catalog.loading {
                        Skeleton(width: 200, height: 14)
                    } else {
                        Picker("Project", selection: $linearPick) {
                            Text("Choose a project").tag(String?.none)
                            ForEach(availableLinear) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280, alignment: .leading)
                    }
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private var githubSection: some View {
        block(.github, optional: true) {
            if app.github == nil {
                notConnected(.github)
            } else if catalog.loading {
                Skeleton(width: 220, height: 14)
            } else {
                Picker("Repository", selection: $project.githubRepo) {
                    Text("No repository").tag(String?.none)
                    ForEach(catalog.repos) { Text($0.full_name).tag(Optional($0.full_name)) }
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
                if project.githubRepo != nil {
                    Toggle(isOn: Binding(get: { project.githubWholeRepo == true },
                                         set: { project.githubWholeRepo = $0 })) {
                        Text("Every pull request in the repo").font(.system(size: 13)).foregroundStyle(Soot.ink)
                    }
                    .toggleStyle(.switch)
                    .tint(Soot.lime)
                    .help("Off: only pull requests linked to this project's Linear issues. Keep it off for shared repositories.")
                }
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
        VStack(alignment: .leading, spacing: 20) {
            SheetTitle(title: source == .slack ? "Import channels" : "Import projects", mark: {
                BrandLogo(service: source == .slack ? .slack : .linear, size: 24).foregroundStyle(Soot.ink)
            }, close: { dismiss() })
            HStack(spacing: 16) {
                UnderlineField(placeholder: source == .slack ? "Search channels" : "Search projects", text: $search, size: 16)
                if source == .slack {
                    if !channelPrefix.isEmpty {
                        FilterChip(label: "Starts with \(channelPrefix)", on: $onlyPrefixed)
                            .help("Only channels starting with \(channelPrefix)")
                    }
                    FilterChip(label: "I'm in", on: $onlyMine)
                        .help("Only channels you're a member of")
                }
            }
            ForEach(catalog.errors, id: \.self) { ErrorLabel($0) }
            list
            footer
        }
        .sootSheet(width: 640, height: 600)
        .task { await catalog.load(app) }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if catalog.loading {
                    ForEach(0..<6, id: \.self) { i in
                        HStack(spacing: 12) {
                            Skeleton(width: 18, height: 18, radius: 9)
                            Skeleton(width: [160, 120, 190, 140, 170, 130][i], height: 12)
                            Spacer()
                            Skeleton(width: 110, height: 12)
                        }
                        .padding(.horizontal, 16).frame(height: 56)
                        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                    }
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    ForEach(candidates) { c in row(c) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ c: Candidate) -> some View {
        let on = selection.contains(c.id)
        return Button {
            if on { selection.remove(c.id) } else { selection.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(on ? Soot.lime.opacity(0.5) : .clear))
            .contentShape(Rectangle())
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
        .padding(.top, 80)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !candidates.isEmpty {
                Button(selection.count == candidates.count ? "Select none" : "Select all") {
                    selection = selection.count == candidates.count ? [] : Set(candidates.map(\.id))
                }
                .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Soot.muted)
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
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(on ? Soot.lime : Soot.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
