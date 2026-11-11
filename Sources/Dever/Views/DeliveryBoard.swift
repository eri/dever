import AppKit
import SwiftUI

/// A situation as a glyph: its own shape and its own colour, always beside its word.
struct SituationGlyph: View {
    let situation: DeliveryPlan.Situation
    var size: CGFloat = 14

    static func look(_ situation: DeliveryPlan.Situation) -> (symbol: String, tint: Color) {
        switch situation {
        case .ciFailed: ("xmark.circle.fill", Theme.negative)
        case .changesRequested: ("arrow.uturn.backward.circle.fill", Theme.chart3)
        case .reviewRequested: ("eye.fill", Theme.chart2)
        case .behind: ("arrow.triangle.merge", Theme.chart3)
        case .readyToMerge: ("checkmark.circle.fill", Theme.positive)
        case .building: ("circle.lefthalf.filled", Soot.ink)
        case .draft: ("pencil.line", Soot.muted)
        case .waitingReview: ("hourglass", Theme.chart2)
        case .todo: ("circle", Soot.muted)
        case .blocked: ("lock.fill", Soot.muted)
        }
    }

    var body: some View {
        let look = Self.look(situation)
        Image(systemName: look.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(look.tint)
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

/// The Delivery panel's body: what is left, the one issue to pick up with its action, the
/// viewer's other issues, then the others' and the shipped ones, folded.
struct DeliveryBoard: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var store = IssueStore.shared
    let plan: DeliveryPlan
    let project: Project
    /// Pull request chips name their repository once the project follows more than one.
    var labelsRepository = false

    @State private var showsOthers = false
    @State private var showsShipped = false
    @ObservedObject private var release = ReleaseStore.shared
    @ObservedObject private var previews = PreviewStore.shared
    @EnvironmentObject private var appState: AppState
    @State private var showsAllShipped = false
    @ObservedObject private var intelligence = IntelligenceStatus.shared
    @AppStorage(IntelligenceFeature.explainFailure.settingKey) private var explainsFailures = true
    /// The pull request whose failure is being explained under the "Start here" tile.
    @State private var why: FailureStore.Key? = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WHY"] == nil ? nil
        : .init(repository: "demo/app", number: 0)
    @State private var teams: [String: LinearTeamContext] = [:]
    @State private var notice: Notice?
    @State private var noticeTask: Task<Void, Never>?

    /// What the last action did, with the way back while it can still be taken.
    private struct Notice: Equatable {
        var text: String
        var failed = false
        var undo: Undo?
        struct Undo: Equatable {
            var issueID: String
            var state: LinearIssue.State?
            var restoresAssignee = false
            var assigneeID: String?
        }
    }

    private static let shippedCap = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headline
            VStack(alignment: .leading, spacing: 8) {
                bar
                whereLine
            }
            if let notice { noticeLine(notice).transition(.opacity) }
            if let start = plan.start {
                startTile(start, grab: plan.startIsGrab)
                    .id(start.id)
                    .transition(.opacity)
            } else if plan.left > 0 {
                QuietEmpty(symbol: "checkmark.circle", text: "Nothing waiting on you")
            }
            if !plan.next.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Next", count: plan.next.count)
                    ForEach(plan.next) { row($0, showsPerson: false).transition(.opacity) }
                }
            }
            if !plan.others.isEmpty || !plan.shipped.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle().fill(Soot.line).frame(height: 1).padding(.bottom, 6)
                    if !plan.others.isEmpty { othersGroup }
                    if !plan.shipped.isEmpty { shippedGroup }
                }
            }
        }
        .motion(Motion.ui, fade: true, value: plan.start?.id)
        .motion(Motion.ui, fade: true, value: notice)
        .task(id: teamIDs) { await loadTeams() }
        // Where the shipped work is needs the release line: read within its own budget.
        .task { await ReleaseStore.shared.refresh(appState) }
        // Snapshots: DEVER_SNAPSHOT_SHIPPED_OPEN=1 unfolds the shipped list.
        .onAppear { if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_SHIPPED_OPEN"] == "1" { showsShipped = true } }
    }

    // MARK: Headline

    @ViewBuilder
    private var headline: some View {
        if plan.left == 0 {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.positive)
                    .accessibilityHidden(true)
                Text(plan.inQA > 0 ? "All merged" : "All \(plan.total) shipped")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4).foregroundStyle(Soot.ink)
                if plan.inQA > 0 {
                    Text("\(plan.inQA) still in QA").font(.system(size: 14)).foregroundStyle(Soot.muted).monospacedDigit()
                }
                Spacer(minLength: 16)
                if let last = plan.lastMerged {
                    Text("last merged \(last.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 13)).foregroundStyle(Soot.muted)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                // The figures roll to their new values when a refresh or an action lands.
                Text("\(plan.left)").font(.system(size: 34, weight: .semibold)).tracking(-1).foregroundStyle(Soot.ink)
                    .monospacedDigit().rollingNumber(plan.left)
                Text("left").font(.system(size: 14)).foregroundStyle(Soot.muted)
                if plan.yours > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                        Text("\(plan.yours) yours").monospacedDigit().rollingNumber(plan.yours)
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                    .padding(.leading, 10)
                }
                Spacer(minLength: 16)
                Text("\(plan.shipped.count) of \(plan.total) shipped").font(.system(size: 13)).foregroundStyle(Soot.muted)
                    .monospacedDigit().rollingNumber(plan.shipped.count * 10_000 + plan.total)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(plan.left) left\(plan.yours > 0 ? ", \(plan.yours) yours" : ""). \(plan.shipped.count) of \(plan.total) shipped")
        }
    }

    /// Shipped, under way, to do: three rounded segments, proportional.
    private var bar: some View {
        let parts: [(count: Int, tint: Color)] = [(plan.shipped.count, Theme.chart1), (plan.moving, Theme.chart2),
                                                   (plan.left - plan.moving, Theme.empty)].filter { $0.count > 0 }
        return GeometryReader { geo in
            let gap: CGFloat = 3
            let usable = geo.size.width - gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Capsule().fill(part.tint)
                        .frame(width: max(6, usable * CGFloat(part.count) / CGFloat(max(plan.total, 1))))
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(plan.shipped.count) shipped, \(plan.moving) under way, \(plan.left - plan.moving) to do")
    }

    // MARK: Start here

    /// The move the tile's button makes: a page on GitHub, or a change in Linear.
    private enum Move {
        case link(String, URL, String)
        case start(LinearTeamContext.WorkflowState)
        case advance(LinearTeamContext.WorkflowState)
        case take
        case copyBranch(String)
        case none
    }

    private func states(of item: DeliveryPlan.Item) -> [LinearTeamContext.WorkflowState] {
        (item.issue.team.flatMap { teams[$0.id] }?.states ?? []).sorted { $0.position < $1.position }
    }

    private func move(for item: DeliveryPlan.Item, grab: Bool) -> Move {
        if grab { return store.viewerID == nil ? .none : .take }
        let pull = item.pull.flatMap { URL(string: $0.url) }
        switch item.situation {
        case .ciFailed:
            guard let url = item.pull?.runURL.flatMap(URL.init(string:)) ?? pull else { return .none }
            return .link("Fix CI", url, "Open the failing run on GitHub")
        case .changesRequested:
            return pull.map { .link("See review", $0, "Open the pull request on GitHub") } ?? .none
        case .reviewRequested:
            return pull.map { .link("Review", $0.appendingPathComponent("files"), "Open the changes on GitHub") } ?? .none
        case .readyToMerge:
            return pull.map { .link("Merge", $0, "Open the pull request on GitHub to merge it") } ?? .none
        case .draft:
            return pull.map { .link("Open PR", $0, "Open the draft on GitHub") } ?? .none
        case .behind:
            let all = states(of: item)
            let target = all.first { $0.type == "started" && Delivery.isReviewState($0.name) } ?? all.first { $0.type == "completed" }
            return target.map { .advance($0) } ?? .none
        case .building:
            return item.issue.branchName.flatMap { $0.isEmpty ? nil : .copyBranch($0) } ?? .none
        case .todo:
            let target = states(of: item).first { $0.type == "started" && !Delivery.isReviewState($0.name) }
            return target.map { .start($0) } ?? .none
        case .waitingReview, .blocked:
            return .none
        }
    }

    /// Why this issue, in one short line.
    private func reason(_ item: DeliveryPlan.Item, grab: Bool) -> String {
        let number = item.pull.map { "#\($0.number)" } ?? ""
        switch item.situation {
        case .ciFailed: return "CI failed on \(number)"
        case .changesRequested: return "Changes requested on \(number)"
        case .reviewRequested: return "\(item.pull?.author ?? "Someone") asked for your review on \(number)"
        case .behind: return "\(item.merged.first.map { "#\($0.number)" } ?? "Its pull request") is merged, the ticket still says \(item.issue.state.name)"
        case .readyToMerge: return "Approved, \(number) is ready to merge"
        case .draft: return "\(number) is still a draft"
        case .building: return "In progress, no pull request yet"
        default:
            var parts = [grab ? "Unassigned" : nil,
                         (item.issue.priority ?? 0) == 0 ? nil : "\(LinearPriority.label(item.issue.priority)) priority",
                         LinearDate.short(item.issue.dueDate).map { "due \($0)" },
                         item.unblocks > 0 ? "unblocks \(item.unblocks)" : nil].compactMap { $0 }
            if parts.isEmpty { parts = ["Next in line"] }
            let line = parts.joined(separator: " · ")
            return line.prefix(1).uppercased() + line.dropFirst()
        }
    }

    /// The failed pull request whose card can be opened, where the feature is offered.
    private func failure(of item: DeliveryPlan.Item) -> FailureStore.Key? {
        guard item.situation == .ciFailed, let pull = item.pull, explainsFailures, intelligence.offers(.explainFailure) else { return nil }
        return .init(repository: pull.repository, number: pull.number)
    }

    private func startTile(_ item: DeliveryPlan.Item, grab: Bool) -> some View {
        let failure = failure(of: item)
        // A capture opens it on whichever pull request the demo starts with.
        let open = failure != nil && (why == failure || why?.number == 0)
        return startLink(item, grab: grab, failure: failure, open: open)
            // The card hangs over the rows under the tile.
            .zIndex(open ? 1 : 0)
    }

    private func startLink(_ item: DeliveryPlan.Item, grab: Bool, failure: FailureStore.Key?, open: Bool) -> some View {
        let move = move(for: item, grab: grab)
        let why = reason(item, grab: grab)
        // The failed state is the button: it opens the checks that failed and why.
        let ask = Button { Motion.run(Motion.ui, fade: true) { self.why = open ? nil : failure } } label: {
            HStack(spacing: 4) {
                Text(why)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(TertiaryButton(tint: open ? .ink : .muted, lift: Soot.surface, font: .system(size: 13), height: 24))
        .help("Show the checks that failed")
        .accessibilityLabel("\(why). Show the checks that failed")
        return NavigationLink(value: IssueRoute(project: project, issue: item.issue)) {
            HStack(alignment: .center, spacing: 14) {
                SituationGlyph(situation: item.situation, size: 22)
                VStack(alignment: .leading, spacing: 6) {
                    Text(grab ? "UP FOR GRABS" : "START HERE").font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Soot.lime)
                    Text(MarkdownTheme.inline(item.issue.title, size: 16)).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Soot.ink).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(verbatim: item.issue.identifier).font(.system(size: 12, weight: .medium, design: .monospaced))
                        if failure != nil {
                            // Room for the button, which sits on top so it takes its own click.
                            ask.hidden().accessibilityHidden(true).padding(.leading, -8)
                                .anchorPreference(key: WhyAnchor.self, value: .bounds) { $0 }
                        } else {
                            Text(why).lineLimit(1)
                        }
                    }
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
                }
                Spacer(minLength: 12)
                // Room for the action, which sits on top so it takes its own click.
                moveButton(move, item: item).hidden().accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Soot.ground, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(RowButton(lift: .tone, radius: 10))
        .accessibilityLabel("\(grab ? "Up for grabs" : "Start here"): \(item.issue.identifier), \(item.issue.title). \(why)")
        .accessibilityHint("Opens the issue")
        .overlay(alignment: .trailing) { moveButton(move, item: item).padding(.trailing, 16) }
        .overlayPreferenceValue(WhyAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor, failure != nil {
                    let place = proxy[anchor]
                    ask
                        .failureCard(open: open, key: failure, heading: item.pull.map { "#\($0.number) \($0.title)" } ?? "",
                                     url: item.pull.flatMap { URL(string: $0.url) }, drop: 30) {
                            Motion.run(Motion.ui, fade: true) { self.why = nil }
                        }
                        .position(x: place.midX, y: place.midY)
                }
            }
        }
    }

    @ViewBuilder
    private func moveButton(_ move: Move, item: DeliveryPlan.Item) -> some View {
        switch move {
        case .link(let label, let url, let help):
            Link(destination: url) {
                HStack(spacing: 5) {
                    Text(label)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
                }
            }
            .buttonStyle(PrimaryButton())
            .help(help)
            .accessibilityHint("Opens on GitHub")
        case .start(let state):
            Button("Start") { start(item, in: state) }
                .buttonStyle(PrimaryButton())
                .help("Move \(item.issue.identifier) to \(state.name) in Linear\(item.issue.branchName == nil ? "" : " and copy its branch name")")
        case .advance(let state):
            Button("Move to \(state.name)") { advance(item, to: state) }
                .buttonStyle(PrimaryButton())
                .help("Move \(item.issue.identifier) to \(state.name) in Linear")
        case .take:
            Button("Take it") { take(item) }
                .buttonStyle(PrimaryButton())
                .help("Assign \(item.issue.identifier) to you in Linear")
        case .copyBranch(let branch):
            Button("Copy branch") {
                copy(branch)
                show(Notice(text: "Branch name copied"))
            }
            .buttonStyle(SecondaryButton())
            .help(branch)
        case .none:
            EmptyView()
        }
    }

    // MARK: Actions

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func start(_ item: DeliveryPlan.Item, in state: LinearTeamContext.WorkflowState) {
        let branch = item.issue.branchName.flatMap { $0.isEmpty ? nil : $0 }
        if let branch { copy(branch) }
        write(item, note: "\(item.issue.identifier) moved to \(state.name)\(branch == nil ? "" : " · branch name copied")",
              change: .init(stateID: state.id),
              undo: .init(issueID: item.issue.id, state: item.issue.state)) {
            $0.state = .init(id: state.id, name: state.name, type: state.type, color: state.color)
        }
    }

    private func advance(_ item: DeliveryPlan.Item, to state: LinearTeamContext.WorkflowState) {
        write(item, note: "\(item.issue.identifier) moved to \(state.name)", change: .init(stateID: state.id),
              undo: .init(issueID: item.issue.id, state: item.issue.state)) {
            $0.state = .init(id: state.id, name: state.name, type: state.type, color: state.color)
        }
    }

    private func take(_ item: DeliveryPlan.Item) {
        guard let me = store.viewerID else { return }
        let account = app.linear?.account
        write(item, note: "\(item.issue.identifier) is yours", change: .init(assigneeID: .some(me)),
              undo: .init(issueID: item.issue.id, restoresAssignee: true, assigneeID: item.issue.assignee?.id)) {
            $0.assignee = .init(id: me, name: account?.userName ?? "You", avatarUrl: account?.avatarUrl)
        }
    }

    /// Shows the new value at once, tells Linear, and puts the old value back if Linear refuses.
    private func write(_ item: DeliveryPlan.Item, note: String, change: LinearClient.IssueChange, undo: Notice.Undo?,
                       mutate: (inout LinearIssue) -> Void) {
        let previous = item.issue
        var optimistic = previous
        mutate(&optimistic)
        Task {
            do {
                try await store.update(previous.id, change: change, optimistic: optimistic, previous: previous, app: app)
                show(Notice(text: note, undo: undo))
            } catch {
                show(Notice(text: "Not saved: \(error.localizedDescription)", failed: true))
            }
        }
    }

    private func undo(_ undo: Notice.Undo) {
        guard let current = store.row(undo.issueID) else { return }
        var change = LinearClient.IssueChange()
        var restored = current
        if undo.restoresAssignee {
            change.assigneeID = .some(undo.assigneeID)
            restored.assignee = nil
        } else if let state = undo.state, let stateID = state.id {
            change.stateID = stateID
            restored.state = state
        } else { return }
        Task {
            do {
                try await store.update(current.id, change: change, optimistic: restored, previous: current, app: app)
                show(Notice(text: "Undone"))
            } catch {
                show(Notice(text: "Not undone: \(error.localizedDescription)", failed: true))
            }
        }
    }

    private func show(_ new: Notice) {
        noticeTask?.cancel()
        notice = new
        AccessibilityNotification.Announcement(new.text).post()
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: new.failed || new.undo != nil ? 8_000_000_000 : 3_000_000_000)
            if !Task.isCancelled { notice = nil }
        }
    }

    private func noticeLine(_ n: Notice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: n.failed ? "exclamationmark.triangle.fill" : "checkmark").font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text(n.text).lineLimit(2)
            if let undo = n.undo {
                Button("Undo") { self.undo(undo) }
                    .buttonStyle(TertiaryButton(tint: .ink))
                    .help("Put the issue back as it was in Linear")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(n.failed ? Theme.negative : Soot.lime)
        .padding(.horizontal, 12)
        .frame(minHeight: Buttons.textHeight)
    }

    private var teamIDs: [String] {
        Array(Set(([plan.start].compactMap { $0 } + plan.next).compactMap { $0.issue.team?.id })).sorted()
    }

    /// The workflow states behind "Start" and "Move to …"; without them the tile only opens the issue.
    private func loadTeams() async {
        for id in teamIDs where teams[id] == nil {
            if let context = try? await store.team(id, app: app) { teams[id] = context }
        }
    }

    // MARK: Rows

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(Soot.ink)
            Text("\(count)").foregroundStyle(Soot.muted).monospacedDigit().rollingNumber(count)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12).padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "5 h", "4 d", "3 w": how long something has been waiting.
    private static func age(_ date: Date) -> String {
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        if hours < 1 { return "now" }
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return days < 14 ? "\(days) d" : "\(days / 7) w"
    }

    /// The row's word: the situation, with what makes it precise (the blocker, the wait).
    private func word(_ item: DeliveryPlan.Item) -> String {
        switch item.situation {
        case .blocked:
            let more = item.blockedBy.count - 1
            return "Blocked by \(item.blockedBy.first ?? "another issue")\(more > 0 ? " +\(more)" : "")"
        case .building where item.pull == nil: return "In progress · no PR"
        case .todo where item.unblocks > 0: return "To do · unblocks \(item.unblocks)"
        default: return item.situation.label
        }
    }

    /// One open issue: its situation as a glyph, key, title, the situation in words with how
    /// long it has waited, then its pull request. The row opens the issue; the chip, GitHub.
    private func row(_ item: DeliveryPlan.Item, showsPerson: Bool) -> some View {
        let issue = item.issue
        let waits = [.waitingReview, .building, .draft].contains(item.situation) ? item.since.map(Self.age) : nil
        let urgent = [.ciFailed, .changesRequested, .reviewRequested, .behind].contains(item.situation)
        let spoken = [word(item), waits.map { "for \($0)\(item.stale ? ", stale" : "")" },
                      item.pull.map { "pull request #\($0.number)" },
                      showsPerson ? (issue.assignee.map { "assigned to \($0.name)" } ?? "unassigned") : nil,
                      item.situation == .todo ? "\(LinearPriority.label(issue.priority)) priority" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        return WorkTile(value: IssueRoute(project: project, issue: issue), trailing: {
            if let pull = item.pull, let url = URL(string: pull.url) {
                PullChip(number: pull.number, kind: pull.draft ? .draft : .open, pipeline: pull.pipeline, title: pull.title,
                         repository: labelsRepository ? pull.repository : nil, url: url)
            } else if let merged = item.merged.first, let url = URL(string: merged.url) {
                PullChip(number: merged.number, kind: .merged, title: merged.title,
                         repository: labelsRepository ? merged.repository : nil, url: url)
            }
            if showsPerson { person(issue) }
        }) {
            SituationGlyph(situation: item.situation)
            IDPill(text: issue.identifier)
            Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.ink).lineLimit(1)
                .help(issue.title)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Text(word(item)).font(.system(size: 12, weight: urgent ? .semibold : .medium))
                    .foregroundStyle(urgent ? Soot.ink : Soot.muted)
                if let waits {
                    HStack(spacing: 3) {
                        if item.stale { Image(systemName: "clock.badge.exclamationmark").font(.system(size: 11, weight: .semibold)) }
                        Text(waits).monospacedDigit()
                    }
                    .font(.system(size: 12, weight: item.stale ? .semibold : .regular))
                    .foregroundStyle(item.stale ? Theme.chart3 : Soot.muted)
                    .help(item.stale ? "No activity for \(waits)" : "Last activity \(waits) ago")
                }
                if item.situation == .todo || item.situation == .blocked {
                    DueDateText(dueDate: issue.dueDate)
                    PriorityGlyph(priority: issue.priority, dimmed: issue.priority == nil || issue.priority == 0)
                        .help(LinearPriority.label(issue.priority))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
        }
        .accessibilityLabel("\(issue.identifier), \(issue.title). \(spoken)")
        .accessibilityHint("Opens the issue")
    }

    @ViewBuilder
    private func person(_ issue: LinearIssue) -> some View {
        if let person = issue.assignee {
            LinearAvatar(name: person.name, avatarURL: person.avatarUrl).help(person.name)
                .accessibilityLabel("Assigned to \(person.name)")
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Soot.muted)
                .help("Unassigned").accessibilityLabel("Unassigned")
        }
    }

    // MARK: Folded groups

    /// A group's head: a chevron, its name and count, and what it holds at a glance.
    private func fold<Accessory: View>(_ title: String, count: Int, open: Binding<Bool>, symbol: String? = nil,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        // The rows it reveals grow in the same transaction as the chevron's turn.
        Button { Motion.run(Motion.ui) { open.wrappedValue.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Soot.muted)
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                    .frame(width: 18)
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.positive)
                }
                Text(title).foregroundStyle(Soot.ink)
                Text("\(count)").foregroundStyle(Soot.muted).monospacedDigit().rollingNumber(count)
                accessory()
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RowButton(lift: .ground))
        .accessibilityLabel("\(title), \(count)")
        .accessibilityValue(open.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint(open.wrappedValue ? "Collapses the list" : "Expands the list")
    }

    /// The others' issues, folded: the ones in trouble (red pipeline, overdue) stay in sight.
    @ViewBuilder
    private var othersGroup: some View {
        let people = plan.others.reduce(into: [LinearIssue.Person]()) { list, item in
            if let p = item.issue.assignee, !list.contains(where: { $0.name == p.name }) { list.append(p) }
        }
        fold("Others", count: plan.others.count, open: $showsOthers) {
            HStack(spacing: -5) {
                ForEach(people.prefix(4), id: \.name) { p in
                    LinearAvatar(name: p.name, avatarURL: p.avatarUrl, size: 18)
                        .overlay(Circle().strokeBorder(Soot.surface, lineWidth: 1.5))
                }
            }
            .padding(.leading, 4)
            .accessibilityHidden(true)
        }
        ForEach(showsOthers ? plan.others : plan.others.filter(\.inTrouble)) { item in
            row(item, showsPerson: true).transition(.opacity)
        }
    }

    @ViewBuilder
    private var shippedGroup: some View {
        fold("Shipped", count: plan.shipped.count, open: $showsShipped, symbol: "checkmark") { EmptyView() }
        if showsShipped {
            let list = showsAllShipped ? plan.shipped : Array(plan.shipped.prefix(Self.shippedCap))
            ForEach(list) { shippedRow($0).transition(.opacity) }
            if plan.shipped.count > Self.shippedCap {
                ShowAllButton(count: plan.shipped.count, expanded: $showsAllShipped).padding(.leading, 8)
            }
        }
    }

    // MARK: Where the work is

    /// Where a shipped issue's code is: on staging until a release took it to production.
    /// Nil when the release line does not follow the pull request's repository.
    private func environment(_ item: DeliveryPlan.Shipped) -> (ReleaseStore.Environment, Date)? {
        guard let state = release.state,
              let merged = item.merged.filter({ $0.repository == state.repository }).compactMap({ m in m.mergedAt.map { (m, $0) } })
                .max(by: { $0.1 < $1.1 }) else { return nil }
        return (state.environment(mergedAt: merged.1), merged.1)
    }

    /// The shipped issues still on staging, newest first.
    private var onStaging: [DeliveryPlan.Shipped] {
        plan.shipped.filter { environment($0)?.0 == .staging }
    }

    /// One quiet line under the bar: what is on staging to test, and the preview when it is live.
    @ViewBuilder
    private var whereLine: some View {
        let staging = onStaging
        let preview = previews.state(for: project)?.status
        let live = preview?.phase == .live ? preview : nil
        if !staging.isEmpty || live != nil {
            HStack(spacing: 14) {
                if !staging.isEmpty {
                    Label { Text("\(staging.count) on staging").monospacedDigit() } icon: {
                        Image(systemName: "testtube.2").foregroundStyle(Theme.chart2)
                    }
                    .help("Merged, waiting for the next release: " + staging.prefix(8).map(\.issue.identifier).joined(separator: ", "))
                }
                if let live {
                    Label { Text(verbatim: "#\(live.pull.number) in preview") } icon: {
                        Image(systemName: "globe").foregroundStyle(Theme.positive)
                    }
                    .help("The preview of pull request #\(live.pull.number) is live")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Soot.muted)
            .labelStyle(QuietLabel())
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    /// A shipped issue, stepped back: key, title, "in QA" while the ticket has not closed, its pull request.
    private func shippedRow(_ item: DeliveryPlan.Shipped) -> some View {
        let issue = item.issue
        return WorkTile(value: IssueRoute(project: project, issue: issue), trailing: {
            if let merged = item.merged.first, let url = URL(string: merged.url) {
                PullChip(number: merged.number, kind: .merged, title: merged.title,
                         repository: labelsRepository ? merged.repository : nil, url: url)
            }
        }) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Soot.muted).frame(width: 18)
                .accessibilityHidden(true)
            IDPill(text: issue.identifier)
            Text(MarkdownTheme.inline(issue.title, size: 14)).font(.system(size: 14)).foregroundStyle(Soot.muted).lineLimit(1)
                .help(issue.title)
            Spacer(minLength: 12)
            if item.inQA {
                Text("in QA").font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted).fixedSize()
                    .help("Merged; the ticket is still \(issue.state.name) in Linear")
            }
            if let (env, at) = environment(item) {
                EnvironmentPill(environment: env, since: at)
            }
        }
        .accessibilityLabel("\(issue.identifier), \(issue.title). Shipped\(item.inQA ? ", still in QA" : "")"
                            + (environment(item).map { $0.0 == .staging ? ", on staging" : ", in production" } ?? ""))
        .accessibilityHint("Opens the issue")
    }
}

/// Where a shipped issue's code is, as a small pill: on staging (and since when), or in
/// production. The word carries it; the tint only repeats it.
private struct EnvironmentPill: View {
    let environment: ReleaseStore.Environment
    let since: Date

    var body: some View {
        let staging = environment == .staging
        Text(staging ? "Staging · \(Brief.ago(since))" : "Prod")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(staging ? Theme.chart2 : Soot.muted)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background((staging ? Theme.chart2 : Soot.muted).opacity(0.12), in: Capsule())
            .fixedSize()
            .help(staging ? "Merged \(since.formatted(.relative(presentation: .named))), waiting for the next release" : "In production")
    }
}

/// A label whose icon sits close and small, for one quiet line of facts.
private struct QuietLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            configuration.title
        }
    }
}
