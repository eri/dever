import SwiftUI
import UserNotifications

struct AccountsView: View {
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
                    Text("Accounts").font(Theme.title).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
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
                SettingsSection("Notifications",
                                description: "Dever checks your projects every 5 minutes while it runs, even with its window closed, and tells you once about each situation.") {
                    NotificationSettings()
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                SettingsSection("Slack channel naming",
                                description: "Project channels start with this prefix. Import from Slack uses it to find them and to name the projects.") {
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
            }
            .padding(Theme.pad)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheetBackground()
        .navigationTitle("Accounts")
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
                Label(service.label, systemImage: service.symbol)
                    .font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Group {
                    if let detail {
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
            if app.isConnected(service) {
                Button(checking ? "Checking…" : "Check connection") { Task { await test() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(checking)
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
            } else if browserFlow != nil {
                Text("Approve in your browser…").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { browserFlow?.cancel(); browserFlow = nil }
            } else {
                Button("Connect") { start() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func test() async {
        checking = true
        defer { checking = false }
        do {
            let who: String = switch service {
            case .github: "@" + (try await app.githubClient().viewerLogin())
            case .slack: try await app.withSlack { try await $0.authTest() }
            case .linear: try await app.withLinear { try await $0.viewer() }.userName
            }
            status = "Working — signed in as \(who)"
            statusIsError = false
        } catch {
            status = error.localizedDescription
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect GitHub").font(.title2.bold())
            if let code {
                Text("Enter this code on GitHub:")
                HStack {
                    Text(code.user_code).font(.system(size: 28, weight: .bold, design: .monospaced)).textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.user_code, forType: .string)
                    }
                }
                Link("Open \(code.verification_uri)", destination: URL(string: code.verification_uri)!)
                Text("Waiting for you to approve on GitHub…").font(Theme.body).foregroundStyle(Theme.muted)
            } else {
                Button("Sign in with GitHub (code)") { startDeviceFlow() }.buttonStyle(PrimaryButtonStyle())
                Button("Use GitHub CLI session (gh)") { importGh() }
            }
            if let error {
                Label {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            HStack { Spacer(); Button("Close") { task?.cancel(); dismiss() } }
        }
        .padding(24)
        .frame(width: 440)
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
                NSWorkspace.shared.open(URL(string: c.verification_uri)!)
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
