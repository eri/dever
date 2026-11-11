import SwiftUI

/// The project's preview environment: the pull request it follows, what the preview is doing,
/// the hosts that are up, and the commands the team's workflows understand, posted from here.
struct PreviewPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var store = PreviewStore.shared
    let project: Project
    /// Tools missing on the page: more than one means the invitation lives in its own section.
    let missing: [ServiceKind]
    @ObservedObject var flow: ConnectFlow
    /// Opens the editor on its Preview step.
    let addPreview: () -> Void
    /// "No preview needed": hides the panel until a pull request is picked in the editor.
    let dismiss: () -> Void

    @State private var options = PreviewOptions()
    @State private var optionsOpen = false
    @State private var confirmingDelete = false
    @State private var confirmingProtect = false
    @State private var sending = false
    @State private var actionError: String?
    @State private var copied = false

    private var state: PreviewState? { store.state(for: project) }
    private var status: PreviewStatus? { state?.status }

    /// GitHub answered with an error: the header stays, the failure row says what and offers a retry.
    private var failure: ServiceState? {
        if case .failed(let serviceState) = state { return serviceState }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let status, project.previewPullNumber != nil, app.github != nil, failure == nil {
                // One line: what the preview is on the left, what to open or do on the right.
                // Too narrow for one line, the right part drops under the header.
                ViewThatFits(in: .horizontal) {
                    header { HStack(spacing: 4) { lineContent(status); menu(status) } }
                    VStack(alignment: .leading, spacing: 12) {
                        header { menu(status) }
                        lineContent(status)
                    }
                }
                // The flags unfold under the line (200 ms), and fold back.
                if optionsOpen { optionsRow.transition(Motion.rise) }
                if let note = status.note { noteRow(note, failed: status.phase == .failed) }
                if let actionError { ErrorLabel(actionError).transition(Motion.rise) }
            } else {
                header {
                    if project.previewPullNumber == nil {
                        noneActions
                    } else if app.github != nil, failure == nil {
                        skeleton.transition(.opacity)
                    }
                }
                if project.previewPullNumber == nil {
                    // The invitation is the header's own line: nothing under it.
                } else if app.github == nil {
                    if missing.count > 1 {
                        ConnectPlaceholder(service: .github, widths: [300, 180, 240])
                    } else {
                        ConnectPanelBody(service: .github, project: project, flow: flow)
                    }
                } else if let failure {
                    ServiceFailureRow(service: .github, state: failure, lastLoaded: store.loadedAt[project.id],
                                      retry: { Task { await store.load(project, app: app, force: true) } }, flow: flow)
                }
            }
        }
        .motion(Motion.ui, value: optionsOpen)
        .motion(Motion.ui, fade: true, value: status == nil)
        .motion(Motion.ui, value: actionError)
        // The invitation hands over to the preview when a pull request is picked.
        .motion(Motion.ui, fade: true, value: project.previewPullNumber == nil)
        .sootPanel()
        .task(id: "\(project.id)-\(project.previewPullNumber ?? 0)-\(app.github != nil)") {
            await store.load(project, app: app)
            if let o = status?.options { options = o }
            // Snapshots: DEVER_SNAPSHOT_PREVIEW_OPTIONS=1 shows the deploy options open.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_PREVIEW_OPTIONS"] == "1" { optionsOpen = true }
        }
        .confirmationDialog("Delete the preview of #\(project.previewPullNumber ?? 0)?", isPresented: $confirmingDelete) {
            Button("Delete preview", role: .destructive) { Task { await send { try await store.delete(project, app: app) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Posts /delete-preview on the pull request. The hosts go down within a few minutes; a new /preview brings them back.")
        }
        .confirmationDialog("Protect the preview from the Saturday cleanup?", isPresented: $confirmingProtect) {
            Button("Protect and redeploy") {
                var o = options; o.keep = true; options = o
                Task { await send { try await store.deploy(project, app: app, options: o) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Posts /preview --keep, which redeploys (about ten minutes) and labels the pull request preview:keep. The only ways back are deleting the preview or closing the pull request.")
        }
    }

    /// The panel's head: the globe, "Preview", the pull request's number (a link), the phase as
    /// glyph and word with its age; `trailing` is what the phase offers. The pull request's
    /// title, the run and the protection live in the tooltip and under More.
    private func header<T: View>(@ViewBuilder trailing: @escaping () -> T) -> some View {
        let s = status
        return PanelHeader(symbol: "globe", title: "Preview",
                           subtitle: project.previewPullNumber == nil ? "Follow a pull request's preview here" : nil, accessory: {
            if let number = project.previewPullNumber {
                HoverLink(destination: s?.pull.url ?? URL(string: "https://github.com/\(app.previewRepository(for: project) ?? "")/pull/\(number)")!) {
                    HStack(spacing: 6) {
                        IDPill(text: "#\(number)")
                        // Merged or closed changes what can be done; open and draft do not.
                        if let state = s?.pull.state, state == .merged || state == .closed {
                            Text(state.word).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                        }
                    }
                }
                .help(s.map { "#\($0.pull.number) \($0.pull.title) · \($0.pull.state.word) · by \($0.pull.author) · Opens on GitHub" } ?? "Opens the pull request on GitHub")
                .accessibilityLabel(s.map { "Pull request #\($0.pull.number), \($0.pull.title), \($0.pull.state.word)" } ?? "Pull request #\(number)")
                .accessibilityHint("Opens on GitHub")
            }
            if let s {
                HStack(spacing: 6) {
                    PreviewPhaseGlyph(phase: s.phase, health: s.health, size: 13)
                    Text(s.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .contentTransition(.opacity).motion(Motion.ui, fade: true, value: s.word)
                    if let at = s.updatedAt {
                        Text(verbatim: "·").foregroundStyle(Soot.muted).accessibilityHidden(true)
                        Text(at.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                            .help("\(s.phase.busy ? "Started" : "Last change") \(at.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .fixedSize()
            }
        }, trailing: trailing)
    }

    // MARK: No preview

    /// No pull request yet: the header says what the block is for, and holds the lime way to
    /// add one and the quiet way to say none is wanted.
    private var noneActions: some View {
        HStack(spacing: 8) {
            Button("Add a preview", action: addPreview).buttonStyle(PrimaryButton())
                .help("Choose the pull request whose preview this project follows")
            Button("No preview needed", action: dismiss).buttonStyle(TertiaryButton(tint: .muted))
                .help("Hides this panel; pick a pull request later in Edit project to bring it back")
        }
        .fixedSize()
    }

    /// What the phase offers, at the right of the line: the products to open when live, the
    /// step when a run is going, the one lime action when there is nothing deployed.
    @ViewBuilder
    private func lineContent(_ s: PreviewStatus) -> some View {
        if sending {
            Text("Sending…").font(.system(size: 13)).foregroundStyle(Soot.muted)
        } else if s.phase.busy {
            progress(s)
        } else if s.pull.state == .merged || s.pull.state == .closed {
            // A closed pull request takes no command: say so instead of greying a button.
            Text("The pull request is \(s.pull.state.word.lowercased()). Change it from More.")
                .font(.system(size: 13)).foregroundStyle(Soot.muted)
        } else if s.phase == .live {
            // The products the workflow deployed, as plain links: a mark only when one is down.
            HStack(spacing: 2) {
                ForEach(PreviewProduct.allCases.filter { $0.isPresent(in: s) }) { product in
                    ProductLink(product: product, status: s)
                }
            }
        } else {
            // One click posts the plain command; the flags wait under More.
            Button("Deploy preview") {
                Task { await send { try await store.deploy(project, app: app, options: options) } }
            }
            .buttonStyle(PrimaryButton())
            .help("Posts \(options.command) on the pull request; about ten minutes")
        }
    }

    /// A deploy takes about ten minutes: the step the run is on, and before it a short track
    /// with a light travelling inside it (clipped to the track): "still going", with no
    /// spinner and no percentage the workflow cannot give.
    private func progress(_ s: PreviewStatus) -> some View {
        HStack(spacing: 10) {
            Text(s.run?.step ?? (s.run == nil ? "Waiting for the workflow to start…" : "Running…"))
                .font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
            WaitingLine()
                .frame(width: 64)
                .background(Soot.edge.opacity(0.5))
                .clipShape(Capsule())
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.phase.word). \(s.run?.step ?? "Waiting for the workflow")")
    }

    private func noteRow(_ note: String, failed: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: failed ? "exclamationmark.circle.fill" : "info.circle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(failed ? Theme.negative : Soot.muted)
                .padding(.top, 1).accessibilityHidden(true)
            Text(note).font(.system(size: 13)).foregroundStyle(Soot.muted).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    /// Everything that is not the phase's one action: redeploy, protect, delete, the links.
    private func menu(_ s: PreviewStatus) -> some View {
        let canCommand = s.pull.state == .open || s.pull.state == .draft
        return Menu {
                if !s.phase.busy, canCommand, s.phase != .live {
                    Button("Deploy with options…") { optionsOpen = true }
                }
                if s.phase == .live, canCommand {
                    Button("Redeploy with the latest commits") { Task { await send { try await store.deploy(project, app: app, options: options) } } }
                        .disabled(sending)
                    if let appURL = s.appURL { Button("Copy app URL") { copyAppURL(s, appURL) } }
                    if s.keep {
                        Button("Protected from the Saturday cleanup") {}.disabled(true)
                    } else {
                        Button("Protect from the Saturday cleanup…") { confirmingProtect = true }
                    }
                }
                if s.phase == .live || s.phase == .failed || s.phase == .updating {
                    Button("Delete preview…", role: .destructive) { confirmingDelete = true }
                }
                Divider()
                Link("Open pull request", destination: s.pull.url)
                if let run = s.run { Link("Open workflow run", destination: run.url) }
                Divider()
                Button("Change pull request…", action: addPreview)
                Button("Refresh") { Task { await store.load(project, app: app, force: true) } }
            } label: {
                Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.button)
            .buttonStyle(MenuTriggerButton(edge: false))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More: redeploy, protect, delete, open on GitHub, change the pull request")
            .accessibilityLabel("More preview actions")
    }

    /// The `/preview` flags, one row, then the command itself before it is sent.
    private var optionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                PodsStepper(label: "API pods", value: $options.apiPods)
                PodsStepper(label: "App pods", value: $options.appPods)
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                OptionSwitch(title: "Prod dependencies", detail: "A canary on production data", isOn: $options.prod)
                OptionSwitch(title: "Autoscale", detail: nil, isOn: $options.autoscale)
                OptionSwitch(title: "Keep", detail: "Skip the Saturday cleanup", isOn: $options.keep)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(sending ? "Sending…" : "Deploy") { Task { await send { try await store.deploy(project, app: app, options: options) }; optionsOpen = false } }
                    .buttonStyle(PrimaryButton()).disabled(sending)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { optionsOpen = false }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Text(verbatim: options.command).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Soot.muted).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel("Comment to post: \(options.command)")
            }
        }
        .padding(16)
        .background(Soot.ground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deploy options")
    }

    private func send(_ body: @escaping () async throws -> Void) async {
        sending = true
        actionError = nil
        defer { sending = false }
        do { try await body() } catch { actionError = error.localizedDescription }
    }

    private func copyAppURL(_ s: PreviewStatus, _ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); copied = false }
    }

    private var skeleton: some View {
        Skeleton(width: 220, height: 20, radius: 6)
            .accessibilityElement()
            .accessibilityLabel("Loading the preview")
    }
}

/// The phase as a shape and a colour together, so neither carries the meaning alone.
struct PreviewPhaseGlyph: View {
    let phase: PreviewStatus.Phase
    /// What the probes found: a live preview with a host down is not drawn as live.
    var health: PreviewStatus.Health = .up
    var size: CGFloat = 14
    var body: some View {
        let (symbol, tint): (String, Color) = switch phase {
        case .live where health == .partlyDown: ("exclamationmark.triangle.fill", Theme.chart3)
        case .live where health == .down: ("xmark.circle.fill", Theme.negative)
        case .live: ("checkmark.circle.fill", Theme.positive)
        case .deploying, .updating: ("clock.fill", Theme.chart2)
        case .deleting: ("clock.fill", Soot.muted)
        case .failed: ("xmark.circle.fill", Theme.negative)
        case .deleted: ("circle.dashed", Soot.muted)
        case .notDeployed: ("circle.dotted", Soot.muted)
        }
        Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(tint)
            .accessibilityLabel("Preview \((phase == .live && health == .partlyDown ? "partly down" : phase == .live && health == .down ? "down" : phase.word.lowercased()))")
    }
}

/// A product of the preview: its front and the API behind it, deployed as separate hosts.
enum PreviewProduct: String, CaseIterable, Identifiable {
    case app, backOffice, clientHub
    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: "App"
        case .backOffice: "Back office"
        case .clientHub: "Client Hub"
        }
    }

    var front: PreviewTarget {
        switch self {
        case .app: .app
        case .backOffice: .bo
        case .clientHub: .clienthub
        }
    }

    var api: PreviewTarget {
        switch self {
        case .app: .api
        case .backOffice: .boapi
        case .clientHub: .clienthubAPI
        }
    }

    func isPresent(in s: PreviewStatus) -> Bool { s.targets[front] != nil || s.targets[api] != nil }
}

/// One product as a link: a click opens its front. Nothing but the name when it answers
/// (the phase already says "Live"); a mark and a word when the front or its API does not.
private struct ProductLink: View {
    let product: PreviewProduct
    let status: PreviewStatus

    private var frontUp: Bool? { status.targets[product.front] ?? nil }
    private var apiUp: Bool? { status.targets[product.api] ?? nil }
    private var url: URL {
        PreviewTarget.url(status.targets[product.front] != nil ? product.front : product.api, pull: status.pull.number)
    }

    /// Shape and word together: a cross for the front, a warning for the API only.
    private var problem: (symbol: String, tint: Color, word: String)? {
        if frontUp == false { return ("xmark.circle.fill", Theme.negative, "down") }
        if apiUp == false { return ("exclamationmark.triangle.fill", Theme.chart3, "API down") }
        return nil
    }

    var body: some View {
        let problem = problem
        ExternalLink(destination: url, tint: .ink, lift: Soot.ground) {
            HStack(spacing: 5) {
                if let problem { Image(systemName: problem.symbol).foregroundStyle(problem.tint).accessibilityHidden(true) }
                Text(product.label)
                if let problem { Text(problem.word).fontWeight(.regular).foregroundStyle(Soot.muted) }
            }
        }
        .help(detail)
        .accessibilityLabel("\(product.label), \(problem?.word ?? (frontUp == nil && apiUp == nil ? "checking" : "up"))")
        .accessibilityHint("Opens in the browser")
    }

    private var detail: String {
        func line(_ t: PreviewTarget, _ up: Bool?) -> String? {
            guard status.targets[t] != nil else { return nil }
            return "\(t.label): \(up == true ? "up" : up == false ? "not answering" : "checking") · \(PreviewTarget.url(t, pull: status.pull.number).host ?? "")"
        }
        return [line(product.front, frontUp), line(product.api, apiUp)].compactMap { $0 }.joined(separator: "\n")
    }
}

/// A count or "default": the workflow's own default when nothing is given.
private struct PodsStepper: View {
    let label: String
    @Binding var value: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
            HStack(spacing: 0) {
                stepButton("minus", enabled: value != nil) { if let v = value { value = v > 1 ? v - 1 : nil } }
                Text(value.map(String.init) ?? "auto").font(.system(size: 13, weight: .medium)).foregroundStyle(value == nil ? Soot.muted : Soot.ink)
                    .monospacedDigit().frame(width: 40)
                stepButton("plus", enabled: (value ?? 0) < 30) { value = min(30, (value ?? 0) + 1) }
            }
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\($0)" } ?? "Workflow default")
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(IconButton(fill: nil, radius: Soot.radius))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "More \(label.lowercased())" : "Fewer \(label.lowercased())")
    }
}

/// A flag of the command as a switch with its word; the detail is a tooltip, not a line.
private struct OptionSwitch: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .handCursor()
        .help(detail ?? title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail ?? "")
    }
}
