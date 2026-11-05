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
        VStack(alignment: .leading, spacing: 12) {
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
                if optionsOpen {
                    optionsRow
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
                if let actionError { ErrorLabel(actionError) }
            } else {
                skeleton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
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

    /// One line: the word "Preview", the pull request it follows (a link), then on the right
    /// the phase as glyph and word, when it changed, the run, the shield.
    private var headline: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe").font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                .accessibilityHidden(true)
            Text("Preview").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
            if let s = status {
                HoverLink(destination: s.pull.url) {
                    HStack(spacing: 6) {
                        IDPill(text: "#\(s.pull.number)")
                        Text(PullTitle.split(s.pull.title).title).font(.system(size: 13)).foregroundStyle(Soot.muted)
                            .lineLimit(1).truncationMode(.tail)
                        if s.pull.state != .open {
                            Text(s.pull.state.word).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                        }
                    }
                }
                .layoutPriority(-1)
                .help("#\(s.pull.number) \(s.pull.title) · \(s.pull.state.word) · by \(s.pull.author) · Opens on GitHub")
                .accessibilityLabel("Pull request #\(s.pull.number), \(s.pull.title), \(s.pull.state.word), by \(s.pull.author)")
                .accessibilityHint("Opens on GitHub")
            } else if let number = project.previewPullNumber {
                IDPill(text: "#\(number)")
            }
            Spacer(minLength: 12)
            if let s = status {
                PreviewPhaseGlyph(phase: s.phase, size: 13)
                Text(s.phase.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                if let at = s.updatedAt {
                    Text(verbatim: "·").foregroundStyle(Soot.muted).accessibilityHidden(true)
                    Text(timeLine(s.phase, at)).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                if let run = s.run {
                    HoverLink(destination: run.url) {
                        HStack(spacing: 4) { Text("Run"); Image(systemName: "arrow.up.right") }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                    }
                    .help("Open the workflow run on GitHub")
                    .accessibilityLabel("Open the workflow run on GitHub")
                }
                if s.keep { KeepPill() }
            }
        }
        .frame(minHeight: 28)
    }

    // MARK: No preview

    /// No pull request yet: one line, the way to add one, and the way to say none is wanted.
    private var nonePart: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { noneText; Spacer(minLength: 12); noneButtons }
            VStack(alignment: .leading, spacing: 12) { noneText; noneButtons }
        }
    }

    private var noneText: some View {
        Text("Follow the preview of one of the repository's pull requests here: deploy, update and delete it without leaving Dever.")
            .font(.system(size: 13)).foregroundStyle(Soot.muted).fixedSize(horizontal: false, vertical: true)
    }

    private var noneButtons: some View {
        HStack(spacing: 8) {
            Button("Add a preview", action: addPreview).buttonStyle(QuietButton())
                .help("Choose the pull request whose preview this project follows")
            Button("No preview needed", action: dismiss).buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.lime)
                .padding(.horizontal, 8).frame(height: 36).contentShape(Rectangle())
                .modifier(FocusOutline(radius: Soot.radius))
                .help("Hides this panel; pick a pull request later in Edit project to bring it back")
        }
        .fixedSize()
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

    /// The hosts the workflow deployed, each a chip that opens it and says whether it answers.
    private func targetChips(_ s: PreviewStatus) -> some View {
        FlowRow(spacing: 6) {
            ForEach(s.sortedTargets) { target in
                TargetChip(target: target, url: PreviewTarget.url(target, pull: s.pull.number), reachable: s.targets[target] ?? nil)
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
                    Button("Deploy preview") { optionsOpen = true }
                        .buttonStyle(LimeButton()).disabled(sending)
                        .help("Choose the options, then post /preview on the pull request")
                case .live:
                    // The preview is there: nothing presses for attention, so no lime.
                    if let appURL = s.appURL {
                        Button(copied ? "Copied" : "Copy app URL") { copyAppURL(s) }
                            .buttonStyle(QuietButton())
                            .help(appURL.absoluteString)
                            .accessibilityValue(copied ? "Copied" : "")
                    }
                    Button(sending ? "Sending…" : "Update preview") { Task { await send { try await store.deploy(project, app: app, options: options) } } }
                        .buttonStyle(QuietButton()).disabled(sending)
                        .help("Post /preview again: rebuilds the targets the diff touched")
                case .deploying, .updating, .deleting:
                    EmptyView()
                }
            }
            Menu {
                if s.phase == .live, !s.keep, canCommand {
                    Button("Protect from Saturday cleanup…") { confirmingProtect = true }
                }
                if s.phase == .live || s.phase == .failed || s.phase == .updating {
                    Button("Delete preview…", role: .destructive) { confirmingDelete = true }
                }
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
            .help("More: protect, delete, open on GitHub, change the pull request")
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

    private func copyAppURL(_ s: PreviewStatus) {
        guard let url = s.appURL else { return }
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

/// `preview:keep`: the preview survives the Saturday cleanup.
struct KeepPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.fill").font(.system(size: 10, weight: .semibold))
            Text("Kept").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Soot.lime)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .overlay(Capsule().strokeBorder(Soot.lime))
        .help("Labelled preview:keep: skipped by the Saturday cleanup. Deleting the preview or closing the pull request lifts it.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kept: protected from the Saturday cleanup")
    }
}

/// One deployed host: its name, whether it answered the probe, a click opens it.
private struct TargetChip: View {
    let target: PreviewTarget
    let url: URL
    /// nil while the probe runs.
    let reachable: Bool?
    @State private var hovering = false

    private var word: String {
        switch reachable {
        case true?: "up"
        case false?: "not answering"
        case nil: "checking"
        }
    }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                switch reachable {
                case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                case false?: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.negative)
                case nil: Image(systemName: "circle.dotted").foregroundStyle(Soot.muted)
                }
                Text(target.label).foregroundStyle(Soot.ink)
                if reachable == false {
                    Text("down").foregroundStyle(Soot.muted)
                }
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
        .help("\(url.absoluteString) · \(word)")
        .accessibilityLabel("\(target.label), \(word)")
        .accessibilityHint("Opens in the browser")
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
