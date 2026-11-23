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

/// An issue whose agent waits for the developer or finished its work, as one card: the agent and
/// its state, the issue it works on, then what it asks or what it did, and the one action that
/// answers it. Everything about the agent sits inside the card, so nothing reads as a separate line.
struct AgentWorkCard: View {
    @ObservedObject private var proposals = ProposalStore.shared
    let project: Project
    let issue: LinearIssue
    let session: AgentSession?
    /// The issue's open pull request, where the finished work is read.
    var pull: URL?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let proposal = proposals.proposal(for: issue.identifier)
            let waiting = session?.state == .waiting
            let tool = session?.tool ?? proposal?.tool ?? .claudeCode
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AgentMark(tool: tool, size: 22)
                    Text(tool.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                    state(waiting: waiting, proposal: proposal, now: now)
                    Spacer(minLength: 8)
                    actions(waiting: waiting, proposal: proposal)
                }
                NavigationLink(value: IssueRoute(project: project, issue: issue)) {
                    HStack(spacing: 8) {
                        IDPill(text: issue.identifier)
                        Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                }
                .buttonStyle(RowButton(lift: .surface, radius: 8))
                .padding(.horizontal, -8)
                .accessibilityHint("Opens the issue")
                if waiting, let sentence = session?.sentence {
                    quote(sentence, tint: Theme.chart3)
                } else if proposal != nil {
                    AgentProposalBlock(project: project, issue: issue, fill: Soot.ground, embedded: true)
                } else if let sentence = session?.sentence {
                    quote(sentence, tint: Soot.edge)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Soot.ground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(waiting ? Theme.chart3.opacity(0.55) : Soot.edge.opacity(0.6)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(tool.label) on \(issue.identifier)")
        }
    }

    /// The state as a small capsule: an icon and its words, never the colour alone.
    private func state(waiting: Bool, proposal: AgentProposal?, now: Date) -> some View {
        let words: String = {
            if let session, session.state == .waiting || session.state == .finished {
                return session.words(at: now)
            }
            return "Finished \(proposal?.at.formatted(.relative(presentation: .named)) ?? "")"
        }()
        let tint = waiting ? Theme.chart3 : Theme.positive
        return HStack(spacing: 5) {
            Image(systemName: waiting ? "questionmark.bubble.fill" : "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(words).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func actions(waiting: Bool, proposal: AgentProposal?) -> some View {
        HStack(spacing: 8) {
            if !waiting, proposal == nil, let session, !proposals.reviewed.contains(session.id) {
                Button("Reviewed") { Motion.run(Motion.ui, fade: true) { proposals.markReviewed(session.id) } }
                    .buttonStyle(TertiaryButton(tint: .muted, lift: Soot.ground, font: .system(size: 13, weight: .medium)))
                    .help("Stop listing this issue as work to review")
            }
            if waiting, let link = session?.link {
                external("Answer", link, primary: true).help("Open the session in \(session?.tool.label ?? "the agent") to answer")
            } else if let pull {
                if let link = session?.link { external("Open session", link, primary: false) }
                external("Open PR", pull, primary: true).help("Open the pull request on GitHub")
            } else if let link = session?.link {
                external("Open session", link, primary: true)
            }
        }
    }

    @ViewBuilder
    private func external(_ title: String, _ url: URL, primary: Bool) -> some View {
        let label = HStack(spacing: 5) {
            Text(title)
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
        }
        if primary {
            Link(destination: url) { label }.buttonStyle(PrimaryButton()).accessibilityHint("Opens outside Dever")
        } else {
            Link(destination: url) { label }.buttonStyle(SecondaryButton()).accessibilityHint("Opens outside Dever")
        }
    }

    /// What the agent said, set off by a thin bar in its state's colour.
    private func quote(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 2)
            Text(text).font(.system(size: 13)).foregroundStyle(Soot.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
