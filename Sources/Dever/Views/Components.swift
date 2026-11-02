import SwiftUI

// Shared building blocks. Status is always carried by words, with colour as a second cue.

extension ProjectStatus {
    var tone: Pill.Tone {
        switch self {
        case .needsAttention: .negative
        case .quiet: .warning
        case .onTrack: .positive
        case .incomplete, .loading: .neutral
        }
    }

    /// Small glyph for the sidebar, where a pill would be too loud.
    var symbol: String {
        switch self {
        case .needsAttention: "exclamationmark.circle.fill"
        case .quiet: "moon.fill"
        case .onTrack: "checkmark.circle"
        case .incomplete: "circle.dashed"
        case .loading: "circle.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .needsAttention: Theme.negative
        case .quiet: Theme.chart3
        case .onTrack, .incomplete, .loading: Theme.muted
        }
    }
}

struct StatusBadge: View {
    let status: ProjectStatus
    var body: some View {
        Pill(text: status.label, tone: status.tone)
            .accessibilityLabel("Status: \(status.label)")
    }
}

/// Pipeline state as a small glyph and a word.
struct PipelineBadge: View {
    let state: ProjectSnapshot.PipelineState

    var body: some View {
        let (text, color, symbol): (String, Color, String) = switch state {
        case .passing: ("Passing", Theme.positive, "checkmark.circle.fill")
        case .failing: ("Failing", Theme.negative, "xmark.circle.fill")
        case .running: ("Running", Theme.chart2, "clock")
        case .unknown: ("No runs", Theme.muted, "")
        }
        HStack(spacing: 4) {
            if !symbol.isEmpty { Image(systemName: symbol).foregroundStyle(color).imageScale(.small) }
            Text(text).foregroundStyle(state == .failing ? Theme.negative : state == .unknown ? Theme.muted : Theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pipeline: \(text)")
    }
}

/// Dever's own chart: every issue of a project on its way to production, as one bar.
struct DeliveryStrip: View {
    let delivery: Delivery
    var height: CGFloat = 8

    static func color(_ stage: Delivery.Stage) -> Color {
        switch stage {
        case .done: Theme.chart1
        case .merged: Theme.chart3
        case .review: Theme.chart2
        case .building: Theme.idle
        case .todo: Theme.empty
        }
    }

    var body: some View {
        GeometryReader { geo in
            let stages = Delivery.Stage.allCases.filter { delivery.count($0) > 0 }
            let spacing: CGFloat = 2
            let usable = geo.size.width - spacing * CGFloat(max(stages.count - 1, 0))
            HStack(spacing: spacing) {
                if delivery.total == 0 {
                    Rectangle().fill(Theme.empty)
                } else {
                    ForEach(stages, id: \.self) { stage in
                        Rectangle()
                            .fill(Self.color(stage))
                            .frame(width: max(2, usable * CGFloat(delivery.count(stage)) / CGFloat(delivery.total)))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityElement()
        .accessibilityLabel(delivery.total == 0 ? "No issues" : Delivery.Stage.allCases
            .filter { delivery.count($0) > 0 }
            .map { "\(delivery.count($0)) \($0.label.lowercased())" }
            .joined(separator: ", "))
    }
}

/// Legend whose swatches are the strip's own marks, with counts; stages at zero are left out.
struct DeliveryLegend: View {
    let delivery: Delivery

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Delivery.Stage.allCases.filter { delivery.count($0) > 0 }, id: \.self) { stage in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(DeliveryStrip.color(stage)).frame(width: 10, height: 8)
                    Text(stage.label).foregroundStyle(Theme.muted)
                    Text(delivery.count(stage), format: .number).foregroundStyle(Theme.text).monospacedDigit()
                }
            }
        }
        .font(Theme.small)
        .accessibilityElement(children: .combine)
    }
}

/// A failed load, inside the block that failed, with a way to recover.
struct LoadErrorRow: View {
    let service: ServiceKind
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Couldn't load \(service.label) data. \(message)")
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.negative)
            }
            HStack(spacing: 12) {
                if let retry { Button("Retry", action: retry) }
                OpenAccountsButton(service: service)
            }
            .buttonStyle(.link)
        }
        .font(Theme.body)
    }
}

struct OpenAccountsButton: View {
    let service: ServiceKind
    @Environment(\.openAccounts) private var openAccounts

    var body: some View {
        Button("Open Accounts") { openAccounts() }
            .help("Check or reconnect \(service.label)")
    }
}

private struct OpenAccountsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Navigates to the Accounts screen; provided by ContentView.
    var openAccounts: () -> Void {
        get { self[OpenAccountsKey.self] }
        set { self[OpenAccountsKey.self] = newValue }
    }
}

/// Empty state inside a block: what belongs here and what to do next. Keeps the block's frame.
struct EmptySection: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
            Text(message).font(Theme.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
            .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Inline error next to the field or block it concerns.
struct ErrorLabel: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label {
            Text(message).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.negative)
        }
        .font(Theme.body)
    }
}

/// Row hover: a tone step, no motion.
struct HoverRow: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.raised : Color.clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverRow() -> some View { modifier(HoverRow()) }
}

// MARK: - Skeletons

/// Placeholder at the real size of the value it stands for, so nothing shifts when data lands.
/// Flat (no shimmer); a slow pulse says it's alive, except under Reduce Motion.
struct Skeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The pulse is computed from the clock, not animated: an implicit animation here also
        // caught the layout of a sheet as it opened and made the bars slide around.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            RoundedRectangle(cornerRadius: radius)
                .fill(Theme.empty)
                .opacity(reduceMotion ? 1 : 0.75 + 0.25 * cos(t * .pi / 0.9))
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .accessibilityHidden(true)
    }
}
struct SkeletonRows: View {
    var count = 4
    var leading: CGFloat? = 64
    var trailing: CGFloat? = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                if i > 0 { Rectangle().fill(Theme.rule).frame(height: 1) }
                HStack(spacing: 12) {
                    if let leading { Skeleton(width: leading) }
                    Skeleton().frame(maxWidth: [260, 200, 300, 230, 180, 280][i % 6])
                    Spacer(minLength: 12)
                    if let trailing { Skeleton(width: trailing) }
                }
                .frame(height: 36)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
