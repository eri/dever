import SwiftUI

// The repository mode, in two places: a stage of the onboarding (soot ground, one control)
// and a section of Settings (the app's own theme), both over the same three choices.

/// Three ways a team keeps its code, as radio rows: a ring, the title, one short line.
/// `tint` and `fill` let the rows sit on the onboarding's ground or on a Settings panel.
struct RepositoryModeRows: View {
    @Binding var mode: RepositoryMode
    var onSoot = true

    var body: some View {
        VStack(spacing: 8) {
            ForEach(RepositoryMode.allCases) { option in
                let on = mode == option
                Button { mode = option } label: {
                    HStack(spacing: 12) {
                        if onSoot {
                            CheckCircle(on: on).frame(width: 22)
                        } else {
                            ThemeRing(on: on).frame(width: 22)
                        }
                        Image(systemName: option.symbol).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(onSoot ? Soot.ink : Theme.text).frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.system(size: onSoot ? 16 : 14, weight: .medium))
                                .foregroundStyle(onSoot ? Soot.ink : Theme.text)
                            Text(option.detail).font(.system(size: onSoot ? 13 : 12))
                                .foregroundStyle(onSoot ? Soot.muted : Theme.muted).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: onSoot ? 64 : 52)
                    .background(onSoot ? Soot.surface : (on ? Theme.sheet : Color.clear),
                                in: RoundedRectangle(cornerRadius: Soot.radius))
                    .overlay(RoundedRectangle(cornerRadius: Soot.radius)
                        .strokeBorder(onSoot ? (on ? Soot.lime.opacity(0.5) : .clear) : (on ? Theme.text : Theme.control),
                                      lineWidth: onSoot ? 1 : (on ? 2 : 1)))
                    .contentShape(Rectangle())
                    .modifier(FocusOutline(radius: Soot.radius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title). \(option.detail)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Repository mode")
    }
}

/// The radio ring of a Settings row, in the app's theme.
private struct ThemeRing: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Theme.text : Theme.control, lineWidth: 1.5)
            if on { Circle().fill(Theme.text).padding(4) }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The user's repositories, loaded once for a picker.
@MainActor
final class RepositoryList: ObservableObject {
    @Published var items: [PickerItem] = []
    @Published var loading = false
    @Published var error: String?
    private var loaded = false

    func load(_ app: AppState) async {
        // The one already picked shows at once, and stays listed even when the account
        // cannot see it any more.
        if items.isEmpty, let current = app.workspaceRepository { items = [PickerItem(id: current, title: current)] }
        guard !loaded, app.github != nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let repos = try await app.githubClient().repos()
            var list = repos.map { PickerItem(id: $0.full_name, title: $0.full_name, subtitle: $0.private ? "Private" : "Public") }
            if let current = app.workspaceRepository, !list.contains(where: { $0.id == current }) {
                list.insert(PickerItem(id: current, title: current), at: 0)
            }
            items = list
            loaded = true
            app.succeeded(.github)
        } catch {
            if let state = app.failure(error, .github) {
                self.error = state == .offline ? "You're offline; the list will fill in later." : error.localizedDescription
            }
        }
    }
}

// MARK: - Settings

/// The "Repositories" section of Settings: the mode, the workspace repository where the mode
/// has one, and one line on what changing it does. Self-contained: its own label column and
/// panel, so Settings only has to place it.
struct RepositoryModeSettings: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @StateObject private var repos = RepositoryList()

    private var mode: Binding<RepositoryMode> {
        Binding(get: { app.repositoryMode }, set: { app.setRepositoryMode($0, workspace: app.workspaceRepository) })
    }

    private var workspace: Binding<String?> {
        Binding(get: { app.workspaceRepository }, set: { app.setRepositoryMode(app.repositoryMode, workspace: $0) })
    }

    /// What the change means for the projects, in one line.
    private var consequence: String {
        switch app.repositoryMode {
        case .single: "Every project follows this repository; their own repositories stay saved and come back when you switch."
        case .perProject: "Each project follows its own repositories; the workspace repository is kept for later."
        case .mixed: "A project follows the workspace repository unless it has repositories of its own."
        }
    }

    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repositories").font(Theme.section).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                Text("One repository for the whole team, one or several per project, or both. Change it any time; nothing is lost.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
            .frame(width: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
                RepositoryModeRows(mode: mode, onSoot: false).frame(maxWidth: 420)
                if app.repositoryMode.usesWorkspaceRepository {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspace repository").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                        if app.github == nil {
                            Text("Connect GitHub above to pick it.").font(Theme.small).foregroundStyle(Theme.muted)
                        } else {
                            SearchPicker(label: "Workspace repository", placeholder: repos.loading ? "Loading…" : "Pick a repository",
                                         items: repos.items, selection: workspace)
                                .frame(maxWidth: 420)
                        }
                        if let error = repos.error { ErrorLabel(error) }
                    }
                }
                Text(consequence).font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSheet))
        }
        .task(id: app.github != nil) { await repos.load(app) }
        // The overview follows the new mode at once.
        .onChange(of: app.repositoryMode) { _, _ in Task { await store.refresh(app) } }
        .onChange(of: app.workspaceRepository) { _, _ in Task { await store.refresh(app) } }
    }
}

// MARK: - Onboarding

/// The onboarding stage: "Where's the code?", three rows, and the workspace repository
/// where the mode has one.
struct RepositoryModeControls: View {
    @EnvironmentObject var app: AppState
    let next: () -> Void
    @State private var mode: RepositoryMode = .perProject
    @State private var workspace: String?
    @StateObject private var repos = RepositoryList()

    private var needsWorkspace: Bool { mode.usesWorkspaceRepository && app.github != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Headline(text: "Where's the code?")
            VStack(alignment: .leading, spacing: 16) {
                RepositoryModeRows(mode: $mode)
                if mode.usesWorkspaceRepository {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: mode == .single ? "The repository" : "The shared repository")
                        if app.github == nil {
                            Text("Connect GitHub to pick it; Settings has it too.").font(.system(size: 13)).foregroundStyle(Soot.muted)
                        } else {
                            SearchPicker(label: "Workspace repository", placeholder: repos.loading ? "Loading…" : "Pick a repository",
                                         items: repos.items, selection: $workspace)
                        }
                        if let error = repos.error { Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(1) }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 400)
            Button("Continue") {
                app.setRepositoryMode(mode, workspace: mode.usesWorkspaceRepository ? workspace : app.workspaceRepository)
                next()
            }
            .buttonStyle(LimeButton())
            .keyboardShortcut(.defaultAction)
            .disabled(needsWorkspace && workspace == nil)
        }
        .onAppear {
            mode = app.repositoryMode
            workspace = app.workspaceRepository
        }
        .task { await repos.load(app) }
    }
}
