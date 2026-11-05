import SwiftUI

// Building blocks of the project page, in the soot language: rows that are rounded tiles,
// identifiers as pills, people as tinted initials, groups as tabs instead of stacked lists.

/// A stable pale tint per person, so each author or assignee is recognisable at a glance.
enum PersonTint {
    static func color(for id: String) -> Color {
        let hues: [Double] = [0.02, 0.10, 0.30, 0.45, 0.55, 0.62, 0.80, 0.92]
        let index = abs(id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % hues.count
        return Color(hue: hues[index], saturation: 0.45, brightness: 0.85)
    }
}

struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 22
    /// When the person is a Slack member, their real picture replaces the initial.
    var slackUser: SlackUser? = nil
    var body: some View {
        if slackUser?.avatar != nil {
            SlackAvatar(user: slackUser, name: name, size: size, radius: size / 2)
        } else {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: size, height: size)
                .background(PersonTint.color(for: name), in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// Panel title: the tool's logo, a name, one quiet line, and an "Open ↗" to the tool.
struct PanelHeader: View {
    var service: ServiceKind?
    let title: String
    var subtitle: String?
    var link: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let service { BrandLogo(service: service, size: 18).foregroundStyle(Soot.ink) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Soot.muted) }
            }
            Spacer()
            if let link {
                HoverLink(destination: link) {
                    HStack(spacing: 4) { Text("Open"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Soot.lime)
                }
                .padding(.trailing, -8)
            }
        }
    }
}

/// An identifier (INA-1050, #4872) as a small monospaced pill.
struct IDPill: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Soot.muted)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Soot.ground, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A row that is a tile: hover lifts it a tone, a click opens `url`.
struct TileRow<Content: View>: View {
    var url: URL?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        let row = HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(hovering ? Soot.ground.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        if let url {
            Link(destination: url) { row }.buttonStyle(.plain).modifier(FocusOutline(radius: 8))
        } else {
            row
        }
    }
}

/// Tabs with counts; empty tabs are left out. `dot` gives a tab the colour it has in a
/// chart, so the legend of a bar can be its filter.
struct CountTabs<Tab: Hashable>: View {
    let tabs: [(label: String, count: Int, tab: Tab)]
    @Binding var selection: Tab
    var dot: (Tab) -> Color? = { _ in nil }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.tab) { t in
                let on = t.tab == selection
                Button { selection = t.tab } label: {
                    HStack(spacing: 6) {
                        if let tint = dot(t.tab) {
                            Circle().fill(tint).frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(on ? Soot.limeInk.opacity(0.4) : Soot.edge, lineWidth: 1))
                        }
                        Text(t.label)
                        Text("\(t.count)").monospacedDigit().foregroundStyle(on ? Soot.limeInk.opacity(0.7) : Soot.muted)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(on ? Soot.lime : Soot.ground, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.clear : Soot.edge))
                }
                .buttonStyle(.plain)
                .modifier(FocusOutline(radius: 15))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// "Show all 15" under a capped list.
struct ShowAllButton: View {
    let count: Int
    @Binding var expanded: Bool
    var body: some View {
        Button(expanded ? "Show fewer" : "Show all \(count)") { expanded.toggle() }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Soot.lime)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering ? Soot.ground.opacity(0.85) : Color.clear, in: Capsule())
            .contentShape(Capsule())
            .modifier(FocusOutline(radius: 14))
            .onHover { hovering = $0 }
            .padding(.leading, 4)
            .padding(.top, 2)
    }
    @State private var hovering = false
}

/// One line of the empty state inside a panel.
struct QuietEmpty: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .font(.system(size: 14))
            .foregroundStyle(Soot.muted)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
    }
}

/// A pull request title split into what changed and its conventional prefix:
/// "feat(back-office): sync tips… [INA-1050]" → ("Sync tips…", "feat · back-office").
enum PullTitle {
    static func split(_ raw: String) -> (title: String, kind: String?) {
        var title = raw.replacingOccurrences(of: #"\s*\[[A-Za-z][A-Za-z0-9]*-\d+\]\s*$"#, with: "", options: .regularExpression)
        var kind: String?
        if let m = title.range(of: #"^([a-z]+)(\(([^)]+)\))?!?:\s*"#, options: .regularExpression) {
            let head = String(title[m]).trimmingCharacters(in: CharacterSet(charactersIn: ": !"))
            let parts = head.replacingOccurrences(of: ")", with: "").split(separator: "(")
            kind = parts.joined(separator: " · ")
            title = String(title[m.upperBound...])
        }
        if let first = title.first { title = first.uppercased() + title.dropFirst() }
        return (title, kind)
    }
}

/// The state of a pipeline run as a glyph with its word: shape and colour together.
struct PipelineGlyph: View {
    let state: ProjectSnapshot.PipelineState
    var body: some View {
        let (symbol, tint, word): (String, Color, String) = switch state {
        case .passing: ("checkmark.circle.fill", Theme.positive, "passing")
        case .failing: ("xmark.circle.fill", Theme.negative, "failing")
        case .running: ("clock.fill", Theme.chart2, "running")
        case .unknown: ("circle.dashed", Soot.muted, "no runs")
        }
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            .accessibilityLabel("Pipeline \(word)")
    }
}
