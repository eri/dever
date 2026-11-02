import SwiftUI
import UserNotifications

struct AccountsView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    @State private var loginSheet: ServiceKind?

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(ServiceKind.allCases) { s in
                    AccountRow(service: s, connect: { loginSheet = s })
                }
            }
            NotificationSettings()
            Section {
                TextField("Project channel prefix", text: $channelPrefix)
                Text("Example: \(Naming.channelName(for: "Acme Corp", prefix: channelPrefix))")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Slack convention")
            }
            Section {
                Text("""
                Slack and Linear: "Connect" opens your browser, you approve the team's Dever app, \
                then come back here. Linear renews its access automatically; Slack never expires. \
                GitHub: enter a code on github.com, or reuse your GitHub CLI session. \
                No API key to create; access tokens are stored in the macOS Keychain.
                """)
                .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("How it works")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
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
        HStack {
            Label(service.label, systemImage: service.symbol).frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let detail {
                    Label {
                        Text(detail).lineLimit(1).help(detail)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .accessibilityLabel("Connected: \(detail)")
                } else {
                    Label {
                        Text("Not connected").foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
                if let status {
                    Label {
                        Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark")
                            .foregroundStyle(statusIsError ? Color.orange : Color.green)
                    }
                    .font(.caption)
                }
            }
            Spacer()
            if app.isConnected(service) {
                if checking {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking connection")
                }
                Button("Check connection") { Task { await test() } }.disabled(checking)
                Button("Disconnect…") { confirmDisconnect = true }
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
                ProgressView().controlSize(.small)
                Text("Approve in your browser…").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { browserFlow?.cancel(); browserFlow = nil }
            } else {
                Button("Connect") { start() }.buttonStyle(.borderedProminent)
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

private struct GitHubLoginSheet: View {
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
                ProgressView("Waiting for authorization…").controlSize(.small)
            } else {
                Button("Sign in with GitHub (code)") { startDeviceFlow() }.buttonStyle(.borderedProminent)
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
        Section {
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
                    .buttonStyle(.borderedProminent)
                }
            default:
                ForEach(AlertKind.allCases) { kind in
                    Toggle(kind.settingLabel, isOn: Binding(
                        get: { kind.isEnabled },
                        set: { UserDefaults.standard.set($0, forKey: kind.settingKey) }
                    ))
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Dever checks your projects every 5 minutes while it's running, even with its window closed. Each situation is notified once.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        status = await Notifier.shared.authorizationStatus()
    }
}
