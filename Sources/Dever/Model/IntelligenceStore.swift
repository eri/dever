import AppKit
import Foundation

// What the Mac's model wrote, for the whole app's lifetime. In memory, with one exception: the
// summary of a long message is also kept on disk until its message is read or it grows old, so
// that it is not written again at every launch (`SummaryCache`; docs/on-device-ai.md, rule 3).
// Views read this store; they never call the model themselves.

/// One use of the model. Each has its own switch in Settings › Intelligence, on by default.
enum IntelligenceFeature: String, CaseIterable, Identifiable, Sendable {
    case messageSummary, detectedMentions, issueSummary, explainFailure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .messageSummary: "Long messages"
        case .detectedMentions: "Detected mentions"
        case .issueSummary: "Issue summary"
        case .explainFailure: "Explain a failure"
        }
    }

    /// One line under the title, only where the title does not say it.
    var detail: String? {
        switch self {
        case .messageSummary: "A summary in their place, the original one click away"
        case .detectedMentions: "Someone speaks of you without an @"
        default: nil
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case summaries = "Summaries", pipelines = "Pipelines"
        var id: String { rawValue }
        var features: [IntelligenceFeature] { IntelligenceFeature.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .messageSummary, .detectedMentions, .issueSummary: .summaries
        case .explainFailure: .pipelines
        }
    }

    var settingKey: String { "intelligence.\(rawValue)" }

    /// How far a feature is trusted. Beta: it runs on this Mac, it can be wrong, and the original
    /// is one click away; Settings says so (`betaMark`). A feature leaves beta here, case by case.
    enum Maturity: Sendable { case beta, settled }

    var maturity: Maturity { .beta }

    /// Where Settings › Intelligence says "Beta" for the features it lists: once beside the
    /// page's title while all of them are, on each row once some have left beta.
    enum BetaMark: Equatable, Sendable { case none, page, rows }

    static func betaMark(among shown: some Collection<IntelligenceFeature>) -> BetaMark {
        let beta = shown.filter { $0.maturity == .beta }.count
        return beta == 0 ? .none : beta == shown.count ? .page : .rows
    }

    /// What "Beta" means here, in short sentences.
    static let betaMeaning = "Runs on this Mac. It can be wrong. The original is always one click away."

    /// Under the page's title: what Intelligence is for, then what Beta means.
    static let purpose = "Dever reads the long parts for you, on this Mac."
    static let betaHeadline = purpose + " It can be wrong. The original is always one click away."

    /// The features that exist in this build. A feature not listed has no switch, no interface
    /// and no invitation; each phase of docs/on-device-ai.md adds its own here.
    static let built: Set<IntelligenceFeature> = [.messageSummary, .explainFailure]

    /// Built, or shown for a capture (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static var shipped: Set<IntelligenceFeature> {
        IntelligenceStatus.snapshotOverride == nil ? built : Set(allCases)
    }
}

/// What is announced and not built: a second model, downloaded to the Mac, for the jobs Apple's
/// built-in one cannot do (docs/local-model-benchmark.md). Nothing here runs a model; it decides
/// where the announcement shows.
enum LocalModelOutlook {
    /// The memory the benchmark's recommendation asks for.
    static let memoryFloor: UInt64 = 16 * 1_073_741_824

    static var appleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// The announcement is made only on a Mac the recommendation covers: Apple silicon with 16 GB
    /// or more. Elsewhere it would promise what may never reach that Mac.
    static func announced(memory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                          appleSilicon: Bool = LocalModelOutlook.appleSilicon) -> Bool {
        appleSilicon && memory >= memoryFloor
    }

    /// What it will bring, in the user's terms; the order of the picture in Settings.
    enum Promise: String, CaseIterable, Identifiable, Sendable {
        case channel = "A busy channel, caught up"
        case issue = "A long issue, summed up"
        case pipeline = "A failed pipeline, explained"
        var id: String { rawValue }
    }

    /// The benefit, never the model's size: "larger" reads as "heavier on my Mac".
    static let title = "Catch up without reading it all"
    static let terms = ["Runs entirely on this Mac", "Nothing leaves it"]

    /// Why a second model, in one line. `today`: this Mac shortens messages with Apple's model.
    static func reason(today: Bool) -> String {
        (today ? "Today Dever shortens one message at a time. " : "")
            + "A second model, an optional download, will take on a whole channel, issue or pipeline."
    }

    /// Settings › Intelligence exists when there is something to show on it: a built feature on a
    /// Mac that can run Apple's model (now or after a fix in System Settings), or the announcement.
    static func settingsPage(availability: IntelligenceAvailability, anyFeature: Bool, announced: Bool) -> Bool {
        (availability != .unsupported && anyFeature) || announced
    }
}

/// The user's choices, in UserDefaults; each key is named here once.
enum IntelligencePreferences {
    static let summaryLanguageKey = "intelligence.summaryLanguage"
    static let invitationDismissedKey = "intelligence.invitationDismissed"

    /// The language summaries are written in.
    enum SummaryLanguage: String, CaseIterable, Identifiable {
        case source, english
        var id: String { rawValue }
        var label: String { self == .source ? "Source" : "English" }
    }

    static func isOn(_ feature: IntelligenceFeature, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: feature.settingKey) as? Bool ?? true
    }

    static func summaryLanguage(defaults: UserDefaults = .standard) -> SummaryLanguage {
        SummaryLanguage(rawValue: defaults.string(forKey: summaryLanguageKey) ?? "") ?? .source
    }

    /// The language a summary of `text` is written in: the text's own, or English when Settings
    /// says so or the text's language cannot be told.
    static func language(forSummaryOf text: String, defaults: UserDefaults = .standard) -> String {
        guard summaryLanguage(defaults: defaults) == .source else { return "en" }
        return Intelligence.language(of: text) ?? "en"
    }
}

/// Whether the model can be used, kept current for views: read at launch, when the system says
/// it changed, and when the user comes back to Dever (from System Settings, say).
@MainActor
final class IntelligenceStatus: ObservableObject {
    static let shared = IntelligenceStatus()

    @Published private(set) var availability: IntelligenceAvailability

    /// Captures: `DEVER_SNAPSHOT_INTELLIGENCE=available|notReady|off|unsupported` stands in for the
    /// system's answer and shows every feature's interface, built or not.
    nonisolated static var snapshotOverride: IntelligenceAvailability? {
        ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_INTELLIGENCE"].flatMap(IntelligenceAvailability.init(rawValue:))
    }

    private let read: () -> IntelligenceAvailability

    init(read: @escaping () -> IntelligenceAvailability = { SystemLanguageModelClient().availability }) {
        self.read = read
        availability = Self.snapshotOverride ?? read()
        guard Self.snapshotOverride == nil else { return }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        watch()
    }

    func refresh() {
        let now = Self.snapshotOverride ?? read()
        if now != availability { availability = now }
    }

    private func watch() {
        SystemLanguageModelClient.onAvailabilityChange { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.watch()
            }
        }
    }

    /// `feature` has an interface right now: built, switched on, and the model is ready.
    func offers(_ feature: IntelligenceFeature) -> Bool {
        availability == .available && IntelligenceFeature.shipped.contains(feature) && IntelligencePreferences.isOn(feature)
    }
}

/// A generated text: sentences, each tied to the message it speaks of when there is one.
struct GeneratedText: Equatable, Sendable {
    struct Sentence: Equatable, Sendable, Identifiable {
        var text: String
        /// What the sentence rests on (a Slack message's `ts`); nil when it is about the whole.
        var source: String?
        /// The line that asks something of the user.
        var forYou = false
        var id: String { text }
    }
    var sentences: [Sentence]
    /// What the text covers when it is not everything ("Covers the last 15 unread messages").
    /// A fact about the input, written by Dever, not by the model.
    var note: String? = nil
    /// What kind of message a summary stands for ("Request", "Question", "Problem", "Update").
    var kind: String? = nil
    var isEmpty: Bool { sentences.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

@MainActor
final class IntelligenceStore: ObservableObject {
    /// Captures never read or write the user's summaries.
    static let shared = IntelligenceStore(cache: SummaryCache(url: IntelligenceStatus.snapshotOverride == nil ? SummaryCache.defaultURL : nil))

    /// Summaries of long messages, kept between launches. In memory only unless given a file.
    private(set) var cache: SummaryCache
    /// Slack's read cursor by channel, as last told: a summary of a read message is not kept.
    private var readUpTo: [String: String] = [:]

    init(cache: SummaryCache = SummaryCache(url: nil)) { self.cache = cache }

    /// What a text is about: a feature and its subject (a channel id, an issue id, a run id).
    struct Subject: Hashable, Sendable {
        let feature: IntelligenceFeature
        let id: String
    }

    struct Entry: Equatable {
        /// The input the entry was made from (first and last unread `ts`, an `updatedAt`): a
        /// different version means the text is out of date.
        var version: String
        /// The last text written, kept on screen while a newer one is being written.
        var text: GeneratedText?
        var writing = false
        /// The model had nothing to say for this version (refusal, overflow, error, empty).
        /// Shown as nothing, and not asked again until the input changes.
        var silent = false
    }

    @Published private(set) var entries: [Subject: Entry] = [:]
    private var tasks: [Subject: Task<Void, Never>] = [:]

    /// Whether features are switched on; replaced in tests.
    var isOn: (IntelligenceFeature) -> Bool = { IntelligencePreferences.isOn($0) }

    /// The text to show for a subject, whatever its version: an older one stays until the newer
    /// one lands, so the place never empties and refills.
    func text(_ subject: Subject) -> GeneratedText? { entries[subject]?.text }

    /// A text is being written and there is none to show yet: the place shows its skeleton.
    func isWriting(_ subject: Subject) -> Bool {
        guard let entry = entries[subject] else { return false }
        return entry.writing && entry.text == nil
    }

    /// A text is being written, whether or not an older one shows meanwhile.
    func isPending(_ subject: Subject) -> Bool { entries[subject]?.writing ?? false }

    /// The model was asked and had nothing to say: the place shows what it showed before.
    func isSilent(_ subject: Subject) -> Bool { entries[subject]?.silent ?? false }

    /// Makes sure the subject has a text for `version`, writing one with `write` when it has not.
    /// Does nothing when that version is already written, being written, or was met with silence.
    func want(_ subject: Subject, version: String,
              write: @escaping @Sendable () async throws -> GeneratedText) {
        guard isOn(subject.feature) else { return drop(subject) }
        if let entry = entries[subject], entry.version == version { return }
        // Written at an earlier launch from the same input: shown at once, the model is not asked.
        if subject.feature == .messageSummary, let kept = cache.record(subject.id, version: version) {
            tasks.removeValue(forKey: subject)?.cancel()
            entries[subject] = Entry(version: version, text: kept.text, silent: kept.text == nil)
            return
        }
        tasks[subject]?.cancel()
        entries[subject] = Entry(version: version, text: entries[subject]?.text, writing: true)
        tasks[subject] = Task { [weak self] in
            let text = try? await write()
            guard !Task.isCancelled, let self, self.entries[subject]?.version == version else { return }
            let written = text.flatMap { $0.isEmpty ? nil : $0 }
            self.entries[subject] = Entry(version: version, text: written, silent: written == nil)
            self.keep(subject, version: version, text: written)
            self.tasks[subject] = nil
        }
    }

    /// The subject no longer has anything to describe (the channel was read, the issue closed).
    func drop(_ subject: Subject) {
        tasks.removeValue(forKey: subject)?.cancel()
        entries[subject] = nil
    }

    /// A switch was turned off: what the feature wrote goes with it, on disk too.
    func drop(_ feature: IntelligenceFeature) {
        for subject in entries.keys where subject.feature == feature { drop(subject) }
        if feature == .messageSummary { cache.removeAll() }
    }

    /// A summary (or the model's silence) goes to disk while its message is unread.
    private func keep(_ subject: Subject, version: String, text: GeneratedText?) {
        guard subject.feature == .messageSummary, let slash = subject.id.lastIndex(of: "/") else { return }
        let channel = String(subject.id[..<slash]), ts = String(subject.id[subject.id.index(after: slash)...])
        if let cursor = readUpTo[channel], SummaryCache.isAtOrBefore(ts, cursor) { return }
        cache.save(subject.id, version: version, text: text)
    }

    /// The channel has been read up to `ts`: the summaries kept on disk for those messages have
    /// served and go, with any that has outlived the limit. What is on screen stays, in memory.
    func read(channel: String, upTo ts: String) {
        readUpTo[channel] = ts
        cache.dropRead(channel: channel, upTo: ts)
        cache.prune()
    }

    /// Waits for whatever is being written; tests only.
    func settle() async {
        for task in tasks.values { await task.value }
    }
}
