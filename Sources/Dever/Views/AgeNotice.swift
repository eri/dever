import SwiftUI

/// One quiet line for data that is not current: which tool, since when, and why when a refresh
/// failed. What is on screen stays; this says how old it is (docs/data-freshness.md, section 3.6).
struct AgeNotice: View {
    struct Item: Identifiable {
        var service: ServiceKind
        /// The last successful read.
        var since: Date
        /// Why the latest refresh did not go through, if it did not.
        var failure: ServiceState?
        var id: String { service.rawValue }
    }

    let items: [Item]
    let refreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: items.contains { $0.failure == .offline } ? "wifi.slash" : "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Soot.muted)
                .accessibilityHidden(true)
            // The age is read off the clock, so the line stays true while it is on screen.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                Text(items.map(Self.sentence).joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Soot.muted)
                    .lineLimit(1)
            }
            if refreshing {
                Text("checking now").font(.system(size: 13)).foregroundStyle(Soot.muted)
            } else {
                Button("Check now", action: retry)
                    .buttonStyle(TertiaryButton(lift: Soot.surface, font: .system(size: 13, weight: .medium)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func sentence(_ item: Item) -> String {
        let age = item.since.formatted(.relative(presentation: .numeric))
        let read = "\(item.service.label) read \(age)"
        switch item.failure {
        case .offline?: return read + ", you're offline"
        case .failed?, .unauthorized?, .notConnected?: return read + ", couldn't refresh"
        case nil: return read
        }
    }
}
