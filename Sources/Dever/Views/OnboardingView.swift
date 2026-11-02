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
        .background(Keynote.board)
        .environment(\.colorScheme, .dark)
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

// MARK: - Welcome: a keynote-style board and the display name

/// Keynote palette: black board, near-black tiles, light carried by the objects themselves.
private enum Keynote {
    static let board = Color(red: 0, green: 0, blue: 0)
    static let tile = Color(red: 0.086, green: 0.086, blue: 0.094)        // #161618
    static let raised = Color(red: 0.145, green: 0.145, blue: 0.157)      // #252528
    static let text = Color.white
    static let muted = Color(white: 0.62)
    static let slack = Color(red: 0.31, green: 0.69, blue: 0.78)          // teal
    static let linear = Color(red: 0.42, green: 0.64, blue: 0.90)         // blue
    static let github = Color(red: 0.85, green: 0.64, blue: 0.25)         // amber
    static let spectrum = LinearGradient(colors: [slack, linear, github], startPoint: .leading, endPoint: .trailing)
    static let radius: CGFloat = 22
}

private struct KTile<Content: View>: View {
    var alignment: Alignment = .center
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(Keynote.tile, in: RoundedRectangle(cornerRadius: Keynote.radius))
            .clipShape(RoundedRectangle(cornerRadius: Keynote.radius))
    }
}

/// A short tile label, centred, at most a few words.
private struct KLabel: View {
    let text: String
    var size: CGFloat = 17
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Keynote.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An SF Symbol lit from within: the glyph, plus a soft halo in its colour.
private struct Glow: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.9), radius: 14)
            .shadow(color: color.opacity(0.5), radius: 32)
            .accessibilityHidden(true)
    }
}

private struct WelcomeStage: View {
    @AppStorage("displayName") private var displayName = ""
    @FocusState private var nameFocused: Bool
    let next: () -> Void

    var body: some View {
        GeometryReader { geo in
            let g: CGFloat = 12
            let w = geo.size.width, h = geo.size.height
            let c1 = (w - 3 * g) * 0.24, c2 = (w - 3 * g) * 0.19, c3 = (w - 3 * g) * 0.33, c4 = (w - 3 * g) * 0.24
            let r1 = (h - 2 * g) * 0.27, r2 = (h - 2 * g) * 0.43, r3 = (h - 2 * g) * 0.30
            HStack(alignment: .top, spacing: g) {
                VStack(spacing: g) {
                    oneList.frame(height: r1)
                    nameTile.frame(height: r2 + r3 + g)
                }
                .frame(width: c1)
                VStack(spacing: g) {
                    HStack(spacing: g) {
                        service(.slack, label: "Channels", color: Keynote.slack).frame(width: c2)
                        delivery.frame(width: c3)
                        alerts.frame(width: c4)
                    }
                    .frame(height: r1)
                    HStack(spacing: g) {
                        hero.frame(width: c2 + c3 + g)
                        service(.linear, label: "Issues", color: Keynote.linear).frame(width: c4)
                    }
                    .frame(height: r2)
                    HStack(spacing: g) {
                        service(.github, label: "Pull requests", color: Keynote.github).frame(width: c2)
                        urgency.frame(width: c3)
                        privacy.frame(width: c4)
                    }
                    .frame(height: r3)
                }
            }
        }
        .padding([.horizontal, .bottom], Onboarding.margin)
        .onAppear { if displayName.isEmpty { nameFocused = true } }
    }

    // The centrepiece: three tools converging on Dever, inside rings of light.
    // Everything scales with the tile so it never spills onto its neighbours.
    private var hero: some View {
        KTile {
            GeometryReader { geo in
                let d = max(120, min(geo.size.height - 64, geo.size.width * 0.6))   // outer ring diameter
                VStack(spacing: 14) {
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .stroke(AngularGradient(colors: [Keynote.slack, Keynote.linear, Keynote.github, Keynote.slack],
                                                        center: .center),
                                        lineWidth: 2)
                                .frame(width: d * (0.62 + CGFloat(i) * 0.19), height: d * (0.62 + CGFloat(i) * 0.19))
                                .opacity(0.55 - Double(i) * 0.15)
                                .blur(radius: CGFloat(i))
                        }
                        Circle()
                            .fill(RadialGradient(colors: [Keynote.linear.opacity(0.35), .clear], center: .center,
                                                 startRadius: 0, endRadius: d * 0.45))
                            .frame(width: d * 0.9, height: d * 0.9)
                        DeverMark().frame(width: d * 0.26, height: d * 0.26)
                            .shadow(color: Keynote.slack.opacity(0.8), radius: 18)
                        orbit(.slack, color: Keynote.slack, angle: -150, radius: d * 0.405)
                        orbit(.linear, color: Keynote.linear, angle: -30, radius: d * 0.405)
                        orbit(.github, color: Keynote.github, angle: 90, radius: d * 0.405)
                    }
                    .frame(width: d, height: d)
                    Text("Every project, in one place.")
                        .font(.system(size: min(30, geo.size.width / 16), weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Keynote.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func orbit(_ service: ServiceKind, color: Color, angle: Double, radius r: CGFloat) -> some View {
        Image(systemName: service.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(Keynote.raised, in: Circle())
            .overlay(Circle().strokeBorder(color.opacity(0.5)))
            .shadow(color: color.opacity(0.7), radius: 10)
            .offset(x: r * cos(angle * .pi / 180), y: r * sin(angle * .pi / 180))
            .accessibilityHidden(true)
    }

    private func service(_ service: ServiceKind, label: String, color: Color) -> some View {
        KTile {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Glow(symbol: service.symbol, color: color)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    KLabel(text: label)
                    Text("from \(service.label)").font(.system(size: 13)).foregroundStyle(Keynote.muted)
                }
            }
        }
    }

    private var oneList: some View {
        KTile {
            VStack(spacing: 6) {
                Text("3 → 1")
                    .font(.system(size: 54, weight: .bold))
                    .tracking(-1.5)
                    .foregroundStyle(Keynote.spectrum)
                    .accessibilityLabel("Three tools, one view")
                Text("tools, one view").font(.system(size: 15, weight: .medium)).foregroundStyle(Keynote.muted)
            }
        }
    }

    private var delivery: some View {
        KTile {
            VStack(spacing: 16) {
                KLabel(text: "Delivery at a glance")
                HStack(spacing: 3) {
                    Capsule().fill(Keynote.slack).frame(width: 110)
                    Capsule().fill(Keynote.github).frame(width: 18)
                    Capsule().fill(Keynote.linear).frame(width: 46)
                    Capsule().fill(Keynote.raised)
                }
                .frame(height: 14)
                .shadow(color: Keynote.slack.opacity(0.6), radius: 12)
                .accessibilityHidden(true)
                Text("10 of 18 shipped").font(.system(size: 13, weight: .medium)).foregroundStyle(Keynote.muted)
                    .monospacedDigit()
            }
        }
    }

    // A real notification, as macOS would show it.
    private var alerts: some View {
        KTile {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    DeverMark().frame(width: 22, height: 22)
                        .padding(6)
                        .background(Keynote.board, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checkout: pipeline failing").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Text("A pull request fails its checks.").font(.system(size: 11)).foregroundStyle(Keynote.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Keynote.raised, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .accessibilityHidden(true)
                KLabel(text: "Alerts that matter")
            }
        }
    }

    private var urgency: some View {
        KTile {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    urgencyRow("Checkout", status: "Needs attention", color: Color(red: 0.94, green: 0.36, blue: 0.40))
                    urgencyRow("Mobile app", status: "On track", color: Color(red: 0.25, green: 0.75, blue: 0.48))
                }
                .accessibilityHidden(true)
                KLabel(text: "Sorted by urgency")
            }
        }
    }

    private func urgencyRow(_ name: String, status: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 5)
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Text(status).font(.system(size: 12)).foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Keynote.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var privacy: some View {
        KTile {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Glow(symbol: "lock.fill", color: .white, size: 32)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    KLabel(text: "Private by design")
                    Text("No server. Keychain only.").font(.system(size: 13)).foregroundStyle(Keynote.muted)
                }
            }
        }
    }

    // The one action: a greeting that answers as you type.
    private var nameTile: some View {
        KTile(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)
                Text("Hi,\n\(greetingName).")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1)
                    .lineSpacing(-4)
                    .foregroundStyle(Keynote.spectrum)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Hi, \(greetingName)")
                Spacer(minLength: 0)
                TextField("Your name", text: $displayName,
                          prompt: Text(Self.suggestedName).foregroundStyle(Color.white.opacity(0.35)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Keynote.raised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(nameFocused ? 0.5 : 0.1)))
                    .focused($nameFocused)
                    .onSubmit(continueTapped)
                    .accessibilityLabel("Your name, shown in Dever's sidebar")
                Button(action: continueTapped) { Text("Continue").frame(maxWidth: .infinity) }
                    .buttonStyle(OnDarkPrimaryStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var greetingName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.suggestedName : trimmed
    }

    private func continueTapped() {
        displayName = greetingName
        next()
    }

    /// The first name from the Mac account, as a starting point.
    static var suggestedName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
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
