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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headline
            if project.previewPullNumber == nil {
                nonePart
            } else if app.github == nil {
                if missing.count > 1 {
                    ConnectPlaceholder(service: .github, widths: [300, 180, 240])
                } else {
                    ConnectPanelBody(service: .github, project: project, flow: flow)
                }
            } else if case .failed(let serviceState) = state {
                ServiceFailureRow(service: .github, state: serviceState, lastLoaded: store.loadedAt[project.id],
                                  retry: { Task { await store.load(project, app: app, force: true) } }, flow: flow)
            } else if let status {
                // Options unfold in place of the second line (200 ms), and fold back.
                if optionsOpen {
                    optionsRow.transition(Motion.rise)
                } else {
                    // Second line: what there is to see or know on the left, what to do on the right.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            secondLine(status)
                            Spacer(minLength: 0)
                            actions(status)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            secondLine(status)
                            actions(status)
                        }
                    }
                }
                if let actionError { ErrorLabel(actionError).transition(Motion.rise) }
            } else {
                skeleton.transition(.opacity)
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

    /// The panel's head: the globe, "Preview", the pull request's number as a pill (a link),
    /// one quiet line (the pull request's title), and on the right the phase as glyph and word
    /// and when it changed. The run, the protection and the rest live under More.
    private var headline: some View {
        let s = status
        return PanelHeader(symbol: "globe", title: "Preview", subtitle: subtitle, accessory: {
            if let number = project.previewPullNumber {
                HoverLink(destination: s?.pull.url ?? URL(string: "https://github.com/\(app.previewRepository(for: project) ?? "")/pull/\(number)")!) {
                    HStack(spacing: 6) {
                        IDPill(text: "#\(number)")
                        if let state = s?.pull.state, state != .open {
                            Text(state.word).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                        }
                    }
                }
                .help(s.map { "#\($0.pull.number) \($0.pull.title) · \($0.pull.state.word) · by \($0.pull.author) · Opens on GitHub" } ?? "Opens the pull request on GitHub")
                .accessibilityLabel(s.map { "Pull request #\($0.pull.number), \($0.pull.title), \($0.pull.state.word)" } ?? "Pull request #\(number)")
                .accessibilityHint("Opens on GitHub")
            }
        }, trailing: {
            if let s {
                HStack(spacing: 6) {
                    PreviewPhaseGlyph(phase: s.phase, size: 13)
                    Text(s.phase.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                        .contentTransition(.opacity).motion(Motion.ui, fade: true, value: s.phase)
                    if let at = s.updatedAt {
                        Text(verbatim: "·").foregroundStyle(Soot.muted).accessibilityHidden(true)
                        Text(timeLine(s.phase, at)).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
            }
        })
    }

    /// The quiet line under the title: the pull request followed, or what the block is for.
    private var subtitle: String {
        if project.previewPullNumber == nil { return "A pull request's environment, from here" }
        if let s = status { return PullTitle.split(s.pull.title).title }
        return app.previewRepository(for: project).map(GitHubRepository.short) ?? "Pull request"
    }

    // MARK: No preview

    /// No pull request yet: one line, the lime way to add one, the quiet way to say none is wanted.
    private var nonePart: some View {
        PanelEmpty(service: .github, line: "Follow a pull request's preview here",
                   primary: ("Add a preview", addPreview),
                   quiet: ("No preview needed", dismiss),
                   primaryHelp: "Choose the pull request whose preview this project follows",
                   quietHelp: "Hides this panel; pick a pull request later in Edit project to bring it back")
    }

    @ViewBuilder
    private func secondLine(_ s: PreviewStatus) -> some View {
        if s.phase == .live { targetChips(s) }
        if s.phase.busy { progress(s) }
        if let note = s.note { noteRow(note, failed: s.phase == .failed) }
    }

    private func timeLine(_ phase: PreviewStatus.Phase, _ at: Date) -> String {
        let when = at.formatted(.relative(presentation: .named))
        switch phase {
        case .deploying, .updating, .deleting: return "since \(when)"
        case .live, .failed, .deleted, .notDeployed: return "updated \(when)"
        }
    }

    /// A deploy takes about ten minutes: a travelling line, and the step the run is on.
    /// The step the run is on, with a short travelling light beside it: the light belongs to
    /// the step, not to the panel, and says "still going" without a spinner or a percentage.
    private func progress(_ s: PreviewStatus) -> some View {
        HStack(spacing: 10) {
            WaitingLine().frame(width: 72)
            Text(s.run?.step ?? (s.run == nil ? "Waiting for the workflow to start…" : "Running…"))
                .font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.phase.word). \(s.run?.step ?? "Waiting for the workflow")")
    }

    /// The products the workflow deployed, one chip each: the chip opens the product and its
    /// glyph says whether the product and its API answer.
    private func targetChips(_ s: PreviewStatus) -> some View {
        FlowRow(spacing: 6) {
            ForEach(PreviewProduct.allCases.filter { $0.isPresent(in: s) }) { product in
                ProductChip(product: product, status: s)
            }
        }
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

    /// One lime action for the phase, the rest quiet or behind "More".
    @ViewBuilder
    private func actions(_ s: PreviewStatus) -> some View {
        let canCommand = s.pull.state == .open || s.pull.state == .draft
        HStack(spacing: 8) {
            if !canCommand, !s.phase.busy {
                // A closed pull request takes no command: say so instead of greying a button.
                Text("The pull request is \(s.pull.state.word.lowercased()): nothing to deploy. Pick another one from More.")
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
            } else {
                switch s.phase {
                case .notDeployed, .deleted, .failed:
                    // One click posts the plain command; the flags wait under More.
                    Button(sending ? "Sending…" : "Deploy preview") {
                        Task { await send { try await store.deploy(project, app: app, options: options) } }
                    }
                    .buttonStyle(LimeButton()).disabled(sending)
                    .help("Posts \(options.command) on the pull request; about ten minutes")
                case .live, .deploying, .updating, .deleting:
                    // The preview is there or on its way: nothing presses for attention.
                    if sending { Text("Sending…").font(.system(size: 13)).foregroundStyle(Soot.muted) }
                }
            }
            Menu {
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
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Soot.ink)
                    .frame(width: 20, height: 36)
            }
            .menuStyle(.button)
            .buttonStyle(QuietButton())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More: redeploy, protect, delete, open on GitHub, change the pull request")
            .accessibilityLabel("More preview actions")
        }
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
                    .buttonStyle(LimeButton()).disabled(sending)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { optionsOpen = false }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
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
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in Skeleton(width: 92, height: 30, radius: 15) }
            Spacer()
            Skeleton(width: 120, height: 36, radius: Soot.radius)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading the preview")
    }
}

/// The phase as a shape and a colour together, so neither carries the meaning alone.
struct PreviewPhaseGlyph: View {
    let phase: PreviewStatus.Phase
    var size: CGFloat = 14
    var body: some View {
        let (symbol, tint): (String, Color) = switch phase {
        case .live: ("checkmark.circle.fill", Theme.positive)
        case .deploying, .updating: ("clock.fill", Theme.chart2)
        case .deleting: ("clock.fill", Soot.muted)
        case .failed: ("xmark.circle.fill", Theme.negative)
        case .deleted: ("circle.dashed", Soot.muted)
        case .notDeployed: ("circle.dotted", Soot.muted)
        }
        Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(tint)
            .accessibilityLabel("Preview \(phase.word.lowercased())")
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

/// One product as a chip: a click opens its front; the glyph folds in the API's health.
private struct ProductChip: View {
    let product: PreviewProduct
    let status: PreviewStatus
    @State private var hovering = false

    private var frontUp: Bool? { status.targets[product.front] ?? nil }
    private var apiUp: Bool? { status.targets[product.api] ?? nil }
    private var url: URL {
        PreviewTarget.url(status.targets[product.front] != nil ? product.front : product.api, pull: status.pull.number)
    }

    /// Shape and word together: a check, a cross for the front, a warning for the API only.
    private var mark: (symbol: String, tint: Color, word: String) {
        if frontUp == false { return ("xmark.circle.fill", Theme.negative, "down") }
        if apiUp == false { return ("exclamationmark.triangle.fill", Theme.chart3, "API down") }
        if frontUp == nil && apiUp == nil { return ("circle.dotted", Soot.muted, "checking") }
        return ("checkmark.circle.fill", Theme.positive, "up")
    }

    var body: some View {
        let mark = mark
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: mark.symbol).foregroundStyle(mark.tint)
                Text(product.label).foregroundStyle(Soot.ink)
                if mark.word.hasSuffix("down") { Text(mark.word).foregroundStyle(Soot.muted) }
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering ? Soot.ground : Soot.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Soot.edge))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .handCursor()
        .modifier(FocusOutline(radius: 15))
        .onHover { hovering = $0 }
        .help(detail)
        .accessibilityLabel("\(product.label), \(mark.word)")
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
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(enabled ? Soot.ink : Soot.muted)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .modifier(FocusOutline(radius: Soot.radius))
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
        .help(detail ?? title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail ?? "")
    }
}
