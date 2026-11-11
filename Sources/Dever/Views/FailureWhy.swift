import SwiftUI

// A failed pipeline opens its own card (docs/on-device-ai.md, 5.6): the failed state is the
// button, as on the release line. The card lists the checks that failed as GitHub names them,
// each leading to its log, and under the first one sentence written on the Mac. The red state,
// the counts and the word "failed" stay GitHub's; nothing is read before the click.

/// The card under a failed pipeline: the pull request, its failed checks, why the first one
/// failed, and the way to GitHub. Built like the release line's card.
struct FailureCard: View {
    let key: FailureStore.Key
    /// The pull request, as the screen that opens the card names it.
    let heading: String
    let url: URL?
    @ObservedObject private var store = FailureStore.shared
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(2)
            switch store.entry(key) {
            case .explained(let explanation): explained(explanation)
            case .problem(let problem):
                HStack(spacing: 4) {
                    Text(problem.text).font(.system(size: 12)).foregroundStyle(Soot.muted)
                    Button("Try again") { ask() }
                        .buttonStyle(TertiaryButton(tint: .ink, lift: Soot.surface, font: .system(size: 12, weight: .semibold), height: 22))
                }
            case .loading, nil:
                Skeleton(width: 150, height: 11).frame(height: 16)
                Rectangle().fill(Soot.line).frame(height: 1)
                Skeleton(width: 200, height: 11).frame(height: 18)
                Skeleton(width: 260, height: 11).frame(height: 18)
            }
            if let url {
                ExternalLink("Open on GitHub", destination: url, lift: Soot.surface).padding(.leading, -8)
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .motion(Motion.ui, fade: true, value: store.entry(key))
        // Floats over what is under it: its links claim the cursor after its own arrow.
        .cursorPriority(2)
        .background(CursorArea(cursor: .arrow, priority: 1))
        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Failed checks of \(heading)")
        .onAppear { ask() }
    }

    private func ask() {
        guard let client = try? app.githubClient() else {
            return store.explain(key, reads: .init(failed: { _, _ in throw AppError.notConnected(.github) },
                                                    log: { _, _ in throw AppError.notConnected(.github) }, write: { _, _, _ in nil }))
        }
        store.explain(key, reads: .live(client))
    }

    @ViewBuilder
    private func explained(_ e: FailureStore.Explanation) -> some View {
        if let date = e.check.completedAt {
            // The run's age: an explanation is never fresher than the run it is about.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text("Failed \(Brief.ago(date)) ago").font(.system(size: 12)).foregroundStyle(Soot.muted)
                    .help(date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        Rectangle().fill(Soot.line).frame(height: 1)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(e.failed.prefix(6).enumerated()), id: \.offset) { _, check in
                HStack(spacing: 6) {
                    PipelineGlyph(state: .failing)
                    let name = check.step.map { "\(check.name) › \($0)" } ?? check.name
                    if let log = URL(string: check.url), log.scheme != nil {
                        Link(name, destination: log)
                            .buttonStyle(TertiaryButton(tint: .ink, lift: Soot.surface, font: .system(size: 12), height: 22))
                            .padding(.leading, -8)
                            .help("Open this check's log on GitHub")
                    } else {
                        Text(name).font(.system(size: 12)).foregroundStyle(Soot.ink)
                    }
                }
                .lineLimit(1)
                if check == e.check { why(e.outcome).padding(.leading, 20).padding(.bottom, 4) }
            }
            if e.failed.count > 6 {
                Text("and \(e.failed.count - 6) more").font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
            Text(summary(e)).font(.system(size: 12)).foregroundStyle(Soot.muted)
        }
    }

    /// What Dever can say of the first failed check, under its name and its log link.
    @ViewBuilder
    private func why(_ outcome: FailureStore.Outcome) -> some View {
        switch outcome {
        case .writing:
            HStack(alignment: .top, spacing: 6) {
                GeneratedMark(size: 10).frame(height: 16)
                Skeleton(width: 220, height: 10).frame(height: 16)
            }
        case .sentence(let sentence):
            HStack(alignment: .top, spacing: 6) {
                GeneratedMark(size: 10).frame(height: 16)
                Text(sentence).font(.system(size: 12)).foregroundStyle(Soot.ink.opacity(0.92)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        case .doesNotSay: fixed("The log does not say why.")
        case .noLog: fixed("No log Dever can read for this check.")
        case .unreadable: fixed("The log can't be read from here.")
        case .silent: EmptyView()
        }
    }

    /// Dever's own words, when there is nothing to generate: no sparkle.
    private func fixed(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Soot.muted)
    }

    private func summary(_ e: FailureStore.Explanation) -> String {
        var parts = ["\(e.failed.count) failing"]
        if e.running > 0 { parts.append("\(e.running) running") }
        parts.append("\(e.passing) passing")
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// Hangs the failure card under this trigger while `open`, inside the window: a click
    /// elsewhere or Escape closes it.
    func failureCard(open: Bool, key: FailureStore.Key?, heading: String, url: URL?, drop: CGFloat, close: @escaping () -> Void) -> some View {
        self.keepsMenuOpen()
            .overlay(alignment: .topLeading) {
                if open, let key {
                    FailureCard(key: key, heading: heading, url: url)
                        .keepsMenuOpen()
                        .offset(y: drop)
                        .transition(Motion.pop.combined(with: .offset(y: Motion.reduced ? 0 : -4)))
                }
            }
            .closesOnOutsideClick(open, close: close)
            .onExitCommand { if open { close() } }
    }
}

/// A pull request's pipeline as the app already holds it, for a screen that shows the pull
/// request without reading GitHub itself.
@MainActor
enum PullFailure {
    /// "https://github.com/owner/name/pull/12" as a repository and a number.
    nonisolated static func key(url: String) -> FailureStore.Key? {
        guard let parts = URL(string: url)?.pathComponents, parts.count >= 5, parts[3] == "pull", let number = Int(parts[4]),
              URL(string: url)?.host?.hasSuffix("github.com") == true else { return nil }
        return .init(repository: "\(parts[1])/\(parts[2])", number: number)
    }

    /// The pull request's checks have failed, by the store's copy, and when that copy was read.
    static func failed(_ key: FailureStore.Key, in store: GitHubStore) -> Date? {
        // Captures: `DEVER_SNAPSHOT_WHY=1` draws every open pull request as failed a moment ago.
        if Snapshotter.directory != nil, ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_WHY"] != nil { return Date() }
        guard let pull = store.repository(key.repository)?.state.pulls.first(where: { $0.number == key.number }),
              ProjectSnapshot.PipelineState(checks: pull.checks) == .failing else { return nil }
        return store.fetchedAt(key.repository)
    }

    /// Past twice the budget of a pull request's checks, a state is not drawn as current.
    static func isStale(_ readAt: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(readAt) > 120 }
}

/// Reports where the placeholder of an overlaid control sits, so the real one can be drawn there.
struct WhyAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}
