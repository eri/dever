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

/// Every block of the project page opens the same way: a tool's logo or a glyph in an 18 px
/// slot, the title, one quiet line, and the action on the right ("Open ↗" to the tool, or
/// whatever the block needs there). `leading` is for a control that must come before the
/// logo (the Slack room's Back), `accessory` for a pill beside the title (the preview's #number).
struct PanelHeader<Leading: View, Accessory: View, Trailing: View>: View {
    var service: ServiceKind?
    var symbol: String?
    let title: String
    var subtitle: String?
    var link: URL?
    /// What the "Open ↗" link opens, for its tooltip and its accessibility label.
    var linkHelp: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            PanelGlyph(service: service, symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soot.ink)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    accessory()
                }
                // One height with or without a pill, so every panel's title sits on the same line.
                .frame(height: 22)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 12)
            trailing()
            if let link {
                HoverLink(destination: link) {
                    HStack(spacing: 4) { Text("Open"); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Soot.lime)
                }
                .padding(.trailing, -8)
                .help(linkHelp ?? "Open in \(service?.label ?? "the browser")")
                .accessibilityLabel(linkHelp ?? "Open in \(service?.label ?? "the browser")")
            }
        }
        .frame(minHeight: 36)
    }
}

extension PanelHeader where Leading == EmptyView, Accessory == EmptyView, Trailing == EmptyView {
    init(service: ServiceKind? = nil, symbol: String? = nil, title: String, subtitle: String? = nil,
         link: URL? = nil, linkHelp: String? = nil) {
        self.init(service: service, symbol: symbol, title: title, subtitle: subtitle, link: link, linkHelp: linkHelp,
                  leading: { EmptyView() }, accessory: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension PanelHeader where Leading == EmptyView, Accessory == EmptyView {
    init(service: ServiceKind? = nil, symbol: String? = nil, title: String, subtitle: String? = nil,
         link: URL? = nil, linkHelp: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(service: service, symbol: symbol, title: title, subtitle: subtitle, link: link, linkHelp: linkHelp,
                  leading: { EmptyView() }, accessory: { EmptyView() }, trailing: trailing)
    }
}

extension PanelHeader where Leading == EmptyView {
    init(service: ServiceKind? = nil, symbol: String? = nil, title: String, subtitle: String? = nil,
         link: URL? = nil, linkHelp: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(service: service, symbol: symbol, title: title, subtitle: subtitle, link: link, linkHelp: linkHelp,
                  leading: { EmptyView() }, accessory: accessory, trailing: trailing)
    }
}

/// The 18 px slot at the head of a panel: the tool's logo, or a glyph for what is not a tool
/// (the preview's globe). Decorative: the title names the block.
struct PanelGlyph: View {
    var service: ServiceKind?
    var symbol: String?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let service {
                BrandLogo(service: service, size: size).foregroundStyle(Soot.ink)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(Soot.ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A block with nothing to show yet, in one shape for the whole page: one quiet line under the
/// panel's header, the lime action that fills the block, and at most one quiet alternative.
/// No tile and no second logo: same flat row as the connect invitation (`ConnectPanelBody`).
struct PanelEmpty: View {
    var service: ServiceKind?
    var symbol: String?
    let line: String
    let primary: (title: String, action: () -> Void)
    var quiet: (title: String, action: () -> Void)? = nil
    /// Tooltips, one per button, in the same order.
    var primaryHelp: String?
    var quietHelp: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { glyphAndLine; Spacer(minLength: 16); buttons }
            VStack(alignment: .leading, spacing: 14) { glyphAndLine; buttons }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }

    /// The line alone: the panel's header already carries the logo, and the panel is the box.
    private var glyphAndLine: some View {
        Text(line).font(.system(size: 13)).foregroundStyle(Soot.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(primary.title, action: primary.action).buttonStyle(LimeButton())
                .help(primaryHelp ?? "")
            if let quiet {
                Button(quiet.title, action: quiet.action).buttonStyle(QuietButton())
                    .help(quietHelp ?? "")
            }
        }
        .fixedSize()
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

    var body: some View {
        let row = HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
        if let url {
            Link(destination: url) { row }.buttonStyle(RowButton(lift: .ground))
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
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.tab) { t in
                let on = t.tab == selection
                // The lime pill slides to the chosen tab (spring, ~300 ms); counts roll on refresh.
                Button { Motion.run(Motion.settle) { selection = t.tab } } label: {
                    HStack(spacing: 6) {
                        if let tint = dot(t.tab) {
                            Circle().fill(tint).frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(on ? Soot.limeInk.opacity(0.4) : Soot.edge, lineWidth: 1))
                        }
                        Text(t.label)
                        Text("\(t.count)").monospacedDigit().foregroundStyle(on ? Soot.limeInk.opacity(0.8) : Soot.muted)
                            .rollingNumber(t.count)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.ink)
                    .padding(.horizontal, 12)
                    .frame(height: Buttons.chipHeight)
                    .background {
                        if on { Capsule().fill(Soot.lime).matchedGeometryEffect(id: "pill", in: marker) }
                        else { Capsule().fill(Soot.ground) }
                    }
                }
                .buttonStyle(ChipButton(on: on, drawsFill: false))
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
        // In one transaction with the rows it reveals, so the list grows instead of jumping.
        Button(expanded ? "Show fewer" : "Show all \(count)") { Motion.run(Motion.ui) { expanded.toggle() } }
            .buttonStyle(TertiaryButton())
            .padding(.leading, 4)
            .padding(.top, 2)
    }
}

/// One line of the empty state inside a panel, when there is nothing to do about it: a glyph
/// in the same 18 px slot as the panel's head, the line, a row's height.
struct QuietEmpty: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.muted)
                .frame(width: 18).accessibilityHidden(true)
            Text(text).font(.system(size: 14)).foregroundStyle(Soot.muted)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
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

/// A pull request on an issue's row: its state as a glyph (merged, open, draft), its number,
/// and the latest pipeline run of its branch when there is one. Opens the PR on GitHub.
struct PullChip: View {
    enum Kind { case merged, open, draft }
    let number: Int
    let kind: Kind
    var pipeline: ProjectSnapshot.PipelineState? = nil
    var title: String? = nil
    /// Named on the chip when the project follows several repositories.
    var repository: String? = nil
    let url: URL

    private var glyph: (symbol: String, tint: Color, word: String) {
        switch kind {
        case .merged: ("arrow.triangle.merge", Theme.chart1, "merged")
        case .open: ("arrow.triangle.pull", Theme.chart2, "open")
        case .draft: ("pencil.line", Soot.muted, "draft")
        }
    }

    private var run: (symbol: String, tint: Color, word: String)? {
        switch pipeline {
        case .passing: ("checkmark.circle.fill", Theme.positive, "pipeline passing")
        case .failing: ("xmark.circle.fill", Theme.negative, "pipeline failing")
        case .running: ("clock.fill", Theme.chart2, "pipeline running")
        default: nil
        }
    }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: glyph.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(glyph.tint)
                if let repository {
                    Text(GitHubRepository.short(repository)).font(.system(size: 11, weight: .medium)).foregroundStyle(Soot.muted)
                        .lineLimit(1)
                }
                Text(verbatim: "#\(number)").font(.system(size: 11, weight: .medium)).foregroundStyle(Soot.ink).monospacedDigit()
                if let run {
                    Image(systemName: run.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(run.tint)
                }
            }
            .padding(.horizontal, 8)
            // The same quiet capsule as the row's other pills (in QA, Staging): a filled tone,
            // no edge; a little taller, as it is the one that opens something.
            .frame(height: 22)
        }
        .buttonStyle(ChipButton(fill: Soot.ink.opacity(0.07), edge: false))
        .help([title.map { "#\(number) \($0)" } ?? "Pull request #\(number)", repository, glyph.word, run?.word].compactMap { $0 }.joined(separator: " · ") + " · Opens on GitHub")
        .accessibilityLabel(["Pull request #\(number)", repository.map { "in \($0)" }, glyph.word, run?.word].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens on GitHub")
    }
}

/// A tile that pushes a destination and carries its own links at the trailing end (the pull
/// request chips). The navigation link spans the whole row, with room reserved for the
/// trailing content; the real trailing content sits on top of it so its links take the
/// click, while the rest of it lets the click fall through to the row.
struct WorkTile<Value: Hashable, Content: View, Trailing: View>: View {
    let value: Value
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) {
                content()
                HStack(spacing: 12) { trailing() }.hidden()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
        }
        .buttonStyle(RowButton(lift: .ground))
        .overlay(alignment: .trailing) {
            HStack(spacing: 12) { trailing() }.padding(.trailing, 12)
        }
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
