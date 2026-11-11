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
        forced != nil || (availability.fixable && !dismissed && IntelligenceFeature.shipped.contains(.catchUp))
    }

    var body: some View {
        if shown {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Soot.muted).padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dever can sum up what you missed here, on this Mac.")
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
        .init(text: "Your answer on the front end is awaited before noon.", source: "1", forYou: true),
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
            row("Invitation, off") { IntelligenceInvitation(forced: .off) }
            row("Invitation, not ready") { IntelligenceInvitation(forced: .notReady) }
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .background(Soot.surface)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
            content()
        }
    }
}
