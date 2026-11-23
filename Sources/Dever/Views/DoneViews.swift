import SwiftUI

// A project marked as done: the confirmation with what happens in the tools, the way back
// ("Reopen project"), the few seconds of "Undo", and what its page shows in place of the work
// to do. One word everywhere: "Done". Removing a project forgets it; marking it as done keeps it.

extension Notification.Name {
    /// Asks to mark a project as done; `object` is its UUID. The window shows the confirmation.
    static let markProjectDone = Notification.Name("dever.markProjectDone")
    /// Asks to reopen a done project; `object` is its UUID.
    static let reopenProject = Notification.Name("dever.reopenProject")
}

private struct FrozenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The page belongs to a done project: it reads, and offers nothing that writes.
    var projectFrozen: Bool {
        get { self[FrozenKey.self] }
        set { self[FrozenKey.self] = newValue }
    }
}

// MARK: - Mark as done

/// The one question: mark this project as done? Under it, what Dever does in the tools, one
/// line each, ticked, that can be unticked. A line that failed says so and can be tried again;
/// the project is done either way.
struct MarkDoneSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let project: Project

    /// Nil while the Linear status is read.
    @State private var steps: [ProjectCompletion.Step]?
    @State private var off: Set<ProjectCompletion.Step.Kind> = []
    @State private var working = false
    /// Set once the project is marked: the lines then say how each went.
    @State private var failures: [ProjectCompletion.Step.Kind: String]?
    @State private var retrying: ProjectCompletion.Step.Kind?

    private var marked: Bool { failures != nil }

    var body: some View {
        SheetScaffold(width: 480) {
            VStack(alignment: .leading, spacing: 8) {
                Text(marked ? "\(project.name) is done" : "Mark \(project.name) as done?")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4).foregroundStyle(Soot.ink)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(marked ? "One thing could not be done in the tools."
                            : "It leaves the rail and the list, and stays readable under Done.")
                    .font(.system(size: 14)).foregroundStyle(Soot.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let steps {
                    ForEach(steps) { step in line(step) }
                } else {
                    Skeleton(height: 56, radius: Soot.fieldRadius)
                        .accessibilityLabel("Reading the project's state in Linear")
                }
                if !marked {
                    Text(project.slack == nil ? "Nothing else changes in your tools."
                                              : "The Slack channel is not archived. Nothing else changes.")
                        .font(.system(size: 12)).foregroundStyle(Soot.muted)
                        .padding(.top, steps?.isEmpty == false || steps == nil ? 8 : 0)
                }
            }
            .motion(Motion.ui, fade: true, value: steps)
        } footer: {
            HStack(spacing: 12) {
                Spacer()
                if marked {
                    Button("Close") { dismiss() }
                        .buttonStyle(PrimaryButton(size: .sheet))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SecondaryButton(size: .sheet))
                        .keyboardShortcut(.cancelAction)
                    Button(working ? "Marking…" : "Mark as done") { confirm() }
                        .buttonStyle(PrimaryButton(size: .sheet))
                        .keyboardShortcut(.defaultAction)
                        .disabled(working || steps == nil)
                }
            }
        }
        .task { steps = await CompletionStore.shared.steps(for: project, app: app) }
    }

    @ViewBuilder
    private func line(_ step: ProjectCompletion.Step) -> some View {
        let on = !off.contains(step.kind)
        let failure = failures?[step.kind]
        if marked {
            // After the mark: each line as it went.
            if on {
                HStack(spacing: 12) {
                    Image(systemName: failure == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(failure == nil ? Soot.lime : Theme.negative)
                        .frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                        Text(failure.map { "Not done: \($0)" } ?? "Done")
                            .font(.system(size: 12)).foregroundStyle(failure == nil ? Soot.muted : Theme.pillNegative.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if failure != nil {
                        Button(retrying == step.kind ? "Trying…" : "Try again") { retry(step.kind) }
                            .buttonStyle(SecondaryButton())
                            .disabled(retrying != nil)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                .accessibilityElement(children: .combine)
            }
        } else {
            Button { if on { off.insert(step.kind) } else { off.remove(step.kind) } } label: {
                HStack(spacing: 12) {
                    CheckCircle(on: on, square: true)
                    stepMark(step.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                        Text(step.detail).font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                .opacity(on ? 1 : 0.6)
            }
            .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
            .disabled(working)
            .accessibilityLabel("\(step.title). \(step.detail)")
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityHint("Dever does this when the project is marked as done")
        }
    }

    @ViewBuilder
    private func stepMark(_ kind: ProjectCompletion.Step.Kind) -> some View {
        switch kind {
        case .linear: BrandLogo(service: .linear, size: 16).foregroundStyle(Soot.ink).frame(width: 20).accessibilityHidden(true)
        case .preview: Image(systemName: "globe").font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)
            .frame(width: 20).accessibilityHidden(true)
        }
    }

    private func confirm() {
        guard let steps else { return }
        working = true
        let wanted = Set(steps.map(\.kind)).subtracting(off)
        Task {
            let failed = await CompletionStore.shared.markDone(project, steps: wanted, app: app)
            working = false
            if failed.isEmpty { dismiss() } else { Motion.run(Motion.ui, fade: true) { failures = failed } }
        }
    }

    private func retry(_ kind: ProjectCompletion.Step.Kind) {
        retrying = kind
        Task {
            let problem = await CompletionStore.shared.retry(kind, project: project, app: app)
            retrying = nil
            Motion.run(Motion.ui, fade: true) { failures?[kind] = problem }
            if failures?.isEmpty == true { dismiss() }
        }
    }
}

// MARK: - Reopen

/// Reopening puts the project back as it was. Linear is not touched unless asked, here.
struct ReopenSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var restoreLinear = false
    @State private var working = false
    @State private var problem: String?

    private var back: LinearProjectStatus? { app.linear == nil ? nil : project.linearStatusBeforeDone }

    var body: some View {
        SheetScaffold(width: 480) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reopen \(project.name)?")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4).foregroundStyle(Soot.ink)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text("It goes back to the rail and the list, and is read again.")
                    .font(.system(size: 14)).foregroundStyle(Soot.muted)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let back {
                    Button { restoreLinear.toggle() } label: {
                        HStack(spacing: 12) {
                            CheckCircle(on: restoreLinear, square: true)
                            BrandLogo(service: .linear, size: 16).foregroundStyle(Soot.ink).frame(width: 20).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Move the Linear project back to \(back.name)")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                                Text("Left off, Linear keeps it Completed").font(.system(size: 12)).foregroundStyle(Soot.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                    }
                    .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
                    .disabled(working)
                    .accessibilityLabel("Move the Linear project back to \(back.name)")
                    .accessibilityValue(restoreLinear ? "On" : "Off")
                } else if project.linear != nil {
                    Text("Linear is not changed.").font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                if let problem { ErrorLabel("Reopened, but Linear was not moved: \(problem)") }
            }
        } footer: {
            HStack(spacing: 12) {
                Spacer()
                if problem != nil {
                    Button("Close") { dismiss() }.buttonStyle(PrimaryButton(size: .sheet)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SecondaryButton(size: .sheet))
                        .keyboardShortcut(.cancelAction)
                    Button(working ? "Reopening…" : "Reopen project") {
                        working = true
                        Task {
                            let failed = await CompletionStore.shared.reopen(project, restoreLinear: restoreLinear, app: app)
                            working = false
                            if let failed { problem = failed } else { dismiss() }
                        }
                    }
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
                }
            }
        }
    }
}

// MARK: - Undo

/// Right after "Mark as done": the name, and the way back for a few seconds. Floats at the
/// window's foot, over whichever screen is in front.
struct DoneUndoBar: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var completion = CompletionStore.shared
    @State private var problem: String?

    var body: some View {
        ZStack {
            if let undo = completion.undo {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.lime)
                        .accessibilityHidden(true)
                    Text("\(undo.name) marked as done").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
                    Button("Undo") {
                        Task { problem = await completion.undoDone(app: app) }
                    }
                    .buttonStyle(TertiaryButton(lift: Soot.surface))
                    .help(undo.deletedPreview ? "Brings the project back. The preview stays deleted."
                                              : undo.movedLinear ? "Brings the project back, in Linear too" : "Brings the project back")
                    Button { completion.dismissUndo() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(IconButton(fill: nil))
                    .accessibilityLabel("Dismiss")
                }
                .padding(.leading, 14).padding(.trailing, 8)
                .frame(height: 44)
                .background(Soot.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Soot.line))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .padding(.bottom, 20)
                .transition(Motion.rise)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(undo.name) marked as done")
            } else if let problem {
                Text("Reopened, but Linear was not moved back: \(problem)")
                    .font(.system(size: 13)).foregroundStyle(Theme.pillNegative.ink)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Soot.ground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Soot.line))
                    .padding(.bottom, 20)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        Motion.run(Motion.ui, fade: true) { self.problem = nil }
                    }
            }
        }
        .motion(Motion.ui, value: completion.undo)
    }
}

// MARK: - The done project's page

/// "Done 12 Nov" beside the project's name, in place of its health.
struct DoneBadge: View {
    let date: Date
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text(ProjectCompletion.doneLabel(date)).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Theme.pillPositive.ink)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Theme.pillPositive.bg, in: RoundedRectangle(cornerRadius: 4))
        .help("Marked as done \(date.formatted(date: .long, time: .shortened))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ProjectCompletion.doneLabel(date)). Read only")
    }
}

/// What a done project's page shows where the Delivery board was: what shipped, and what was
/// left open, as plain rows that open the issue. No "Start here", nothing that writes.
struct DoneWork: View {
    let project: Project
    let plan: DeliveryPlan
    @State private var expanded: Set<String> = []
    private static let cap = 6

    private var left: [LinearIssue] {
        ([plan.start].compactMap { $0 } + plan.agents + plan.next + plan.others).map(\.issue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(plan.shipped.count)").font(.system(size: 34, weight: .semibold)).tracking(-1).foregroundStyle(Soot.ink)
                    .monospacedDigit()
                Text(plan.left == 0 ? (plan.total == 1 ? "issue shipped" : "issues shipped, all of them")
                                    : "of \(plan.total) issues shipped")
                    .font(.system(size: 14)).foregroundStyle(Soot.muted)
            }
            .accessibilityElement(children: .combine)
            if !left.isEmpty { list("Left open", left, key: "left") }
            if !plan.shipped.isEmpty { list("Shipped", plan.shipped.map(\.issue), key: "shipped") }
        }
    }

    private func list(_ title: String, _ issues: [LinearIssue], key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(expanded.contains(key) ? issues : Array(issues.prefix(Self.cap))) { issue in
                TileLink(value: IssueRoute(project: project, issue: issue)) {
                    StateDot(state: issue.state)
                    IssueRow(issue: issue)
                }
                .transition(.opacity)
                .accessibilityHint("Opens the issue, read only")
            }
            if issues.count > Self.cap {
                ShowAllButton(count: issues.count, expanded: Binding(
                    get: { expanded.contains(key) },
                    set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }))
            }
        }
    }
}
