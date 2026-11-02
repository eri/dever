import SwiftUI

// Shared building blocks. Status is always carried by an icon and a label, never by
// color alone, and colored glyphs sit next to primary/secondary text so contrast
// stays readable in both light and dark mode.

extension ProjectStatus {
    var tint: Color {
        switch self {
        case .needsAttention: .red
        case .quiet: .orange
        case .onTrack: .green
        case .incomplete, .loading: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .needsAttention: "exclamationmark.octagon.fill"
        case .quiet: "moon.zzz.fill"
        case .onTrack: "checkmark.circle.fill"
        case .incomplete: "circle.dashed"
        case .loading: "circle.dotted"
        }
    }
}

/// Icon + label status badge.
struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).foregroundStyle(status.tint)
            Text(status.label).foregroundStyle(.primary)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

/// Pipeline state as icon + label.
struct PipelineBadge: View {
    let state: ProjectSnapshot.PipelineState

    var body: some View {
        let (text, color, symbol): (String, Color, String) = switch state {
        case .passing: ("Passing", .green, "checkmark.circle.fill")
        case .failing: ("Failing", .red, "xmark.octagon.fill")
        case .running: ("Running", .orange, "clock.fill")
        case .unknown: ("No runs", .secondary, "minus.circle")
        }
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pipeline: \(text)")
    }
}

/// A titled surface that groups one area of a screen.
struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, symbol: String,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                accessory()
            }
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surface()
    }
}

/// Elevated surface: layered shadow for depth instead of a border.
struct Surface: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                // Hairline only for structure in dark mode and the keyboard/hover highlight.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: highlighted ? 2 : 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(highlighted ? 0.10 : 0.04), radius: highlighted ? 10 : 6, y: 3)
    }
}

extension View {
    func surface(highlighted: Bool = false) -> some View { modifier(Surface(highlighted: highlighted)) }
}

/// Plain button that scales to 0.96 when pressed (no scale under Reduce Motion).
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A failed load, with the reason and a way to recover.
struct LoadErrorRow: View {
    let service: ServiceKind
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Couldn't load \(service.label) data. \(message)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if let retry { Button("Try again", action: retry) }
                OpenAccountsButton(service: service)
            }
            .controlSize(.small)
        }
        .font(.callout)
    }
}

/// Sends the user to the Accounts screen, where a service can be reconnected.
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

/// Empty state for a section: what belongs here and what to do next.
struct EmptySection: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.medium))
            Text(message).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Inline error: icon plus readable text (red text alone fails contrast and relies on color).
struct ErrorLabel: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
    }
}
