import SwiftUI
import UserNotifications

// Settings in the onboarding's spirit: one screen, few words, the three tools as tiles with
// their real logos and the account behind each, the rest as small visual choices. Everything
// fits the 1080×680 minimum window without scrolling.

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var flow = ConnectFlow()
    @State private var section: Section = .accounts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Section: String, CaseIterable, Identifiable {
        case accounts, repositories, agents, overview, appearance, alerts, intelligence, launch, about
        var id: String { rawValue }

        /// The sections this Mac has: Intelligence where a feature can run (now or after a fix in
        /// System Settings), or where the coming local model is announced.
        @MainActor static var visible: [Section] {
            let intelligence = LocalModelOutlook.settingsPage(
                availability: IntelligenceStatus.shared.availability,
                anyFeature: !IntelligenceFeature.shipped.isEmpty,
                announced: LocalModelOutlook.announced())
            return allCases.filter { $0 != .intelligence || intelligence }
        }
        var label: String {
            switch self {
            case .accounts: "Accounts"
            case .repositories: "Repositories"
            case .agents: "Agents"
            case .overview: "Overview"
            case .appearance: "Appearance"
            case .alerts: "Notifications"
            case .intelligence: "Intelligence"
            case .launch: "Launch"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .accounts: "link"
            case .repositories: "shippingbox"
            case .agents: "terminal"
            case .overview: "list.bullet.rectangle"
            case .appearance: "circle.lefthalf.filled"
            case .alerts: "bell"
            case .intelligence: "sparkles"
            case .launch: "power"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Identity(section: $section)
                .frame(width: 248)
                .padding(.leading, 28)
                .padding(.vertical, 28)
            ScrollView {
                Group {
                    switch section {
                    case .accounts: AccountsSection(flow: flow)
                    case .repositories: RepositoriesSection()
                    case .agents: AgentsSection()
                    case .overview: OverviewSettingsView()
                    case .appearance: AppearanceSection()
                    case .alerts: AlertsSection()
                    case .intelligence: IntelligenceSection()
                    case .launch: LaunchSection()
                    case .about: AboutSection()
                    }
                }
                .id(section)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .animation(.easeOut(duration: 0.2), value: section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Soot.ground)
        .navigationTitle("Settings")
        .windowTitleHidden()
        .sheet(isPresented: $flow.githubSheet) { GitHubLoginSheet() }
        .onAppear { flow.simulateIfAsked() }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsSection)) { note in
            if let raw = note.object as? String, let s = Section(rawValue: raw) { section = s }
        }
    }
}

extension Notification.Name {
    /// Switches Settings to a section; `object` is its raw value (snapshots).
    static let showSettingsSection = Notification.Name("dever.showSettingsSection")
}

// MARK: - Identity and navigation

/// The left column: who you are (your name and your generated picture) and the sections.
private struct Identity: View {
    @EnvironmentObject var app: AppState
    @Binding var section: SettingsView.Section
    @AppStorage("displayName") private var displayName = ""
    @State private var seed = GenerativeAvatar.storedSeed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var marker

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                GenerativeAvatar(seed: seed, size: 72)
                    .id(seed)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { seed = GenerativeAvatar.reseed() }
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(IconButton())
                    .overlay(Circle().strokeBorder(Soot.ground, lineWidth: 2))
                    .offset(x: 4, y: 4)
                .help("Draw another picture")
                .accessibilityLabel("Draw another picture")
            }
            .padding(.bottom, 14)
            Text(displayName.isEmpty ? "You" : displayName)
                .font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                .foregroundStyle(Soot.ink).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 2) {
                ForEach(SettingsView.Section.visible) { s in
                    let on = s == section
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { section = s }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.symbol).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? Soot.ink : Soot.muted).frame(width: 18)
                                .accessibilityHidden(true)
                            Text(s.label).font(.system(size: 14, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? Soot.ink : Soot.muted)
                            Spacer(minLength: 0)
                            if s == .accounts, let n = attention { AttentionDot(count: n) }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: Soot.radius).fill(Soot.surface)
                                    .matchedGeometryEffect(id: "row", in: marker)
                            }
                        }
                        }
                        .buttonStyle(RowButton(lift: .tone, radius: Soot.radius))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        }
            }
            .padding(.top, 32)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
        }
    }

    /// Tools to connect or reconnect, shown on the Accounts row.
    private var attention: Int? {
        let n = ServiceKind.allCases.filter { !app.isConnected($0) || app.expired.contains($0) }.count
        return n == 0 ? nil : n
    }
}

/// A small count on a section row: tools still to connect.
private struct AttentionDot: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.limeInk)
            .frame(minWidth: 18, minHeight: 18)
            .background(Soot.lime, in: Capsule())
            .accessibilityLabel("\(count) to connect")
    }
}

/// The right column's head: the section's name, one quiet line.
struct SectionHead: View {
    let title: String
    var detail: String? = nil
    /// A word beside the title that qualifies the whole page ("Beta").
    var tag: StageTag.Kind? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                if let tag { StageTag(kind: tag).padding(.top, 4) }
            }
            if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted) }
        }
        .padding(.bottom, 24)
    }
}

/// Settings as rows on one surface: a label, a control, a hairline between rows.
struct SettingRows<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One row: a title (and a line) on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var divided = true
    /// For a switch: the whole row is the target, not the 15px control (WCAG 2.5.8).
    var tap: (() -> Void)? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                    if let detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                control()
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .onTapGesture { tap?() }
            .handCursor(tap != nil)
            if divided { Rectangle().fill(Soot.line).frame(height: 1) }
        }
    }
}

// MARK: - Accounts

private struct AccountsSection: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: ConnectFlow
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    /// The tool whose status menu is open, if any: one at a time.
    @State private var menu: ServiceKind?

    private var connected: Int { ServiceKind.allCases.filter(app.isConnected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Accounts", detail: "\(connected) of 3 connected · Tokens stay in your Keychain and never leave your device")
            VStack(spacing: 8) {
                ForEach(ServiceKind.allCases) { ServiceRow(service: $0, flow: flow, menu: $menu) }
            }
            .zIndex(1)
            ChannelPrefixCard(prefix: $channelPrefix)
            .padding(.top, 20)
        }
        // A click anywhere else in the window closes the open menu.
        .closesOnOutsideClick(menu != nil) { Motion.run(Motion.ui, fade: true) { menu = nil } }
        .onExitCommand { if menu != nil { Motion.run(Motion.ui, fade: true) { menu = nil } } }
    }
}

/// One action in an account's status menu, in the overview menu's row language: a glyph on a
/// tile, a title, one quiet line. `busy` runs the lime line along its foot (never a spinner).
private struct StatusMenuRow: View {
    let symbol: String
    let title: String
    let detail: String
    var destructive = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.negative : Soot.ink)
                    .frame(width: 28, height: 28)
                    .background(Soot.surface, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(destructive ? Theme.negative : Soot.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .overlay(alignment: .bottom) { if busy { WaitingLine().padding(.horizontal, 8) } }
            .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
            }
            .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
        .accessibilityLabel(destructive ? "\(title). \(detail)" : title)
    }
}

/// How Dever finds project channels in Slack, the onboarding's question again: by a shared
/// prefix, or by hand. Two pictures make the choice. With a prefix, a second row holds the
/// field and names the user's own channels that start with it.
private struct ChannelPrefixCard: View {
    @EnvironmentObject var app: AppState
    @Binding var prefix: String
    @State private var shared = true
    @State private var draft = ""
    @State private var channels: [String]?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    private var trimmed: String { draft.trimmingCharacters(in: .whitespaces) }
    private var matches: [String] {
        guard let channels, !trimmed.isEmpty else { return [] }
        return channels.filter { $0.hasPrefix(trimmed) }.sorted()
    }

    var body: some View {
        SettingRows {
            SettingRow(title: "Project channels",
                       detail: shared ? "Dever finds them in Slack by their prefix" : "You pick them yourself when you import",
                       divided: shared) {
                HStack(spacing: 8) {
                    tile(on: shared, label: "Shared prefix", marked: true) { choose(true) }
                    tile(on: !shared, label: "No prefix", marked: false) { choose(false) }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Project channels")
            }
            if shared {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prefix").font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                        effect.font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                            .help(matches.map { "#" + $0 }.joined(separator: "\n"))
                    }
                    Spacer(minLength: 16)
                    TextField("Prefix", text: $draft, prompt: Text("proj-").foregroundStyle(Soot.muted))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14)).foregroundStyle(Soot.ink)
                        .focused($focused)
                        .padding(.horizontal, 12)
                        .frame(width: 120, height: 36)
                        .background(Soot.ground, in: RoundedRectangle(cornerRadius: Soot.radius))
                        .overlay(RoundedRectangle(cornerRadius: Soot.radius)
                            .strokeBorder(focused ? Soot.lime : Soot.edge, lineWidth: focused ? 2 : 1))
                        .accessibilityLabel("Slack channel prefix")
                }
                .frame(minHeight: 56)
                .transition(.opacity)
            }
        }
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_NO_PREFIX shows the "No prefix" choice.
            shared = !prefix.isEmpty && ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_NO_PREFIX"] == nil
            draft = prefix
        }
        .onChange(of: draft) { if shared { prefix = trimmed } }
        .task(id: app.slack?.teamID) { await load() }
    }

    /// What the prefix does, said with the user's own channels (their prefix in lime) when
    /// there are some.
    private var effect: Text {
        if trimmed.isEmpty { return Text("What your project channels start with") }
        guard app.slack != nil, channels != nil else { return Text("Import offers the channels that start with it") }
        if matches.isEmpty { return Text("None of your channels start with \(trimmed)") }
        var line = Text(Plural.text("^[\(matches.count) channel](inflect: true)")).foregroundColor(Soot.ink)
        for name in matches.prefix(2) {
            line = line + Text("  #") + Text(trimmed).foregroundColor(Soot.lime) + Text(name.dropFirst(trimmed.count))
        }
        return matches.count > 2 ? line + Text("…") : line
    }

    /// One choice as a picture of three channel names: with the same lime start, or without.
    private func tile(on: Bool, label: String, marked: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 2) {
                            if marked { Capsule().fill(Soot.lime).frame(width: 12, height: 3) }
                            Capsule().fill(Soot.ink).frame(width: marked ? [26, 16, 34][i] : [36, 22, 44][i], height: 3)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: 84, height: 40, alignment: .leading)
                .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.edge))
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime, lineWidth: 2)
                            .matchedGeometryEffect(id: "ring", in: ring)
                    }
                }
                Text(label).font(.system(size: 12, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Soot.ink : Soot.muted)
            }
            .padding(4)
        }
        .buttonStyle(RowButton(lift: .tone, radius: 8))
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "No prefix" clears the stored prefix but keeps the typed one, so coming back restores
    /// it; with nothing typed yet, the prefix most of the user's channels share is proposed.
    private func choose(_ usesPrefix: Bool) {
        guard usesPrefix != shared else { return }
        if usesPrefix, trimmed.isEmpty { draft = Naming.commonPrefix(in: channels ?? [])?.prefix ?? "" }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { shared = usesPrefix }
        prefix = usesPrefix ? trimmed : ""
        focused = usesPrefix && trimmed.isEmpty
    }

    /// The channels the user is in, once per workspace.
    private func load() async {
        guard app.slack != nil else { channels = nil; return }
        if let list = try? await app.withSlack({ try await $0.channels() }) {
            channels = list.filter { $0.is_member == true }.map(\.name)
        } else {
            channels = []
        }
    }
}

// MARK: - Service rows

/// Who is signed in to a tool: the name to show, one quiet line, and a picture.
private struct AccountProfile: Codable, Equatable {
    var name: String
    var detail: String
    var avatar: URL?
}

/// One tool as a row: its logo, the account behind it, and the one thing to do.
/// Four faces: not connected (dashed edge, muted), connecting (lime sweep), connected
/// (account and a check), rejected or unreachable (the problem in words, Reconnect).
private struct ServiceRow: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    @ObservedObject var flow: ConnectFlow
    @Binding var menu: ServiceKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var confirmDisconnect = false
    @State private var profile: AccountProfile?
    /// The last health check: nil while unchecked or fine.
    @State private var trouble: ServiceState?
    @State private var checking = false
    @State private var lastChecked: Date?

    private var menuOpen: Bool { menu == service }
    /// Snapshots: DEVER_SNAPSHOT_ACCOUNT_MENU=slack opens that row's status menu.
    private var snapshotMenu: Bool { ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_ACCOUNT_MENU"] == service.rawValue }
    private func setMenu(_ open: Bool) { Motion.run(Motion.ui, fade: true) { menu = open ? service : nil } }

    private var connected: Bool { app.isConnected(service) }
    private var expired: Bool { app.expired.contains(service) }
    private var running: Bool { flow.running == service }

    /// What the tool brings, for the empty tile.
    private var pitch: String {
        switch service {
        case .slack: "Channels and messages"
        case .linear: "Issues and delivery"
        case .github: "Pull requests and previews"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            BrandLogo(service: service, size: 24)
                .foregroundStyle(Soot.ink)
                .opacity(connected ? 1 : 0.55)
                .scaleEffect(hovering && !reduceMotion ? 1.08 : 1)
                .animation(.easeOut(duration: 0.16), value: hovering)
                .modifier(Breathing(active: running))
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(service.label)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                .frame(width: 64, alignment: .leading)
            account
            Spacer(minLength: 12)
            action
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(Soot.surface.opacity(connected ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .fill(Soot.ink.opacity(hovering ? 0.04 : 0))
            .allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Soot.edge, style: StrokeStyle(lineWidth: 1, dash: connected ? [] : [4, 4]))
            .opacity(connected ? 0 : 1))
        .overlay(alignment: .bottom) { if running { WaitingLine().transition(.opacity) } }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The status menu hangs from the row's trailing edge, over the rows below.
        .overlay(alignment: .topTrailing) {
            if menuOpen {
                statusMenu
                    .keepsMenuOpen()
                    .offset(x: -16, y: 64 - 8)
                    .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
            }
        }
        .zIndex(menuOpen ? 2 : 0)
        .animation(.easeOut(duration: 0.2), value: connected)
        .animation(.easeOut(duration: 0.2), value: running)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibleSummary)
        .task(id: connectionKey) { await check() }
        .onAppear { if snapshotMenu { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { setMenu(true) } } }
        .confirmationDialog("Disconnect \(service.label)?", isPresented: $confirmDisconnect) {
            Button("Disconnect \(service.label)", role: .destructive) { trouble = nil; app.disconnect(service) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dever stops showing \(service.label) data until you connect again. Your projects and their links are kept.")
        }
    }

    /// Changes when the token does, so the profile reloads after a connect or a disconnect.
    private var connectionKey: String {
        switch service {
        case .slack: app.slack?.userID ?? ""
        case .linear: app.linear?.account.email ?? ""
        case .github: app.github?.login ?? ""
        }
    }

    private var accessibleSummary: String {
        if running { return "\(service.label): waiting for approval in your browser" }
        if !connected { return "\(service.label): not connected. \(pitch)" }
        if expired { return "\(service.label): session expired, reconnect" }
        if let trouble { return "\(service.label): \(troubleText(trouble))" }
        return "\(service.label): connected as \(profile?.name ?? connectionKey)"
    }

    // The glyph top-right says the state; the words under it repeat it (1.4.1).
    @ViewBuilder private var stateGlyph: some View {
        if connected && !expired && trouble == nil {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Soot.lime)
                .transition(.opacity).accessibilityHidden(true)
        } else if connected {
            Image(systemName: trouble == .offline ? "wifi.slash" : "exclamationmark.circle.fill")
                .font(.system(size: 16)).foregroundStyle(trouble == .offline ? Soot.muted : Theme.negative)
                .transition(.opacity).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var account: some View {
        if connected {
            HStack(spacing: 10) {
                AccountAvatar(url: profile?.avatar, name: displayName, size: 30, authorize: avatarAuthorizer)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .help(statusLine)
                }
            }
            .transition(.opacity)
        } else {
            Text(pitch).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
                .transition(.opacity)
        }
    }

    private var displayName: String { profile?.name ?? connectionKey }

    private var avatarAuthorizer: ImageCache.Authorizer? {
        guard service == .linear else { return nil }
        return linearAuthorizer
    }

    /// Red only for a problem the user can act on; offline is quiet.
    private var statusColor: Color {
        if expired { return Theme.negative }
        if let trouble, trouble != .offline { return Theme.negative }
        return Soot.muted
    }

    /// The quiet line under the name: the workspace, or what is wrong.
    private var statusLine: String {
        if expired { return "Session expired" }
        if let trouble { return troubleText(trouble) }
        return profile?.detail ?? ""
    }

    private func troubleText(_ state: ServiceState) -> String {
        switch state {
        case .offline: "You're offline"
        case .failed: "Can't reach \(service.label)"
        case .unauthorized: "Session expired"
        case .notConnected: "Not connected"
        }
    }

    @ViewBuilder private var action: some View {
        if running {
            HStack(spacing: 10) {
                Text("Approve in your browser…").font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                Button("Cancel") { flow.cancel() }.buttonStyle(SecondaryButton())
            }
        } else if expired {
            HStack(spacing: 10) {
                Button("Reconnect") { flow.start(service, app: app) }.buttonStyle(PrimaryButton())
                statusTrigger
            }
        } else if connected {
            statusTrigger
        } else {
            HStack(spacing: 10) {
                if let error = flow.error, error.service == service {
                    Text(error.message).font(.system(size: 12)).foregroundStyle(Theme.negative).lineLimit(1)
                        .help(error.message)
                }
                Button("Connect") { flow.start(service, app: app) }.buttonStyle(PrimaryButton())
                    .accessibilityLabel("Connect \(service.label)")
                    .help(service == .github ? "Sign in with a code on github.com" : "Approve Dever in your browser")
            }
        }
    }

    // MARK: Status menu

    /// The state in a few words, for the menu's head and the trigger's name.
    private var statusTitle: String {
        if expired { return "Session expired" }
        switch trouble {
        case .offline: return "You're offline"
        case .failed: return "Can't reach \(service.label)"
        default: return "Connected and working"
        }
    }

    /// What the state means, in one or two lines.
    private var statusDetail: String {
        if expired { return "\(service.label) rejected the token. Reconnect to keep reading it." }
        switch trouble {
        case .offline: return "The token is fine; \(service.label) comes back with the network."
        case .failed(let message): return message
        default:
            let when = lastChecked.map { $0.formatted(.relative(presentation: .named)) } ?? "not yet"
            return "\(service.label) answered \(when)."
        }
    }

    /// The state glyph and a chevron, on a small tile: opens the status menu.
    private var statusTrigger: some View {
        Button { setMenu(!menuOpen) } label: {
            HStack(spacing: 6) {
                stateGlyph
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Soot.muted)
                    .rotationEffect(.degrees(menuOpen ? 180 : 0))
                    .motion(Motion.ui, value: menuOpen)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            }
            .buttonStyle(MenuTriggerButton(open: menuOpen, fill: Soot.ground.opacity(0.7), edge: false))
            .keepsMenuOpen()
        .help(statusTitle)
        .accessibilityLabel("\(service.label) status: \(statusTitle)")
        .accessibilityHint("Shows the status, Check status and Disconnect")
        .accessibilityAddTraits(menuOpen ? .isSelected : [])
    }

    /// The menu: what the glyph means in words, then Check status and Disconnect.
    private var statusMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                stateGlyph.frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                    Text(statusDetail).font(.system(size: 12)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Soot.line).frame(height: 1).padding(.horizontal, 6).padding(.bottom, 4)
            StatusMenuRow(symbol: "arrow.clockwise", title: checking ? "Checking…" : "Check status",
                          detail: "Ask \(service.label) now", busy: checking) {
                Task { await check() }
            }
            .disabled(checking)
            StatusMenuRow(symbol: "xmark.circle", title: "Disconnect", detail: "Projects and links are kept",
                          destructive: true) {
                setMenu(false)
                confirmDisconnect = true
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(service.label) status")
    }

    private var linearAuthorizer: ImageCache.Authorizer? {
        guard let token = app.linear?.accessToken else { return nil }
        let authorize: ImageCache.Authorizer = { (req: inout URLRequest) in
            if req.url?.host?.hasSuffix("linear.app") == true {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return authorize
    }

    // MARK: Profile and health

    private var profileKey: String { "profile.\(service.rawValue)" }

    /// The account behind the token: what the credentials already know first, then the
    /// cheapest call that needs the token, which doubles as the health check.
    /// The health check: loads the profile, notes when, and never shows a spinner.
    private func check() async {
        checking = true
        defer { checking = false; lastChecked = Date() }
        await loadProfile()
    }

    private func loadProfile() async {
        trouble = nil
        guard connected else { profile = nil; return }
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let cached = try? JSONDecoder().decode(AccountProfile.self, from: data) {
            profile = cached
        } else {
            profile = knownProfile
        }
        do {
            let fresh: AccountProfile
            switch service {
            case .slack:
                guard let creds = app.slack else { return }
                let user = try await app.withSlack { try await $0.user(creds.userID) }
                fresh = AccountProfile(name: user.name, detail: "\(creds.teamName) · \(creds.domain).slack.com", avatar: user.avatar)
            case .linear:
                let account = try await app.withLinear { try await $0.viewer() }
                if var creds = app.linear, creds.account.avatarUrl != account.avatarUrl {
                    creds.account.avatarUrl = account.avatarUrl
                    app.linear = creds
                }
                fresh = AccountProfile(name: account.userName, detail: account.orgName,
                                       avatar: account.avatarUrl.flatMap(URL.init(string:)))
            case .github:
                let login = try await app.githubClient().viewerLogin()
                fresh = AccountProfile(name: "@\(login)", detail: "github.com",
                                       avatar: URL(string: "https://github.com/\(login).png?size=96"))
            }
            app.succeeded(service)
            profile = fresh
            if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: profileKey) }
        } catch {
            if let state = app.failure(error, service), state != .unauthorized { trouble = state }
        }
    }

    /// What the stored credentials say, before any call.
    private var knownProfile: AccountProfile? {
        switch service {
        case .slack: app.slack.map { AccountProfile(name: $0.teamName, detail: "\($0.domain).slack.com") }
        case .linear: app.linear.map {
            AccountProfile(name: $0.account.userName, detail: $0.account.orgName,
                           avatar: $0.account.avatarUrl.flatMap(URL.init(string:)))
        }
        case .github: app.github.map {
            AccountProfile(name: "@\($0.login)", detail: "github.com", avatar: URL(string: "https://github.com/\($0.login).png?size=96"))
        }
        }
    }
}

/// The signed-in person's picture; their initial on a tint until it loads, with a fade.
private struct AccountAvatar: View {
    var url: URL?
    let name: String
    var size: CGFloat = 30
    var authorize: ImageCache.Authorizer? = nil
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Text(String(name.trimmingCharacters(in: ["@"]).prefix(1)).uppercased())
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: size, height: size)
                .background(PersonTint.color(for: name), in: Circle())
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image == nil)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.image(url, kind: .avatars, source: "account", maxPixels: Int(size * 2.5),
                                                  authorize: authorize)
        }
    }
}

// MARK: - Repositories

/// Where the code lives, as three pictures in the Appearance section's language: projects on
/// top, repositories under them, the workspace repository in lime. One line says what the
/// choice does; the workspace repository has its row where the mode has one.
private struct RepositoriesSection: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: OverviewStore
    @StateObject private var repos = RepositoryList()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    private var workspace: Binding<String?> {
        Binding(get: { app.workspaceRepository }, set: { app.setRepositoryMode(app.repositoryMode, workspace: $0) })
    }

    /// What the choice means for the projects, in one line.
    private var consequence: String {
        switch app.repositoryMode {
        case .single: "Every project follows the workspace repository"
        case .perProject: "Each project links its own repositories"
        case .mixed: "A project follows the workspace repository unless it has its own"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Repositories", detail: "Tell Dever where your projects' code lives. You can switch any time without losing anything.")
            HStack(spacing: 16) {
                ForEach(RepositoryMode.allCases) { option in
                    let on = app.repositoryMode == option
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                            app.setRepositoryMode(option, workspace: app.workspaceRepository)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            RepositoryModeThumb(mode: option)
                                .overlay {
                                    if on {
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime, lineWidth: 2)
                                            .matchedGeometryEffect(id: "ring", in: ring)
                                    }
                                }
                            VStack(spacing: 1) {
                                Text(option.short).font(.system(size: 13, weight: on ? .semibold : .medium))
                                    .foregroundStyle(on ? Soot.ink : Soot.muted)
                                Text(option.term).font(.system(size: 11)).foregroundStyle(Soot.muted)
                            }
                        }
                        .frame(width: 128, height: 128)
                    }
                    .buttonStyle(RowButton(lift: .tone, radius: 8))
                    .accessibilityLabel("\(option.title), \(option.term)")
                    .accessibilityHint(option.detail)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Repository mode")
            Text(consequence)
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.top, 16)
                .id(app.repositoryMode)
                .transition(.opacity)
            if app.repositoryMode.usesWorkspaceRepository {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 16) {
                        HStack(spacing: 8) {
                            // The lime repository of the pictures above.
                            RoundedRectangle(cornerRadius: 3).fill(Soot.lime).frame(width: 12, height: 10)
                                .accessibilityHidden(true)
                            Text("Workspace repository").font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                        }
                        Spacer(minLength: 16)
                        if app.github == nil {
                            Text("Connect GitHub to pick it").font(.system(size: 13)).foregroundStyle(Soot.muted)
                        } else {
                            SearchPicker(label: "Workspace repository", placeholder: repos.loading ? "Loading…" : "Pick a repository",
                                         items: repos.items, selection: workspace)
                                .frame(width: 280)
                        }
                    }
                    .frame(minHeight: 64)
                    if let error = repos.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 16)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 20)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: app.repositoryMode)
        .task(id: app.github != nil) { await repos.load(app) }
        // The overview follows the new mode at once.
        .onChange(of: app.repositoryMode) { _, _ in Task { await store.refresh(app) } }
        .onChange(of: app.workspaceRepository) { _, _ in Task { await store.refresh(app) } }
    }
}

private extension RepositoryMode {
    /// The title short enough to sit under a picture.
    var short: String {
        switch self {
        case .single: "One repository"
        case .perProject: "Per project"
        case .mixed: "Both"
        }
    }
}

/// A mode drawn as three projects (bars) wired to their repositories (boxes): one lime box
/// for all, a box each, or a shared lime box and one of its own.
private struct RepositoryModeThumb: View {
    let mode: RepositoryMode

    private static let projects: [CGFloat] = [24, 58, 92]
    /// Where each project's repository sits, and whether it is the workspace one.
    private var links: [(project: CGFloat, repo: CGFloat, workspace: Bool)] {
        let p = Self.projects
        switch mode {
        case .single: return p.map { ($0, 58, true) }
        case .perProject: return p.map { ($0, $0, false) }
        case .mixed: return [(p[0], 41, true), (p[1], 41, true), (p[2], 92, false)]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for link in links {
                    path.move(to: CGPoint(x: link.project, y: 24))
                    path.addLine(to: CGPoint(x: link.project, y: 34))
                    path.addLine(to: CGPoint(x: link.repo, y: 42))
                    path.addLine(to: CGPoint(x: link.repo, y: 48))
                }
            }
            .stroke(Soot.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            ForEach(Self.projects, id: \.self) { x in
                Capsule().fill(Soot.ink).frame(width: 20, height: 4).position(x: x, y: 20)
            }
            ForEach(Array(Set(links.map(\.repo))).sorted(), id: \.self) { x in
                let workspace = links.first { $0.repo == x }?.workspace == true
                RoundedRectangle(cornerRadius: 3)
                    .fill(workspace ? Soot.lime : Soot.surface)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(workspace ? Soot.lime : Soot.ink, lineWidth: 1.5))
                    .frame(width: 18, height: 14)
                    .position(x: x, y: 55)
            }
        }
        .frame(width: 116, height: 76)
        .background(Soot.ground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.edge))
        .accessibilityHidden(true)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Appearance")
            HStack(spacing: 16) {
                ForEach(Appearance.allCases) { option in
                    let on = appearance == option.rawValue
                    Button {
                        // The window cross-fades through a picture of itself (Appearance.apply);
                        // here only the ring travels.
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                            appearance = option.rawValue
                        }
                    } label: {
                        VStack(spacing: 8) {
                            AppearanceThumb(option: option)
                                .overlay {
                                    if on {
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime, lineWidth: 2)
                                            .matchedGeometryEffect(id: "ring", in: ring)
                                    }
                                }
                            Text(option.label).font(.system(size: 13, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? Soot.ink : Soot.muted)
                        }
                        .frame(width: 128, height: 112)
                        }
                        .buttonStyle(RowButton(lift: .tone, radius: 8))
                    .accessibilityLabel("\(option.label) appearance")
                    .accessibilityHint(option.meaning)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            // What the chosen option does, in one line under the choices.
            Text((Appearance(rawValue: appearance) ?? .system).meaning)
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.top, 16)
                .id(appearance)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: appearance)
        }
    }
}

/// A tiny Dever window in that appearance: a rail, a title bar and two rows. Auto is split
/// down the middle, light on the left.
private struct AppearanceThumb: View {
    let option: Appearance

    var body: some View {
        ZStack {
            switch option {
            case .light: face(dark: false)
            case .dark: face(dark: true)
            case .system:
                face(dark: false)
                face(dark: true).mask(alignment: .trailing) { Rectangle().frame(width: 58) }
            }
        }
        .frame(width: 116, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.edge))
        .accessibilityHidden(true)
    }

    private func face(dark: Bool) -> some View {
        let ground = Color(white: dark ? 0.06 : 0.96)
        let surface = Color(white: dark ? 0.16 : 1)
        let ink = Color(white: dark ? 0.85 : 0.2)
        return HStack(spacing: 0) {
            VStack(spacing: 6) {
                Circle().fill(Soot.lime).frame(width: 8, height: 8)
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.35)).frame(width: 12, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.35)).frame(width: 12, height: 12)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(width: 24)
            .background(surface)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(ink).frame(width: 36, height: 5)
                Capsule().fill(ink.opacity(0.35)).frame(width: 60, height: 4)
                Capsule().fill(ink.opacity(0.35)).frame(width: 46, height: 4)
            }
            .padding(.leading, 12).padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ground)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What choosing it does, shown under the choices.
    var meaning: String {
        switch self {
        case .system: "Follows your Mac, light or dark"
        case .light: "Always light, whatever your Mac uses"
        case .dark: "Always dark, whatever your Mac uses"
        }
    }

    /// Applied app-wide, so sheets, menus and popovers follow too. The window cross-fades:
    /// a picture of it as it was fades out over the new appearance (250 ms), the way macOS
    /// itself switches, so no colour smears through an intermediate tone. Instant under
    /// Reduce Motion, and on the first application at launch.
    @MainActor func apply() {
        let appearance: NSAppearance? = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        let window = NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        // The picture is taken before the switch, so it holds the old colours.
        var rep: NSBitmapImageRep?
        if let content = window?.contentView, !Motion.reduced,
           let cache = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: cache)
            rep = cache
        }
        let before = window?.effectiveAppearance.name
        NSApp.appearance = appearance
        guard let window, let content = window.contentView, let rep,
              window.effectiveAppearance.name != before else { return }
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(rep)
        let veil = NSImageView(frame: content.bounds)
        veil.image = image
        veil.imageScaling = .scaleAxesIndependently
        veil.autoresizingMask = [.width, .height]
        content.addSubview(veil, positioned: .above, relativeTo: nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            veil.animator().alphaValue = 0
        }, completionHandler: { veil.removeFromSuperview() })
    }
}

// MARK: - Notifications

private struct AlertsSection: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: UNAuthorizationStatus = .notDetermined
    @AppStorage(AlertKind.pipelineFailing.settingKey) private var wanted = true

    /// The notification reaches the user: the switch is on and macOS allows it.
    private var on: Bool { wanted && status != .denied && status != .notDetermined }

    private var stateLine: String {
        switch status {
        case .denied: "Blocked for Dever in System Settings"
        case .notDetermined: "macOS asks you once"
        default: wanted ? "A macOS notification, once per failure" : "Off"
        }
    }

    /// Turning it on the first time is what makes macOS ask.
    private func set(_ value: Bool) {
        wanted = value
        guard value, status == .notDetermined else { return }
        Task { _ = await Notifier.shared.requestAuthorization(); await refresh() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Notifications", detail: "Dever tells you when a project needs you")
            SettingRows {
                SettingRow(title: "When a pipeline fails", detail: stateLine,
                           tap: status == .denied ? nil : { set(!on) }) {
                    if status == .denied {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(SecondaryButton())
                    } else {
                        Toggle("Notify me when a pipeline fails", isOn: Binding(get: { on }, set: set))
                            .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
                    }
                }
                // What it sends, in the user's own project. Dimmed while it is off.
                NotificationPreview(title: "\(app.projects.first?.name ?? "Checkout"): pipeline failing",
                                    message: "The default branch fails its checks.")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .opacity(on ? 1 : 0.4)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: on)
            }
        }
        .task { await refresh() }
        // Back from System Settings: show the new state.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        status = await Notifier.shared.authorizationStatus()
        // Snapshots: DEVER_SNAPSHOT_NOTIFY=ask|denied|on shows the other states.
        switch ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_NOTIFY"] {
        case "ask": status = .notDetermined
        case "denied": status = .denied
        case "on": status = .authorized
        default: break
        }
    }
}

/// A macOS notification banner in miniature: the app's mark, a title, a line, "now".
private struct NotificationPreview: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DeverMark().frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Soot.line))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("now").font(.system(size: 11)).foregroundStyle(Soot.muted)
                }
                Text(message).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 420, alignment: .leading)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Soot.line))
        .accessibilityHidden(true)
    }
}

// MARK: - Intelligence

/// What the Mac's own model does in Dever: one switch per use, the language of summaries, all
/// marked Beta. While the model is off or not ready, the reason and the way to System Settings
/// instead. Under either, on a Mac it could reach, the picture of the local model to come; on a
/// Mac that cannot run Apple's model, that picture alone.
private struct IntelligenceSection: View {
    @ObservedObject private var status = IntelligenceStatus.shared
    @AppStorage(IntelligencePreferences.summaryLanguageKey) private var language = IntelligencePreferences.SummaryLanguage.source.rawValue

    private var shown: [IntelligenceFeature] {
        status.availability == .unsupported ? [] : IntelligenceFeature.allCases.filter(IntelligenceFeature.shipped.contains)
    }
    private var mark: IntelligenceFeature.BetaMark { IntelligenceFeature.betaMark(among: shown) }

    private var headline: String {
        switch status.availability {
        case .available: mark == .none ? IntelligenceFeature.purpose + " Nothing leaves it." : IntelligenceFeature.betaHeadline
        case .off: "Apple Intelligence is off on this Mac"
        case .notReady: "Apple Intelligence is not ready on this Mac yet"
        case .unsupported: "Apple Intelligence is not available on this Mac"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Intelligence", detail: headline, tag: mark == .page ? .beta : nil)
            if status.availability == .available {
                ForEach(IntelligenceFeature.Group.allCases) { group in
                    let features = group.features.filter(shown.contains)
                    if !features.isEmpty {
                        Text(group.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                            .padding(.leading, 16).padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        SettingRows {
                            ForEach(features) { feature in
                                let last = feature == features.last && group != .summaries
                                IntelligenceSwitch(feature: feature, divided: !last,
                                                   beta: mark == .rows && feature.maturity == .beta)
                            }
                            if group == .summaries {
                                SettingRow(title: "Language", divided: false) {
                                    SegmentPicker(label: "Language of summaries",
                                                  options: IntelligencePreferences.SummaryLanguage.allCases.map { (label: $0.label, value: $0.rawValue) },
                                                  selection: $language)
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else if status.availability.fixable {
                SettingRows {
                    SettingRow(title: status.availability == .off ? "Turn it on to use it here" : "Dever will use it once it is ready",
                               detail: "Summaries are written on this Mac. Nothing leaves it.",
                               divided: false) {
                        ExternalLink("Open System Settings", destination: IntelligenceInvitation.settingsURL,
                                     lift: Soot.ground)
                    }
                }
                .padding(.bottom, 24)
            }
            if LocalModelOutlook.announced() { ComingSoonBlock(today: status.availability != .unsupported) }
        }
    }
}

/// One use of the model, on or off. Turning it off removes what it had written.
private struct IntelligenceSwitch: View {
    let feature: IntelligenceFeature
    let divided: Bool
    /// Marked on the row: some features on the page have left beta, this one has not.
    let beta: Bool
    @AppStorage private var on: Bool

    init(feature: IntelligenceFeature, divided: Bool, beta: Bool = false) {
        self.feature = feature
        self.divided = divided
        self.beta = beta
        _on = AppStorage(wrappedValue: true, feature.settingKey)
    }

    private func set(_ value: Bool) { IntelligencePreferences.set(feature, on: value) }

    var body: some View {
        SettingRow(title: feature.title, detail: feature.detail, divided: divided, tap: { set(!on) }) {
            HStack(spacing: 10) {
                if beta { StageTag(kind: .beta) }
                if feature == .detectedMentions { GeneratedMark(size: 12, mention: true) }
                Toggle(feature.title, isOn: Binding(get: { on }, set: set))
                    .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
            }
        }
    }
}

// MARK: - Launch, prefix

private struct LaunchSection: View {
    @AppStorage(Preferences.landingKey) private var landing = Preferences.Landing.overview.rawValue
    @State private var atLogin = Preferences.launchesAtLogin
    @State private var loginError: String?

    private func setLogin(_ on: Bool) {
        do { try Preferences.setLaunchAtLogin(on); atLogin = on; loginError = nil }
        catch { loginError = error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Launch", detail: "Dever keeps checking while it runs, even with its window closed")
            SettingRows {
                SettingRow(title: "Open at login", detail: loginError, tap: { setLogin(!atLogin) }) {
                    Toggle("Open at login", isOn: Binding(get: { atLogin }, set: setLogin))
                    .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
                }
                SettingRow(title: "Open on", divided: false) {
                    SegmentPicker(label: "Screen at launch",
                                  options: Preferences.Landing.allCases.map { (label: $0.label, value: $0.rawValue) },
                                  selection: $landing)
                }
            }
        }
    }
}

/// A few mutually exclusive options in one capsule: a 360pt track on the ground tone, segments of
/// equal width so every picker's edges line up, the lime pill springing to the chosen one. 32 high,
/// 13pt; the words not chosen are muted. `width: nil` fills the room it is given (the View popover).
struct SegmentPicker<Value: Hashable>: View {
    let label: String
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var width: CGFloat? = Buttons.controlWidth
    /// The track's tone: ground on a surface card, surface when the picker sits on the ground (a popover).
    var track: Color = Soot.ground
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { Motion.run(Motion.settle) { selection = option.value } } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Soot.limeInk : Soot.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if on { Capsule().fill(Soot.lime).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                }
                .buttonStyle(SegmentButton(on: on))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(width: width, height: 32)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(track, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Agents

/// The coding agents: which one a start uses, where each opens, and where each repository the
/// projects follow is cloned on this Mac. Every tool in `AgentTool` gets its tile and its row;
/// nothing here names one.
private struct AgentsSection: View {
    @EnvironmentObject var app: AppState
    @AppStorage(AgentPreferences.preferredKey) private var preferred = ""
    @State private var clones = AgentPreferences.clones
    /// What the last pick or search did, or why it was refused.
    @State private var note: (text: String, failed: Bool)?
    @State private var searching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    private var choice: AgentChoice { AgentChoice(stored: preferred) }

    /// Every repository a project follows, once.
    private var repositories: [String] {
        var seen = Set<String>()
        return app.projects.flatMap { app.repositories(for: $0) }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// What the choice means at a start, in one line.
    private var consequence: String {
        switch choice {
        case .unset: "Not chosen yet: the first start asks"
        case .ask: "Every start shows the agents to pick from"
        case .tool(let tool): "One click starts \(tool.label); the chevron beside it offers the others"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Agents",
                        detail: "Start a coding agent on an issue: in your own tool, on a worktree of the issue's branch, the brief filled in and not sent.")
            title("Your agent")
            HStack(spacing: 16) {
                ForEach(AgentTool.allCases) { tool in
                    tile(.tool(tool), name: tool.label, detail: AgentApps.app(tool) == nil ? "App not found" : "Installed") {
                        AgentMark(tool: tool, size: 44)
                    }
                }
                tile(.ask, name: "Ask each time", detail: "Any of them") {
                    // The agents' marks, fanned: any of them.
                    ZStack {
                        ForEach(Array(AgentTool.allCases.enumerated()), id: \.element) { index, tool in
                            AgentMark(tool: tool, size: 30)
                                .offset(x: CGFloat(index) * 18 - CGFloat(AgentTool.allCases.count - 1) * 9)
                        }
                    }
                    .frame(height: 44)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your agent")
            Text(consequence).font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.top, 14)
                .id(preferred)
                .transition(.opacity)

            title("Where it opens")
            SettingRows {
                ForEach(Array(AgentTool.allCases.enumerated()), id: \.element) { index, tool in
                    AgentSurfaceRow(tool: tool, divided: index < AgentTool.allCases.count - 1)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                title("Your clones")
                Spacer(minLength: 16)
                if !repositories.isEmpty {
                    Button(searching ? "Looking…" : "Find them in a folder…", action: search)
                        .buttonStyle(TertiaryButton(tint: .lime, lift: Soot.surface, font: .system(size: 13, weight: .medium)))
                        .disabled(searching)
                        .help("Pick a folder; Dever finds the clones under it by their GitHub remote")
                }
            }
            if repositories.isEmpty {
                Text("No project follows a repository yet.").font(.system(size: 13)).foregroundStyle(Soot.muted)
            } else {
                SettingRows {
                    ForEach(Array(repositories.enumerated()), id: \.element) { index, name in
                        let clone = AgentPreferences.clone(of: name, in: clones)
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                BrandLogo(service: .github, size: 20).foregroundStyle(Soot.ink).opacity(clone == nil ? 0.55 : 1)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: name).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                                    HStack(spacing: 5) {
                                        Image(systemName: clone == nil ? "questionmark.folder" : "folder.fill")
                                            .font(.system(size: 11)).foregroundStyle(clone == nil ? Soot.muted : Soot.lime)
                                            .accessibilityHidden(true)
                                        Text(verbatim: clone.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Asked the first time an agent starts on it")
                                            .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer(minLength: 16)
                                Button(clone == nil ? "Choose…" : "Change…") { choose(name) }
                                    .buttonStyle(SecondaryButton())
                                    .accessibilityLabel("\(clone == nil ? "Choose" : "Change") the folder of \(name)")
                            }
                            .frame(minHeight: 60)
                            if index < repositories.count - 1 { Rectangle().fill(Soot.line).frame(height: 1) }
                        }
                    }
                }
            }
            if let note {
                Text(note.text).font(.system(size: 12)).foregroundStyle(note.failed ? Theme.negative : Soot.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            Text("A worktree goes beside its clone, in .dever/worktrees. A branch already checked out somewhere is opened where it is.")
                .font(.system(size: 12)).foregroundStyle(Soot.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .motion(Motion.ui, fade: true, value: note?.text)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: preferred)
        .onAppear { clones = AgentPreferences.clones }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
            .padding(.top, 28).padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    /// One choice of "Your agent": a mark, a name, a quiet word, the lime ring on the chosen one.
    private func tile<Mark: View>(_ option: AgentChoice, name: String, detail: String, @ViewBuilder mark: () -> Mark) -> some View {
        let on = choice == option
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { preferred = option.stored }
        } label: {
            VStack(spacing: 10) {
                mark()
                VStack(spacing: 1) {
                    Text(name).font(.system(size: 13, weight: on ? .semibold : .medium)).foregroundStyle(on ? Soot.ink : Soot.muted)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted)
                }
            }
            .frame(width: 148, height: 124)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.lime, lineWidth: 2)
                        .matchedGeometryEffect(id: "ring", in: ring)
                }
            }
        }
        .buttonStyle(RowButton(lift: .tone, radius: 12))
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func choose(_ repository: String) {
        guard let folder = AgentFolderPanel.choose(clone: repository) else { return }
        do {
            try AgentLauncher.register(folder, as: repository)
            note = nil
        } catch {
            note = (error.localizedDescription, true)
        }
        clones = AgentPreferences.clones
    }

    /// Fills in the repositories whose clone is under the folder picked; those already set are kept.
    private func search() {
        guard let folder = AgentFolderPanel.chooseSearchFolder() else { return }
        searching = true
        let wanted = repositories
        Task {
            let found = await Task.detached { CloneFinder.clones(under: folder) }.value
            var added = 0
            for name in wanted where AgentPreferences.clone(of: name) == nil {
                if let clone = found[name.lowercased()] { AgentPreferences.setClone(clone, for: name); added += 1 }
            }
            clones = AgentPreferences.clones
            searching = false
            note = (added == 0 ? "No new clone found under \((folder.path as NSString).abbreviatingWithTildeInPath)"
                               : "\(added) clone\(added == 1 ? "" : "s") found", false)
        }
    }
}

/// One agent's row of "Where it opens": its mark, its name, desktop app or terminal.
private struct AgentSurfaceRow: View {
    let tool: AgentTool
    let divided: Bool
    @AppStorage private var surface: String

    init(tool: AgentTool, divided: Bool) {
        self.tool = tool
        self.divided = divided
        _surface = AppStorage(wrappedValue: AgentSurface.app.rawValue, AgentPreferences.surfaceKey(tool))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AgentMark(tool: tool, size: 24)
                Text(tool.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                Spacer(minLength: 16)
                SegmentPicker(label: "\(tool.label) opens in",
                              options: AgentSurface.allCases.map { (label: $0.label, value: $0.rawValue) }, selection: $surface)
            }
            .frame(minHeight: 56)
            if divided { Rectangle().fill(Soot.line).frame(height: 1) }
        }
    }
}

// MARK: - About

/// Version, updates, and the welcome tour.
private struct AboutSection: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "About", detail: "Dever \(version)")
            SettingRows {
                SettingRow(title: "Updates", detail: "Releases on GitHub") {
                    ExternalLink("Check for updates", destination: URL(string: "https://github.com/eri/dever/releases")!)
                        .padding(.trailing, -8)
                    .accessibilityLabel("Check for updates on GitHub")
                }
                SettingRow(title: "Welcome tour", detail: "The first-launch setup again; nothing is reset", divided: false) {
                    Button("Start") { NotificationCenter.default.post(name: .showOnboarding, object: nil) }
                        .buttonStyle(SecondaryButton())
                        .accessibilityLabel("Start the welcome tour")
                }
            }
        }
    }
}

// MARK: - GitHub

struct GitHubLoginSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code: GitHubAuth.DeviceCode?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var copied = false

    var body: some View {
        StepSheet(close: { task?.cancel(); dismiss() }) {
            VStack(alignment: .leading, spacing: 28) {
                if let code {
                    VStack(alignment: .leading, spacing: 8) {
                        StepTitle(text: "Enter this code on GitHub")
                        Text("Dever connects as soon as you approve.").font(.system(size: 14)).foregroundStyle(Soot.muted)
                    }
                    HStack(spacing: 16) {
                        Text(code.user_code)
                            .font(.system(size: 36, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Soot.lime)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code.user_code, forType: .string)
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(SecondaryButton(size: .sheet))
                    }
                    // Waiting: a light travelling along the bottom edge, like the onboarding rows.
                    HStack(spacing: 12) {
                        BrandLogo(service: .github, size: 18).foregroundStyle(Soot.ink)
                        Text("Waiting for your approval").font(.system(size: 14)).foregroundStyle(Soot.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .frame(maxWidth: 420)
                    .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                    .overlay(alignment: .bottom) { WaitingLine() }
                    .clipShape(RoundedRectangle(cornerRadius: Soot.fieldRadius))
                    .accessibilityElement(children: .combine)
                    Link(destination: URL(string: code.verification_uri)!) {
                        HStack(spacing: 6) { Text("Open GitHub"); Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)) }
                    }
                    .buttonStyle(PrimaryButton(size: .sheet))
                } else {
                    StepTitle(text: "Connect GitHub")
                    VStack(spacing: 8) {
                        OptionRow(icon: AnyView(BrandLogo(service: .github, size: 20).foregroundStyle(Soot.ink)),
                                  title: "Sign in with a code", detail: "Approve Dever on github.com",
                                  recommended: true, enabled: true) { startDeviceFlow() }
                        OptionRow(icon: AnyView(Image(systemName: "terminal").font(.system(size: 16)).foregroundStyle(Soot.ink)),
                                  title: "Use GitHub CLI", detail: "Reuse your gh session",
                                  recommended: false, enabled: true) { importGh() }
                    }
                    .frame(maxWidth: 420)
                }
                if let error { ErrorLabel(error) }
            }
        }
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_GITHUB_CODE shows the waiting state with a sample code.
            if let sample = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_GITHUB_CODE"] {
                code = .init(device_code: "", user_code: sample, verification_uri: "https://github.com/login/device",
                             interval: 5, expires_in: 900)
            }
        }
    }

    private func finish(token: String) async throws {
        let login = try await GitHubClient(token: token).viewerLogin()
        app.github = GitHubCredentials(token: token, login: login)
        dismiss()
    }

    private func startDeviceFlow() {
        task = Task {
            do {
                let c = try await GitHubAuth.startDeviceFlow()
                code = c
                try await finish(token: try await GitHubAuth.pollToken(c))
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                code = nil
            }
        }
    }

    private func importGh() {
        Task {
            do { try await finish(token: try GitHubAuth.tokenFromGhCLI()) } catch { self.error = error.localizedDescription }
        }
    }
}

/// Indeterminate progress as light travelling along an edge, not a spinner (still under Reduce Motion).
struct WaitingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: 1.4)) / 1.4
                Rectangle()
                    .fill(LinearGradient(colors: [Soot.lime.opacity(0), Soot.lime, Soot.lime.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.35, height: 2)
                    .offset(x: -w * 0.35 + CGFloat(phase) * w * 1.35)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
