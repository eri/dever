import SwiftUI

/// First run. Three stages, shown in order by position rather than by number:
/// what Dever is (a bento board) and your name, then the accounts, then a first project.
struct OnboardingView: View {
    enum Stage: Int, CaseIterable {
        case welcome, connect, project
        var label: String {
            switch self {
            case .welcome: "Welcome"
            case .connect: "Connect"
            case .project: "First project"
            }
        }
    }

    @EnvironmentObject var app: AppState
    @AppStorage("displayName") private var displayName = ""
    @State var stage: Stage = .welcome
    let finish: (_ then: OnboardingExit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, Onboarding.margin)
                .padding(.top, 12)
                .padding(.bottom, 20)
            Group {
                switch stage {
                case .welcome: WelcomeStage(next: { stage = .connect })
                case .connect: ConnectStage(back: { stage = .welcome }, next: { stage = .project })
                case .project: FirstProjectStage(back: { stage = .connect }, finish: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Onboarding.board)
        .onReceive(NotificationCenter.default.publisher(for: .showOnboardingStage)) { note in
            if let raw = note.object as? Int, let s = Stage(rawValue: raw) { stage = s }
        }
    }

    /// Setup progress at its true ratio, with the stages named instead of numbered.
    private var progress: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                DeverMark().frame(width: 18, height: 18)
                Text("Dever").font(Theme.bodyStrong).foregroundStyle(Theme.text)
            }
            Spacer()
            HStack(spacing: 20) {
                ForEach(Stage.allCases, id: \.self) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.label)
                            .font(s == stage ? Theme.smallStrong : Theme.small)
                            .foregroundStyle(s.rawValue <= stage.rawValue ? Theme.text : Theme.muted)
                        Capsule()
                            .fill(s.rawValue <= stage.rawValue ? Theme.text : Theme.empty)
                            .frame(width: 120, height: 3)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(s == stage ? .isSelected : [])
                }
            }
            Spacer()
            Button("Skip setup") { finish(.overview) }
                .buttonStyle(.link)
                .font(Theme.small)
                .help("Go straight to Dever. You can connect accounts later in Accounts.")
        }
        .frame(height: 40)
    }
}

/// Where to go when onboarding ends.
enum OnboardingExit { case overview, newProject, importSlack, importLinear }

/// Board geometry and fills, after the bento brief: one gap, one radius, flat tiles,
/// separation by fill contrast. Colours come from Dever's own palette.
enum Onboarding {
    static let gap: CGFloat = 12
    static let margin: CGFloat = 28
    static let radius: CGFloat = 22
    static let pad: CGFloat = 24

    static let board = Color(light: 0xEDEDEA, dark: 0x0A0B0D)
    static let paper = Color(light: 0xFFFFFF, dark: 0x17191B)
    static let ink = Color(light: 0x131416, dark: 0xF5F6F7)
    static let dark = Color(light: 0x16181A, dark: 0x22262A)         // the dark tile in both themes
    static let onDark = Color(light: 0xF5F6F7, dark: 0xF5F6F7)
    static let tealTint = Color(light: 0xD9ECEF, dark: 0x13302F)
    static let blueTint = Color(light: 0xDCE7F7, dark: 0x16253A)
    static let amberTint = Color(light: 0xF6E7C6, dark: 0x332811)
    static let teal = Color(light: 0x1B6C80, dark: 0x1B6C80)
}

private struct Tile<Content: View>: View {
    var fill: Color = Onboarding.paper
    var padding: CGFloat = Onboarding.pad
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill, in: RoundedRectangle(cornerRadius: Onboarding.radius))
    }
}

/// Block title: sentence case, neutral, pinned top-left.
private struct TileTitle: View {
    let text: String
    var color: Color = Onboarding.ink
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(color.opacity(0.75))
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Welcome: the bento board and the display name

private struct WelcomeStage: View {
    @AppStorage("displayName") private var displayName = ""
    @FocusState private var nameFocused: Bool
    let next: () -> Void

    var body: some View {
        GeometryReader { geo in
            let heroWidth = max(320, geo.size.width * 0.34)
            HStack(spacing: Onboarding.gap) {
                hero.frame(width: heroWidth)
                board
            }
            .padding([.horizontal, .bottom], Onboarding.margin)
        }
        .onAppear {
            if displayName.isEmpty { nameFocused = true }
        }
    }

    // The one dominant tile: what Dever is, and the first thing to do.
    private var hero: some View {
        Tile(fill: Onboarding.dark, padding: 32) {
            VStack(alignment: .leading, spacing: 0) {
                DeverMark().frame(width: 40, height: 40)
                Spacer(minLength: 24)
                Text("Every project, in one place.")
                    .font(.system(size: 38, weight: .medium))
                    .tracking(-0.6)
                    .lineSpacing(2)
                    .foregroundStyle(Onboarding.onDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Slack, Linear and GitHub, joined project by project.")
                    .font(.system(size: 16))
                    .foregroundStyle(Onboarding.onDark.opacity(0.7))
                    .padding(.top, 12)
                Spacer(minLength: 28)
                nameForm
            }
        }
    }

    private var nameForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should we call you?")
                .font(Theme.bodyStrong).foregroundStyle(Onboarding.onDark)
            TextField("Display name", text: $displayName,
                      prompt: Text(Self.suggestedName).foregroundStyle(Onboarding.onDark.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Onboarding.onDark)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Onboarding.onDark.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Onboarding.onDark.opacity(nameFocused ? 0.6 : 0.18)))
                .focused($nameFocused)
                .onSubmit(continueTapped)
                .accessibilityLabel("Display name")
            Text("Shown in Dever's sidebar. You can change it later.")
                .font(Theme.small).foregroundStyle(Onboarding.onDark.opacity(0.6))
            Button(action: continueTapped) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(OnDarkPrimaryStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
    }

    private func continueTapped() {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        displayName = trimmed.isEmpty ? Self.suggestedName : trimmed
        next()
    }

    /// The first name from the Mac account, as a starting point.
    static var suggestedName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "You"
    }

    // The supporting tiles, three equal columns over three rows of different heights.
    private var board: some View {
        GeometryReader { geo in
            let h = geo.size.height - Onboarding.gap * 2
            VStack(spacing: Onboarding.gap) {
                HStack(spacing: Onboarding.gap) {
                    mission.frame(width: twoCols(geo.size.width))
                    proof
                }
                .frame(height: h * 0.30)
                HStack(spacing: Onboarding.gap) {
                    serviceTile(.slack, fill: Onboarding.tealTint,
                                line: "Each project's channel: who talked, and when.")
                    serviceTile(.linear, fill: Onboarding.paper,
                                line: "Its issues, from to do to done.")
                    serviceTile(.github, fill: Onboarding.amberTint,
                                line: "Its pull requests and their pipeline.")
                }
                .frame(height: h * 0.32)
                HStack(spacing: Onboarding.gap) {
                    howItWorks.frame(width: twoCols(geo.size.width))
                    alerts
                }
            }
        }
    }

    private func twoCols(_ width: CGFloat) -> CGFloat {
        (width - Onboarding.gap * 2) / 3 * 2 + Onboarding.gap
    }

    private var mission: some View {
        Tile {
            VStack(alignment: .leading, spacing: 0) {
                TileTitle(text: "What Dever does")
                Spacer(minLength: 8)
                Text("Dever follows each project across its Slack channel, Linear issues and GitHub pull requests, and tells you which one needs you.")
                    .font(.system(size: 21, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(Onboarding.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
        }
    }

    private var proof: some View {
        Tile(fill: Onboarding.blueTint) {
            VStack(alignment: .leading, spacing: 4) {
                TileTitle(text: "In one list")
                Spacer(minLength: 8)
                Text("3 → 1").font(.system(size: 48, weight: .medium)).tracking(-1).foregroundStyle(Onboarding.ink)
                    .accessibilityLabel("Three tools, one list")
                Text("tools to check, list to read").font(.system(size: 14)).foregroundStyle(Onboarding.ink.opacity(0.75))
            }
        }
    }

    private func serviceTile(_ service: ServiceKind, fill: Color, line: String) -> some View {
        Tile(fill: fill) {
            VStack(alignment: .leading, spacing: 0) {
                TileTitle(text: service.label)
                Spacer(minLength: 8)
                Image(systemName: service.symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Onboarding.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(line).font(.system(size: 14)).foregroundStyle(Onboarding.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one concrete tile: a real piece of Dever's interface, drawn with its own components.
    private var howItWorks: some View {
        Tile(fill: Onboarding.paper) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    TileTitle(text: "How it works")
                    Spacer(minLength: 8)
                    Text("See what shipped, and what's stuck.")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Onboarding.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: 170, alignment: .leading)
                SampleProjectRow()
            }
        }
    }

    private var alerts: some View {
        Tile(fill: Onboarding.teal) {
            VStack(alignment: .leading, spacing: 0) {
                TileTitle(text: "Alerts", color: .white)
                Spacer(minLength: 8)
                Image(systemName: "bell")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text("Told once when a pipeline fails or a ticket falls behind.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A sample project row built from Dever's own components, so the board shows the real product.
private struct SampleProjectRow: View {
    private let delivery = Delivery(
        issues: (1...18).map { i in
            let (type, name): (String, String) = switch i {
            case 1...9: ("completed", "Done")
            case 10...12: ("started", "In Review")
            case 13...14: ("started", "In Progress")
            default: ("unstarted", "Todo")
            }
            return ("WEB-\(i)", type, name)
        },
        openPR: [], mergedPR: ["WEB-13"])

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Checkout redesign").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Pill(text: "Needs attention", tone: .negative)
            }
            Text("#proj-checkout-redesign · Checkout").font(Theme.small).foregroundStyle(Theme.muted)
            DeliveryStrip(delivery: delivery)
            HStack(spacing: 4) {
                Text("\(delivery.shipped)/\(delivery.total) shipped").foregroundStyle(Theme.text)
                Text("· \(delivery.merged) to move").foregroundStyle(Theme.chart3)
            }
            .font(Theme.small)
            .monospacedDigit()
            HStack(spacing: 16) {
                PipelineBadge(state: .failing)
                Text("4 open pull requests").foregroundStyle(Theme.muted)
            }
            .font(Theme.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: a project with 10 of 18 issues shipped, one to move, and a failing pipeline")
    }
}

private struct OnDarkPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(Onboarding.dark)
            .frame(height: 40)
            .background(Color.white.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Connect: each tool, why Dever needs it, what it reads

private struct ConnectStage: View {
    @EnvironmentObject var app: AppState
    @AppStorage("displayName") private var displayName = ""
    let back: () -> Void
    let next: () -> Void
    @State private var githubSheet = false

    private var required: [ServiceKind] { [.slack, .linear] }
    private var ready: Bool { required.allSatisfy(app.isConnected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName.isEmpty ? "Connect your tools" : "Connect your tools, \(displayName)")
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Dever reads them to build each project's view. You approve each one in your browser; there is no API key to create, and you can disconnect at any time in Accounts.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            HStack(alignment: .top, spacing: Onboarding.gap) {
                ConnectCard(service: .slack, required: true,
                            why: "Projects live in Slack channels. Dever finds them by name, shows each channel's latest messages and can create channels for new projects.",
                            reads: ["Channel list and history", "Member names", "Create channels (only when you ask)"],
                            githubSheet: $githubSheet)
                ConnectCard(service: .linear, required: true,
                            why: "Each project's issues and their states. That is how Dever measures delivery and spots tickets that fell behind the code.",
                            reads: ["Projects, teams and issues", "Create projects (only when you ask)"],
                            githubSheet: $githubSheet)
                ConnectCard(service: .github, required: false,
                            why: "Pull requests and pipeline runs, matched to Linear issues. Optional: skip it if your team doesn't use GitHub.",
                            reads: ["Repositories you can access", "Pull requests and workflow runs"],
                            githubSheet: $githubSheet)
            }
            .fixedSize(horizontal: false, vertical: true)
            privacy
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Back", action: back).buttonStyle(SecondaryButtonStyle())
                Spacer()
                if !ready {
                    Text("Connect Slack and Linear to continue, or skip for now.")
                        .font(Theme.small).foregroundStyle(Theme.muted)
                    Button("Skip for now", action: next).buttonStyle(.link).font(Theme.small)
                }
                Button("Continue", action: next)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Onboarding.paper, in: RoundedRectangle(cornerRadius: Onboarding.radius))
        .padding([.horizontal, .bottom], Onboarding.margin)
        .sheet(isPresented: $githubSheet) { GitHubLoginSheet() }
    }
}

private extension ConnectStage {
    /// What new users ask before granting access.
    var privacy: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock").foregroundStyle(Theme.text).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your data stays on this Mac").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text("Dever talks to Slack, Linear and GitHub directly; there is no Dever server. Access tokens sit in the macOS Keychain. Dever never posts messages, and only creates a channel or a project when you ask it to.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ConnectCard: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    let required: Bool
    let why: String
    let reads: [String]
    @Binding var githubSheet: Bool
    @State private var flow: Task<Void, Never>?
    @State private var error: String?

    private var connectedAs: String? {
        switch service {
        case .slack: app.slack.map { "\($0.teamName) workspace" }
        case .linear: app.linear.map { "\($0.account.orgName), as \($0.account.userName)" }
        case .github: app.github.map { "@\($0.login)" }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: service.symbol).font(.system(size: 18)).foregroundStyle(Theme.text)
                    .frame(width: 22).accessibilityHidden(true)
                Text(service.label).font(Theme.section).foregroundStyle(Theme.text)
                Spacer()
                Pill(text: required ? "Needed" : "Optional", tone: .neutral)
            }
            Text(why).font(Theme.body).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dever can").font(Theme.smallStrong).foregroundStyle(Theme.muted)
                ForEach(reads, id: \.self) { item in
                    Label {
                        Text(item).foregroundStyle(Theme.text)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Theme.muted)
                    }
                    .font(Theme.small)
                }
            }
            Spacer(minLength: 0)
            if let error { ErrorLabel(error) }
            if let connectedAs {
                Label {
                    Text("Connected to \(connectedAs)").foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                }
                .font(Theme.bodyStrong)
                .frame(height: 32)
            } else if flow != nil {
                HStack(spacing: 12) {
                    Text("Approve in your browser…").font(Theme.body).foregroundStyle(Theme.muted)
                    Button("Cancel") { flow?.cancel(); flow = nil }.buttonStyle(.link)
                }
                .frame(height: 32)
            } else {
                Button("Connect \(service.label)", action: connect)
                    .buttonStyle(required ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    private func connect() {
        error = nil
        if service == .github { githubSheet = true; return }
        flow = Task {
            do {
                switch service {
                case .slack: app.slack = try await SlackAuth.connect()
                case .linear: app.linear = try await LinearAuth.connect()
                case .github: break
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            flow = nil
        }
    }
}

/// Lets one control pick between two button styles.
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - First project: naming convention, a way in, notifications

private struct FirstProjectStage: View {
    @EnvironmentObject var app: AppState
    @AppStorage("slackChannelPrefix") private var channelPrefix = "proj-"
    let back: () -> Void
    let finish: (OnboardingExit) -> Void
    @State private var notifications: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add your first project")
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("A project joins a Slack channel and a Linear project. Bring in the ones you already have, or start a new one.")
                    .font(Theme.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: Onboarding.gap) {
                choice(title: "From Slack channels", symbol: ServiceKind.slack.symbol,
                       text: "Lists channels named with your prefix and pairs each with its Linear project.",
                       action: "Import from Slack", exit: .importSlack, enabled: app.slack != nil,
                       disabledReason: "Connect Slack first.") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Channel prefix").font(Theme.smallStrong).foregroundStyle(Theme.muted)
                        TextField("Prefix", text: $channelPrefix, prompt: Text("proj-"))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 180).labelsHidden()
                        Text("e.g. #\(Naming.channelName(for: "Checkout redesign", prefix: channelPrefix))")
                            .font(Theme.small).foregroundStyle(Theme.muted)
                    }
                }
                choice(title: "From Linear projects", symbol: ServiceKind.linear.symbol,
                       text: "Lists your Linear projects and finds the matching Slack channel for each.",
                       action: "Import from Linear", exit: .importLinear, enabled: app.linear != nil,
                       disabledReason: "Connect Linear first.") { EmptyView() }
                choice(title: "Start a new one", symbol: "plus",
                       text: "Creates the Slack channel and the Linear project for you, or links existing ones.",
                       action: "New project", exit: .newProject, enabled: true, disabledReason: nil) { EmptyView() }
            }
            .fixedSize(horizontal: false, vertical: true)
            notificationsRow
            Spacer(minLength: 0)
            HStack {
                Button("Back", action: back).buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("I'll do it later") { finish(.overview) }.buttonStyle(.link).font(Theme.small)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Onboarding.paper, in: RoundedRectangle(cornerRadius: Onboarding.radius))
        .padding([.horizontal, .bottom], Onboarding.margin)
        .task { notifications = await Notifier.shared.authorizationStatus() == .authorized }
    }

    private func choice<Extra: View>(title: String, symbol: String, text: String, action: String,
                                     exit: OnboardingExit, enabled: Bool, disabledReason: String?,
                                     @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.text).frame(width: 22)
                    .accessibilityHidden(true)
                Text(title).font(Theme.section).foregroundStyle(Theme.text)
            }
            Text(text).font(Theme.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            extra()
            Spacer(minLength: 0)
            Button(action) { finish(exit) }
                .buttonStyle(exit == .importSlack ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                .disabled(!enabled)
            if !enabled, let disabledReason {
                Text(disabledReason).font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    private var notificationsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell").foregroundStyle(Theme.text).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Get told when a project needs you").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text("A failing pipeline, a missed target date, merged work whose ticket didn't move. Once per situation.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            Spacer()
            if notifications == true {
                Label("Notifications on", systemImage: "checkmark.circle.fill")
                    .font(Theme.bodyStrong).foregroundStyle(Theme.positive)
            } else {
                Button("Turn on notifications") {
                    Task {
                        _ = await Notifier.shared.requestAuthorization()
                        notifications = await Notifier.shared.authorizationStatus() == .authorized
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Notification.Name {
    /// Switches onboarding to a stage; `object` is the stage's raw value (snapshots).
    static let showOnboardingStage = Notification.Name("dever.showOnboardingStage")
}
