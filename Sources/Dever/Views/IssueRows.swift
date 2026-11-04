import AppKit
import SwiftUI

// Pieces of a Linear issue drawn in the soot language: state as a dot and a word, priority as
// Linear's bars, labels as small pills with their colour and name, people as avatars. Colour
// never carries meaning alone: every mark has text or an accessible name.

/// Where an issue's row leads: the issue page, with what the list already knows about it.
struct IssueRoute: Hashable {
    var projectID: UUID
    var issueID: String
    var identifier: String
    var title: String
    var url: String
    /// The list's `updatedAt`, so a cached detail can be trusted or refreshed.
    var updatedAt: String?

    init(project: Project, issue: LinearIssue) {
        projectID = project.id; issueID = issue.id; identifier = issue.identifier; title = issue.title
        url = issue.url; updatedAt = issue.updatedAt
    }

    init(projectID: UUID, brief: LinearIssueDetail.Brief) {
        self.projectID = projectID; issueID = brief.id; identifier = brief.identifier; title = brief.title
        url = brief.url; updatedAt = nil
    }
}

extension Color {
    /// "#f2c94c" or "f2c94c" → a colour; nil when the string is not a hex triplet.
    init?(linearHex string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Linear's state colour as a dot, with the name beside it where there is room.
struct StateDot: View {
    let state: LinearIssue.State
    var size: CGFloat = 9
    var body: some View {
        let color = state.color.flatMap(Color.init(linearHex:)) ?? Soot.muted
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.5)
            switch state.type {
            case "completed": Circle().fill(color).padding(1.5)
            case "started": Circle().trim(from: 0, to: 0.5).fill(color).padding(2).rotationEffect(.degrees(-90))
            case "canceled": Image(systemName: "xmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(color)
            default: EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StateLabel: View {
    let state: LinearIssue.State
    var body: some View {
        HStack(spacing: 6) {
            StateDot(state: state)
            Text(state.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(state.name)")
    }
}

/// Linear's priority as its bars: one to three filled, an exclamation for urgent, dashes for none.
struct PriorityGlyph: View {
    let priority: Int?
    var size: CGFloat = 12
    var dimmed = false

    private var level: Int { priority ?? 0 }

    var body: some View {
        let ink = dimmed ? Soot.muted : Soot.ink
        Group {
            if level == 1 {
                Image(systemName: "exclamationmark.square.fill")
                    .font(.system(size: size + 1, weight: .semibold))
                    .foregroundStyle(Theme.chart3)
            } else {
                HStack(alignment: .bottom, spacing: size * 0.15) {
                    ForEach(0..<3, id: \.self) { i in
                        let filled = level != 0 && i < (5 - level)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(filled ? ink : Soot.muted.opacity(level == 0 ? 0.6 : 0.35))
                            .frame(width: size * 0.22, height: size * (0.4 + 0.3 * CGFloat(i)))
                    }
                }
            }
        }
        .frame(width: size + 2, height: size + 2)
        .accessibilityHidden(true)
    }
}

struct PriorityLabel: View {
    let priority: Int?
    var body: some View {
        HStack(spacing: 6) {
            PriorityGlyph(priority: priority)
            Text(LinearPriority.label(priority)).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Priority: \(LinearPriority.label(priority))")
    }
}

/// A label as a small pill: its colour as a dot, its name in ink on a faint tint of the colour.
struct LabelPill: View {
    let label: LinearIssue.Label
    var body: some View {
        let color = Color(linearHex: label.color) ?? Soot.muted
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Label: \(label.name)")
    }
}

/// A Linear member's picture from the shared cache, or their initial on a tint.
struct LinearAvatar: View {
    @EnvironmentObject var app: AppState
    let name: String
    var avatarURL: String?
    var size: CGFloat = 22
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PersonTint.color(for: name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: avatarURL) {
            guard let avatarURL, let url = URL(string: avatarURL) else { image = nil; return }
            let token = app.linear?.accessToken
            image = await ImageCache.shared.image(url, kind: .avatars, source: "linear", maxPixels: Int(size * 2.5)) { req in
                if let token, req.url?.host?.hasSuffix("linear.app") == true {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
        }
    }
}

/// Dates Linear sends: ISO 8601 with fractions ("2026-11-04T09:12:33.123Z") or a plain day.
enum LinearDate {
    private static let full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return full.date(from: s) ?? plain.date(from: s) ?? day.date(from: s)
    }

    /// "Nov 12", "Mar 3, 2027" when in another year.
    static func short(_ s: String?) -> String? {
        guard let d = parse(s) else { return nil }
        let sameYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
        return sameYear ? d.formatted(.dateTime.month(.abbreviated).day())
            : d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func relative(_ s: String?) -> String? {
        parse(s).map { $0.formatted(.relative(presentation: .named)) }
    }

    static func isPast(_ day: String?) -> Bool {
        guard let d = parse(day) else { return false }
        return d < Calendar.current.startOfDay(for: Date())
    }
}

/// Due date as a short date; red when it has passed.
struct DueDateText: View {
    let dueDate: String?
    var body: some View {
        if let text = LinearDate.short(dueDate) {
            let late = LinearDate.isPast(dueDate)
            HStack(spacing: 4) {
                Image(systemName: late ? "calendar.badge.exclamationmark" : "calendar").font(.system(size: 11))
                Text(text)
            }
            .font(.system(size: 12, weight: late ? .semibold : .regular))
            .foregroundStyle(late ? Theme.negative : Soot.muted)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(late ? "Due \(text), overdue" : "Due \(text)")
        }
    }
}

/// One issue in the project page's list: priority, identifier, title, labels, due date, assignee.
struct IssueRow: View {
    let issue: LinearIssue
    var body: some View {
        PriorityGlyph(priority: issue.priority, dimmed: issue.priority == nil || issue.priority == 0)
            .help(LinearPriority.label(issue.priority))
        IDPill(text: issue.identifier)
        Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
            .help(issue.title)
            .layoutPriority(1)
        Spacer(minLength: 12)
        DueDateText(dueDate: issue.dueDate)
        if let person = issue.assignee {
            LinearAvatar(name: person.name, avatarURL: person.avatarUrl).help(person.name)
                .accessibilityLabel("Assigned to \(person.name)")
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted)
                .help("Unassigned").accessibilityLabel("Unassigned")
        }
    }
}

/// A row that pushes a destination instead of opening a URL: same tile, same hover.
struct TileLink<Value: Hashable, Content: View>: View {
    let value: Value
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) { content() }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(hovering ? Soot.ground.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 8))
        .onHover { hovering = $0 }
    }
}

extension Notification.Name {
    /// Pushes an issue page; `object` is an `IssueRoute`.
    static let openIssue = Notification.Name("dever.openIssue")
    /// Asks the project page to open its first listed issue (snapshots).
    static let openFirstIssue = Notification.Name("dever.openFirstIssue")
}

/// A chip that opens a short list of choices in a popover: the one place the issue page
/// changes something. Menus on macOS keep only a label's text, so the chip draws its own.
struct ChoiceChip<Label: View, Item: Identifiable, Row: View>: View {
    let accessibilityLabel: String
    let items: [Item]
    let selectedID: Item.ID?
    let choose: (Item) -> Void
    @ViewBuilder var label: () -> Label
    @ViewBuilder var row: (Item) -> Row
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                label()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering || open ? Soot.surface.opacity(0.7) : Soot.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(open ? Soot.lime : Soot.edge))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 8))
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_CHOICE=Status|Priority|Assignee opens that chip.
            if let want = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_CHOICE"], accessibilityLabel.hasPrefix(want) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { open = true }
            }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        Text("Loading…").font(.system(size: 13)).foregroundStyle(Soot.muted).padding(12)
                    }
                    ForEach(items) { item in
                        ChoiceRow(selected: item.id == selectedID) { choose(item); open = false } content: { row(item) }
                    }
                }
                .padding(6)
            }
            .frame(width: 260)
            .frame(maxHeight: 360)
            .background(Soot.ground)
        }
    }
}

private struct ChoiceRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content()
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Soot.lime)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Soot.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Soot.surface : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .modifier(FocusOutline(radius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension Notification.Name {
    /// Scrolls the issue page to its end (snapshots).
    static let scrollToEnd = Notification.Name("dever.scrollToEnd")
}

/// A text link with a hover state: a faint pill behind it, no motion. `hoverTint` is the tone
/// one step from the surface it sits on (ground on a panel, surface on the page).
struct HoverLink<Label: View>: View {
    let destination: URL
    var hoverTint: Color = Soot.ground
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Link(destination: destination) {
            label()
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(hovering ? hoverTint.opacity(0.85) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 14))
        .onHover { hovering = $0 }
    }
}

/// A chip that copies a value (the issue's branch name) and says so for a moment.
struct CopyChip: View {
    let value: String
    let what: String
    var maxWidth: CGFloat = 240
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            Task { try? await Task.sleep(nanoseconds: 1_600_000_000); copied = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(copied ? Soot.lime : Soot.muted)
                Text(copied ? "Copied" : value)
                    .font(.system(size: 12, weight: .medium, design: copied ? .default : .monospaced))
                    .foregroundStyle(Soot.ink).lineLimit(1).truncationMode(.middle).frame(maxWidth: maxWidth)
                Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .semibold)).foregroundStyle(Soot.muted)
                    .opacity(hovering && !copied ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hovering ? Soot.edge : Soot.edge.opacity(0.5)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .modifier(FocusOutline(radius: 8))
        .onHover { hovering = $0 }
        .help("Copy the \(what): \(value)")
        .accessibilityLabel(copied ? "\(what) copied" : "Copy the \(what)")
    }
}

/// Inline styling of Linear's Markdown: code in a soft peach monospace on the ground tone,
/// links in lime and underlined. The peach is warm and quiet on purpose: blue or green would
/// read as a link, and only links open.
enum MarkdownTheme {
    /// Code, inline and in blocks: 11.6:1 on dark ground, 6.2:1 on light ground.
    static let code = Color(light: 0x8A4A2C, dark: 0xE9C2A6)

    static func style(_ text: AttributedString, size: CGFloat) -> AttributedString {
        var out = text
        for run in out.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                out[run.range].font = .system(size: size - 1.5, weight: .medium, design: .monospaced)
                out[run.range].backgroundColor = Soot.ground
                out[run.range].foregroundColor = code
            }
            if run.link != nil {
                out[run.range].foregroundColor = Soot.lime
                out[run.range].underlineStyle = .single
            }
        }
        return out
    }

    /// A one-line string (a title) with its inline Markdown rendered.
    static func inline(_ raw: String, size: CGFloat) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return style((try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw), size: size)
    }
}
