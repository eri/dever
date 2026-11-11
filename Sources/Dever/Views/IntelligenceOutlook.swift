import SwiftUI

// How Intelligence is presented as a product (docs/on-device-ai.md, section 6): what exists is
// marked Beta, what is coming is a picture, not a control. Nothing here calls a model.

/// A small word beside a title: "Beta" in lime where a feature exists and is still being proven,
/// "Coming soon" in muted ink where it does not exist yet. Text, not a control.
struct StageTag: View {
    enum Kind { case beta, comingSoon }
    let kind: Kind

    private var word: String { kind == .beta ? "Beta" : "Coming soon" }
    private var tint: Color { kind == .beta ? Soot.lime : Soot.muted }

    var body: some View {
        Text(word)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).frame(height: 20)
            .overlay(Capsule().strokeBorder(tint.opacity(0.55)))
            .help(kind == .beta ? IntelligenceFeature.betaMeaning : "Not in Dever yet")
            .accessibilityLabel(kind == .beta ? "Beta. \(IntelligenceFeature.betaMeaning)" : word)
    }
}

/// The announcement of the local model: a dashed frame (a place kept, not a control), the tag, one
/// title and why, three small pictures of what it will do, and its terms. Nothing in it can be clicked.
struct ComingSoonBlock: View {
    /// This Mac shortens messages with Apple's model today (or would, once it is on).
    var today = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(LocalModelOutlook.title).font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(Soot.ink)
                StageTag(kind: .comingSoon)
            }
            .padding(.bottom, 6)
            Text(LocalModelOutlook.reason(today: today)).font(.system(size: 13)).foregroundStyle(Soot.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
            HStack(alignment: .top, spacing: 20) {
                ForEach(LocalModelOutlook.Promise.allCases) { promise in
                    VStack(alignment: .leading, spacing: 12) {
                        PromisePicture(promise: promise)
                        Text(promise.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 20)
            HStack(spacing: 16) {
                ForEach(LocalModelOutlook.terms.indices, id: \.self) { index in
                    Label(LocalModelOutlook.terms[index], systemImage: Self.termSymbols[index]).labelStyle(TermLabel())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Soot.edge.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let promises = LocalModelOutlook.Promise.allCases.map(\.rawValue).joined(separator: "; ")
        let terms = LocalModelOutlook.terms.joined(separator: ". ")
        return "Coming soon. \(LocalModelOutlook.title). \(LocalModelOutlook.reason(today: today)) \(promises). \(terms)."
    }

    private static let termSymbols = ["laptopcomputer", "lock"]
}

private struct TermLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .medium))
            configuration.title.font(.system(size: 12))
        }
        .foregroundStyle(Soot.muted)
        .lineLimit(1)
    }
}

/// One promise drawn in the app's own shapes: the raw thing above (messages, an issue's text, a
/// pipeline's jobs) in hairline tones, and under it what the model will write, behind the sparkle.
private struct PromisePicture: View {
    let promise: LocalModelOutlook.Promise

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            raw.frame(height: 46, alignment: .top)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Soot.lime)
                VStack(alignment: .leading, spacing: 5) {
                    bar(width: 92, tone: Soot.ink.opacity(0.55))
                    bar(width: 58, tone: Soot.ink.opacity(0.55))
                }
                .padding(.top, 3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var raw: some View {
        switch promise {
        case .channel:
            // A conversation: people (three tints) and their bubbles, of uneven length.
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(zip([Theme.chart1, Theme.chart3, Theme.chart2], [92, 58, 110]).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        Circle().fill(row.0).frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 6).fill(Soot.edge.opacity(0.3))
                            .frame(width: CGFloat(row.1), height: 12)
                    }
                }
            }
        case .issue:
            // A ticket: its state and identifier, a title, then a paragraph that runs the full width.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.chart3)
                    RoundedRectangle(cornerRadius: 2).strokeBorder(Soot.edge.opacity(0.7)).frame(width: 30, height: 9)
                }
                bar(width: 104, tone: Soot.edge.opacity(0.8), height: 7)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { line in
                        Rectangle().fill(Soot.edge.opacity(0.3)).frame(height: 3)
                            .frame(maxWidth: line == 2 ? 70 : .infinity, alignment: .leading)
                    }
                }
            }
        case .pipeline:
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { step in
                    if step > 0 { Rectangle().fill(Soot.edge.opacity(0.4)).frame(width: 14, height: 1) }
                    Image(systemName: step == 3 ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(step == 3 ? Theme.negative : Soot.edge.opacity(0.6))
                }
            }
            .frame(height: 46)
        }
    }

    private func bar(width: CGFloat, tone: Color, height: CGFloat = 5) -> some View {
        Capsule().fill(tone).frame(width: width, height: height)
    }
}
