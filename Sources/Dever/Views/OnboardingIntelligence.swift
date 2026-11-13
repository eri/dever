import SwiftUI

// The Intelligence stage of onboarding (docs/on-device-ai.md, section 6): what the Mac's own
// model does in Dever today, one switch per use over the same keys as Settings › Intelligence,
// and on the stage a long message and a failed pipeline that answer to the switches. While the
// model is off or not ready, the reason and the way to System Settings instead of the switches.
// On a Mac that can never run the model the stage is not part of the flow at all.

/// The uses the stage presents, in its order: those that exist in this build and have a picture.
enum OnboardingIntelligence {
    static var features: [IntelligenceFeature] {
        [.messageSummary, .explainFailure].filter(IntelligenceFeature.built.contains)
    }

    /// One short line under a use's title; the picture on the stage says the rest.
    static func detail(_ feature: IntelligenceFeature) -> String {
        switch feature {
        case .messageSummary: "One sentence in their place"
        case .explainFailure: "Why a pipeline failed, when you ask"
        default: feature.detail ?? ""
        }
    }

    static func symbol(_ feature: IntelligenceFeature) -> String {
        feature == .explainFailure ? "xmark.circle" : "text.alignleft"
    }

    /// The promise of rule 3, in the app's own words.
    static let privacy = "Runs on this Mac. Nothing leaves it."

    /// What the model's state means here, while there is nothing to switch.
    static func waiting(_ availability: IntelligenceAvailability) -> (title: String, detail: String) {
        availability == .off
            ? ("Apple Intelligence is off on this Mac", "Turn it on to use it here")
            : ("Apple Intelligence is not ready on this Mac yet", "Dever will use it once it is ready")
    }
}

struct IntelligenceControls: View {
    @ObservedObject private var status = IntelligenceStatus.shared
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                StageTag(kind: .beta)
                Headline(text: "Skip the long reads")
            }
            Group {
                if status.availability == .available {
                    VStack(spacing: 8) {
                        ForEach(OnboardingIntelligence.features) { IntelligenceChoice(feature: $0) }
                    }
                } else {
                    IntelligenceWaiting(availability: status.availability)
                }
            }
            .frame(maxWidth: 400)
            HStack(spacing: 16) {
                Button("Continue", action: next)
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .keyboardShortcut(.defaultAction)
                Label(OnboardingIntelligence.privacy, systemImage: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(Soot.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .motion(Motion.ui, fade: true, value: status.availability)
    }
}

/// One use of the model as a row that is its own switch: the whole row toggles it.
private struct IntelligenceChoice: View {
    let feature: IntelligenceFeature
    @AppStorage private var on: Bool

    init(feature: IntelligenceFeature) {
        self.feature = feature
        _on = AppStorage(wrappedValue: true, feature.settingKey)
    }

    var body: some View {
        Button { IntelligencePreferences.set(feature, on: !on) } label: {
            HStack(spacing: 12) {
                Image(systemName: OnboardingIntelligence.symbol(feature)).font(.system(size: 16))
                    .foregroundStyle(Soot.ink).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
                    Text(OnboardingIntelligence.detail(feature)).font(.system(size: 13)).foregroundStyle(Soot.muted)
                        .lineLimit(1)
                }
                Spacer()
                // Drawn by the system so it reads as a switch; the row is the control.
                Toggle(feature.title, isOn: .constant(on))
                    .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
        }
        .buttonStyle(RowButton(lift: .tone, radius: Soot.radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(feature.title). \(OnboardingIntelligence.detail(feature))")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
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
                    SummarisedMessage(text: Self.summary)
                    Text("Show original").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
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
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Soot.muted).frame(height: 16)
                        Text(Self.reason).font(.system(size: 12)).foregroundStyle(Soot.ink.opacity(0.92)).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 20)
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
