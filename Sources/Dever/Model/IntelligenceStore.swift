import AppKit
import Foundation

// What the Mac's model wrote, for the whole app's lifetime and in memory only: nothing generated
// is ever written to disk (docs/on-device-ai.md, rule 3). Views read this store; they never call
// the model themselves.

/// One use of the model. Each has its own switch in Settings › Intelligence, on by default.
enum IntelligenceFeature: String, CaseIterable, Identifiable, Sendable {
    case messageSummary, detectedMentions, issueSummary, draftReply, issueFromMessage, explainFailure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .messageSummary: "Long messages"
        case .detectedMentions: "Detected mentions"
        case .issueSummary: "Issue summary"
        case .draftReply: "Draft a reply"
        case .issueFromMessage: "Issue from a message"
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
        case summaries = "Summaries", writing = "Writing", pipelines = "Pipelines"
        var id: String { rawValue }
        var features: [IntelligenceFeature] { IntelligenceFeature.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .messageSummary, .detectedMentions, .issueSummary: .summaries
        case .draftReply, .issueFromMessage: .writing
        case .explainFailure: .pipelines
        }
    }

    var settingKey: String { "intelligence.\(rawValue)" }

    /// The features that exist in this build. A feature not listed has no switch, no interface
    /// and no invitation; each phase of docs/on-device-ai.md adds its own here.
    static let built: Set<IntelligenceFeature> = [.messageSummary]

    /// Built, or shown for a capture (`DEVER_SNAPSHOT_INTELLIGENCE`).
    static var shipped: Set<IntelligenceFeature> {
        IntelligenceStatus.snapshotOverride == nil ? built : Set(allCases)
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
    static let shared = IntelligenceStore()

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

    /// Makes sure the subject has a text for `version`, writing one with `write` when it has not.
    /// Does nothing when that version is already written, being written, or was met with silence.
    func want(_ subject: Subject, version: String,
              write: @escaping @Sendable () async throws -> GeneratedText) {
        guard isOn(subject.feature) else { return drop(subject) }
        if let entry = entries[subject], entry.version == version { return }
        tasks[subject]?.cancel()
        entries[subject] = Entry(version: version, text: entries[subject]?.text, writing: true)
        tasks[subject] = Task { [weak self] in
            let text = try? await write()
            guard !Task.isCancelled, let self, self.entries[subject]?.version == version else { return }
            if let text, !text.isEmpty {
                self.entries[subject] = Entry(version: version, text: text)
            } else {
                self.entries[subject] = Entry(version: version, text: nil, silent: true)
            }
            self.tasks[subject] = nil
        }
    }

    /// The subject no longer has anything to describe (the channel was read, the issue closed).
    func drop(_ subject: Subject) {
        tasks.removeValue(forKey: subject)?.cancel()
        entries[subject] = nil
    }

    /// A switch was turned off: what the feature wrote goes with it.
    func drop(_ feature: IntelligenceFeature) {
        for subject in entries.keys where subject.feature == feature { drop(subject) }
    }

    /// Waits for whatever is being written; tests only.
    func settle() async {
        for task in tasks.values { await task.value }
    }
}
