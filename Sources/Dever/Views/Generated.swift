import SwiftUI

// How a text written by the Mac's model looks, everywhere (docs/on-device-ai.md, section 4):
// one sparkle before it, the same muted ink as secondary text, no tinted block and no "AI" word.
// A sentence that speaks of a message leads to it; one that cannot be tied to a message is text.

/// The sparkle that marks generated text. Its tooltip and accessible name say what it means.
struct GeneratedMark: View {
    var size: CGFloat = 12
    /// A detected mention: `@` with the sparkle, where a Slack mention is `@` alone.
    var mention = false

    static let meaning = "Generated on this Mac. May be wrong."

    var body: some View {
        HStack(spacing: 1) {
            if mention {
                Image(systemName: "at").font(.system(size: size, weight: .semibold))
            }
            Image(systemName: "sparkles").font(.system(size: mention ? size * 0.8 : size, weight: .semibold))
                .offset(y: mention ? -size * 0.25 : 0)
        }
        .foregroundStyle(Soot.muted)
        .help(mention ? "Detected by Dever, not a Slack mention. May be wrong." : Self.meaning)
        .accessibilityElement()
        .accessibilityLabel(mention ? "Detected mention, may be wrong" : Self.meaning)
    }
}

/// A generated text in its place: the mark, then the sentences, or skeleton lines while the
/// first one is being written. The place keeps its height from skeleton to text.
struct GeneratedBlock: View {
    let text: GeneratedText?
    /// Nothing to show yet and one is being written.
    var writing = false
    /// The tone under the block, for the hover pill of a sentence that leads somewhere.
    var lift: RowButton.Lift = .ground
    /// Opens what a sentence rests on; sentences without a source are plain text.
    var open: ((String) -> Void)? = nil

    var body: some View {
        if text != nil || writing {
            // Top-aligned on the first line's height: skeleton bars have no baseline to sit on.
            HStack(alignment: .top, spacing: 8) {
                GeneratedMark().frame(height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    if let text {
                        ForEach(text.sentences) { sentence in line(sentence) }
                        if let note = text.note {
                            Text(note).font(.system(size: 11)).foregroundStyle(Soot.muted).padding(.top, 2)
                        }
                    } else {
                        Skeleton(height: 12).frame(height: 18)
                        Skeleton(width: 180, height: 12).frame(height: 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(.opacity)
            .motion(Motion.ui, fade: true, value: text)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func line(_ sentence: GeneratedText.Sentence) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 6) {
            if sentence.forYou {
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Soot.lime).accessibilityLabel("For you")
            }
            Text(sentence.text)
                .font(.system(size: 13, weight: sentence.forYou ? .medium : .regular))
                .foregroundStyle(sentence.forYou ? Soot.ink : Soot.muted)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let source = sentence.source, let open {
            Button { open(source) } label: {
                label.padding(.horizontal, 6).padding(.vertical, 2).contentShape(Rectangle())
            }
            .buttonStyle(RowButton(lift: lift, radius: 6))
            .padding(.horizontal, -6).padding(.vertical, -2)
            .help("Show the message")
        } else {
            label
        }
    }
}

/// A long message as its summary, in the message's own place: a block that cannot be taken for
/// the message itself. The block is there from the start, so the rail does not move when the
/// summary lands: while it is written the header says so and the start of the message stands,
/// muted, where the sentence will be. The original is one click away (the row's "Show original").
struct SummarisedMessage: View {
    /// The summary; nil until the first one is written.
    let text: GeneratedText?
    /// The start of the message, shown while there is no summary yet.
    var excerpt = ""
    /// A summary is wanted and not there yet, or a newer one after an edit.
    var writing = false
    /// The model is on this one now: its sparkle breathes. The others wait, still.
    var active = false
    /// A request or a question in a message that names the reader: an arrow says so.
    var forYou = false

    /// The lines the excerpt takes: what most summaries take at the rail's width. A longer
    /// sentence grows the block by a line, and the rows under it follow.
    static let heldLines = 2

    /// What was there leaves first (150 ms ease-in), then what replaces it comes (200 ms
    /// ease-out): two texts are never read through each other. Opacity only.
    private static let leaves = AnyTransition.opacity.animation(Motion.exit)
    private static let comes = AnyTransition.opacity.animation(Motion.ui.delay(0.12))
    private static let swap = AnyTransition.asymmetric(insertion: comes, removal: leaves)

    private var sentence: String? { text?.sentences.map(\.text).joined(separator: " ") }
    private var kind: String { text?.kind ?? "Summary" }
    private var pressing: Bool { text?.kind.map(MessageSummary.pressing.contains) ?? false }
    private var asked: Bool { forYou && !writing }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BreathingSparkle(on: writing && active).help(GeneratedMark.meaning)
                if asked {
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Soot.lime).help("Asked of you").transition(Self.swap)
                }
                // One word at a time: the kind takes the place of "Summarising".
                ZStack(alignment: .leading) {
                    if writing {
                        Text("Summarising").foregroundStyle(Soot.muted).transition(Self.swap)
                    } else {
                        Text(kind).foregroundStyle(pressing ? Soot.ink : Soot.muted).transition(Self.swap)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            ZStack(alignment: .topLeading) {
                if let sentence {
                    Text(sentence)
                        .font(.system(size: 14)).foregroundStyle(Soot.ink.opacity(0.92))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .id(sentence)
                        .transition(Self.swap)
                } else {
                    Text(excerpt)
                        .font(.system(size: 14)).foregroundStyle(Soot.muted)
                        .lineSpacing(3)
                        .lineLimit(Self.heldLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(Self.swap)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.line))
        .dissolveWhenReduced(value: sentence)
        .dissolveWhenReduced(value: writing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(sentence == nil ? "" : GeneratedMark.meaning)
    }

    /// What it is first, the caveat last (the hint): "Summary, Request, asked of you: …".
    private var spoken: String {
        guard let sentence else { return "Writing a summary of this message. It starts: \(excerpt.prefix(160))" }
        let head = ["Summary", text?.kind, asked ? "asked of you" : nil, writing ? "being rewritten" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        return "\(head): \(sentence)"
    }
}

/// The sparkle at the head of a summary. It breathes, in lime, on the one summary the model is
/// writing: the only loop here, and it says work is being done. Lime and still under Reduce
/// Motion; muted while a summary waits its turn and once it is written, like every other mark.
private struct BreathingSparkle: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glyph: some View {
        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
    }

    var body: some View {
        if on && !reduceMotion {
            // Computed from the clock, like `Skeleton`: an implicit animation here would also
            // catch the layout of the rows around it.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let wave = 0.5 + 0.5 * cos(context.date.timeIntervalSinceReferenceDate * .pi / 0.7)
                glyph.foregroundStyle(Soot.lime)
                    .opacity(0.45 + 0.55 * wave)
                    .scaleEffect(0.9 + 0.15 * wave)
            }
        } else {
            glyph.foregroundStyle(on ? Soot.lime : Soot.muted)
        }
    }
}

/// Once, where Dever would sum up what was missed: the Mac can run the model but it is off or
/// not ready. Dismissed for good; never shown on a Mac that cannot run it.
struct IntelligenceInvitation: View {
    @ObservedObject private var status = IntelligenceStatus.shared
    @AppStorage(IntelligencePreferences.invitationDismissedKey) private var dismissed = false

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    /// The gallery shows it whatever this Mac's state.
    var forced: IntelligenceAvailability? = nil

    private var availability: IntelligenceAvailability { forced ?? status.availability }
    private var shown: Bool {
        forced != nil || (availability.fixable && !dismissed && IntelligenceFeature.shipped.contains(.messageSummary))
    }

    var body: some View {
        if shown {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Soot.muted).padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dever can shorten long messages here, on this Mac.")
                        .font(.system(size: 13)).foregroundStyle(Soot.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ExternalLink(availability == .off ? "Turn on Apple Intelligence" : "Check Apple Intelligence",
                                 destination: Self.settingsURL, tint: .muted,
                                 font: .system(size: 12, weight: .semibold))
                        .padding(.leading, -8)
                }
                Spacer(minLength: 0)
                GlyphButton(symbol: "xmark", label: "Don't show this again", size: 24, glyphSize: 9, fill: nil) {
                    Motion.run(Motion.exit, fade: true) { dismissed = true }
                }
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Soot.line).frame(height: 1) }
            .padding(.bottom, 14)
            .transition(.opacity)
        }
    }
}

/// Generated text in each of its states, for captures (`DEVER_SNAPSHOT_GALLERY=1` with
/// `DEVER_SNAPSHOT_INTELLIGENCE` set): generated-dark.png, generated-light.png.
struct GeneratedGallery: View {
    private let sample = GeneratedText(sentences: [
        .init(text: "Answer on the front end before noon", source: "1", forYou: true),
        .init(text: "Review the migration fix", source: "3", forYou: true),
        .init(text: "The migration breaks billing for older accounts; the CSV export leaves this release.", source: "2"),
        .init(text: "Nobody has told the client about the delay yet."),
    ])

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            row("Marks") {
                HStack(spacing: 24) { GeneratedMark(); GeneratedMark(mention: true) }
            }
            row("Being written") { GeneratedBlock(text: nil, writing: true) }
            row("Written") { GeneratedBlock(text: sample, open: { _ in }) }
            row("A long message, its summary being written") {
                SummarisedMessage(text: nil, excerpt: MessageSummary.sampleExcerpt, writing: true, active: true)
            }
            row("A long message, waiting its turn") {
                SummarisedMessage(text: nil, excerpt: MessageSummary.sampleExcerpt, writing: true)
            }
            row("A long message, summarised") { SummarisedMessage(text: MessageSummary.sample) }
            row("A long message that asks something of you") { SummarisedMessage(text: MessageSummary.sampleRequest, forYou: true) }
            row("Invitation, off") { IntelligenceInvitation(forced: .off) }
            row("Invitation, not ready") { IntelligenceInvitation(forced: .notReady) }
        }
        .padding(28)
        // The rail's width at its widest, so lines break as they do there.
        .frame(width: 380, alignment: .leading)
        .background(Soot.surface)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
            content()
        }
    }
}

/// A rail of made-up messages whose summaries land one after the other, for captures of the
/// wait and of the arrival (`DEVER_SNAPSHOT_SUMMARIES=1` with `DEVER_SNAPSHOT_INTELLIGENCE=available`):
/// summaries-{dark,light}-waiting.png, -landing-0…5.png, -landed.png. No model, no network.
struct SummaryRailScene: View {
    static let channel = "SAMPLE"
    static let users = [
        "U1": SlackUser(id: "U1", name: "Ada Moreau", avatar: nil, isBot: false),
        "U2": SlackUser(id: "U2", name: "Sam Rivers", avatar: nil, isBot: false),
    ]
    private static let start = Date().timeIntervalSince1970 - 3_600

    /// Newest first, as the rail receives them: four long messages and a short one.
    static let messages: [SlackMessage] = [
        (4, "U1", "Sam, can you look at SUP-931 before the release? The export button stays disabled after a failed upload, and the only way out is a reload. I traced it to the retry state that is never cleared, the details and a recording are in the ticket. It blocks nothing today, but support has had three reports since Monday and I would rather not ship the release with it."),
        (3, "U2", "Good for me."),
        (2, "U2", "Quick update on the migration: the script ran on staging last night without errors, 41,200 accounts moved in 38 minutes. Two accounts created before 2019 have a billing address in the old format and were skipped; I fixed them by hand and added a case to the script. Production is planned for Thursday at 7:00, with the rollback ready."),
        (1, "U1", "Hello team, here is the final QA report for AI Tips. We went through the 24 criteria this morning and three of them still fail on the staging build, the rest pass. The failing ones are the empty state on a new workspace, the keyboard order in the side panel and SUP-931. The details are in the sheet, with a recording for each."),
        (0, "U2", "Welcome to the channel, everyone. This is where the release is followed day to day: what ships, what slips and what is decided. Threads for anything that needs a discussion, the weekly summary on Fridays, and the planning lives in the project linked at the top of the channel. Say hello when you have a minute, and ask anything here."),
    ].map { SlackMessage(ts: String(format: "%.6f", start + Double($0.0) * 400), user: $0.1, text: $0.2) }

    /// What the scene's model answers, by message, oldest first; nil is silence.
    private static let answers: [GeneratedText?] = [
        nil,
        MessageSummary.sample,
        GeneratedText(sentences: [.init(text: "The migration ran on staging without errors; production is planned for Thursday at 7:00.")], kind: "Update"),
        MessageSummary.sampleRequest,
    ]

    /// Asks for each summary as the page does, the newest first; they land `pace` seconds apart.
    @MainActor static func play(pace: Double = 1.5) {
        let store = IntelligenceStore.shared
        store.drop(.messageSummary)
        let long = messages.filter { MessageSummary.isSummarised($0, users: users) }
        for (index, message) in long.enumerated() {
            let answer = answers[long.count - 1 - index]
            store.want(MessageSummary.subject(channel: channel, ts: message.ts), version: "sample") {
                try await Task.sleep(nanoseconds: UInt64(pace * Double(index + 1) * 1_000_000_000))
                guard let answer else { throw IntelligenceError.unavailable }
                return answer
            }
        }
    }

    var body: some View {
        SlackThreadView(messages: Self.messages, users: Self.users, domain: nil, channelID: Self.channel,
                        railMessages: Self.messages, readUpTo: Self.messages.last?.ts)
            .padding(20)
            .frame(width: 420, alignment: .leading)
            .background(Soot.surface)
    }
}
