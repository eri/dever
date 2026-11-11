import SwiftUI

/// One Linear issue, read as a document with a margin: the title and the facts that decide
/// what happens next on top (status, priority, assignee, due date, blockers, code), the
/// description and the conversation in the reading column, every other detail and link in
/// the side column. Below ~1120px the side column follows the text.
struct IssueDetailView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var store = IssueStore.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var intelligence = IntelligenceStatus.shared
    @AppStorage(IntelligenceFeature.explainFailure.settingKey) private var explainsFailures = true
    /// The pull request whose failed pipeline is being explained under the signals.
    @State private var why: FailureStore.Key?
    @State private var whyShown = false
    @Environment(\.dismiss) private var dismiss
    let route: IssueRoute

    @State private var detail: LinearIssueDetail?
    @State private var team: LinearTeamContext?
    @State private var error: ServiceState?
    @StateObject private var flow = ConnectFlow()
    @State private var blocks: [MarkdownBlock]?
    @State private var notice: (text: String, failed: Bool)?
    @State private var noticeTask: Task<Void, Never>?
    /// Set by the blocked-by chip: scrolls to Linked issues and outlines it for a moment.
    @State private var linksJump = 0
    @State private var linksHighlighted = false
    @State private var labelsExpanded = false
    /// The description opens on its first lines: Dever is for triage, Linear for reading.
    @State private var descriptionExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            ServiceFailureRow(service: .linear, state: error, retry: { Task { await load() } }, flow: flow)
                        } else if let detail {
                            // Its failure card hangs over what follows.
                            signals(detail).zIndex(1)
                            if let notice { noticeLine(notice).transition(Motion.rise) }
                            if let pull = mergedPull(detail) { mergedBanner(pull, detail) }
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
                            loadingBody.transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    // The skeleton dissolves into the issue (200 ms); nothing else on the page
                    // animates with it. The confirmation line rises in and fades out.
                    .motion(Motion.ui, fade: true, value: detail == nil)
                    .motion(Motion.ui, value: notice?.text)
                    .frame(maxWidth: measure + 20 + aside, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(width: geo.size.width, alignment: twoColumns ? .center : .leading)
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToEnd)) { _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: linksJump) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo("links", anchor: .top) }
                }
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
            }
            .buttonStyle(ChipButton(fill: Soot.surface))
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to the project (⌘[)")
            .accessibilityLabel("Back to the project")
            Spacer()
            if let url = URL(string: route.url) {
                ExternalLink("Open in Linear", destination: url, lift: Soot.surface)
                    .padding(.trailing, -8)
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
            Text(MarkdownTheme.inline(detail?.title ?? route.title, size: 30))
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
        // Sub-issues in a review or QA state are out of the developer's hands: they count
        // towards the bar and are named, instead of reading as not done.
        let subs = d.subIssues.filter { $0.state.type != "canceled" }
        let done = subs.filter { $0.state.type == "completed" }.count
        let inQA = subs.filter { $0.state.type != "completed" && Delivery.isReviewState($0.state.name) }.count
        let subsText = inQA == 0 ? "\(done) of \(subs.count) sub-issues done"
            : inQA == subs.count ? "All \(subs.count) sub-issues in QA"
            : "\(done) done · \(inQA) in QA of \(subs.count) sub-issues"
        var open = pulls(d).filter { $0.ref.state != .merged }
        // Captures: a made-up open pull request, so the failed chip shows whatever the issue holds.
        if Snapshotter.directory != nil, ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WHY"] != nil, open.isEmpty {
            open = [(IssueStore.PullRef(number: 951, title: "Demo", state: .open), URL(string: "https://github.com/demo/app/pull/951")!)]
        }
        let code = open.prefix(2)
        let explains = explainsFailures && intelligence.offers(.explainFailure)
        return VStack(alignment: .leading, spacing: 10) {
          FlowRow(spacing: 8) {
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
                let text = open == 0 ? "Was blocked, now clear"
                    : "Blocked by \(open) other \(open == 1 ? "issue" : "issues")"
                Button { jumpToLinks() } label: {
                    signal(symbol: "hand.raised.fill", text: text, tint: open == 0 ? nil : Theme.chart3, label: text)
                }
                .buttonStyle(RowButton(lift: .ground, radius: 8))
                .help("Show the blocking issues")
                .accessibilityHint("Scrolls to the linked issues")
            }
            if !subs.isEmpty {
                signal(symbol: done == subs.count ? "checklist.checked" : "checklist", text: subsText,
                       tint: nil, label: subsText) {
                    MiniBar(fraction: Double(done + inQA) / Double(subs.count))
                }
            }
            // Merged work has its own banner below; open pull requests are a signal here.
            ForEach(Array(code), id: \.ref.number) { entry in
                let pull = entry.ref
                let n = String(pull.number)
                // Its checks failed, by the copy the app already holds: said here with its age,
                // and never in red once that copy is old.
                if let key = PullFailure.key(url: entry.url.absoluteString), let readAt = PullFailure.failed(key, in: github) {
                    let stale = PullFailure.isStale(readAt)
                    let chip = signal(symbol: "xmark.circle.fill", text: stale ? "#\(n) CI failed · read \(Brief.ago(readAt)) ago" : "#\(n) CI failed",
                                      tint: stale ? nil : Theme.negative, label: "Pull request \(n), CI failed\(stale ? ", read \(Brief.ago(readAt)) ago" : "")") {
                        if explains {
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.muted)
                                .rotationEffect(.degrees(why == key ? 180 : 0))
                        }
                    }
                    if explains {
                        // A capture shows it open.
                        let _ = Snapshotter.directory != nil && why == nil && !whyShown && ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WHY"] == "open"
                            ? DispatchQueue.main.async { whyShown = true; why = key } : ()
                        // The failed state is the button: it opens the checks that failed and why.
                        Button { Motion.run(Motion.ui, fade: true) { why = why == key ? nil : key } } label: { chip }
                            .buttonStyle(MenuTriggerButton(open: why == key, fill: Soot.surface, radius: 8, edge: false))
                            .help("Show the checks that failed")
                            .accessibilityHint("Shows the checks that failed")
                            .failureCard(open: why == key, key: key, heading: "#\(n) \(PullTitle.split(pull.title).title)", url: entry.url, drop: 36) {
                                Motion.run(Motion.ui, fade: true) { why = nil }
                            }
                            .zIndex(why == key ? 1 : 0)
                    } else {
                        chip
                    }
                } else {
                    signal(symbol: "arrow.triangle.pull", text: "#\(n) \(pull.state.label.lowercased())",
                           tint: Theme.chart2, label: "Pull request \(n), \(pull.state.label)")
                }
            }
          }
        }
    }

    // MARK: Merged banner

    /// The pull requests behind this issue: those Linear attached, and those the project page
    /// matched by branch or title (a branch not named after the issue still counts).
    private func pulls(_ d: LinearIssueDetail) -> [(ref: IssueStore.PullRef, url: URL)] {
        let attached = Set((d.attachments?.nodes ?? []).map(\.url))
        return store.pullsByURL
            .filter { attached.contains($0.key) || $0.value.issue == d.identifier }
            .compactMap { key, ref in URL(string: key).map { (ref, $0) } }
            .sorted { $0.ref.number > $1.ref.number }
    }

    /// The merged pull request the banner names, the newest one.
    private func mergedPull(_ d: LinearIssueDetail) -> (ref: IssueStore.PullRef, url: URL)? {
        pulls(d).first { $0.ref.state == .merged }
    }

    private func mergedBanner(_ pull: (ref: IssueStore.PullRef, url: URL), _ d: LinearIssueDetail) -> some View {
        let done = (row ?? d.asRow).state.type == "completed"
        let number = String(pull.ref.number)
        let title = PullTitle.split(pull.ref.title).title
        return HStack(alignment: .center, spacing: 14) {
            MergeGlyph()
                .stroke(Soot.limeInk, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 18)
                .frame(width: 34, height: 34)
                .background(Soot.lime, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: done ? "Merged and shipped" : "Merged")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                Text(verbatim: "PR #\(number) · \(title)")
                    .font(.system(size: 14)).foregroundStyle(Soot.muted)
                    .lineLimit(1)
                    .help("Pull request #\(number): \(title)")
            }
            Spacer(minLength: 16)
            ExternalLink(destination: pull.url, tint: .ink) {
                HStack(spacing: 5) { BrandLogo(service: .github, size: 13); Text("Open on GitHub") }
            }
            .help("Open pull request #\(number) on GitHub")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: measure + 20 + aside)
        .background(Soot.lime.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.lime.opacity(0.45)))
        .accessibilityElement(children: .combine)
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

    private func jumpToLinks() {
        linksJump += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { linksHighlighted = true }
        // Snapshots hold the outline so the capture can show it.
        let hold: UInt64 = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_JUMP"] == "1" ? 30 : 0
        Task {
            try? await Task.sleep(nanoseconds: hold > 0 ? hold * 1_000_000_000 : 1_800_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { linksHighlighted = false }
        }
    }

    // MARK: Reading column

    private func reading(_ d: LinearIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            card(symbol: "doc.text", title: "Description") {
                description(d)
            }
            card(symbol: "bubble.left.and.bubble.right", title: "Activity") {
                activity(d)
            }
            linksCard(d)
                .id("links")
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.lime, lineWidth: 2).opacity(linksHighlighted ? 1 : 0))
                .background(Soot.lime.opacity(linksHighlighted ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 12))
            attachmentsCard(d)
        }
    }

    // MARK: Side column

    private func sideColumn(_ d: LinearIssueDetail) -> some View {
        let current = row ?? d.asRow
        return VStack(alignment: .leading, spacing: 16) {
            card(symbol: "info.circle", title: "Details") {
                VStack(alignment: .leading, spacing: 18) {
                    if !current.labelList.isEmpty {
                        let labels = current.labelList
                        let shown = labelsExpanded ? labels : Array(labels.prefix(3))
                        caption("Labels") {
                            FlowRow(spacing: 6) {
                                ForEach(shown) { LabelPill(label: $0) }
                                if labels.count > 3 {
                                    Button(labelsExpanded ? "Less" : "+\(labels.count - 3)") { labelsExpanded.toggle() }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Soot.ink)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .overlay(Capsule().strokeBorder(Soot.edge))
                                        .contentShape(Capsule())
                                        .modifier(FocusOutline(radius: 10))
                                        .help(labelsExpanded ? "Show fewer labels" : labels.dropFirst(3).map(\.name).joined(separator: ", "))
                                        .accessibilityLabel(labelsExpanded ? "Show fewer labels" : "Show \(labels.count - 3) more labels")
                                }
                            }
                        }
                    }
                    let facts: [(String, String)] = [
                        d.estimate.map { ("Estimate", $0.formatted() + ($0 == 1 ? " point" : " points")) },
                        current.dueDate.map { ("Due", LinearDate.short($0) ?? $0) },
                        d.cycle.map { ("Cycle", $0.name ?? "Cycle \($0.number)") },
                        d.projectMilestone.map { ("Milestone", $0.name) },
                    ].compactMap { $0 }
                    if !facts.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                            ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { i in
                                GridRow {
                                    caption(facts[i].0) { factValue(facts[i].1) }
                                    if i + 1 < facts.count { caption(facts[i + 1].0) { factValue(facts[i + 1].1) } } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                                }
                            }
                        }
                    }
                    if let branch = d.branchName ?? current.branchName, !branch.isEmpty {
                        caption("Branch") {
                            CopyChip(value: branch, what: "branch name", maxWidth: 200)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(Soot.line).frame(height: 1).padding(.bottom, 8)
                        datedLine("Created", d.createdAt)
                        if current.updatedAt != d.createdAt { datedLine("Updated", current.updatedAt) }
                    }
                }
            }
        }
    }

    /// A small caption above its value: the Details card's one pattern.
    private func caption<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func factValue(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func datedLine(_ label: String, _ date: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Soot.muted)
            Text(LinearDate.dayAndAge(date) ?? "").foregroundStyle(Soot.ink)
        }
        .font(.system(size: 13))
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
            Group {
                if let blocks {
                    foldedDescription(blocks).transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Skeleton(height: 12); Skeleton(width: 420, height: 12); Skeleton(width: 360, height: 12)
                    }
                    .transition(.opacity)
                    .accessibilityElement().accessibilityLabel("Loading description")
                }
            }
            .motion(Motion.ui, fade: true, value: blocks == nil)
        } else {
            Text("No description").font(.system(size: 14)).foregroundStyle(Soot.muted)
        }
    }

    /// Folded height: about six lines of body text, enough to tell what the issue is about.
    private let foldHeight: CGFloat = 168

    /// The description, cut to its first lines with a fade and a way to open the rest.
    /// Short ones (a few lines, no picture) show whole, with no control.
    @ViewBuilder
    private func foldedDescription(_ blocks: [MarkdownBlock]) -> some View {
        let length = blocks.reduce(0) { $0 + $1.text.characters.count }
        let hasImage = blocks.contains { if case .image = $0.kind { true } else { false } }
        let short = !hasImage && blocks.count <= 4 && length <= 420
        if short {
            MarkdownView(blocks: blocks)
        } else {
            // Folded, only the opening blocks are laid out at all (a few hundred characters), so
            // nothing below the fade exists to spill out; the height cap then trims the last one.
            let opening: [MarkdownBlock] = {
                var used = 0
                var out: [MarkdownBlock] = []
                for b in blocks {
                    if case .image = b.kind { break }
                    out.append(b)
                    used += b.text.characters.count
                    if used > 320 || out.count >= 4 { break }
                }
                return out
            }()
            VStack(alignment: .leading, spacing: 8) {
                MarkdownView(blocks: descriptionExpanded ? blocks : opening)
                    .frame(maxHeight: descriptionExpanded ? nil : foldHeight, alignment: .top)
                    .clipShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if !descriptionExpanded {
                            LinearGradient(colors: [Soot.surface.opacity(0), Soot.surface], startPoint: .top, endPoint: .bottom)
                                .frame(height: 56)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                Button {
                    descriptionExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(descriptionExpanded ? "Show less" : "Show full description")
                        Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(TertiaryButton(tint: .lime, lift: Soot.ground))
                .padding(.leading, -8)
                .accessibilityHint(descriptionExpanded ? "Folds the description to its first lines" : "Shows the whole description")
            }
            .motion(Motion.ui, value: descriptionExpanded)
        }
    }

    // MARK: Links between issues

    @ViewBuilder
    private func linksCard(_ d: LinearIssueDetail) -> some View {
        // What stands in the way first; sub-issues stay out (their progress is a signal up top).
        let groups: [(String, String, [LinearIssueDetail.Brief])] = [
            ("hand.raised", "Blocked by", d.blockedBy),
            ("lock", "Blocks", d.blocks),
            ("arrow.turn.left.up", "Parent", d.parent.map { [$0] } ?? []),
            ("link", "Related", d.related),
        ].filter { !$0.2.isEmpty }
        let total = groups.reduce(0) { $0 + $1.2.count }
        let cap = 3
        // Five rows across the groups, in order; the rest behind "Show all".
        let visible: [(String, String, [LinearIssueDetail.Brief], Int)] = {
            var budget = cap
            var out: [(String, String, [LinearIssueDetail.Brief], Int)] = []
            for (symbol, title, briefs) in groups where budget > 0 {
                out.append((symbol, title, Array(briefs.prefix(budget)), briefs.count))
                budget -= min(budget, briefs.count)
            }
            return out
        }()
        if !groups.isEmpty {
            card(symbol: "point.3.connected.trianglepath.dotted", title: "Linked issues", count: total) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(visible, id: \.1) { symbol, title, briefs, count in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                                    .frame(width: 14).accessibilityHidden(true)
                                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                                if count > 1 { Text("\(count)").font(.system(size: 12)).foregroundStyle(Soot.muted).monospacedDigit() }
                            }
                            .padding(.leading, 12)
                            .padding(.bottom, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                            ForEach(briefs) { b in
                                TileLink(value: IssueRoute(projectID: route.projectID, brief: b)) {
                                    PriorityGlyph(priority: b.priority, dimmed: (b.priority ?? 0) == 0).help(LinearPriority.label(b.priority))
                                    IDPill(text: b.identifier).fixedSize()
                                    Text(MarkdownTheme.inline(b.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1).help(b.title)
                                    Spacer(minLength: 12)
                                    HStack(spacing: 6) {
                                        StateDot(state: b.state)
                                        Text(b.state.name).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                                    }
                                    .fixedSize()
                                    if let p = b.assignee {
                                        LinearAvatar(name: p.name, avatarURL: p.avatarUrl).help(p.name)
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted).help("Unassigned")
                                    }
                                }
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
        let banner = mergedPull(d)?.url.absoluteString
        let list = (d.attachments?.nodes ?? []).filter { $0.url != banner }
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
                                    .font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                                HStack(spacing: 6) {
                                    if let pull { Text(verbatim: "#" + String(pull.number)); Text("·"); Text(pull.state.label) }
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

    // MARK: Activity: comments and the issue's history on one thread, oldest first

    private enum Item: Identifiable {
        case created(String, LinearIssue.State?)
        case comment(LinearIssueDetail.Comment)
        case event(LinearIssueDetail.HistoryEvent, [Change])
        case pull(IssueStore.PullRef, String)
        var id: String {
            switch self {
            case .created: "created"; case .comment(let c): "c-" + c.id; case .event(let e, _): "h-" + e.id
            case .pull(let p, _): "p-\(p.number)"
            }
        }
        var date: String {
            switch self {
            case .created(let d, _): d; case .comment(let c): c.createdAt; case .event(let e, _): e.createdAt
            case .pull(_, let d): d
            }
        }
    }

    /// One change inside a history event, as a glyph and words.
    private struct Change: Identifiable {
        let symbol: String
        let text: String
        var state: LinearIssue.State? = nil
        var id: String { symbol + text }
    }

    private func items(_ d: LinearIssueDetail) -> [Item] {
        let labels = Dictionary(d.labelList.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // The state the issue was created in: the first move's origin, or today's state when it never moved.
        let moves = (d.history?.nodes ?? []).filter { $0.toState != nil }.sorted { $0.createdAt < $1.createdAt }
        let initial = moves.first?.fromState ?? (moves.isEmpty ? (row ?? d.asRow).state : nil)
        var list: [Item] = [.created(d.createdAt, initial)]
        list += d.thread.map { .comment($0) }
        let iso = ISO8601DateFormatter()
        for p in pulls(d) { if let date = p.ref.date { list.append(.pull(p.ref, iso.string(from: date))) } }
        for e in d.history?.nodes ?? [] {
            let changes = describe(e, labels: labels)
            if !changes.isEmpty { list.append(.event(e, changes)) }
        }
        return list.sorted { $0.date > $1.date }
    }

    /// Under six hours old: the thread marks it so the newest changes stand out.
    private func isRecent(_ date: String) -> Bool {
        guard let d = LinearDate.parse(date) else { return false }
        return Date().timeIntervalSince(d) < 6 * 3600
    }

    private func describe(_ e: LinearIssueDetail.HistoryEvent, labels: [String: String]) -> [Change] {
        var out: [Change] = []
        if let to = e.toState {
            out.append(Change(symbol: "", text: e.fromState.map { "moved from \($0.name) to \(to.name)" } ?? "set status to \(to.name)", state: to))
        }
        if let to = e.toAssignee { out.append(Change(symbol: "person", text: "assigned to \(to.name)")) }
        else if let from = e.fromAssignee { out.append(Change(symbol: "person.slash", text: "unassigned \(from.name)")) }
        if let p = e.toPriority { out.append(Change(symbol: "chart.bar", text: "set priority to \(LinearPriority.label(p))")) }
        if e.toTitle != nil { out.append(Change(symbol: "pencil", text: "renamed the issue")) }
        if e.updatedDescription == true { out.append(Change(symbol: "doc.text", text: "edited the description")) }
        if let to = e.toEstimate { out.append(Change(symbol: "scalemass", text: "set the estimate to \(to.formatted())")) }
        else if e.fromEstimate != nil { out.append(Change(symbol: "scalemass", text: "removed the estimate")) }
        if let to = e.toDueDate { out.append(Change(symbol: "calendar", text: "set the due date to \(LinearDate.short(to) ?? to)")) }
        else if e.fromDueDate != nil { out.append(Change(symbol: "calendar", text: "removed the due date")) }
        for id in e.addedLabelIds ?? [] { out.append(Change(symbol: "tag", text: "added the label \(labels[id] ?? "")".trimmingCharacters(in: .whitespaces))) }
        for id in e.removedLabelIds ?? [] { out.append(Change(symbol: "tag.slash", text: "removed the label \(labels[id] ?? "")".trimmingCharacters(in: .whitespaces))) }
        if let to = e.toCycle { out.append(Change(symbol: "arrow.triangle.2.circlepath", text: "moved to \(to.name ?? "cycle \(to.number ?? 0)")")) }
        else if e.fromCycle != nil { out.append(Change(symbol: "arrow.triangle.2.circlepath", text: "removed from its cycle")) }
        if let to = e.toParent?.identifier { out.append(Change(symbol: "arrow.turn.left.up", text: "set the parent to \(to)")) }
        else if e.fromParent != nil { out.append(Change(symbol: "arrow.turn.left.up", text: "removed the parent")) }
        if e.archived == true { out.append(Change(symbol: "archivebox", text: "archived the issue")) }
        if e.trashed == true { out.append(Change(symbol: "trash", text: "deleted the issue")) }
        if e.autoClosed == true { out.append(Change(symbol: "checkmark.circle", text: "closed automatically")) }
        return out
    }

    private func activity(_ d: LinearIssueDetail) -> some View {
        let list = items(d)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                let previous = index > 0 ? list[index - 1] : nil
                switch item {
                case .created(let date, let state):
                    eventRow(name: d.creator?.name, avatar: d.creator?.avatarUrl,
                             changes: [Change(symbol: state == nil ? "plus.circle" : "", text: state.map { "created the issue in \($0.name)" } ?? "created the issue", state: state)],
                             date: date)
                case .pull(let p, let date):
                    let n = String(p.number)
                    eventRow(name: "GitHub", avatar: nil,
                             changes: [Change(symbol: p.state == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull",
                                              text: p.state == .merged ? "PR #\(n) merged"
                                                  : (p.state == .draft ? "draft PR #\(n)" : "PR #\(n)") + (p.author.map { " by \($0)" } ?? "") + (p.state == .draft ? "" : ", waiting for review"))],
                             date: date)
                case .comment(let c):
                    let grouped: Bool = {
                        guard case .comment(let p)? = previous else { return false }
                        return p.authorName == c.authorName
                            && (LinearDate.parse(p.createdAt)?.timeIntervalSince(LinearDate.parse(c.createdAt) ?? .distantPast) ?? 1e9) < 600
                    }()
                    CommentRow(comment: c, grouped: grouped, reply: c.parent != nil, measure: measure, recent: isRecent(c.createdAt))
                        .padding(.top, grouped ? 2 : 16)
                        .padding(.bottom, 8)
                case .event(let e, let changes):
                    eventRow(name: e.actorName, avatar: e.actor?.avatarUrl, changes: changes, date: e.createdAt)
                }
            }
        }
        .padding(.horizontal, -8)
    }

    /// One quiet line of history: who, what, when.
    private func eventRow(name: String?, avatar: String?, changes: [Change], date: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let name { LinearAvatar(name: name, avatarURL: avatar, size: 26) }
                else { Image(systemName: "plus.circle").font(.system(size: 16)).foregroundStyle(Soot.muted) }
            }
            .frame(width: 28, height: 26, alignment: .center)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        if let state = change.state { StateDot(state: state, size: 13).frame(width: 18) }
                        else if !change.symbol.isEmpty {
                            Image(systemName: change.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.muted).frame(width: 18)
                        }
                        (Text(name.map { $0 + " " } ?? "Someone ").fontWeight(.semibold).foregroundColor(Soot.ink)
                            + Text(change.text).foregroundColor(Soot.muted))
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                    .frame(minHeight: 26)
                }
            }
            Spacer(minLength: 12)
            RecentTime(date: date, recent: isRecent(date)).frame(minHeight: 26)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isRecent(date) ? Soot.lime.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
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
        descriptionExpanded = false
        error = nil
        if let cached = store.cachedDetail(route.issueID), route.updatedAt == nil || cached.updatedAt == route.updatedAt {
            detail = cached
        }
        do {
            let d = try await store.detail(route.issueID, updatedAt: route.updatedAt, app: app)
            detail = d
            if let text = d.description { blocks = await store.blocks(for: text) }
            if let teamID = d.team?.id { team = try? await store.team(teamID, app: app) }
            // Snapshots: DEVER_SNAPSHOT_JUMP=1 presses the blocked-by chip.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_JUMP"] == "1", !d.blockedBy.isEmpty {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                jumpToLinks()
            }
            // Snapshots: DEVER_SNAPSHOT_TRIAGE=1 writes the current priority back, to show the confirmation.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_TRIAGE"] == "1", let current = row {
                change(current, note: "Priority → \(LinearPriority.label(current.priority))") { _ in } request: { .init(priority: current.priority ?? 0) }
            }
        } catch {
            if detail == nil { self.error = app.failure(error, .linear) }
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
    var recent = false
    @State private var blocks: [MarkdownBlock]?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if grouped {
                    Color.clear
                } else {
                    LinearAvatar(name: comment.authorName, avatarURL: comment.user?.avatarUrl, size: 30)
                }
            }
            .frame(width: 30, height: grouped ? 4 : 30)
            VStack(alignment: .leading, spacing: 4) {
                if !grouped {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(comment.authorName).font(.system(size: 15, weight: .bold)).foregroundStyle(Soot.ink)
                        RecentTime(date: comment.createdAt, recent: recent)
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
        .background(hovering ? Soot.ground.opacity(0.6) : recent ? Soot.lime.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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

    private var bodySize: CGFloat { 15 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    VStack(alignment: .leading, spacing: 6) {
                        text(block.text, size: [22, 18, 16, 15, 14, 14][min(max(level, 1), 6) - 1], weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        if level <= 2, !compact { Rectangle().fill(Soot.line).frame(height: 1) }
                    }
                    .padding(.top, compact ? 2 : 10)
                case .paragraph:
                    text(block.text, size: bodySize)
                case .quote:
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Soot.edge).frame(width: 3)
                        text(block.text, size: bodySize, color: Soot.muted).italic()
                    }
                    .padding(.vertical, 2)
                    .fixedSize(horizontal: false, vertical: true)
                case .code(let language):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text)
                            .font(.system(size: bodySize - 2, design: .monospaced))
                            .foregroundStyle(MarkdownTheme.code)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.line))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(MarkdownTheme.code.opacity(0.55)).frame(width: 3).padding(.vertical, 8).padding(.leading, 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let language, !language.isEmpty {
                            Text(language).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Soot.muted)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
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
        Text(MarkdownTheme.style(s, size: size))
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
                .buttonStyle(RowButton(lift: .none))
                .help("Open the image")
                .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else if failed {
                ExternalLink(destination: url, font: .system(size: 13, weight: .medium)) {
                    HStack(spacing: 6) { Image(systemName: "photo"); Text(alt.isEmpty ? "Image" : alt) }
                }
                .padding(.leading, -8)
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

/// A relative time; under six hours it is lime with a dot and says so to VoiceOver.
private struct RecentTime: View {
    let date: String
    let recent: Bool
    var body: some View {
        HStack(spacing: 5) {
            if recent { Circle().fill(Soot.lime).frame(width: 6, height: 6) }
            Text(LinearDate.relative(date) ?? "")
                .font(.system(size: 13, weight: recent ? .semibold : .regular))
                .foregroundStyle(recent ? Soot.lime : Soot.muted)
        }
        .help(LinearDate.parse(date)?.formatted(date: .abbreviated, time: .shortened) ?? "")
        .accessibilityLabel((LinearDate.relative(date) ?? "") + (recent ? ", recent" : ""))
    }
}

/// A pull request merge drawn like GitHub's: two commits on a line, the branch curving into
/// the third. Drawn rather than taken from SF Symbols, whose merge arrow is too thin at 16pt.
struct MergeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let d = min(r.width, r.height) * 0.28
        let left = r.minX + d / 2 + 1, right = r.maxX - d / 2 - 1
        let top = r.minY + d / 2 + 1, bottom = r.maxY - d / 2 - 1
        p.addEllipse(in: CGRect(x: left - d / 2, y: top - d / 2, width: d, height: d))
        p.addEllipse(in: CGRect(x: left - d / 2, y: bottom - d / 2, width: d, height: d))
        p.addEllipse(in: CGRect(x: right - d / 2, y: r.midY + d * 0.3 - d / 2, width: d, height: d))
        p.move(to: CGPoint(x: left, y: top + d / 2))
        p.addLine(to: CGPoint(x: left, y: bottom - d / 2))
        p.move(to: CGPoint(x: left, y: top + d / 2))
        p.addQuadCurve(to: CGPoint(x: right - d / 2, y: r.midY + d * 0.3), control: CGPoint(x: left, y: r.midY + d * 0.3))
        return p
    }
}
