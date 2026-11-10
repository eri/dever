import SwiftUI

// The repository mode, in two places: a stage of the onboarding and the Repositories
// section of Settings (`RepositoriesSection` in SettingsView.swift), over the same rows.

/// Three ways a team keeps its code, as radio rows: a ring, the title, one short line.
struct RepositoryModeRows: View {
    @Binding var mode: RepositoryMode

    var body: some View {
        VStack(spacing: 8) {
            ForEach(RepositoryMode.allCases) { option in
                let on = mode == option
                Button { mode = option } label: {
                    HStack(spacing: 12) {
                        CheckCircle(on: on).frame(width: 22)
                        Image(systemName: option.symbol).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Soot.ink).frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
                            Text(option.detail).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 64)
                    .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                    .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(on ? Soot.lime.opacity(0.5) : .clear))
                }
                .buttonStyle(RowButton(lift: .tone, radius: Soot.radius))
                .accessibilityLabel("\(option.title). \(option.detail)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Repository mode")
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
            // Same line as the Connect stage's reassurance: the choice is not final.
            HStack(spacing: 16) {
                Button("Continue") {
                    app.setRepositoryMode(mode, workspace: mode.usesWorkspaceRepository ? workspace : app.workspaceRepository)
                    next()
                }
                .buttonStyle(PrimaryButton(size: .sheet))
                .keyboardShortcut(.defaultAction)
                .disabled(needsWorkspace && workspace == nil)
                Label("Change it any time in Settings", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(Soot.muted)
            }
        }
        .onAppear {
            mode = app.repositoryMode
            workspace = app.workspaceRepository
        }
        .task { await repos.load(app) }
    }
}
