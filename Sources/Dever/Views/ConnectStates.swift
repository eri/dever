import SwiftUI

// A tool that isn't connected is an invitation; a tool that fails is an error. These are
// the two faces, shared by the project page, the overview and Settings.

/// Runs a service's OAuth flow from wherever the user is. One flow at a time per page;
/// GitHub goes through its code sheet, which the owner presents from `githubSheet`.
@MainActor
final class ConnectFlow: ObservableObject {
    @Published private(set) var running: ServiceKind?
    @Published var error: (service: ServiceKind, message: String)?
    @Published var githubSheet = false
    private var task: Task<Void, Never>?

    func start(_ service: ServiceKind, app: AppState) {
        error = nil
        if service == .github { githubSheet = true; return }
        task?.cancel()
        running = service
        task = Task {
            do {
                switch service {
                case .slack: app.slack = try await SlackAuth.connect()
                case .linear: app.linear = try await LinearAuth.connect()
                case .github: break
                }
            } catch is CancellationError {
            } catch {
                self.error = (service, error.localizedDescription)
            }
            running = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = nil
    }

    /// Snapshots: `DEVER_SNAPSHOT_CONNECTING=slack` shows that tool mid-connection.
    func simulateIfAsked() {
        guard running == nil, let name = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_CONNECTING"],
              let service = ServiceKind(rawValue: name) else { return }
        running = service
        task = Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
    }
}

/// What connecting a tool gives the user for this project, in one line.
enum ConnectPitch {
    static func line(_ service: ServiceKind, for project: Project) -> String {
        switch service {
        case .slack: project.slack.map { "Read and reply in #\($0.name) here" } ?? "Read the project's channel here"
        case .linear: project.linear.map { "Track issues and delivery for \($0.name)" } ?? "Track issues and delivery"
        case .github: project.githubRepos.first.map { "Follow pull requests on \($0)" } ?? "Follow pull requests"
        }
    }

    /// What a panel shows once its tool is connected ("…to see its issues").
    static func noun(_ service: ServiceKind) -> String {
        switch service {
        case .slack: "the conversation"
        case .linear: "issues and delivery"
        case .github: "pull requests"
        }
    }
}

// MARK: - Not connected

/// One section for the page when more than one tool is missing: the logos, one line each,
/// one button each, and the count as they connect.
struct ConnectSection: View {
    @EnvironmentObject var app: AppState
    let project: Project
    /// The tools this project links, connected or not, so the count reads "1 of 3".
    let services: [ServiceKind]
    @ObservedObject var flow: ConnectFlow

    private var connected: Int { services.filter(app.isConnected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your tools").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soot.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Each one fills its panel below as soon as it is connected. Tokens stay in your Keychain.")
                        .font(.system(size: 12)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Text("\(connected) of \(services.count) connected")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.muted).monospacedDigit()
                    .accessibilityLabel("\(connected) of \(services.count) tools connected")
            }
            VStack(spacing: 6) {
                ForEach(services) { service in
                    ConnectRow(service: service, why: ConnectPitch.line(service, for: project), flow: flow)
                }
            }
        }
        .sootPanel()
        .accessibilityElement(children: .contain)
        .onAppear { flow.simulateIfAsked() }
    }
}

/// A tool as a row: its logo, its name, what it brings here, and the one thing to do.
struct ConnectRow: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    let why: String
    @ObservedObject var flow: ConnectFlow

    private var running: Bool { flow.running == service }
    private var connected: Bool { app.isConnected(service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                BrandLogo(service: service, size: 22)
                    .foregroundStyle(Soot.ink)
                    .modifier(Breathing(active: running))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.label).font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)
                    Text(why).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1).help(why)
                }
                Spacer(minLength: 16)
                ConnectControl(service: service, flow: flow, verb: "Connect")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Soot.ground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) { if running { WaitingLine().transition(.opacity) } }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .motion(Motion.ui, fade: true, value: running)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(service.label): \(connected ? "connected" : why)")
            .accessibilityValue(running ? "Waiting for approval in your browser" : "")
            if let error = flow.error, error.service == service {
                ErrorLabel(error.message).padding(.leading, 4)
            }
        }
    }
}

/// The trailing control of a connect row or a failure row: Connect / Reconnect, then
/// "Approve in your browser…" with Cancel, then a check once the token is in.
struct ConnectControl: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    @ObservedObject var flow: ConnectFlow
    /// "Connect" for a missing tool, "Reconnect" for a rejected token.
    var verb = "Connect"

    var body: some View {
        if app.isConnected(service) && !app.expired.contains(service) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Soot.lime)
                Text("Connected").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
            }
            .accessibilityElement(children: .combine)
        } else if flow.running == service {
            HStack(spacing: 12) {
                Text("Approve in your browser…").font(.system(size: 13)).foregroundStyle(Soot.muted)
                Button("Cancel") { flow.cancel() }.buttonStyle(SecondaryButton())
            }
        } else {
            Button("\(verb) \(service.label)") { flow.start(service, app: app) }
                .buttonStyle(PrimaryButton())
                .help(service == .github ? "Sign in with a code on github.com" : "Approve Dever in your browser")
        }
    }
}

/// A panel body while its tool is still missing and the invitation lives elsewhere on the
/// page: quiet bars at the panel's usual shape, and one line saying what fills it.
struct ConnectPlaceholder: View {
    let service: ServiceKind
    /// Bar widths, one per line, so the placeholder keeps the panel's silhouette.
    var widths: [CGFloat] = [260, 200, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                RoundedRectangle(cornerRadius: 3).fill(Theme.empty).frame(width: width, height: 12).opacity(0.6)
            }
            Text("Connect \(service.label) above to see \(ConnectPitch.noun(service)).")
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connect \(service.label) above to see \(ConnectPitch.noun(service))")
    }
}

/// The in-panel invitation when just one tool is missing: logo, one line, one button, in the
/// same tile as the page's other empty states (`PanelEmpty`).
struct ConnectPanelBody: View {
    let service: ServiceKind
    let project: Project
    @ObservedObject var flow: ConnectFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { logoAndLine; Spacer(minLength: 16); ConnectControl(service: service, flow: flow) }
                VStack(alignment: .leading, spacing: 14) { logoAndLine; ConnectControl(service: service, flow: flow) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { if flow.running == service { WaitingLine().transition(.opacity) } }
            .clipped()
            .motion(Motion.ui, fade: true, value: flow.running == service)
            if let error = flow.error, error.service == service { ErrorLabel(error.message) }
        }
    }

    private var logoAndLine: some View {
        // The line alone: the panel's header already carries the logo (see `PanelEmpty`).
        Text(ConnectPitch.line(service, for: project)).font(.system(size: 13)).foregroundStyle(Soot.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// On the overview: a quiet chip in the column whose tool is not connected.
struct ConnectChip: View {
    let service: ServiceKind
    var verb = "Connect"
    var body: some View {
        HStack(spacing: 5) {
            BrandLogo(service: service, size: 11).foregroundStyle(Theme.muted)
            Text("\(verb) \(service.label)")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .overlay(Capsule().strokeBorder(Theme.muted.opacity(0.7)))
        .lineLimit(1)
        .fixedSize()
        .help("\(verb) \(service.label) from the project page")
    }
}

// MARK: - Failed

/// A load that failed, inside the panel that failed: what happened, since when the data is
/// stale, and the one action that fixes it. The negative colour is on the icon only.
struct ServiceFailureRow: View {
    @EnvironmentObject var app: AppState
    let service: ServiceKind
    let state: ServiceState
    var lastLoaded: Date?
    var retry: (() -> Void)?
    @ObservedObject var flow: ConnectFlow
    /// A second panel of the same tool: the title and where the action is, nothing else.
    var compact = false

    private var title: String {
        switch state {
        case .unauthorized: "\(service.label) needs reconnecting"
        case .offline: "You're offline"
        case .failed: "Couldn't reach \(service.label)"
        case .notConnected: "\(service.label) is not connected"
        }
    }

    private var detail: String? {
        switch state {
        case .unauthorized: "Its session expired or was revoked. Reconnecting takes one approval in your browser."
        case .offline: "\(service.label) data comes back when the connection does."
        case .failed(let message): message
        case .notConnected: nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state == .offline ? "wifi.slash" : "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(state == .offline ? Soot.muted : Theme.negative)
                .frame(width: 18, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                    if compact {
                        Text(state == .unauthorized ? "Reconnect from the Delivery panel above." : "Retry from the Delivery panel above.")
                            .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    } else if let detail {
                        Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let lastLoaded, !compact {
                        Text("Last loaded \(lastLoaded.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                }
                HStack(spacing: 10) {
                    if compact {
                        EmptyView()
                    } else if state == .unauthorized {
                        ConnectControl(service: service, flow: flow, verb: "Reconnect")
                    } else if let retry {
                        Button("Retry", action: retry).buttonStyle(SecondaryButton())
                    }
                }
                if let error = flow.error, error.service == service { ErrorLabel(error.message) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(detail ?? "")")
    }
}
