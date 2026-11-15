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
                Image(systemName: "hand.raised.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.chart3)
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
    let session: AgentSession
    /// The tone of what the line sits on, for the link's hover.
    var lift: Color = Soot.ground

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
                if let sentence = session.sentence, session.state == .waiting || session.state == .finished {
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
