import AppKit
import SwiftUI

/// Where a tool's desktop app is on this Mac, found by the scheme it answers, and its icon:
/// the tools' own marks come from the apps the user installed, so Dever ships none of them.
@MainActor enum AgentApps {
    private static var icons: [AgentTool: NSImage] = [:]

    static func app(_ tool: AgentTool) -> URL? {
        URL(string: "\(tool.appScheme)://").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    static func icon(_ tool: AgentTool) -> NSImage? {
        if let cached = icons[tool] { return cached }
        guard let app = app(tool) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icons[tool] = icon
        return icon
    }
}

/// A coding agent's mark: its app's icon, or a terminal glyph on a tile when the app is not on this Mac.
struct AgentMark: View {
    let tool: AgentTool
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = AgentApps.icon(tool) {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Soot.muted)
                    .frame(width: size, height: size)
                    .background(Soot.ground, in: RoundedRectangle(cornerRadius: size * 0.24))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Soot.edge))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Starting a coding agent on an issue, in the user's own tool, on a worktree of the issue's branch,
/// the brief filled in and not sent (docs/agents-integration.md, phase 1). With a preferred agent
/// it is one button ("Start with <agent>") and a chevron for another one this time; asked each
/// time, or never asked yet, it is a menu. The caller says what else a start does (move the issue).
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
    @AppStorage(AgentPreferences.preferredKey) private var preferred = ""
    @State private var chosenRepository: String?

    private var choice: AgentChoice { AgentChoice(stored: preferred) }
    private var repositories: [String] { app.repositories(for: project) }
    private var repositoryKey: String { "agentRepository.\(project.id.uuidString)" }
    private var repository: String? {
        let saved = chosenRepository ?? UserDefaults.standard.string(forKey: repositoryKey)
        return saved.flatMap { repositories.contains($0) ? $0 : nil } ?? repositories.first
    }
    private var branch: String? { issue.branchName.flatMap { $0.isEmpty ? nil : $0 } }
    private var ready: Bool { branch != nil && repository != nil }
    /// The tools the menu lists: all of them, the one started last first; with a preferred agent, the others.
    private var listed: [AgentTool] {
        let all = AgentTool.allCases.sorted { a, _ in a.rawValue == lastTool }
        if case .tool(let mine) = choice { return all.filter { $0 != mine } }
        return all
    }

    var body: some View {
        HStack(spacing: 4) {
            if case .tool(let tool) = choice {
                Button { start(tool) } label: {
                    HStack(spacing: 8) {
                        AgentMark(tool: tool, size: 18)
                        Text(busy.map { "Opening \($0.label)…" } ?? "\(title) \(tool.label)").lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.leading, 10).padding(.trailing, 14)
                    .frame(height: ButtonSize.panel.height)
                }
                .buttonStyle(MenuTriggerButton(fill: fill))
                .disabled(busy != nil || !ready)
                .help(branch.map { "Opens \(tool.label) on a worktree of \($0), the brief filled in and not sent" } ?? "Linear gives no branch for this issue")
                chevron.frame(width: 30, height: ButtonSize.panel.height)
            } else {
                HStack(spacing: 6) {
                    Text(busy.map { "Opening \($0.label)…" } ?? "\(title) an agent").lineLimit(1)
                    chevronGlyph
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: ButtonSize.panel.height)
                .modifier(Trigger(open: open, fill: fill, label: "\(title) a coding agent", hint: "Shows the agents") { set(!open) })
                .disabled(busy != nil)
            }
        }
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

    private var chevronGlyph: some View {
        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
            .rotationEffect(.degrees(open ? 180 : 0))
            .motion(Motion.ui, value: open)
            .accessibilityHidden(true)
    }

    /// Beside the preferred agent's button: another agent, this time.
    private var chevron: some View {
        chevronGlyph
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(Trigger(open: open, fill: fill, label: "\(title) another agent", hint: "Shows the other agents") { set(!open) })
            .disabled(busy != nil)
            .help("Another agent, this time")
    }

    /// The button that opens the menu, in the menu trigger's role.
    private struct Trigger: ViewModifier {
        let open: Bool
        let fill: Color
        let label: String
        let hint: String
        let action: () -> Void
        func body(content: Content) -> some View {
            Button(action: action) { content }
                .buttonStyle(MenuTriggerButton(open: open, fill: fill))
                .keepsMenuOpen()
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityAddTraits(open ? .isSelected : [])
        }
    }

    private func set(_ value: Bool) { Motion.run(Motion.ui, fade: true) { open = value } }

    private var menu: some View {
        MenuPanel(width: 300, label: "\(title) a coding agent") {
            switch choice {
            case .unset:
                MenuPanelHead(title: "Which agent do you use?", detail: "One click from now on; Settings changes it")
            case .ask:
                MenuPanelHead(title: "\(title)…", detail: branch.map { "A worktree on \($0)" } ?? "Linear gives no branch for this issue")
            case .tool:
                MenuPanelHead(title: "Another agent, this time", detail: branch.map { "A worktree on \($0)" } ?? "Linear gives no branch for this issue")
            }
            ForEach(listed) { tool in
                MenuPanelRow(agent: tool, title: tool.label,
                             detail: "\(AgentPreferences.surface(tool).label) · brief filled in, not sent") {
                    if choice == .unset { preferred = AgentChoice.tool(tool).stored }
                    start(tool)
                }
                .disabled(!ready)
            }
            if choice == .unset {
                MenuPanelRow(symbol: "questionmark", title: "Ask me each time", detail: "This menu, at every start") {
                    preferred = AgentChoice.ask.stored
                }
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
            MenuPanelRow(symbol: "gearshape", title: "Agent settings", detail: "Your agent, where it opens, your clones") {
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
