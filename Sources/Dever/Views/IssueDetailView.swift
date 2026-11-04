import SwiftUI

/// One Linear issue, read as a calm document: the title, a compact grid of facts (three of
/// them editable), the description, what it is linked to, and the conversation under it.
struct IssueDetailView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var store = IssueStore.shared
    @Environment(\.dismiss) private var dismiss
    let route: IssueRoute

    @State private var detail: LinearIssueDetail?
    @State private var team: LinearTeamContext?
    @State private var error: String?
    @State private var blocks: [MarkdownBlock]?
    @State private var notice: (text: String, failed: Bool)?
    @State private var noticeTask: Task<Void, Never>?

    private let measure: CGFloat = 640   // about 70 characters at 15pt

    /// The freshest row-level facts: the store's copy follows optimistic changes.
    private var row: LinearIssue? { store.row(route.issueID) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                topBar
                heading
                if let error {
                    LoadErrorRow(service: .linear, message: error) { Task { await load() } }
                } else if let detail {
                    facts(detail)
                    if let notice { noticeLine(notice) }
                    description(detail)
                    links(detail)
                    attachments(detail)
                    comments(detail)
                } else {
                    loadingBody
                }
                Color.clear.frame(height: 1).id("end")
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToEnd)) { _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .background(Soot.ground)
        .navigationTitle(route.identifier)
        .navigationBarBackButtonHidden(true)
        .windowTitleHidden()
        .task(id: route.issueID) { await load() }
        .onChange(of: store.cachedDetail(route.issueID)) { _, fresh in if let fresh { detail = fresh } }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    Text("Back")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Soot.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Soot.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Soot.edge))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modifier(FocusOutline(radius: 15))
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to the project (⌘[)")
            .accessibilityLabel("Back to the project")
            Spacer()
            if let url = URL(string: route.url) {
                Link(destination: url) { HStack(spacing: 4) { Text("Open in Linear"); Image(systemName: "arrow.up.right") } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Soot.lime)
                    .help("Open \(route.identifier) in Linear")
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandLogo(service: .linear, size: 14).foregroundStyle(Soot.muted)
                IDPill(text: route.identifier)
                if let state = row?.state ?? detail?.state { StateLabel(state: state) }
            }
            Text(detail?.title ?? route.title)
                .font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                .foregroundStyle(Soot.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Facts

    private func facts(_ d: LinearIssueDetail) -> some View {
        let current = row ?? d.asRow
        return VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    fact("Status") { statusMenu(current) }
                    fact("Priority") { priorityMenu(current) }
                }
                GridRow {
                    fact("Assignee") { assigneeMenu(current) }
                    if let due = current.dueDate {
                        fact("Due") {
                            Text(LinearDate.short(due) ?? due).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(LinearDate.isPast(due) ? Theme.negative : Soot.ink)
                        }
                    } else if let estimate = d.estimate {
                        fact("Estimate") { Text(estimate.formatted()).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink) }
                    } else {
                        fact("Created") { Text(LinearDate.short(d.createdAt) ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink) }
                    }
                }
                if !current.labelList.isEmpty {
                    GridRow {
                        fact("Labels") {
                            HStack(spacing: 4) { ForEach(current.labelList) { LabelPill(label: $0) } }
                        }
                        .gridCellColumns(2)
                    }
                }
                let extras = extraFacts(d, current: current)
                ForEach(Array(stride(from: 0, to: extras.count, by: 2)), id: \.self) { i in
                    GridRow {
                        fact(extras[i].0) { Text(extras[i].1).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink) }
                        if i + 1 < extras.count {
                            fact(extras[i + 1].0) { Text(extras[i + 1].1).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink) }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: measure, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The facts that are set, beyond the four that always show.
    private func extraFacts(_ d: LinearIssueDetail, current: LinearIssue) -> [(String, String)] {
        var out: [(String, String)] = []
        if current.dueDate != nil, let e = d.estimate { out.append(("Estimate", e.formatted())) }
        if let c = d.cycle { out.append(("Cycle", c.name ?? "Cycle \(c.number)")) }
        if let m = d.projectMilestone { out.append(("Milestone", m.name)) }
        if current.dueDate != nil || d.estimate != nil { out.append(("Created", LinearDate.short(d.createdAt) ?? "")) }
        out.append(("Updated", LinearDate.relative(current.updatedAt) ?? ""))
        return out
    }

    private func fact<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(Soot.muted).frame(width: 64, alignment: .leading)
            value()
        }
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Triage chips

    private struct Choice<T>: Identifiable { let id: String; let value: T }

    private func statusMenu(_ current: LinearIssue) -> some View {
        ChoiceChip(accessibilityLabel: "Status, \(current.state.name). Changes the issue's status",
                   items: (team?.orderedStates ?? []).map { Choice(id: $0.id, value: $0) },
                   selectedID: current.state.id) { c in
            let s = c.value
            change(current, note: "Status → \(s.name)") { row in
                row.state = LinearIssue.State(id: s.id, name: s.name, type: s.type, color: s.color)
            } request: { .init(stateID: s.id) }
        } label: {
            StateLabel(state: current.state)
        } row: { c in
            StateDot(state: .init(id: c.value.id, name: c.value.name, type: c.value.type, color: c.value.color))
            Text(c.value.name)
        }
    }

    private func priorityMenu(_ current: LinearIssue) -> some View {
        ChoiceChip(accessibilityLabel: "Priority, \(LinearPriority.label(current.priority)). Changes the issue's priority",
                   items: LinearPriority.all.map { Choice(id: String($0.value), value: $0) },
                   selectedID: String(current.priority ?? 0)) { c in
            let p = c.value
            change(current, note: "Priority → \(p.label)") { $0.priority = p.value } request: { .init(priority: p.value) }
        } label: {
            PriorityLabel(priority: current.priority)
        } row: { c in
            PriorityGlyph(priority: c.value.value, dimmed: c.value.value == 0)
            Text(c.value.label)
        }
    }

    private func assigneeMenu(_ current: LinearIssue) -> some View {
        let members = (team?.members ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = [Choice<LinearTeamContext.Member?>(id: "", value: nil)] + members.map { Choice(id: $0.id, value: $0) }
        return ChoiceChip(accessibilityLabel: "Assignee, \(current.assignee?.name ?? "unassigned"). Changes who the issue is assigned to",
                          items: items, selectedID: current.assignee?.id ?? "") { c in
            if let m = c.value {
                change(current, note: "Assigned to \(m.name)") {
                    $0.assignee = LinearIssue.Person(id: m.id, name: m.name, avatarUrl: m.avatarUrl)
                } request: { .init(assigneeID: .some(m.id)) }
            } else {
                change(current, note: "Unassigned") { $0.assignee = nil } request: { .init(assigneeID: .some(nil)) }
            }
        } label: {
            if let p = current.assignee {
                LinearAvatar(name: p.name, avatarURL: p.avatarUrl, size: 18)
                Text(p.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).lineLimit(1)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted)
                Text("Unassigned").font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.muted)
            }
        } row: { c in
            if let m = c.value {
                LinearAvatar(name: m.name, avatarURL: m.avatarUrl, size: 20)
                Text(m.name)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted).frame(width: 20)
                Text("Unassigned").foregroundStyle(Soot.muted)
            }
        }
    }

    /// Shows the new value at once, tells Linear, and puts the old value back if Linear refuses.
    private func change(_ current: LinearIssue, note: String, mutate: (inout LinearIssue) -> Void,
                        request: () -> LinearClient.IssueChange) {
        var optimistic = current
        mutate(&optimistic)
        let change = request()
        Task {
            do {
                try await store.update(current.id, change: change, optimistic: optimistic, previous: current, app: app)
                show(note, failed: false)
            } catch {
                show("Not saved: \(error.localizedDescription)", failed: true)
            }
        }
    }

    private func show(_ text: String, failed: Bool) {
        noticeTask?.cancel()
        notice = (text, failed)
        let snapshot = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_TRIAGE"] == "1"
        if snapshot { FileHandle.standardError.write(Data("triage: \(text)\n".utf8)) }
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: snapshot ? 30_000_000_000 : failed ? 8_000_000_000 : 3_500_000_000)
            if !Task.isCancelled { notice = nil }
        }
    }

    private func noticeLine(_ n: (text: String, failed: Bool)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: n.failed ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(n.text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(n.failed ? Theme.negative : Soot.lime)
        .padding(.top, -16)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Description

    @ViewBuilder
    private func description(_ d: LinearIssueDetail) -> some View {
        if let text = d.description, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let blocks {
                MarkdownView(blocks: blocks).frame(maxWidth: measure, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Skeleton(height: 12); Skeleton(width: 420, height: 12); Skeleton(width: 360, height: 12)
                }
                .frame(maxWidth: measure)
                .accessibilityElement().accessibilityLabel("Loading description")
            }
        } else {
            Text("No description").font(.system(size: 14)).foregroundStyle(Soot.muted)
        }
    }

    // MARK: Links between issues

    @ViewBuilder
    private func links(_ d: LinearIssueDetail) -> some View {
        let groups: [(String, [LinearIssueDetail.Brief])] = [
            ("Parent", d.parent.map { [$0] } ?? []),
            ("Sub-issues", d.subIssues),
            ("Blocked by", d.blockedBy),
            ("Blocks", d.blocks),
            ("Related", d.related),
        ].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { title, briefs in
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle(title, count: briefs.count > 1 ? briefs.count : nil)
                        ForEach(briefs) { b in
                            TileLink(value: IssueRoute(projectID: route.projectID, brief: b)) {
                                StateDot(state: b.state)
                                IDPill(text: b.identifier)
                                Text(b.title).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1).help(b.title)
                                Spacer(minLength: 12)
                                Text(b.state.name).font(.system(size: 12)).foregroundStyle(Soot.muted)
                                if let p = b.assignee { LinearAvatar(name: p.name, avatarURL: p.avatarUrl).help(p.name) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(12)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
            if let count { Text("\(count)").font(.system(size: 13)).foregroundStyle(Soot.muted).monospacedDigit() }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Attachments

    @ViewBuilder
    private func attachments(_ d: LinearIssueDetail) -> some View {
        let list = d.attachments?.nodes ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Attachments", count: list.count > 1 ? list.count : nil)
                ForEach(list) { a in
                    let pull = store.pullsByURL[a.url]
                    TileRow(url: URL(string: a.url)) {
                        Image(systemName: symbol(for: a, pull: pull))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(pull?.state == .merged ? Soot.lime : pull != nil ? Theme.chart2 : Soot.muted)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pull.map { PullTitle.split($0.title).title } ?? a.title ?? a.url)
                                .font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                            HStack(spacing: 6) {
                                if let pull { Text(verbatim: "#\(pull.number)"); Text("·"); Text(pull.state.label) }
                                else if let s = a.subtitle, !s.isEmpty { Text(s) }
                                else { Text(URL(string: a.url)?.host ?? "") }
                            }
                            .font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func symbol(for a: LinearIssueDetail.Attachment, pull: IssueStore.PullRef?) -> String {
        if let pull { return pull.state == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull" }
        switch a.sourceType {
        case "github": return "arrow.triangle.pull"
        case "slack": return "number"
        case "figma": return "paintbrush"
        default: return "link"
        }
    }

    // MARK: Comments

    private func comments(_ d: LinearIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Comments").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                if !d.thread.isEmpty { Text("\(d.thread.count)").font(.system(size: 14)).foregroundStyle(Soot.muted).monospacedDigit() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 14)
            if d.thread.isEmpty {
                QuietEmpty(symbol: "bubble.left", text: "No comments yet")
            } else {
                let thread = d.thread
                ForEach(Array(thread.enumerated()), id: \.element.id) { index, c in
                    let previous = index > 0 ? thread[index - 1] : nil
                    let grouped = previous.map {
                        $0.authorName == c.authorName
                            && (LinearDate.parse(c.createdAt)?.timeIntervalSince(LinearDate.parse($0.createdAt) ?? .distantPast) ?? 1e9) < 600
                    } ?? false
                    CommentRow(comment: c, grouped: grouped, reply: c.parent != nil, measure: measure)
                        .padding(.top, grouped ? 2 : (index == 0 ? 0 : 14))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Loading

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 28) {
                        HStack(spacing: 10) { Skeleton(width: 64, height: 10); Skeleton(width: 120, height: 28, radius: 7) }
                        HStack(spacing: 10) { Skeleton(width: 64, height: 10); Skeleton(width: 120, height: 28, radius: 7) }
                    }
                }
            }
            .padding(16)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Skeleton(height: 12); Skeleton(width: 480, height: 12); Skeleton(width: 420, height: 12); Skeleton(width: 300, height: 12)
            }
            .frame(maxWidth: measure)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading issue")
    }

    private func load() async {
        error = nil
        if let cached = store.cachedDetail(route.issueID), route.updatedAt == nil || cached.updatedAt == route.updatedAt {
            detail = cached
        }
        do {
            let d = try await store.detail(route.issueID, updatedAt: route.updatedAt, app: app)
            detail = d
            if let text = d.description { blocks = await store.blocks(for: text) }
            if let teamID = d.team?.id { team = try? await store.team(teamID, app: app) }
            // Snapshots: DEVER_SNAPSHOT_TRIAGE=1 writes the current priority back, to show the confirmation.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_TRIAGE"] == "1", let current = row {
                change(current, note: "Priority → \(LinearPriority.label(current.priority))") { _ in } request: { .init(priority: current.priority ?? 0) }
            }
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Comments

private struct CommentRow: View {
    @ObservedObject private var store = IssueStore.shared
    let comment: LinearIssueDetail.Comment
    let grouped: Bool
    let reply: Bool
    let measure: CGFloat
    @State private var blocks: [MarkdownBlock]?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if grouped {
                    Color.clear
                } else {
                    LinearAvatar(name: comment.authorName, avatarURL: comment.user?.avatarUrl, size: 28)
                }
            }
            .frame(width: 28, height: grouped ? 4 : 28)
            VStack(alignment: .leading, spacing: 4) {
                if !grouped {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(comment.authorName).font(.system(size: 14, weight: .bold)).foregroundStyle(Soot.ink)
                        Text(LinearDate.relative(comment.createdAt) ?? "").font(.system(size: 12)).foregroundStyle(Soot.muted)
                            .help(LinearDate.parse(comment.createdAt)?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        if comment.updatedAt != comment.createdAt {
                            Text("edited").font(.system(size: 11)).foregroundStyle(Soot.muted)
                        }
                    }
                }
                if let blocks {
                    MarkdownView(blocks: blocks, compact: true).frame(maxWidth: measure, alignment: .leading)
                } else {
                    Skeleton(width: 260, height: 12).padding(.vertical, 3)
                }
            }
        }
        .padding(.leading, reply ? 28 : 0)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hovering ? Soot.ground.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .task(id: comment.body) { blocks = await store.blocks(for: comment.body) }
    }
}

// MARK: - Markdown

/// Markdown blocks as a column: headings, paragraphs, lists, quotes, code, images, tables.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var compact = false

    private var bodySize: CGFloat { compact ? 14 : 15 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    text(block.text, size: [22, 18, 16, 15, 14, 14][min(max(level, 1), 6) - 1], weight: .semibold)
                        .padding(.top, compact ? 2 : 8)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph:
                    text(block.text, size: bodySize)
                case .quote:
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Soot.edge).frame(width: 3)
                        text(block.text, size: bodySize, color: Soot.ink.opacity(0.85))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .code:
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text)
                            .font(.system(size: bodySize - 2, design: .monospaced))
                            .foregroundStyle(Soot.ink)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.line))
                case .listItem(let ordinal, let depth, let checked):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Group {
                            if let checked {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: bodySize - 1))
                                    .foregroundStyle(checked ? Soot.lime : Soot.muted)
                                    .accessibilityLabel(checked ? "Done" : "To do")
                            } else if let ordinal {
                                Text("\(ordinal).").font(.system(size: bodySize)).foregroundStyle(Soot.muted).monospacedDigit()
                            } else {
                                Text("•").font(.system(size: bodySize)).foregroundStyle(Soot.muted)
                            }
                        }
                        .frame(minWidth: 16, alignment: .trailing)
                        text(block.text, size: bodySize, color: checked == true ? Soot.muted : Soot.ink)
                    }
                    .padding(.leading, CGFloat(max(depth - 1, 0)) * 20)
                case .image(let url, let alt):
                    LinearImage(url: url, alt: alt)
                case .rule:
                    Rectangle().fill(Soot.line).frame(height: 1).padding(.vertical, 4)
                case .tableRow(let header):
                    text(block.text, size: bodySize - 1, weight: header ? .semibold : .regular)
                        .font(.system(size: bodySize - 1, design: .monospaced))
                }
            }
        }
    }

    private func text(_ s: AttributedString, size: CGFloat, weight: Font.Weight = .regular, color: Color = Soot.ink) -> some View {
        Text(s)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .tint(Soot.lime)
            .lineSpacing(size * 0.3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A picture in a description, fetched with the Linear token (`uploads.linear.app` needs it).
private struct LinearImage: View {
    @EnvironmentObject var app: AppState
    let url: URL
    let alt: String
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Link(destination: url) {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 560, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else if failed {
                Link(destination: url) {
                    HStack(spacing: 6) { Image(systemName: "photo"); Text(alt.isEmpty ? "Image" : alt); Image(systemName: "arrow.up.right") }
                }
                .font(.system(size: 13)).foregroundStyle(Soot.lime)
            } else {
                Skeleton(width: 320, height: 160, radius: 8).accessibilityLabel("Loading image")
            }
        }
        .task(id: url) {
            let token = app.linear?.accessToken
            image = await ImageCache.shared.image(url, kind: .files, source: "linear", maxPixels: 1200) { req in
                if let token, req.url?.host?.hasSuffix("linear.app") == true {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            failed = image == nil
        }
    }
}
