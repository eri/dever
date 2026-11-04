import SwiftUI

/// One Linear issue, read as a document with a margin: the title and the facts that decide
/// what happens next on top (status, priority, assignee, due date, blockers, code), the
/// description and the conversation in the reading column, every other detail and link in
/// the side column. Below ~1120px the side column follows the text.
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

    private let measure: CGFloat = 680   // about 70 characters at 15pt, padding included
    private let aside: CGFloat = 312

    /// The freshest row-level facts: the store's copy follows optimistic changes.
    private var row: LinearIssue? { store.row(route.issueID) }

    var body: some View {
        GeometryReader { geo in
            let twoColumns = geo.size.width >= 1120
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        topBar
                        heading
                        if let error {
                            LoadErrorRow(service: .linear, message: error) { Task { await load() } }
                        } else if let detail {
                            signals(detail)
                            if let notice { noticeLine(notice) }
                            if twoColumns {
                                HStack(alignment: .top, spacing: 20) {
                                    reading(detail).frame(maxWidth: measure)
                                    sideColumn(detail).frame(width: aside)
                                }
                            } else {
                                reading(detail).frame(maxWidth: measure)
                                sideColumn(detail).frame(maxWidth: measure)
                            }
                        } else {
                            loadingBody
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: measure + 20 + aside, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(width: geo.size.width, alignment: twoColumns ? .center : .leading)
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToEnd)) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
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
            HStack(spacing: 8) {
                BrandLogo(service: .linear, size: 14).foregroundStyle(Soot.muted)
                if let key = detail?.team?.key {
                    Text(key).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                    Text("›").font(.system(size: 12)).foregroundStyle(Soot.muted)
                }
                Text(verbatim: route.identifier).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Soot.muted)
            }
            .accessibilityElement(children: .combine)
            Text(detail?.title ?? route.title)
                .font(.system(size: 30, weight: .semibold)).tracking(-0.7)
                .lineSpacing(3)
                .foregroundStyle(Soot.ink)
                .frame(maxWidth: measure + 20 + aside, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Signals: what decides the next step, each with its glyph

    private func signals(_ d: LinearIssueDetail) -> some View {
        let current = row ?? d.asRow
        let done = d.subIssues.filter { $0.state.type == "completed" }.count
        let code = (d.attachments?.nodes ?? []).compactMap { store.pullsByURL[$0.url] }
        return FlowRow(spacing: 8) {
            statusMenu(current)
            priorityMenu(current)
            assigneeMenu(current)
            if let due = current.dueDate, let text = LinearDate.short(due) {
                let late = LinearDate.isPast(due)
                signal(symbol: late ? "calendar.badge.exclamationmark" : "calendar", text: late ? "Due \(text) · late" : "Due \(text)",
                       tint: late ? Theme.negative : nil, label: late ? "Due \(text), overdue" : "Due \(text)")
            }
            if !d.blockedBy.isEmpty {
                let open = d.blockedBy.filter { $0.state.type != "completed" && $0.state.type != "canceled" }.count
                signal(symbol: "hand.raised.fill", text: open == 0 ? "Was blocked, now clear" : "Blocked by \(open)",
                       tint: open == 0 ? nil : Theme.chart3, label: open == 0 ? "No open blockers" : "Blocked by \(open) issues")
            }
            if !d.subIssues.isEmpty {
                signal(symbol: done == d.subIssues.count ? "checklist.checked" : "checklist", text: "\(done) of \(d.subIssues.count) sub-issues done",
                       tint: nil, label: "\(done) of \(d.subIssues.count) sub-issues done") {
                    MiniBar(fraction: Double(done) / Double(d.subIssues.count))
                }
            }
            ForEach(code.prefix(2), id: \.number) { pull in
                signal(symbol: pull.state == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull",
                       text: "#\(pull.number) \(pull.state.label.lowercased())",
                       tint: pull.state == .merged ? Soot.lime : Theme.chart2, label: "Pull request \(pull.number), \(pull.state.label)")
            }
        }
    }

    /// A read-only fact in the signal strip: glyph, words, optional extra.
    private func signal<Extra: View>(symbol: String, text: String, tint: Color?, label: String,
                                     @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint ?? Soot.muted)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(tint == Theme.negative ? Theme.negative : Soot.ink)
            extra()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    // MARK: Reading column

    private func reading(_ d: LinearIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            card(symbol: "doc.text", title: "Description") {
                description(d)
            }
            card(symbol: "bubble.left.and.bubble.right", title: "Comments", count: d.thread.count) {
                comments(d)
            }
        }
    }

    // MARK: Side column

    private func sideColumn(_ d: LinearIssueDetail) -> some View {
        let current = row ?? d.asRow
        return VStack(alignment: .leading, spacing: 16) {
            card(symbol: "info.circle", title: "Details") {
                VStack(alignment: .leading, spacing: 0) {
                    if !current.labelList.isEmpty {
                        detailRow(symbol: "tag", label: "Labels") {
                            FlowRow(spacing: 4) { ForEach(current.labelList) { LabelPill(label: $0) } }
                        }
                    }
                    if let e = d.estimate { detailRow(symbol: "scalemass", label: "Estimate", value: e.formatted() + (e == 1 ? " point" : " points")) }
                    if let c = d.cycle { detailRow(symbol: "arrow.triangle.2.circlepath", label: "Cycle", value: c.name ?? "Cycle \(c.number)") }
                    if let m = d.projectMilestone { detailRow(symbol: "flag", label: "Milestone", value: m.name) }
                    if let due = current.dueDate { detailRow(symbol: "calendar", label: "Due", value: LinearDate.short(due) ?? due) }
                    detailRow(symbol: "clock", label: "Created", value: LinearDate.short(d.createdAt) ?? "")
                    detailRow(symbol: "clock.arrow.circlepath", label: "Updated", value: LinearDate.relative(current.updatedAt) ?? "")
                }
            }
            linksCard(d)
            attachmentsCard(d)
        }
    }

    private func detailRow(symbol: String, label: String, value: String) -> some View {
        detailRow(symbol: symbol, label: label) {
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).multilineTextAlignment(.trailing)
        }
    }

    private func detailRow<V: View>(symbol: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                .frame(width: 16).accessibilityHidden(true)
            Text(label).font(.system(size: 13)).foregroundStyle(Soot.muted)
            Spacer(minLength: 12)
            value()
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    /// A block with a glyph and a name, the page's one container.
    private func card<Content: View>(symbol: String, title: String, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.muted)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                if let count, count > 0 {
                    Text("\(count)").font(.system(size: 13)).foregroundStyle(Soot.muted).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
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
        .padding(.top, -12)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Description

    @ViewBuilder
    private func description(_ d: LinearIssueDetail) -> some View {
        if let text = d.description, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let blocks {
                MarkdownView(blocks: blocks)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Skeleton(height: 12); Skeleton(width: 420, height: 12); Skeleton(width: 360, height: 12)
                }
                .accessibilityElement().accessibilityLabel("Loading description")
            }
        } else {
            Text("No description").font(.system(size: 14)).foregroundStyle(Soot.muted)
        }
    }

    // MARK: Links between issues

    @ViewBuilder
    private func linksCard(_ d: LinearIssueDetail) -> some View {
        let groups: [(String, String, [LinearIssueDetail.Brief])] = [
            ("arrow.turn.left.up", "Parent", d.parent.map { [$0] } ?? []),
            ("list.bullet.indent", "Sub-issues", d.subIssues),
            ("hand.raised", "Blocked by", d.blockedBy),
            ("lock", "Blocks", d.blocks),
            ("link", "Related", d.related),
        ].filter { !$0.2.isEmpty }
        if !groups.isEmpty {
            card(symbol: "point.3.connected.trianglepath.dotted", title: "Linked issues") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.1) { symbol, title, briefs in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                                    .frame(width: 14).accessibilityHidden(true)
                                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                                if briefs.count > 1 { Text("\(briefs.count)").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit() }
                            }
                            .padding(.bottom, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                            ForEach(briefs) { b in
                                TileLink(value: IssueRoute(projectID: route.projectID, brief: b)) {
                                    StateDot(state: b.state).help(b.state.name)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.title).font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(2).help(b.title)
                                        HStack(spacing: 6) {
                                            Text(verbatim: b.identifier).font(.system(size: 11, design: .monospaced))
                                            Text("·")
                                            Text(b.state.name)
                                        }
                                        .font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if let p = b.assignee { LinearAvatar(name: p.name, avatarURL: p.avatarUrl, size: 20).help(p.name) }
                                }
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(b.identifier), \(b.title), \(b.state.name)")
                            }
                        }
                    }
                }
                .padding(.horizontal, -8)
            }
        }
    }

    // MARK: Attachments

    @ViewBuilder
    private func attachmentsCard(_ d: LinearIssueDetail) -> some View {
        let list = d.attachments?.nodes ?? []
        if !list.isEmpty {
            card(symbol: "paperclip", title: "Attachments", count: list.count > 1 ? list.count : nil) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { a in
                        let pull = store.pullsByURL[a.url]
                        TileRow(url: URL(string: a.url)) {
                            Image(systemName: symbol(for: a, pull: pull))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(pull?.state == .merged ? Soot.lime : pull != nil ? Theme.chart2 : Soot.muted)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pull.map { PullTitle.split($0.title).title } ?? a.title ?? a.url)
                                    .font(.system(size: 13)).foregroundStyle(Soot.ink).lineLimit(2)
                                HStack(spacing: 6) {
                                    if let pull { Text(verbatim: "#\(pull.number)"); Text("·"); Text(pull.state.label) }
                                    else if let s = a.subtitle, !s.isEmpty { Text(s) }
                                    else { Text(URL(string: a.url)?.host ?? "") }
                                }
                                .font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Soot.muted)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, -8)
            }
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

    @ViewBuilder
    private func comments(_ d: LinearIssueDetail) -> some View {
        if d.thread.isEmpty {
            Text("No comments yet").font(.system(size: 14)).foregroundStyle(Soot.muted)
        } else {
            let thread = d.thread
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(thread.enumerated()), id: \.element.id) { index, c in
                    let previous = index > 0 ? thread[index - 1] : nil
                    let grouped = previous.map {
                        $0.authorName == c.authorName
                            && (LinearDate.parse(c.createdAt)?.timeIntervalSince(LinearDate.parse($0.createdAt) ?? .distantPast) ?? 1e9) < 600
                    } ?? false
                    CommentRow(comment: c, grouped: grouped, reply: c.parent != nil, measure: measure)
                        .padding(.top, grouped ? 2 : (index == 0 ? 0 : 16))
                }
            }
            .padding(.horizontal, -8)
        }
    }

    // MARK: Loading

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(width: 110, height: 30, radius: 8) } }
            VStack(alignment: .leading, spacing: 10) {
                Skeleton(width: 120, height: 14)
                Skeleton(height: 12); Skeleton(width: 480, height: 12); Skeleton(width: 420, height: 12); Skeleton(width: 300, height: 12)
            }
            .padding(18)
            .frame(maxWidth: measure, alignment: .leading)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
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


/// Items laid out left to right, wrapping to the next line when the width runs out.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A short progress bar for a count, lime for the done part.
struct MiniBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Soot.edge.opacity(0.35))
                Capsule().fill(Soot.lime).frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(width: 48, height: 5)
        .accessibilityHidden(true)
    }
}
