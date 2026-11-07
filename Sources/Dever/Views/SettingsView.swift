import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    private var summary: String {
        let connected = ServiceKind.allCases.filter(app.isConnected)
        if connected.count == ServiceKind.allCases.count { return "Slack, Linear and GitHub are connected." }
        let missing = ServiceKind.allCases.filter { !app.isConnected($0) }.map(\.label)
        return "Connect \(ListFormatter.localizedString(byJoining: missing)) to see every part of your projects."
    }
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @State private var loginSheet: ServiceKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(Theme.title).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Text(summary).font(Theme.body).foregroundStyle(Theme.muted)
                }
                SettingsSection("Connected services",
                                description: "Connect opens your browser, where you approve the team's Dever app. Linear renews its access on its own; Slack and GitHub don't expire. Tokens stay in the macOS Keychain.") {
                    VStack(spacing: 0) {
                        ForEach(Array(ServiceKind.allCases.enumerated()), id: \.element) { index, s in
                            if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                            AccountRow(service: s, connect: { loginSheet = s }).padding(.vertical, 12)
                        }
                    }
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                SettingsSection("Appearance", description: "Auto follows your Mac's light or dark setting.") {
                    AppearancePicker().padding(.vertical, 12)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                SettingsSection("Notifications",
                                description: "Dever checks your projects every 5 minutes while it runs, even with its window closed, and tells you once about each situation.") {
                    NotificationSettings()
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                SettingsSection("Slack channel naming",
                                description: "Project channels start with this prefix, so Dever can find them. Leave it empty if they don't share one.") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prefix").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                        TextField("Prefix", text: $channelPrefix, prompt: Text("proj-"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .labelsHidden()
                        Text("A project named \u{201C}Acme website\u{201D} gets #\(Naming.channelName(for: "Acme website", prefix: channelPrefix)).")
                            .font(Theme.small).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                }
                RepositoryModeSettings()
            }
            .padding(Theme.pad)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheetBackground()
        .navigationTitle("Settings")
        .windowTitleHidden()
        .sheet(item: $loginSheet) { s in
            switch s {
            case .github: GitHubLoginSheet()
            case .slack, .linear: EmptyView()
            }
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    let connect: () -> Void
    @State private var status: String?
    @State private var statusIsError = false
    @State private var checking = false
    @State private var confirmDisconnect = false
    @State private var browserFlow: Task<Void, Never>?

    /// Connected, but the service rejected the token the last time Dever used it.
    private var expired: Bool { app.expired.contains(service) }

    /// GitHub opens its sheet (code entry); Slack and Linear go through the browser.
    private func start() {
        guard service != .github else { return connect() }
        status = nil
        statusIsError = false
        browserFlow = Task {
            do {
                switch service {
                case .slack: app.slack = try await SlackAuth.connect()
                case .linear: app.linear = try await LinearAuth.connect()
                case .github: break
                }
            } catch is CancellationError {
            } catch {
                status = error.localizedDescription
                statusIsError = true
            }
            browserFlow = nil
        }
    }

    var detail: String? {
        switch service {
        case .github: app.github.map { "@\($0.login)" }
        case .slack: app.slack.map { "\($0.teamName) (\($0.domain).slack.com)" }
        case .linear: app.linear.map { "\($0.account.orgName) — \($0.account.userName)" }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label { Text(service.label) } icon: { BrandLogo(service: service, size: 16) }
                    .font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Group {
                    if let detail, expired {
                        Label {
                            Text("Session expired for \(detail). Reconnect to keep reading \(service.label).")
                                .foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.negative)
                        }
                    } else if let detail {
                        Label {
                            Text(detail).foregroundStyle(Theme.muted).lineLimit(1).help(detail)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                        }
                        .accessibilityLabel("Connected: \(detail)")
                    } else {
                        Label {
                            Text("Not connected").foregroundStyle(Theme.muted)
                        } icon: {
                            Image(systemName: "circle.dashed").foregroundStyle(Theme.muted)
                        }
                    }
                    if let status {
                        Label {
                            Text(status).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark")
                                .foregroundStyle(statusIsError ? Theme.negative : Theme.positive)
                        }
                    }
                }
                .font(Theme.small)
            }
            Spacer(minLength: 12)
            if browserFlow != nil {
                Text("Approve in your browser…").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { browserFlow?.cancel(); browserFlow = nil }
            } else if app.isConnected(service) {
                if expired {
                    Button("Reconnect") { start() }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(checking ? "Checking…" : "Check connection") { Task { await test() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(checking)
                }
                Button("Disconnect…") { confirmDisconnect = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .confirmationDialog("Disconnect \(service.label)?", isPresented: $confirmDisconnect) {
                        Button("Disconnect \(service.label)", role: .destructive) {
                            status = nil
                            app.disconnect(service)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Dever stops showing \(service.label) data until you connect again. Your projects and their links are kept.")
                    }
            } else {
                Button("Connect") { start() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    /// The cheapest call that needs the token (auth.test, viewer, /user): tells a rejected
    /// token from a network that is down.
    private func test() async {
        checking = true
        defer { checking = false }
        do {
            let who: String = switch service {
            case .github: "@" + (try await app.githubClient().viewerLogin())
            case .slack: try await app.withSlack { try await $0.authTest() }
            case .linear: try await app.withLinear { try await $0.viewer() }.userName
            }
            app.succeeded(service)
            status = "Working — signed in as \(who)"
            statusIsError = false
        } catch {
            status = switch app.failure(error, service) ?? .failed(error.localizedDescription) {
            case .unauthorized: "\(service.label) rejected the token. Reconnect to continue."
            case .offline: "You're offline. \(service.label) couldn't be reached; the token is unchanged."
            case .failed(let message): "\(service.label) answered with an error: \(message)"
            case .notConnected: "\(service.label) is not connected."
            }
            statusIsError = true
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

// MARK: - Notifications

private struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch status {
            case .denied:
                HStack {
                    Label {
                        Text("Notifications are off for Dever in System Settings.")
                    } icon: {
                        Image(systemName: "bell.slash").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .notDetermined:
                HStack {
                    Label("Dever can alert you when a project needs action.", systemImage: "bell")
                    Spacer()
                    Button("Turn on notifications") {
                        Task { _ = await Notifier.shared.requestAuthorization(); await refresh() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            default:
                ForEach(AlertKind.allCases) { kind in
                    Toggle(kind.settingLabel, isOn: Binding(
                        get: { kind.isEnabled },
                        set: { UserDefaults.standard.set($0, forKey: kind.settingKey) }
                    ))
                }
            }
        }
        .font(Theme.body)
        .padding(.vertical, 12)
        .task { await refresh() }
    }

    private func refresh() async {
        status = await Notifier.shared.authorizationStatus()
    }
}

/// Settings row: a label column with the section's title and description, beside its panel.
private struct SettingsSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            label.frame(width: 240, alignment: .leading)
            panel
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.section).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text(description).font(Theme.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var panel: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSheet))
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

// MARK: - Appearance

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

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
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

private struct AppearancePicker: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Appearance.allCases) { option in
                let on = appearance == option.rawValue
                Button { appearance = option.rawValue } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 18))
                        Text(option.label).font(Theme.bodyStrong)
                    }
                    .foregroundStyle(on ? Theme.text : Theme.muted)
                    .frame(width: 96, height: 64)
                    .background(on ? Theme.sheet : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.text : Theme.control, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(FocusOutline(radius: 10))
                .accessibilityLabel("\(option.label) appearance")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
