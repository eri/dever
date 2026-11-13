import AppKit
import SwiftUI

/// "Start with ⌄" on an issue: a menu of the coding agents, each opening in the user's own tool
/// on a worktree of the issue's branch, the brief filled in and not sent
/// (docs/agents-integration.md, phase 1). The caller says what else a start does (move the issue).
struct AgentStartMenu: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var store = IssueStore.shared
    let project: Project
    let issue: LinearIssue
    var title = "Start with"
    /// The trigger's fill: the tone of what it sits on.
    var fill: Color = Soot.surface
    /// The corner of the trigger the menu hangs from: trailing on a tile's right edge, leading in a narrow column.
    var edge: Alignment = .topTrailing
    /// Open, for the caller to raise the tile above the rows the menu hangs over.
    @Binding var open: Bool
    /// The tool opened on `folder`.
    var started: (AgentTool, URL) -> Void = { _, _ in }
    var failed: (String) -> Void = { _ in }

    @State private var busy: AgentTool?
    @AppStorage(AgentPreferences.lastToolKey) private var lastTool = AgentTool.claudeCode.rawValue
    @State private var chosenRepository: String?

    private var repositories: [String] { app.repositories(for: project) }
    private var repositoryKey: String { "agentRepository.\(project.id.uuidString)" }
    private var repository: String? {
        let saved = chosenRepository ?? UserDefaults.standard.string(forKey: repositoryKey)
        return saved.flatMap { repositories.contains($0) ? $0 : nil } ?? repositories.first
    }
    private var branch: String? { issue.branchName.flatMap { $0.isEmpty ? nil : $0 } }
    /// The tool started last comes first.
    private var tools: [AgentTool] {
        AgentTool.allCases.sorted { a, _ in a.rawValue == lastTool }
    }

    var body: some View {
        Button { set(!open) } label: {
            HStack(spacing: 6) {
                Text(busy.map { "Opening \($0.label)…" } ?? title)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .motion(Motion.ui, value: open)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: ButtonSize.panel.height)
        }
        .buttonStyle(MenuTriggerButton(open: open, fill: fill))
        .keepsMenuOpen()
        .disabled(busy != nil)
        .accessibilityLabel("\(title) a coding agent")
        .accessibilityHint("Shows Claude Code and Codex")
        .accessibilityAddTraits(open ? .isSelected : [])
        .overlay(alignment: edge) {
            if open {
                menu
                    .offset(y: ButtonSize.panel.height + 6)
                    .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
            }
        }
        // Above the siblings drawn after it, which the menu hangs over.
        .zIndex(open ? 1 : 0)
        .closesOnOutsideClick(open) { set(false) }
        .onAppear {
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_AGENT_MENU"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { set(true) }
            }
        }
    }

    private func set(_ value: Bool) { Motion.run(Motion.ui, fade: true) { open = value } }

    private var menu: some View {
        MenuPanel(width: 300, label: "\(title) a coding agent") {
            MenuPanelHead(title: "\(title)…", detail: branch.map { "A worktree on \($0)" } ?? "Linear gives no branch for this issue")
            ForEach(tools) { tool in
                let surface = AgentPreferences.surface(tool)
                MenuPanelRow(symbol: surface == .app ? "macwindow" : "terminal", title: tool.label,
                             detail: "\(surface.label) · brief filled in, not sent") { start(tool) }
                    .disabled(branch == nil || repository == nil)
            }
            if repositories.count > 1 {
                MenuPanelDivider()
                ForEach(repositories, id: \.self) { name in
                    MenuPanelRow(symbol: name == repository ? "checkmark" : "shippingbox", title: name,
                                 detail: name == repository ? "The agent opens here" : nil) {
                        chosenRepository = name
                        UserDefaults.standard.set(name, forKey: repositoryKey)
                    }
                }
            }
            MenuPanelDivider()
            MenuPanelRow(symbol: "gearshape", title: "Agent settings", detail: "Where each repository is, where each tool opens") {
                set(false)
                openSettings()
                // Settings listens once it is on screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .showSettingsSection, object: SettingsView.Section.agents.rawValue)
                }
            }
        }
    }

    private func start(_ tool: AgentTool) {
        set(false)
        // The first start on a repository asks where its clone is; Dever remembers it.
        if let repository, AgentPreferences.clone(of: repository) == nil {
            guard let folder = AgentFolderPanel.choose(clone: repository) else { return }
            do { try AgentLauncher.register(folder, as: repository) } catch { return failed(error.localizedDescription) }
        }
        busy = tool
        Task {
            defer { busy = nil }
            // The description makes the brief; without it (Linear unreachable) the title and the link still do.
            let detail = try? await store.detail(issue.id, updatedAt: issue.updatedAt, app: app)
            do {
                let folder = try await AgentLauncher.start(tool: tool, issue: issue, detail: detail ?? store.cachedDetail(issue.id),
                                                           repository: repository)
                started(tool, folder)
            } catch {
                failed(error.localizedDescription)
            }
        }
    }
}

/// The folder pickers of the agents: a repository's clone, or a folder to look for clones in.
enum AgentFolderPanel {
    @MainActor private static func choose(message: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Where `repository` is cloned on this Mac.
    @MainActor static func choose(clone repository: String) -> URL? {
        choose(message: "Where is \(repository) cloned on this Mac? Dever asks once per repository.", prompt: "Use this clone")
    }

    /// A folder to search for the projects' clones.
    @MainActor static func chooseSearchFolder() -> URL? {
        choose(message: "Dever looks for your projects' clones in this folder, three levels deep.", prompt: "Look here")
    }
}
