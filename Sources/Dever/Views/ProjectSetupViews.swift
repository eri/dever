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
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Project name", text: $project.name, prompt: Text("Acme website"))
                    if let nameError {
                        ErrorLabel(nameError)
                    }
                }
                slackSection
                linearSection
                Section("GitHub (optional)") {
                    if app.github == nil {
                        Text("GitHub not connected").foregroundStyle(.secondary)
                    } else {
                        Picker("Repository", selection: $project.githubRepo) {
                            Text("None").tag(String?.none)
                            ForEach(catalog.repos) { Text($0.full_name).tag(Optional($0.full_name)) }
                        }
                        if project.githubRepo != nil {
                            Toggle(isOn: Binding(get: { project.githubWholeRepo == true },
                                                 set: { project.githubWholeRepo = $0 })) {
                                Text("Show every pull request in the repository")
                                Text("When off, only pull requests linked to this project's Linear issues count. Keep it off for repositories shared by several projects.")
                            }
                        }
                    }
                }
                if !catalog.errors.isEmpty || error != nil {
                    Section {
                        ForEach(catalog.errors + [error].compactMap { $0 }, id: \.self) { ErrorLabel($0) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                if catalog.loading || saving {
                    ProgressView().controlSize(.small).accessibilityLabel(saving ? "Saving" : "Loading")
                }
                Text(consequence).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create project" : "Save changes") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
            .padding(16)
        }
        .frame(width: 580, height: 640)
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

    private var slackSection: some View {
        Section("Slack channel") {
            if app.slack == nil {
                Text("Slack not connected").foregroundStyle(.secondary)
            } else {
                Picker("Slack channel", selection: $slackMode) {
                    Text("Create").tag(SlackMode.create)
                    Text("Existing").tag(SlackMode.existing)
                    Text("Later").tag(SlackMode.none)
                }.pickerStyle(.segmented).labelsHidden()
                switch slackMode {
                case .create:
                    TextField("Channel name", text: $newChannelName,
                              prompt: Text(Naming.channelName(for: project.name, prefix: channelPrefix)))
                    Toggle("Private channel", isOn: $privateChannel)
                case .existing:
                    Picker("Channel", selection: $slackPick) {
                        Text("—").tag(String?.none)
                        ForEach(availableChannels) { Text("#\($0.name)").tag(Optional($0.id)) }
                    }
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private var linearSection: some View {
        Section("Linear project") {
            if app.linear == nil {
                Text("Linear not connected").foregroundStyle(.secondary)
            } else {
                Picker("Linear project", selection: $linearMode) {
                    Text("Create").tag(LinearMode.create)
                    Text("Existing").tag(LinearMode.existing)
                    Text("Later").tag(LinearMode.none)
                }.pickerStyle(.segmented).labelsHidden()
                switch linearMode {
                case .create:
                    Picker("Team", selection: $teamPick) {
                        ForEach(catalog.teams) { Text("\($0.name) (\($0.key))").tag(Optional($0.id)) }
                    }
                case .existing:
                    Picker("Project", selection: $linearPick) {
                        Text("—").tag(String?.none)
                        ForEach(availableLinear) { Text($0.name).tag(Optional($0.id)) }
                    }
                case .none:
                    EmptyView()
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
            parts.append("creates #\(name) in Slack")
        }
        if linearMode == .create, let team = catalog.teams.first(where: { $0.id == teamPick }) {
            parts.append("creates a Linear project in \(team.name)")
        }
        guard !parts.isEmpty else { return "" }
        return (isNew ? "Creating " : "Saving ") + parts.joined(separator: " and ") + "."
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
    @State private var onlyConvention = true
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
                .filter { !onlyConvention || channelPrefix.isEmpty || $0.name.hasPrefix(channelPrefix) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(source == .slack ? "Import from Slack channels" : "Import from Linear projects")
                .font(.title2.bold())
            HStack {
                TextField(source == .slack ? "Search channels" : "Search projects", text: $search)
                .textFieldStyle(.roundedBorder)
                if source == .slack {
                    Toggle("Only \"\(channelPrefix)…\"", isOn: $onlyConvention)
                }
            }
            if catalog.loading { ProgressView().controlSize(.small).accessibilityLabel("Loading") }
            ForEach(catalog.errors, id: \.self) { ErrorLabel($0) }
            Table(candidates, selection: $selection) {
                TableColumn(source == .slack ? "Channel" : "Linear project", value: \.title)
                TableColumn("Dever project name", value: \.projectName)
                TableColumn(source == .slack ? "Matching Linear project" : "Matching Slack channel") {
                    Text($0.match ?? "None found").foregroundStyle($0.match == nil ? .secondary : .primary)
                }
            }
            .overlay {
                if candidates.isEmpty && !catalog.loading {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "tray")
                    } description: {
                        Text(emptyMessage)
                    } actions: {
                        if source == .slack && onlyConvention && search.isEmpty {
                            Button("Show all channels") { onlyConvention = false }
                        } else if !search.isEmpty {
                            Button("Clear search") { search = "" }
                        }
                    }
                }
            }
            HStack {
                Text("\(selection.count) selected").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import ^[\(selection.count) project](inflect: true)") { importSelected() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .task { await catalog.load(app) }
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "No results for \u{201C}\(search)\u{201D}" }
        return source == .slack ? "No channels to import" : "No projects to import"
    }

    private var emptyMessage: String {
        if !search.isEmpty { return "Check the spelling or clear the search." }
        if source == .slack && onlyConvention {
            return "No unlinked channel starts with \u{201C}\(channelPrefix)\u{201D}. Change the prefix in Accounts, or show all channels."
        }
        return "Everything is already linked to a Dever project."
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
