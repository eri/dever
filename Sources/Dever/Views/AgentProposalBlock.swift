import SwiftUI

/// What an agent left for the developer on an issue: its account of the work, what it did not
/// verify, the acceptance criteria to tick, and what it suggests (move the issue, answer the
/// thread), each applied, edited or dismissed by the developer. Nothing here was done by the
/// agent, and nothing is sent without a click.
struct AgentProposalBlock: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var proposals = ProposalStore.shared
    @ObservedObject private var store = IssueStore.shared
    let project: Project
    let issue: LinearIssue
    /// The tone the block sits on: the ground on a panel, the surface on the page.
    var fill: Color = Soot.surface
    /// The acceptance criteria are listed where there is room for them: the issue page.
    var showsCriteria = false

    @State private var editing = false
    @State private var draft = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var states: [LinearTeamContext.WorkflowState] = []

    private var lift: Color { fill == Soot.ground ? Soot.surface : Soot.ground }

    var body: some View {
        if let proposal = proposals.proposal(for: issue.identifier) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AgentMark(tool: proposal.tool, size: 18)
                    Text("\(proposal.tool.label) finished").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                    Text(proposal.at.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(Soot.muted)
                    Spacer(minLength: 8)
                    Button("Dismiss") { Motion.run(Motion.ui, fade: true) { proposals.dismiss(issue.identifier) } }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: lift, font: .system(size: 12, weight: .medium), height: 24))
                        .help("Remove the agent's account and its suggestions")
                }
                Text(proposal.summary).font(.system(size: 14)).foregroundStyle(Soot.ink)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let missing = proposal.notVerified {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.chart3)
                            .accessibilityHidden(true)
                        Text("Not verified: \(missing)").font(.system(size: 13)).foregroundStyle(Soot.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if showsCriteria { criteria }
                if proposal.status != nil || proposal.reply != nil {
                    Rectangle().fill(Soot.line).frame(height: 1)
                    if proposal.status != nil { statusRow(proposal) }
                    if proposal.reply != nil { replyRow(proposal) }
                }
                if let problem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Soot.edge.opacity(0.6)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(proposal.tool.label)'s account of its work on \(issue.identifier)")
            .task(id: issue.team?.id) {
                guard proposal.status != nil, let team = issue.team?.id else { return }
                states = (try? await store.team(team, app: app))?.states ?? []
            }
        }
    }

    // MARK: Acceptance criteria

    /// The criteria read from the description, ticked by the developer; the ticks are theirs and local.
    @ViewBuilder private var criteria: some View {
        let list = AcceptanceCriteria.parse(store.cachedDetail(issue.id)?.description)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Acceptance criteria").font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                    .padding(.bottom, 4)
                ForEach(list, id: \.self) { criterion in
                    let on = proposals.isTicked(criterion, of: issue.identifier)
                    Button { proposals.toggle(criterion, of: issue.identifier) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 13))
                                .foregroundStyle(on ? Soot.lime : Soot.muted)
                                .accessibilityHidden(true)
                            Text(MarkdownTheme.inline(criterion, size: 13)).font(.system(size: 13))
                                .foregroundStyle(on ? Soot.muted : Soot.ink).strikethrough(on, color: Soot.muted)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6)
                    }
                    .buttonStyle(RowButton(lift: fill == Soot.ground ? .surface : .ground, radius: 6))
                    .accessibilityLabel(criterion)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Suggestions

    private func statusRow(_ proposal: AgentProposal) -> some View {
        let target = proposal.state(in: states)
        return HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.muted)
                .accessibilityHidden(true)
            if let moved = proposal.movedTo {
                Text("Moved to \(moved)").font(.system(size: 13)).foregroundStyle(Soot.muted)
            } else if proposal.statusDismissed {
                Text("Move to \(proposal.status ?? "") · dismissed").font(.system(size: 13)).foregroundStyle(Soot.muted)
            } else {
                Text("Move to \(target?.name ?? proposal.status ?? "")").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                if target == nil, !states.isEmpty {
                    Text("no state by that name").font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                Spacer(minLength: 8)
                Button("Dismiss") { proposals.update(issue.identifier) { $0.statusDismissed = true } }
                    .buttonStyle(TertiaryButton(tint: .muted, lift: lift, font: .system(size: 13, weight: .medium)))
                Button("Apply") { if let target { move(to: target) } }
                    .buttonStyle(SecondaryButton())
                    .disabled(target == nil || busy)
                    .help(target.map { "Move \(issue.identifier) to \($0.name) in Linear" } ?? "Linear has no state named \(proposal.status ?? "")")
            }
        }
        .frame(minHeight: 36)
    }

    private func replyRow(_ proposal: AgentProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                BrandLogo(service: .slack, size: 13).padding(.top, 3).accessibilityHidden(true)
                if proposal.replied {
                    Text("Reply sent in the thread").font(.system(size: 13)).foregroundStyle(Soot.muted)
                } else if proposal.replyDismissed {
                    Text("Reply in the thread · dismissed").font(.system(size: 13)).foregroundStyle(Soot.muted)
                } else if !editing {
                    Text("“\(proposal.reply ?? "")”").font(.system(size: 13)).foregroundStyle(Soot.ink)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Dismiss") { proposals.update(issue.identifier) { $0.replyDismissed = true } }
                        .buttonStyle(TertiaryButton(tint: .muted, lift: lift, font: .system(size: 13, weight: .medium)))
                    Button("Review & send") {
                        draft = proposal.reply ?? ""
                        Motion.run(Motion.ui, fade: true) { editing = true }
                    }
                    .buttonStyle(SecondaryButton())
                    .help("Read and edit the reply before it is posted in the issue's Slack thread")
                } else {
                    Text("Reply in the issue's Slack thread, as you").font(.system(size: 13)).foregroundStyle(Soot.muted)
                }
            }
            if editing, !proposal.replied {
                TextEditor(text: $draft)
                    .font(.system(size: 13)).foregroundStyle(Soot.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 72, maxHeight: 140)
                    .background(lift, in: RoundedRectangle(cornerRadius: Soot.radius))
                    .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge))
                    .accessibilityLabel("Reply to post in the Slack thread")
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") { Motion.run(Motion.ui, fade: true) { editing = false } }
                        .buttonStyle(SecondaryButton())
                    Button(busy ? "Sending…" : "Send") { send() }
                        .buttonStyle(PrimaryButton())
                        .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minHeight: 36)
    }

    // MARK: Actions

    /// The existing optimistic write: shown at once, restored if Linear refuses.
    private func move(to state: LinearTeamContext.WorkflowState) {
        guard let current = store.row(issue.id) ?? Optional(issue) else { return }
        var optimistic = current
        optimistic.state = .init(id: state.id, name: state.name, type: state.type, color: state.color)
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await store.update(current.id, change: .init(stateID: state.id), optimistic: optimistic, previous: current, app: app)
                proposals.update(issue.identifier) { $0.movedTo = state.name }
            } catch {
                problem = "Not moved: \(error.localizedDescription)"
            }
        }
    }

    /// Posts the edited reply in the Slack thread Linear links to the issue, as the developer.
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                let detail = try await store.detail(issue.id, updatedAt: issue.updatedAt, app: app)
                guard let link = (detail.attachments?.nodes ?? []).compactMap({ AgentContextText.slackLocation($0.url) }).first else {
                    problem = "Not sent: Linear links no Slack thread to \(issue.identifier)."
                    return
                }
                try await app.withSlack { try await $0.reply(link.channel, threadTS: link.thread ?? link.ts, text: text) }
                proposals.update(issue.identifier) { $0.replied = true }
                editing = false
            } catch {
                problem = "Not sent: \(error.localizedDescription)"
            }
        }
    }
}
