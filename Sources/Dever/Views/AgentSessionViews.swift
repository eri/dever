import SwiftUI

/// A session's state as a dot: lime while it works, amber when it waits for the user, a check
/// once it finished, muted when it is old or not started. Always beside its word.
private struct AgentStateDot: View {
    let session: AgentSession
    let now: Date

    var body: some View {
        Group {
            switch session.state {
            case .finished:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.positive)
            case .waiting:
                Image(systemName: "questionmark.bubble.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.chart3)
            default:
                Circle().fill(session.state == .working && !session.stale(at: now) ? Soot.lime : Soot.muted).frame(width: 7, height: 7)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// The agent working on an issue, as one line: its mark, its state with its age, a way to its
/// session, and under it the agent's last sentence or what it waits for. A state is never drawn
/// as current once it is old: "last heard 14 min ago".
struct AgentSessionLine: View {
    @ObservedObject private var proposals = ProposalStore.shared
    let session: AgentSession
    /// The tone of what the line sits on, for the link's hover.
    var lift: Color = Soot.ground
    /// The agent's proposal is shown beside this line.
    var hasProposal = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    AgentMark(tool: session.tool, size: 16)
                    AgentStateDot(session: session, now: now)
                    Text("\(session.tool.label) · \(session.words(at: now))")
                        .font(.system(size: 13, weight: session.state == .waiting ? .semibold : .medium))
                        .foregroundStyle(session.state == .waiting ? Soot.ink : Soot.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    // A finished turn stays "to review" until the developer says it was looked at.
                    if session.state == .finished, !proposals.reviewed.contains(session.id) {
                        Button("Reviewed") { Motion.run(Motion.ui, fade: true) { proposals.markReviewed(session.id) } }
                            .buttonStyle(TertiaryButton(tint: .muted, lift: lift, font: .system(size: 13, weight: .medium), height: 24))
                            .help("Stop listing this issue as work to review")
                    }
                    if let link = session.link {
                        Link(destination: link) {
                            HStack(spacing: 4) {
                                Text("Open session")
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(TertiaryButton(tint: .lime, lift: lift, font: .system(size: 13, weight: .medium), height: 24))
                        .accessibilityHint("Opens in \(session.tool.label)")
                    }
                }
                // With a proposal under the line, the agent's account says it better than its last sentence.
                if let sentence = session.sentence, session.state == .waiting || (session.state == .finished && !hasProposal) {
                    Text("“\(sentence)”").font(.system(size: 13)).foregroundStyle(Soot.ink.opacity(0.85))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 23)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// The same on a Delivery row, in a few characters: the mark, the dot, one word.
struct AgentSessionChip: View {
    let session: AgentSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            HStack(spacing: 5) {
                AgentMark(tool: session.tool, size: 14)
                AgentStateDot(session: session, now: now)
                Text(word(now)).font(.system(size: 12, weight: session.state == .waiting ? .semibold : .regular))
                    .foregroundStyle(session.state == .waiting ? Soot.ink : Soot.muted)
            }
            .lineLimit(1)
            .fixedSize()
            .help([("\(session.tool.label) · \(session.words(at: now))"), session.sentence].compactMap { $0 }.joined(separator: "\n"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.tool.label): \(session.words(at: now))")
        }
    }

    private func word(_ now: Date) -> String {
        switch session.state {
        case .ready: "open"
        case .working: session.stale(at: now) ? "quiet" : "working"
        case .waiting: "waiting for you"
        case .finished: "finished"
        case .ended: "closed"
        }
    }
}

/// An issue whose agent waits for the developer or finished its work, as one compact row: the
/// agent's mark, the issue's title (a link to the issue, without a button of its own), its state,
/// and the one action that answers it. A finished agent's suggestions follow as explicit choices,
/// "Codex suggests", ticked by default and applied with one button: nothing is done without it.
struct AgentWorkRow: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var proposals = ProposalStore.shared
    @ObservedObject private var store = IssueStore.shared
    let project: Project
    let issue: LinearIssue
    let session: AgentSession?
    /// The issue's open pull request, where the finished work is read.
    var pull: URL?
    /// The title opens the issue; on the issue's own page it is plain text.
    var linksIssue = true

    @State private var moveOn = true
    @State private var replyOn = true
    @State private var editing = false
    @State private var draft: String?
    @State private var busy = false
    @State private var problem: String?
    @State private var states: [LinearTeamContext.WorkflowState] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let proposal = proposals.proposal(for: issue.identifier)
            let waiting = session?.state == .waiting
            let tool = session?.tool ?? proposal?.tool ?? .claudeCode
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    AgentMark(tool: tool, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        if linksIssue {
                            NavigationLink(value: IssueRoute(project: project, issue: issue)) {
                                Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Soot.ink).lineLimit(1)
                            }
                            .buttonStyle(TertiaryButton(tint: .ink, lift: Soot.ground, font: .system(size: 14, weight: .semibold), height: 22))
                            .padding(.horizontal, -6)
                            .accessibilityHint("Opens the issue")
                        } else {
                            Text(tool.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                        }
                        subline(tool: tool, waiting: waiting, proposal: proposal, now: now)
                    }
                    Spacer(minLength: 12)
                    actions(waiting: waiting, proposal: proposal)
                }
                if let proposal, proposal.status != nil || proposal.reply != nil {
                    suggestions(proposal, tool: tool)
                        .padding(.leading, 40)
                }
            }
            .padding(.vertical, 14)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(tool.label) on \(issue.identifier)")
        }
        .task(id: issue.team?.id) { await loadStates() }
    }

    /// "APP-306 · Waiting for you · 35 min", the state with its icon, never the colour alone.
    private func subline(tool: AgentTool, waiting: Bool, proposal: AgentProposal?, now: Date) -> some View {
        let words: String = {
            if let session, session.state == .waiting || session.state == .finished { return session.words(at: now) }
            return "Finished \(proposal?.at.formatted(.relative(presentation: .named)) ?? "")"
        }()
        // On the issue's own page the agent is the head and the issue is the page: only the state.
        return HStack(spacing: 6) {
            if linksIssue {
                Text(verbatim: issue.identifier).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Soot.muted)
                Text("·").foregroundStyle(Soot.muted)
            }
            Image(systemName: waiting ? "questionmark.bubble.fill" : "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(waiting ? Theme.chart3 : Theme.positive)
                .accessibilityHidden(true)
            Text(linksIssue ? "\(tool.label) · \(words)" : words).font(.system(size: 12, weight: waiting ? .semibold : .regular))
                .foregroundStyle(waiting ? Soot.ink : Soot.muted)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func actions(waiting: Bool, proposal: AgentProposal?) -> some View {
        HStack(spacing: 8) {
            if !waiting, proposal == nil, let session, !proposals.reviewed.contains(session.id) {
                Button("Reviewed") { Motion.run(Motion.ui, fade: true) { proposals.markReviewed(session.id) } }
                    .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 13, weight: .medium)))
                    .help("Stop listing this issue as work to review")
            }
            // With suggestions to apply, "Apply" below is the primary action; the pull request is a peer.
            let pending = proposal?.pending == true
            if waiting, let link = session?.link {
                external("Answer", link, primary: true).help("Open the session in \(session?.tool.label ?? "the agent") to answer it")
            } else if let pull {
                external("Open PR", pull, primary: !pending).help("Open the pull request on GitHub")
            } else if let link = session?.link {
                external("Open session", link, primary: !pending)
            }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private func suggestions(_ proposal: AgentProposal, tool: AgentTool) -> some View {
        let target = proposal.state(in: states)
        let canMove = proposal.status != nil && proposal.movedTo == nil && !proposal.statusDismissed && target != nil
        let canReply = proposal.reply != nil && !proposal.replied && !proposal.replyDismissed
        let chosen = (canMove && moveOn ? 1 : 0) + (canReply && replyOn ? 1 : 0)
        VStack(alignment: .leading, spacing: 8) {
            Text("\(tool.label) suggests").font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
            if proposal.status != nil {
                if let moved = proposal.movedTo {
                    done("Moved to \(moved) in Linear")
                } else if !proposal.statusDismissed {
                    choice(on: $moveOn, enabled: target != nil,
                           text: target.map { "Move the issue to \($0.name)" } ?? "Move the issue to \(proposal.status ?? "")",
                           detail: target == nil ? "Linear has no state by that name" : "Linear", service: .linear)
                }
            }
            if proposal.reply != nil {
                if proposal.replied {
                    done("Posted in the Slack thread")
                } else if !proposal.replyDismissed {
                    HStack(alignment: .center, spacing: 8) {
                        choice(on: $replyOn, enabled: true, text: "Post in the issue's Slack thread", detail: "as you", service: .slack)
                        Button(editing ? "Hide" : "Edit…") { Motion.run(Motion.ui, fade: true) { editing.toggle() } }
                            .buttonStyle(TertiaryButton(tint: .lime, lift: Soot.surface, font: .system(size: 13, weight: .medium), height: 24))
                            .help("Read and change the message before it is posted")
                    }
                    if editing {
                        TextEditor(text: Binding(get: { draft ?? proposal.reply ?? "" }, set: { draft = $0 }))
                            .font(.system(size: 13)).foregroundStyle(Soot.ink)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 64, maxHeight: 120)
                            .background(Soot.ground, in: RoundedRectangle(cornerRadius: Soot.radius))
                            .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge))
                            .accessibilityLabel("Message to post in the Slack thread")
                            .padding(.leading, 26)
                    }
                }
            }
            if let problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if canMove || canReply {
                    Button("Dismiss") { Motion.run(Motion.ui, fade: true) { proposals.update(issue.identifier) { $0.statusDismissed = true; $0.replyDismissed = true } } }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.surface, font: .system(size: 13, weight: .medium)))
                        .help("Do none of it")
                    Button(busy ? "Applying…" : chosen > 1 ? "Apply \(chosen)" : "Apply") { apply(proposal, target: canMove && moveOn ? target : nil, reply: canReply && replyOn) }
                        .buttonStyle(PrimaryButton())
                        .disabled(chosen == 0 || busy)
                } else {
                    Button("Done") {
                        Motion.run(Motion.ui, fade: true) {
                            proposals.dismiss(issue.identifier)
                            if let session { proposals.markReviewed(session.id) }
                        }
                    }
                    .buttonStyle(SecondaryButton())
                    .help("Stop listing this issue as work to review")
                }
            }
        }
    }

    /// One suggestion: a checkbox, what it does in plain words, and where.
    private func choice(on: Binding<Bool>, enabled: Bool, text: String, detail: String, service: ServiceKind) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                SootCheckbox(on: on.wrappedValue, enabled: enabled)
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(enabled ? Soot.ink : Soot.muted)
                BrandLogo(service: service, size: 12).foregroundStyle(Soot.muted).accessibilityHidden(true)
                Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            .padding(.vertical, 3).padding(.horizontal, 4)
        }
        .buttonStyle(RowButton(lift: .surface, radius: 6))
        .padding(.horizontal, -4)
        .disabled(!enabled)
        .accessibilityLabel("\(text), \(detail)")
        .accessibilityAddTraits(on.wrappedValue && enabled ? .isSelected : [])
    }

    private func done(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.positive).accessibilityHidden(true)
            Text(text).font(.system(size: 13)).foregroundStyle(Soot.muted)
        }
        .padding(.leading, 2)
    }

    private func external(_ title: String, _ url: URL, primary: Bool) -> some View {
        let label = HStack(spacing: 5) {
            Text(title)
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
        }
        return Group {
            if primary {
                Link(destination: url) { label }.buttonStyle(PrimaryButton())
            } else {
                Link(destination: url) { label }.buttonStyle(SecondaryButton())
            }
        }
        .accessibilityHint("Opens outside Dever")
    }

    // MARK: Applying

    private func loadStates() async {
        if DeliveryPlan.snapshotDemo() != nil { states = DeliveryPlan.demoTeam.states; return }
        guard let team = issue.team?.id else { return }
        states = (try? await store.team(team, app: app))?.states ?? []
    }

    /// What is ticked, in order: the move (the existing optimistic write), then the message, as
    /// edited. Canary does both on screen only.
    private func apply(_ proposal: AgentProposal, target: LinearTeamContext.WorkflowState?, reply: Bool) {
        busy = true
        problem = nil
        let text = (draft ?? proposal.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            if let target {
                do {
                    if !Canary.isOn {
                        let current = store.row(issue.id) ?? issue
                        var optimistic = current
                        optimistic.state = .init(id: target.id, name: target.name, type: target.type, color: target.color)
                        try await store.update(current.id, change: .init(stateID: target.id), optimistic: optimistic, previous: current, app: app)
                    }
                    proposals.update(issue.identifier) { $0.movedTo = target.name }
                } catch {
                    problem = "Not moved: \(error.localizedDescription)"
                    return
                }
            }
            if reply, !text.isEmpty {
                do {
                    if !Canary.isOn {
                        let detail = try await store.detail(issue.id, updatedAt: issue.updatedAt, app: app)
                        guard let link = (detail.attachments?.nodes ?? []).compactMap({ AgentContextText.slackLocation($0.url) }).first else {
                            problem = "Not posted: Linear links no Slack thread to \(issue.identifier)"
                            return
                        }
                        try await app.withSlack { try await $0.reply(link.channel, threadTS: link.thread ?? link.ts, text: text) }
                    }
                    proposals.update(issue.identifier) { $0.replied = true }
                    editing = false
                } catch {
                    problem = "Not posted: \(error.localizedDescription)"
                }
            }
        }
    }
}
