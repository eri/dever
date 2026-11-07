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
        case accounts, repositories, overview, appearance, alerts, launch, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .accounts: "Accounts"
            case .repositories: "Repositories"
            case .overview: "Overview"
            case .appearance: "Appearance"
            case .alerts: "Alerts"
            case .launch: "Launch"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .accounts: "link"
            case .repositories: "shippingbox"
            case .overview: "list.bullet.rectangle"
            case .appearance: "circle.lefthalf.filled"
            case .alerts: "bell"
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
                    case .overview: OverviewSettingsView()
                    case .appearance: AppearanceSection()
                    case .alerts: AlertsSection()
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
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.ink)
                        .frame(width: 26, height: 26)
                        .background(Soot.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Soot.ground, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .modifier(FocusOutline(radius: 13))
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
                ForEach(SettingsView.Section.allCases) { s in
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
                        .contentShape(RoundedRectangle(cornerRadius: Soot.radius))
                    }
                    .buttonStyle(.plain)
                    .modifier(FocusOutline(radius: Soot.radius))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
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
            if divided { Rectangle().fill(Soot.line).frame(height: 1) }
        }
    }
}

// MARK: - Accounts

private struct AccountsSection: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: ConnectFlow
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"

    private var connected: Int { ServiceKind.allCases.filter(app.isConnected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Accounts", detail: "\(connected) of 3 connected · tokens stay in your Keychain")
            VStack(spacing: 8) {
                ForEach(ServiceKind.allCases) { ServiceRow(service: $0, flow: flow) }
            }
            SettingRows {
                SettingRow(title: "Slack channel prefix",
                           detail: "#\(Naming.channelName(for: "Acme website", prefix: channelPrefix))", divided: false) {
                    TextField("Prefix", text: $channelPrefix, prompt: Text("proj-").foregroundStyle(Soot.muted))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14)).foregroundStyle(Soot.ink)
                        .padding(.horizontal, 12)
                        .frame(width: 140, height: 36)
                        .background(Soot.ground, in: RoundedRectangle(cornerRadius: Soot.radius))
                        .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge))
                        .accessibilityLabel("Slack channel prefix")
                }
            }
            .padding(.top, 20)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var confirmDisconnect = false
    @State private var profile: AccountProfile?
    /// The last health check: nil while unchecked or fine.
    @State private var trouble: ServiceState?

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
            stateGlyph
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
        .animation(.easeOut(duration: 0.2), value: connected)
        .animation(.easeOut(duration: 0.2), value: running)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibleSummary)
        .task(id: connectionKey) { await loadProfile() }
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
                Button("Cancel") { flow.cancel() }.buttonStyle(QuietButton())
            }
        } else if expired {
            HStack(spacing: 10) {
                Button("Reconnect") { flow.start(service, app: app) }.buttonStyle(LimeButton())
                Button("Disconnect") { confirmDisconnect = true }.buttonStyle(QuietButton())
                    .accessibilityLabel("Disconnect \(service.label)")
            }
        } else if connected {
            Button("Disconnect") { confirmDisconnect = true }.buttonStyle(QuietButton())
                .accessibilityLabel("Disconnect \(service.label)")
        } else {
            HStack(spacing: 10) {
                if let error = flow.error, error.service == service {
                    Text(error.message).font(.system(size: 12)).foregroundStyle(Theme.negative).lineLimit(1)
                        .help(error.message)
                }
                Button("Connect") { flow.start(service, app: app) }.buttonStyle(LimeButton())
                    .accessibilityLabel("Connect \(service.label)")
                    .help(service == .github ? "Sign in with a code on github.com" : "Approve Dever in your browser")
            }
        }
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

/// Where the code lives: the mode as three rows (shared with onboarding), the workspace
/// repository where the mode has one, and one line on what the choice means.
private struct RepositoriesSection: View {
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
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Repositories", detail: "Change it any time; nothing is lost")
            RepositoryModeRows(mode: mode).frame(maxWidth: 480)
            if app.repositoryMode.usesWorkspaceRepository {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Workspace repository")
                    if app.github == nil {
                        Text("Connect GitHub to pick it").font(.system(size: 13)).foregroundStyle(Soot.muted)
                    } else {
                        SearchPicker(label: "Workspace repository", placeholder: repos.loading ? "Loading…" : "Pick a repository",
                                     items: repos.items, selection: workspace)
                            .frame(maxWidth: 480)
                    }
                    if let error = repos.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 20)
                .transition(.opacity)
            }
            Text(consequence).font(.system(size: 12)).foregroundStyle(Soot.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 16)
        }
        .animation(.easeOut(duration: 0.2), value: app.repositoryMode.usesWorkspaceRepository)
        .task(id: app.github != nil) { await repos.load(app) }
        // The overview follows the new mode at once.
        .onChange(of: app.repositoryMode) { _, _ in Task { await store.refresh(app) } }
        .onChange(of: app.workspaceRepository) { _, _ in Task { await store.refresh(app) } }
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
                        // The theme itself switches at once (no cross-fade: every colour would
                        // smear); only the ring travels.
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(FocusOutline(radius: 8))
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

    /// Applied app-wide, so sheets, menus and popovers follow too.
    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Alerts

private struct AlertsSection: View {
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var enabled: [AlertKind: Bool] = Dictionary(uniqueKeysWithValues: AlertKind.allCases.map { ($0, $0.isEnabled) })

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Alerts", detail: "A macOS notification, once per situation")
            switch status {
            case .denied:
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Off for Dever in System Settings").font(.system(size: 13)).foregroundStyle(Soot.ink)
                    } icon: {
                        Image(systemName: "bell.slash").foregroundStyle(Soot.muted)
                    }
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(QuietButton())
                }
            case .notDetermined:
                VStack(alignment: .leading, spacing: 12) {
                    Text("When a pipeline fails or a project slips")
                        .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    Button("Turn on alerts") {
                        Task { _ = await Notifier.shared.requestAuthorization(); await refresh() }
                    }
                    .buttonStyle(LimeButton())
                }
            default:
                SettingRows {
                    ForEach(Array(AlertKind.allCases.enumerated()), id: \.element) { index, kind in
                        let binding = Binding(
                            get: { enabled[kind] ?? true },
                            set: { enabled[kind] = $0; UserDefaults.standard.set($0, forKey: kind.settingKey) }
                        )
                        SettingRow(title: kind.shortLabel, detail: kind.detail, divided: index < AlertKind.allCases.count - 1,
                                   tap: { binding.wrappedValue.toggle() }) {
                            Toggle(kind.shortLabel, isOn: binding)
                            .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
                        }
                    }
                }
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
    }
}

extension AlertKind {
    /// The situation in three words, for a switch beside it.
    var shortLabel: String {
        switch self {
        case .pipelineFailing: "Pipeline failing"
        case .pastTarget: "Past target date"
        case .mergedButOpen: "Merged but still open"
        }
    }

    var detail: String {
        switch self {
        case .pipelineFailing: "A branch of the project fails its checks"
        case .pastTarget: "Issues still open after the Linear target date"
        case .mergedButOpen: "Merged in code, still in progress in Linear"
        }
    }
}

// MARK: - Refresh, launch, prefix

private struct LaunchSection: View {
    @AppStorage(Preferences.refreshMinutesKey) private var minutes = 5
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
                SettingRow(title: "Open on") {
                    SegmentPicker(label: "Screen at launch",
                                  options: Preferences.Landing.allCases.map { (label: $0.label, value: $0.rawValue) },
                                  selection: $landing)
                }
                SettingRow(title: "Refresh every", detail: "Alerts follow the same beat", divided: false) {
                    SegmentPicker(label: "Refresh interval",
                                  options: Preferences.refreshChoices.map { (label: "\($0) min", value: $0) },
                                  selection: $minutes)
                }
            }
        }
    }
}

/// A few mutually exclusive options in one capsule; the lime pill springs to the chosen one.
struct SegmentPicker<Value: Hashable>: View {
    let label: String
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Soot.limeInk : Soot.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if on { Capsule().fill(Soot.lime).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modifier(SegmentFocus(on: on))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Soot.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Soot.edge))
        // The stroke is drawn once more a few points taller by the row's layout pass; the
        // capsule clip keeps only the real one.
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The focus ring of a segment, drawn inside it: ink on the lime pill, lime on the track,
/// so it reads whichever segment has it (2.4.7) and never crosses the picker's edge.
private struct SegmentFocus: ViewModifier {
    let on: Bool
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.overlay(
            Capsule().strokeBorder(on ? Soot.limeInk : Soot.lime, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        )
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
                    HoverLink(destination: URL(string: "https://github.com/eri/dever/releases")!, hoverTint: Soot.ground) {
                        HStack(spacing: 4) { Text("Check for updates"); Image(systemName: "arrow.up.right") }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Soot.lime)
                    }
                    .padding(.trailing, -8)
                    .accessibilityLabel("Check for updates on GitHub")
                }
                SettingRow(title: "Welcome tour", detail: "The first-launch setup again; nothing is reset", divided: false) {
                    Button("Start") { NotificationCenter.default.post(name: .showOnboarding, object: nil) }
                        .buttonStyle(QuietButton())
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
                        .buttonStyle(QuietButton())
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
                    Link(destination: URL(string: code.verification_uri)!) { Text("Open GitHub") }
                        .buttonStyle(LimeButton())
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
