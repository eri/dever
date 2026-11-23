import Foundation
import SwiftUI

/// Marks projects as done and reopens them, in Dever and in the tools, and keeps the one thing
/// a done project is still watched for: a Slack message that names the user.
///
/// Data contract (docs/data-freshness.md):
/// - Reads: the Linear project's status when the confirmation opens (`IssueStore.status`), the
///   preview as `PreviewStore` holds it; for each done project with a channel, the messages
///   since the newest one seen, every ten minutes (`watch`).
/// - Writes: the Linear project's status (optimistic, reconciled, restored on refusal:
///   `IssueStore.moveProject`), the preview's delete command (`PreviewStore.delete`, the panel's
///   own path). One failing is reported and does not undo the other, nor the mark itself.
/// - Invalidates: the Overview's list and the rail (they follow `AppState.projects`).
@MainActor
final class CompletionStore: ObservableObject {
    static let shared = CompletionStore()

    /// A mention on a done project, as the Overview lists it.
    typealias Mention = ProjectSnapshot.SlackStats.Mention

    /// The done projects where someone named the user since, by project, newest first.
    @Published private(set) var mentions: [UUID: [Mention]] = [:]
    /// The project just marked as done, for the few seconds "Undo" is offered.
    @Published private(set) var undo: Undo?
    private var undoExpiry: Task<Void, Never>?
    /// The newest message seen in each done project's channel: where the next look starts.
    private var seen: [UUID: String] = [:]
    private var lastWatch: Date?
    private var watching = false

    struct Undo: Equatable {
        var project: UUID
        var name: String
        /// The Linear project was moved: undoing moves it back.
        var movedLinear: Bool
        /// The preview's delete command was posted: undoing cannot take it back.
        var deletedPreview: Bool
    }

    static let undoFor: TimeInterval = 10

    // MARK: Snapshots

    /// `DEVER_SNAPSHOT_DONE=<scene>` (with `DEVER_SNAPSHOT_DIR`): see docs/DEVELOPMENT.md.
    static var snapshotScene: String? {
        guard Snapshotter.directory != nil else { return nil }
        return ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_DONE"]
    }

    /// The confirmation's lines in a snapshot run: both, from made-up states.
    static var demoSteps: [ProjectCompletion.Step]? {
        guard snapshotScene != nil else { return nil }
        return [.init(kind: .linear, title: "Move the Linear project to Completed", detail: "Now In Progress"),
                .init(kind: .preview, title: "Delete the preview of #4714", detail: "Posts /delete-preview on the pull request")]
    }

    func setDemo(mentions: [UUID: [Mention]], undo: Undo?) {
        self.mentions = mentions
        self.undo = undo
    }

    // MARK: Marking as done

    /// The lines of the confirmation for a project, the Linear status read now so the line
    /// says what is true (a refusal to answer leaves the line as last known).
    func steps(for project: Project, app: AppState) async -> [ProjectCompletion.Step] {
        if let demo = Self.demoSteps { return demo }
        var status = project.linear.flatMap { IssueStore.shared.statuses[$0.id] }
        if let linear = project.linear, app.linear != nil,
           let read = try? await IssueStore.shared.status(project: linear.id, app: app) {
            status = read
        }
        return ProjectCompletion.steps(project, linearStatus: status, linearConnected: app.linear != nil,
                                       preview: PreviewStore.shared.state(for: project)?.status, githubConnected: app.github != nil)
    }

    /// Marks the project as done at once, then does what was left ticked in the tools.
    /// - Returns: what could not be done, by step. The project stays done either way.
    func markDone(_ project: Project, steps: Set<ProjectCompletion.Step.Kind>, app: AppState) async -> [ProjectCompletion.Step.Kind: String] {
        let previous = project.linear.flatMap { IssueStore.shared.statuses[$0.id] }
        let movesLinear = steps.contains(.linear) && project.linear != nil
        Motion.run(Motion.move) { app.markDone(project, previousLinearStatus: movesLinear ? previous : nil) }
        var failures: [ProjectCompletion.Step.Kind: String] = [:]
        guard Self.snapshotScene == nil else { return failures }
        var moved = false, deleted = false
        if movesLinear, let linear = project.linear {
            do {
                let before = try await IssueStore.shared.moveProject(linear.id, app: app)
                moved = true
                // The status read when the move was made is the one to offer back.
                if before != previous, let i = app.projects.firstIndex(where: { $0.id == project.id }) {
                    app.projects[i].linearStatusBeforeDone = before
                }
            } catch {
                failures[.linear] = error.localizedDescription
                app.forgetLinearStatusBeforeDone(project.id)
            }
        }
        if steps.contains(.preview) {
            do {
                try await PreviewStore.shared.delete(project, app: app)
                deleted = true
            } catch {
                failures[.preview] = error.localizedDescription
            }
        }
        offerUndo(.init(project: project.id, name: project.name, movedLinear: moved, deletedPreview: deleted))
        return failures
    }

    /// One step again, after it failed.
    func retry(_ kind: ProjectCompletion.Step.Kind, project: Project, app: AppState) async -> String? {
        do {
            switch kind {
            case .linear:
                guard let linear = project.linear else { return nil }
                let before = try await IssueStore.shared.moveProject(linear.id, app: app)
                if let i = app.projects.firstIndex(where: { $0.id == project.id }) { app.projects[i].linearStatusBeforeDone = before }
            case .preview:
                try await PreviewStore.shared.delete(project, app: app)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func offerUndo(_ value: Undo) {
        undoExpiry?.cancel()
        Motion.run(Motion.ui) { undo = value }
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.undoFor * 1_000_000_000))
            guard !Task.isCancelled else { return }
            Motion.run(Motion.ui, fade: true) { self?.undo = nil }
        }
    }

    func dismissUndo() {
        undoExpiry?.cancel()
        Motion.run(Motion.ui, fade: true) { undo = nil }
    }

    /// Takes the mark back, right after it: the project returns, and so does its Linear status
    /// when Dever moved it. A deleted preview stays deleted.
    func undoDone(app: AppState) async -> String? {
        guard let undo, let project = app.projects.first(where: { $0.id == undo.project }) else { return nil }
        dismissUndo()
        return await reopen(project, restoreLinear: undo.movedLinear, app: app)
    }

    // MARK: Reopening

    /// Puts the project back in the rail and the list; it is read again at once
    /// (`OverviewStore.relinked`). Linear is touched only when asked.
    /// - Returns: why the Linear project could not be moved back, when it could not.
    func reopen(_ project: Project, restoreLinear: Bool, app: AppState) async -> String? {
        let back = project.linearStatusBeforeDone
        mentions[project.id] = nil
        seen[project.id] = nil
        if undo?.project == project.id { dismissUndo() }
        Motion.run(Motion.move) { app.reopen(project) }
        guard restoreLinear, let back, let linear = project.linear, Self.snapshotScene == nil else { return nil }
        do {
            try await IssueStore.shared.moveProject(linear.id, to: back, app: app)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: The mention exception

    /// The channel was read up to `ts`, in Dever: the mentions before it are no longer waiting.
    func slackRead(_ project: UUID, upTo ts: String) {
        guard let held = mentions[project] else { return }
        let left = held.filter { !SlackTS.isAtOrBefore($0.ts, ts) }
        if left.count != held.count { Motion.run(Motion.ui) { mentions[project] = left.isEmpty ? nil : left } }
    }

    /// A project that is no longer done, or gone: nothing is kept of it.
    private func prune(_ app: AppState) {
        let done = Set(app.projects.filter(\.isDone).map(\.id))
        for id in mentions.keys where !done.contains(id) { mentions[id] = nil }
        for id in seen.keys where !done.contains(id) { seen[id] = nil }
    }

    /// Looks at the done projects' channels for a message that names the user, when it is time
    /// (`ProjectCompletion.watchInterval`). Cost: one `conversations.history` per done project
    /// with a channel, from the newest message seen (about 0.2 kB when nothing is new); only
    /// when a mention is found or held, one `conversations.info` more for Slack's read cursor.
    /// Six requests an hour per done project, two in Low Power Mode. Replies inside a thread
    /// are not seen, as on the active projects' rows.
    func watch(_ app: AppState, force: Bool = false) async {
        guard Self.snapshotScene == nil, OverviewDemo.scene == nil, !watching else { return }
        prune(app)
        guard force || ProjectCompletion.isWatchDue(last: lastWatch, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) else { return }
        let watched = ProjectCompletion.cycle(app.projects).watched
        guard !watched.isEmpty, let me = app.slack?.userID else { return }
        watching = true
        defer { watching = false; lastWatch = Date() }
        for project in watched {
            guard let channel = project.slack?.id, let cursor = ProjectCompletion.watchCursor(project, seen: seen[project.id]) else { continue }
            guard let page = try? await app.withSlack({ try await $0.historyAfter(channel, ts: cursor, limit: 100) }) else { continue }
            if let newest = page.messages.map(\.ts).max(by: { (Double($0) ?? 0) < (Double($1) ?? 0) }) { seen[project.id] = newest }
            let held = mentions[project.id] ?? []
            var found = ProjectCompletion.mentions(in: page.messages, me: me, after: cursor)
            guard !found.isEmpty || !held.isEmpty else { continue }
            // Names, and who is a bot, only once someone was named: the directory is kept a quarter of an hour.
            let team = app.slack?.teamID ?? ""
            let users = (try? await app.withSlack { try await SlackDirectory.shared.users(team: team, via: $0) }) ?? [:]
            found.removeAll { $0.user.flatMap { users[$0]?.isBot } == true }
            let lastRead = try? await app.withSlack { try await $0.lastRead(channel) }
            let fresh = found.filter { m in !held.contains { $0.ts == m.ts } }
                .map { Mention(ts: $0.ts, author: $0.user.flatMap { users[$0]?.name } ?? "Someone",
                               text: SlackPlain.text($0.text ?? "", users: users), date: $0.date) }
            let unread = ProjectCompletion.unread(fresh + held, ts: \.ts, lastRead: lastRead ?? nil)
            // The project may have been reopened while Slack answered.
            guard app.projects.first(where: { $0.id == project.id })?.isDone == true else { continue }
            Motion.run(Motion.ui) { mentions[project.id] = unread.isEmpty ? nil : unread }
            for mention in fresh where unread.contains(where: { $0.ts == mention.ts }) {
                Notifier.shared.mentioned(in: project, by: mention.author, text: mention.text, ts: mention.ts)
            }
        }
    }
}
