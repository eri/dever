import SwiftUI

// First run, after the "product performs" direction: every screen is a short headline and one
// control on the left; on the right, a crop of Dever's own window on a flat lime stage fills in
// as you answer. Your name appears in its sidebar, each tool you connect lights its column, and
// your first projects take their place in the list. Words are kept to a minimum; the "why" of
// each tool lives in its tooltip.

/// Where to go when onboarding ends.
enum OnboardingExit { case overview, newProject, importSlack, importLinear }

/// Soot and lime: black ground, one lime for actions and the stage behind the product.
private enum Soot {
    static let ground = Color(red: 0.059, green: 0.059, blue: 0.059)     // #0f0f0f
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.102)    // #1a1a1a
    static let ink = Color.white
    static let muted = Color(red: 0.56, green: 0.56, blue: 0.56)         // #8f8f8f
    static let lime = Color(red: 0.855, green: 0.98, blue: 0.612)        // #dafa9c
    static let limeInk = ground
    static let radius: CGFloat = 8
    static let margin: CGFloat = 40
}

struct OnboardingView: View {
    enum Stage: Int, CaseIterable { case name, connect, project }

    @EnvironmentObject var app: AppState
    @State var stage: Stage = .name
    let finish: (_ then: OnboardingExit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                HStack(spacing: 48) {
                    controls
                        .frame(width: geo.size.width * 5 / 12, alignment: .topLeading)
                    StageView(stage: stage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, Soot.margin)
            .padding(.bottom, Soot.margin)
        }
        .background(Soot.ground)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .showOnboardingStage)) { note in
            if let raw = note.object as? Int, let s = Stage(rawValue: raw) { stage = s }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                DeverMark().frame(width: 18, height: 18)
                Text("Dever").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
            }
            Spacer()
            Button("Skip") { finish(.overview) }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Soot.muted)
                .help("Go straight to Dever; set things up later in Accounts.")
        }
        .padding(.horizontal, Soot.margin)
        .frame(height: 56)
    }

    // MARK: Left column: headline, one control, progress

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Group {
                switch stage {
                case .name: NameControls(next: { stage = .connect })
                case .connect: ConnectControls(next: { stage = .project })
                case .project: ProjectControls(finish: finish)
                }
            }
            Spacer(minLength: 0)
            progress
        }
    }

    /// Order shown by position: three marks, the current one long.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Stage.allCases, id: \.self) { s in
                Button { if s.rawValue < stage.rawValue { stage = s } } label: {
                    Capsule()
                        .fill(s == stage ? Soot.ink : s.rawValue < stage.rawValue ? Soot.muted : Soot.surface)
                        .frame(width: s == stage ? 28 : 8, height: 8)
                }
                .buttonStyle(.plain)
                .disabled(s.rawValue >= stage.rawValue)
                .accessibilityLabel(["Name", "Connect", "First project"][s.rawValue])
                .accessibilityAddTraits(s == stage ? .isSelected : [])
            }
        }
    }
}

// MARK: - Shared controls

private struct Headline: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 44, weight: .semibold))
            .tracking(-1.5)
            .foregroundStyle(Soot.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct LimeButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Soot.limeInk)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Soot.lime.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3),
                        in: RoundedRectangle(cornerRadius: Soot.radius))
    }
}

private struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Soot.ink)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Soot.surface.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Soot.radius))
    }
}

// MARK: - Name

private struct NameControls: View {
    @AppStorage("displayName") private var displayName = ""
    @FocusState private var focused: Bool
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Headline(text: "What's your name?")
            TextField("Name", text: $displayName, prompt: Text("Your name").foregroundStyle(Soot.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Soot.ink)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(focused ? Soot.ink : Soot.muted.opacity(0.5)).frame(height: 1)
                }
                .frame(maxWidth: 360)
                .focused($focused)
                .onSubmit(go)
                .accessibilityLabel("Your name")
            Button("Continue", action: go)
                .buttonStyle(LimeButton())
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
            }
            focused = true
        }
    }

    private func go() {
        displayName = displayName.trimmingCharacters(in: .whitespaces)
        guard !displayName.isEmpty else { return }
        next()
    }
}

// MARK: - Connect

private struct ConnectControls: View {
    @EnvironmentObject var app: AppState
    let next: () -> Void
    @State private var githubSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Headline(text: "Connect your tools")
            VStack(spacing: 8) {
                ServiceRow(service: .slack, why: "Each project's channel and its latest messages.", githubSheet: $githubSheet)
                ServiceRow(service: .linear, why: "Each project's issues, to measure delivery.", githubSheet: $githubSheet)
                ServiceRow(service: .github, why: "Pull requests and pipeline. Optional.", githubSheet: $githubSheet)
            }
            .frame(maxWidth: 400)
            HStack(spacing: 16) {
                Button("Continue", action: next)
                    .buttonStyle(LimeButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.slack == nil || app.linear == nil)
                Label("Stays on this Mac", systemImage: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(Soot.muted)
                    .help("No Dever server: tokens stay in your Keychain, and Dever never posts on your behalf.")
            }
        }
        .sheet(isPresented: $githubSheet) { GitHubLoginSheet() }
    }
}

private struct ServiceRow: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    let why: String
    @Binding var githubSheet: Bool
    @State private var flow: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            BrandLogo(service: service, size: 20)
                .foregroundStyle(Soot.ink)
                .modifier(Breathing(active: flow != nil))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(service.label).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
            if service == .github {
                Text("Optional").font(.system(size: 13)).foregroundStyle(Soot.muted)
            }
            Spacer()
            if app.isConnected(service) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Soot.lime)
                    .font(.system(size: 18))
                    .accessibilityLabel("\(service.label) connected")
            } else if flow != nil {
                Button("Cancel") { flow?.cancel(); flow = nil }
                    .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Soot.muted)
            } else {
                Button("Connect", action: connect).buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.lime)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
        .overlay(alignment: .bottom) {
            // While the browser is open: a lime light sweeping along the row's bottom edge.
            if flow != nil { SweepLine().transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
        .accessibilityValue(flow != nil ? "Waiting for approval in your browser" : "")
        .overlay(alignment: .bottomLeading) {
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).offset(y: 18).lineLimit(1) }
        }
        .help(why)
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_CONNECTING=slack shows that row mid-connection.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_CONNECTING"] == service.rawValue {
                flow = Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
            }
        }
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

/// Indeterminate progress as light travelling along an edge, not a spinner.
/// Under Reduce Motion it is a still, half-lit line.
private struct SweepLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(LinearGradient(colors: [Soot.lime.opacity(0), Soot.lime, Soot.lime.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 0.35, height: 2)
                .offset(x: reduceMotion ? w * 0.325 : -w * 0.35 + phase * w * 1.35)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: phase)
        }
        .frame(height: 2)
        .onAppear { phase = 1 }
        .accessibilityHidden(true)
    }
}

/// A slow, small pulse on the logo of the service being connected.
private struct Breathing: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && up && !reduceMotion ? 1.12 : 1)
            .opacity(active && up ? 0.7 : 1)
            .animation(active ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: up)
            .onChange(of: active) { _, isActive in up = isActive }
    }
}

// MARK: - First project

private struct ProjectControls: View {
    @EnvironmentObject var app: AppState
    let finish: (OnboardingExit) -> Void
    @State private var notificationsOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Headline(text: "Add your projects")
            VStack(alignment: .leading, spacing: 8) {
                Button { finish(.importSlack) } label: { Label("Import from Slack", systemImage: ServiceKind.slack.symbol) }
                    .buttonStyle(LimeButton())
                    .disabled(app.slack == nil)
                    .help("Finds channels named with your project prefix and pairs each with its Linear project.")
                HStack(spacing: 8) {
                    Button { finish(.importLinear) } label: { Label("From Linear", systemImage: ServiceKind.linear.symbol) }
                        .buttonStyle(QuietButton())
                        .disabled(app.linear == nil)
                    Button { finish(.newProject) } label: { Label("New project", systemImage: "plus") }
                        .buttonStyle(QuietButton())
                }
            }
            Toggle(isOn: Binding(get: { notificationsOn }, set: { on in
                guard on else { return }
                Task {
                    _ = await Notifier.shared.requestAuthorization()
                    notificationsOn = await Notifier.shared.authorizationStatus() == .authorized
                }
            })) {
                Text("Alert me when a project needs me").font(.system(size: 14)).foregroundStyle(Soot.ink)
            }
            .toggleStyle(.switch)
            .tint(Soot.lime)
            .disabled(notificationsOn)
            .help("A failing pipeline, a missed target date, merged work whose ticket didn't move.")
        }
        .task { notificationsOn = await Notifier.shared.authorizationStatus() == .authorized }
    }
}

// MARK: - The stage: Dever's own window, filling in

private struct StageView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("displayName") private var displayName = ""
    let stage: OnboardingView.Stage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Soot.radius).fill(Soot.lime)
            GeometryReader { geo in
                // The crop is drawn at true size, then scaled to fill most of the stage's height.
                // Fit the height, and the width up to the GitHub column (the right edge may crop).
                let scale = max(0.7, min(1.5, (geo.size.height - 120) / 380, (geo.size.width - 56) / 640))
                DeverWindowCrop(name: displayName, stage: stage,
                                slack: app.slack != nil, linear: app.linear != nil, github: app.github != nil)
                    .scaleEffect(scale, anchor: .leading)
                    .frame(width: geo.size.width - 56, height: geo.size.height, alignment: .leading)
                    .offset(x: 56)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of Dever")
    }
}

/// A crop of the real interface (sidebar and project list), in Dever's own components,
/// running off the stage's right edge like a window seen through a frame.
private struct DeverWindowCrop: View {
    let name: String
    let stage: OnboardingView.Stage
    let slack: Bool
    let linear: Bool
    let github: Bool

    private struct Sample {
        let name: String
        let channel: String
        let status: ProjectStatus
        let delivery: Delivery
        let pipeline: ProjectSnapshot.PipelineState
        let messages: Int
    }

    private static func delivery(_ done: Int, _ merged: Int, _ review: Int, _ building: Int, _ todo: Int) -> Delivery {
        var issues: [(identifier: String, stateType: String, stateName: String)] = []
        func add(_ n: Int, _ type: String, _ name: String) {
            for _ in 0..<n { issues.append(("X-\(issues.count)", type, name)) }
        }
        add(done, "completed", "Done"); add(review, "started", "In Review")
        add(building, "started", "In Progress"); add(todo, "unstarted", "Todo")
        let mergedIDs = Set((0..<merged).map { "M-\($0)" })
        for id in mergedIDs { issues.append((id, "started", "In Progress")) }
        return Delivery(issues: issues, openPR: [], mergedPR: mergedIDs)
    }

    private let samples: [Sample] = [
        Sample(name: "Checkout redesign", channel: "#proj-checkout", status: .needsAttention,
               delivery: delivery(9, 1, 3, 2, 3), pipeline: .failing, messages: 42),
        Sample(name: "Mobile app", channel: "#proj-mobile", status: .onTrack,
               delivery: delivery(14, 0, 2, 3, 5), pipeline: .passing, messages: 18),
        Sample(name: "Billing v2", channel: "#proj-billing", status: .onTrack,
               delivery: delivery(4, 0, 1, 2, 9), pipeline: .passing, messages: 7),
    ]

    /// Projects show once the user reaches the last screen.
    private var showsProjects: Bool { stage == .project }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 180)
            Rectangle().fill(Theme.border).frame(width: 1)
            list.frame(width: 500)
        }
        .frame(height: 380)
        .background(Theme.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                DeverMark().frame(width: 16, height: 16)
                Text("Dever").font(Theme.bodyStrong).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 14)
            row(symbol: "square.grid.2x2", text: "Overview", selected: stage != .name)
            Text("Projects").font(Theme.small).foregroundStyle(Theme.muted).padding(.top, 14).padding(.leading, 8)
            if showsProjects {
                ForEach(samples, id: \.name) { s in
                    HStack(spacing: 8) {
                        Image(systemName: s.status.symbol).foregroundStyle(s.status.tint).imageScale(.small).frame(width: 14)
                        Text(s.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .transition(.opacity)
                }
            } else {
                ForEach(0..<3, id: \.self) { i in
                    Skeleton(width: [100, 76, 88][i], height: 10).padding(.horizontal, 8).frame(height: 28)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(String((name.isEmpty ? "?" : name).prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.chart1)
                    .frame(width: 22, height: 22)
                    .background(Theme.chart1.opacity(0.15), in: Circle())
                Text(name.isEmpty ? "Your name" : name)
                    .font(Theme.body).foregroundStyle(name.isEmpty ? Theme.muted : Theme.text).lineLimit(1)
            }
            .padding(.horizontal, 8).frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stage == .name ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stage == .name ? Soot.lime : .clear, lineWidth: 1.5))
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.frame)
    }

    private func row(symbol: String, text: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.muted).frame(width: 14)
            Text(text).font(Theme.body).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 8).frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Overview").font(Theme.section).foregroundStyle(Theme.text).padding(.bottom, 14)
            HStack(spacing: 16) {
                Text("Project").foregroundStyle(Theme.muted).frame(width: 130, alignment: .leading)
                header("Slack", lit: slack, width: 50)
                header("Linear", lit: linear, width: 140)
                header("GitHub", lit: github, width: 80)
            }
            .font(Theme.small)
            .frame(height: 28)
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                Rectangle().fill(Theme.rule).frame(height: 1)
                projectRow(s)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func header(_ text: String, lit: Bool, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(text)
            if lit { Circle().fill(Theme.positive).frame(width: 5, height: 5) }
        }
        .foregroundStyle(lit ? Theme.text : Theme.muted)
        .frame(width: width, alignment: .leading)
    }

    private func projectRow(_ s: Sample) -> some View {
        HStack(spacing: 16) {
            Group {
                if showsProjects {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.name).font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                        Text(s.channel).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) { Skeleton(width: 110, height: 10); Skeleton(width: 70, height: 8) }
                }
            }
            .frame(width: 130, alignment: .leading)
            cell(lit: slack, width: 50) {
                Text("\(s.messages)").font(Theme.body).foregroundStyle(Theme.text).monospacedDigit()
            }
            cell(lit: linear, width: 140) {
                VStack(alignment: .leading, spacing: 4) {
                    DeliveryStrip(delivery: s.delivery, height: 6)
                    Text("\(s.delivery.shipped)/\(s.delivery.total) shipped").font(Theme.small).foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
            }
            cell(lit: github, width: 80) { PipelineBadge(state: s.pipeline).font(Theme.small) }
        }
        .frame(height: 58)
    }

    /// A column shows its data once its tool is connected (from the connect screen on), a skeleton before.
    @ViewBuilder
    private func cell<C: View>(lit: Bool, width: CGFloat, @ViewBuilder content: () -> C) -> some View {
        Group {
            if lit && stage != .name { content() } else { Skeleton(width: width * 0.6, height: 10) }
        }
        .frame(width: width, alignment: .leading)
    }
}

extension Notification.Name {
    /// Switches onboarding to a stage; `object` is the stage's raw value (snapshots).
    static let showOnboardingStage = Notification.Name("dever.showOnboardingStage")
}
