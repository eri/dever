import SwiftUI

// "Why?" beside a failed pipeline (docs/on-device-ai.md, 5.6). The red state, the count and the
// word "failed" stay GitHub's; this adds, on a click only, the failed job as GitHub names it,
// one generated sentence, and the link to the real log, always.

/// The link that asks. Shown only where the feature is offered and the pipeline has failed.
struct WhyLink: View {
    var open: Bool
    /// The tone under it: `Soot.surface` on the page, `Soot.ground` on a panel.
    var lift: Color = Soot.surface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                Text("Why?")
            }
        }
        .buttonStyle(TertiaryButton(tint: .muted, lift: lift, font: .system(size: 12, weight: .semibold), height: 24))
        .help(open ? "Hide the explanation" : "Read the failed job's log on GitHub and say why. Generated on this Mac, may be wrong.")
        .accessibilityLabel(open ? "Hide why the pipeline failed" : "Why did the pipeline fail?")
    }
}

/// What Dever can say of a pull request's failure, in its place: skeleton lines while GitHub is
/// read, then the job, the sentence, the log.
struct FailurePanel: View {
    let key: FailureStore.Key
    /// The tone under the panel, for the hover of its links.
    var lift: Color = Soot.surface
    @ObservedObject private var store = FailureStore.shared
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch store.entry(key) {
            case .explained(let explanation): explained(explanation)
            case .problem(let problem):
                HStack(spacing: 4) {
                    Text(problem.text).font(.system(size: 13)).foregroundStyle(Soot.muted)
                    Button("Try again") { ask() }
                        .buttonStyle(TertiaryButton(tint: .ink, lift: lift, font: .system(size: 12, weight: .semibold), height: 24))
                }
            case .loading, nil:
                Skeleton(width: 220, height: 12).frame(height: 18)
                Skeleton(width: 320, height: 12).frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Motion.ui, fade: true, value: store.entry(key))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Why the pipeline failed")
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
        // The job and its step, as GitHub names them, and how old that run is.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack(spacing: 6) {
                Text(verbatim: e.check.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                    .lineLimit(1).truncationMode(.middle)
                if let step = e.check.step {
                    Text(verbatim: "› \(step)").lineLimit(1).truncationMode(.tail)
                }
                if let date = e.check.completedAt {
                    Text("· failed \(Brief.ago(date)) ago").fixedSize()
                        .help(date.formatted(date: .abbreviated, time: .shortened))
                }
                if e.others > 0 {
                    Text("· \(e.others) more failed").fixedSize()
                }
            }
            .font(.system(size: 13)).foregroundStyle(Soot.muted)
        }
        switch e.outcome {
        case .writing:
            HStack(alignment: .top, spacing: 8) {
                GeneratedMark().frame(height: 18)
                Skeleton(width: 300, height: 12).frame(height: 18)
            }
        case .sentence(let sentence):
            HStack(alignment: .top, spacing: 8) {
                GeneratedMark().frame(height: 18)
                Text(sentence).font(.system(size: 13)).foregroundStyle(Soot.ink.opacity(0.92)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        case .doesNotSay: fixed("The log does not say why.")
        case .noLog: fixed("This check has no log Dever can read.")
        case .unreadable: fixed("The log can't be read from here.")
        case .silent: EmptyView()
        }
        if let url = URL(string: e.check.url), url.scheme != nil {
            ExternalLink("Open log", destination: url, tint: .ink, lift: lift, font: .system(size: 12, weight: .semibold))
                .padding(.leading, -8)
                .help("Open this job's log on GitHub")
        }
    }

    /// Dever's own words, when there is nothing to generate: no sparkle.
    private func fixed(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Soot.muted)
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
