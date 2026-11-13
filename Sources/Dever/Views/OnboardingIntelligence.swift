import SwiftUI

// The Intelligence stage of onboarding (docs/on-device-ai.md, section 6): one question, whether
// Dever uses the model built into the Mac. It says whose model it is (Apple Intelligence), what
// it does here, and what it costs (nothing to install, nothing leaves the Mac); two rows answer
// it, on or off, over the same keys as Settings › Intelligence, and on the stage a long message
// and a failed pipeline show the answer. While the model is off or not ready, the reason and the
// way to System Settings instead of the rows. On a Mac that can never run the model the stage
// is not part of the flow at all.

/// The uses the stage presents, in its order: those that exist in this build and have a picture.
enum OnboardingIntelligence {
    static var features: [IntelligenceFeature] {
        [.messageSummary, .explainFailure].filter(IntelligenceFeature.built.contains)
    }

    /// What the stage asks, above its headline.
    static let name = "Enable Local Intelligence"

    /// Whose model it is and what it does here, in one sentence.
    static let lead = "Apple Intelligence, the model built into your Mac, sums up long messages and explains failed pipelines."

    /// What turning it on gives, under the row that does.
    static let onDetail = "Long messages summed up, failures explained"
    static let offDetail = "Turn it on any time in Settings"

    /// What it costs, as short facts with a glyph each. "Nothing to install" only while the
    /// model is there: off or not ready, the system may still have it to fetch. Never a word
    /// on speed or power: a summary keeps the Mac's chip busy for a second or three.
    static func terms(_ availability: IntelligenceAvailability) -> [(symbol: String, text: String)] {
        var terms = [("cpu", "Runs on your Mac's own chip"), ("lock", "Nothing leaves it")]
        if availability == .available { terms.append(("checkmark.circle", "Nothing to install")) }
        return terms
    }

    /// What the model's state means here, while there is nothing to switch.
    static func waiting(_ availability: IntelligenceAvailability) -> (title: String, detail: String) {
        availability == .off
            ? ("Apple Intelligence is off on this Mac", "Turn it on to use it here")
            : ("Apple Intelligence is not ready on this Mac yet", "Dever will use it once it is ready")
    }
}

struct IntelligenceControls: View {
    @ObservedObject private var status = IntelligenceStatus.shared
    @AppStorage(IntelligenceFeature.messageSummary.settingKey) private var summaries = true
    @AppStorage(IntelligenceFeature.explainFailure.settingKey) private var failures = true
    let next: () -> Void

    /// On while any of its uses is: Settings can switch them one by one.
    private var on: Bool {
        OnboardingIntelligence.features.contains { $0 == .messageSummary ? summaries : failures }
    }

    /// The answer, written at once to the keys Settings reads, every use together.
    private func choose(_ value: Bool) {
        for feature in OnboardingIntelligence.features { IntelligencePreferences.set(feature, on: value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // The sparkle is the mark every generated text carries in the app, here lit and alive.
            StageHead(eyebrow: OnboardingIntelligence.name, symbol: "sparkles", title: "Skip the long reads",
                      lead: OnboardingIntelligence.lead, twinkles: true, beta: true)
            Group {
                if status.availability == .available {
                    VStack(spacing: 8) {
                        choice(selected: on, title: "Turn it on", tag: "Recommended",
                               detail: OnboardingIntelligence.onDetail) { choose(true) }
                        choice(selected: !on, title: "Not now", tag: nil,
                               detail: OnboardingIntelligence.offDetail) { choose(false) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Local Intelligence")
                } else {
                    IntelligenceWaiting(availability: status.availability)
                }
            }
            .frame(maxWidth: 400)
            terms
            Button("Continue", action: next)
                .buttonStyle(PrimaryButton(size: .sheet))
                .keyboardShortcut(.defaultAction)
        }
        .motion(Motion.ui, fade: true, value: status.availability)
    }

    /// The facts on one line where they fit, one under the other where they do not.
    private var terms: some View {
        let labels = ForEach(OnboardingIntelligence.terms(status.availability), id: \.text) { term in
            HStack(spacing: 6) {
                Image(systemName: term.symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                    .accessibilityHidden(true)
                Text(term.text).font(.system(size: 13)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Soot.muted)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { labels }
            VStack(alignment: .leading, spacing: 6) { labels }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    /// One of the two answers, as the channel-naming stage draws its own: a ring, the title,
    /// one short line, a lime edge on the one that holds.
    private func choice(selected: Bool, title: String, tag: String?, detail: String, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                CheckCircle(on: selected).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
                        if let tag {
                            Text(tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.lime)
                        }
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(selected ? Soot.lime.opacity(0.5) : .clear))
        }
        .buttonStyle(RowButton(lift: .tone, radius: Soot.radius))
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The model is off or not there yet: what that means here, and where to change it.
private struct IntelligenceWaiting: View {
    let availability: IntelligenceAvailability

    var body: some View {
        let words = OnboardingIntelligence.waiting(availability)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Soot.muted)
                .frame(width: 22).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(words.title).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(words.detail).font(.system(size: 13)).foregroundStyle(Soot.muted)
                ExternalLink("Open System Settings", destination: IntelligenceInvitation.settingsURL, lift: Soot.surface)
                    .padding(.leading, -8).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
    }
}

// MARK: - The stage: a long message and a failed pipeline, as the switches leave them

/// A crop of a project page in Dever's own shapes, with made-up content: on the left a long
/// message of the rail, as its summary or cut as before; on the right a failed pipeline, with
/// its card and the generated sentence or as the plain state. The same size as the window crop
/// of the other stages, so the stage frames it the same way.
struct IntelligencePicture: View {
    @AppStorage(IntelligenceFeature.messageSummary.settingKey) private var summaries = true
    @AppStorage(IntelligenceFeature.explainFailure.settingKey) private var failures = true

    private static let long = "Here is the final QA report for the checkout. We went through the 24 criteria this morning and three of them still fail on the staging build, the rest pass. The failing ones are the empty state on a new workspace, the keyboard order in the side panel and the export button."
    private static let summary = GeneratedText(sentences: [
        .init(text: "The checkout QA report passes 21 of 24 criteria; three still fail on staging.")
    ], kind: "Problem")
    private static let reason = "19.97 was not equal to 19.98 in tests/test_billing.py"

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rail.frame(width: 320)
            Rectangle().fill(Soot.line).frame(width: 1)
            pipeline.frame(width: 360)
        }
        .frame(height: 380)
        .background(Soot.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .motion(Motion.ui, fade: true, value: summaries)
        .motion(Motion.ui, fade: true, value: failures)
        .allowsHitTesting(false)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("#proj-checkout").font(Theme.smallStrong).foregroundStyle(Soot.muted)
            message(initial: "A", tint: Theme.chart1, name: "Ada", time: "9:41") {
                if summaries {
                    // Before and after: the message as it came, dimmed, then what the Mac wrote of it.
                    Text(Self.long).font(.system(size: 13)).foregroundStyle(Soot.muted.opacity(0.6))
                        .lineSpacing(2).lineLimit(3)
                    written("Summed up by your Mac")
                    SummarisedMessage(text: Self.summary).modifier(Lit())
                } else {
                    Text(Self.long).font(.system(size: 14)).foregroundStyle(Soot.ink.opacity(0.92))
                        .lineSpacing(3).lineLimit(4)
                    Text("Show more").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                }
            }
            message(initial: "S", tint: Theme.chart3, name: "Sam", time: "9:44") {
                Text("Good for me.").font(.system(size: 14)).foregroundStyle(Soot.ink.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message<Content: View>(initial: String, tint: Color, name: String, time: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(initial).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name).font(Theme.bodyStrong).foregroundStyle(Soot.ink)
                    Text(time).font(Theme.small).foregroundStyle(Soot.muted)
                }
                content()
            }
        }
    }

    /// Says which part of the picture the Mac wrote: the sparkle, lit, and a few words.
    private func written(_ words: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).modifier(Twinkle())
            Text(words).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Soot.lime)
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start here").font(Theme.smallStrong).foregroundStyle(Soot.muted).padding(.bottom, 6)
            Text("Round totals per line, not per order").font(Theme.bodyStrong).foregroundStyle(Soot.ink).lineLimit(1)
            HStack(spacing: 6) {
                PipelineGlyph(state: .failing)
                Text("CI failed on #128").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                if failures {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Soot.muted)
                }
            }
            if failures {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Failed 12m ago").font(.system(size: 12)).foregroundStyle(Soot.muted)
                    Rectangle().fill(Soot.line).frame(height: 1)
                    HStack(spacing: 6) {
                        PipelineGlyph(state: .failing)
                        Text("test › Run unit tests").font(.system(size: 12)).foregroundStyle(Soot.ink)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        written("Explained by your Mac")
                        Text(Self.reason).font(.system(size: 13)).foregroundStyle(Soot.ink).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Soot.surface, in: RoundedRectangle(cornerRadius: 8))
                    .modifier(Lit())
                    Text("1 failing · 17 passing").font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                .padding(12)
                .frame(width: 300, alignment: .leading)
                .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Sparkles

/// A sparkle that breathes: it dims and shrinks a little, then comes back, every 2.4 s. Still
/// and full under Reduce Motion. Computed from the clock, like `Skeleton`, so it animates
/// nothing around it.
struct Twinkle: ViewModifier {
    /// Where in its cycle this one starts, 0 to 1, so that neighbours do not pulse together.
    var phase: Double = 0
    /// Off: the content is drawn as it is.
    var on = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !on)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 2.4 + phase
            let wave = reduceMotion || !on ? 1 : 0.5 + 0.5 * cos(t * 2 * .pi)
            content.opacity(0.6 + 0.4 * wave).scaleEffect(0.86 + 0.14 * wave)
        }
    }
}

/// What the Mac wrote, in the picture: a lime edge and a soft lime light around it.
private struct Lit: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime.opacity(0.7)))
            .shadow(color: Soot.lime.opacity(0.28), radius: 10)
    }
}

/// Sparkles on the lime stage, around the picture: large, in the ground's ink, each on its own
/// beat. Decoration only.
struct SparkleField: View {
    private static let marks: [(x: CGFloat, y: CGFloat, size: CGFloat, phase: Double)] = [
        (0.13, 0.13, 64, 0), (0.30, 0.07, 24, 0.4), (0.80, 0.16, 40, 0.7),
        (0.60, 0.90, 52, 0.2), (0.22, 0.88, 28, 0.55), (0.90, 0.82, 22, 0.85),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Self.marks.indices, id: \.self) { index in
                let mark = Self.marks[index]
                Image(systemName: "sparkle").font(.system(size: mark.size, weight: .semibold))
                    .foregroundStyle(Soot.limeInk.opacity(0.22))
                    .modifier(Twinkle(phase: mark.phase))
                    .position(x: geo.size.width * mark.x, y: geo.size.height * mark.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
