import SwiftUI

/// A Linear issue from a Slack message: title, description and priority, filled from the message
/// by the Mac's model when it is there, every field the user's to change. "Create" creates the
/// issue in the project's Linear project; nothing is sent before it.
struct IssueFromMessageSheet: View {
    /// What the sheet is opened on.
    struct Source: Identifiable {
        let message: SlackMessage
        let author: String
        /// The message in plain text.
        let text: String
        let permalink: URL?
        var id: String { message.ts }
    }

    let source: Source
    let linear: Project.LinearLink
    /// English name of the language the project's issues are written in.
    let language: String

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var status = IntelligenceStatus.shared
    @State private var title = ""
    @State private var description = ""
    @State private var priority = 0
    /// The model is writing; the fields are already the user's to type in.
    @State private var filling = false
    /// The fields came from the model and were not typed over since.
    @State private var filled = false
    @State private var creating = false
    @State private var failure: String?
    @FocusState private var describing: Bool

    private var input: IssueDraft.Input { .init(author: source.author, text: source.text, language: language) }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !creating }

    var body: some View {
        SheetScaffold(width: 560, header: {
            SheetTitle(title: "New issue", mark: { BrandLogo(service: .linear, size: 22).foregroundStyle(Soot.ink) },
                       close: { dismiss() })
        }, content: {
            VStack(alignment: .leading, spacing: 20) {
                origin
                SootField(label: "Title", placeholder: "What is to do", text: $title)
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Description")
                    TextEditor(text: $description)
                        .font(.system(size: 14)).foregroundStyle(Soot.ink)
                        .scrollContentBackground(.hidden)
                        .focused($describing)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .frame(height: 132)
                        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
                        .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
                            .strokeBorder(describing ? Soot.lime : Soot.edge, lineWidth: describing ? 2 : 1))
                        .accessibilityLabel("Description")
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Priority")
                    SegmentPicker(label: "Priority",
                                  options: LinearPriority.all.map { (label: $0.value == 0 ? "None" : $0.label, value: $0.value) },
                                  selection: $priority, width: nil, track: Soot.surface)
                }
            }
        }, footer: {
            HStack(spacing: 12) {
                if let failure {
                    Text(failure).font(.system(size: 12)).foregroundStyle(Soot.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("In \(linear.name)").font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButton())
                Button(creating ? "Creating" : "Create") { create() }
                    .buttonStyle(PrimaryButton(size: .sheet))
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
            }
        })
        .task { await fill() }
        // Typing over what the model wrote makes the text the user's: the mark goes.
        .onChange(of: title) { _, new in if filled, new != written?.title { filled = false } }
        .onChange(of: description) { _, new in if filled, new != written?.description { filled = false } }
    }

    /// Where the fields come from, said once above them: the message's author, and whether the
    /// Mac wrote them or is writing them.
    @ViewBuilder
    private var origin: some View {
        HStack(spacing: 8) {
            if filling {
                SummarisingLine(label: "Reading \(source.author)'s message")
            } else if filled {
                GeneratedMark(size: 11)
                Text("Filled from \(source.author)'s message").font(.system(size: 12)).foregroundStyle(Soot.muted)
            } else {
                Text("From \(source.author)'s message").font(.system(size: 12)).foregroundStyle(Soot.muted)
            }
        }
        .frame(height: 16)
        .motion(Motion.ui, fade: true, value: filling)
        .motion(Motion.ui, fade: true, value: filled)
    }

    /// What the model wrote, to tell it from what the user typed since.
    @State private var written: IssueDraft.Fields?

    /// The message's own words at once; the model's proposal when it lands, unless the user has
    /// started to write.
    private func fill() async {
        let plain = IssueDraft.plain(input)
        title = plain.title; description = plain.description; priority = plain.priority
        guard status.offers(.issueFromMessage) else { return }
        filling = true
        let fields = try? await IssueDraft.write(input)
        filling = false
        guard let fields, title == plain.title, description == plain.description else { return }
        written = fields
        Motion.run(Motion.ui, fade: true) {
            title = fields.title; description = fields.description; priority = fields.priority
            filled = true
        }
    }

    /// The sheet on a made-up message, for captures.
    static var sample: some View {
        IssueFromMessageSheet(
            source: .init(message: SlackMessage(ts: "1", user: nil, text: ""), author: "Kyryl",
                          text: "The tips list isn't refreshed after a language change, learners see and open tips in the previous language.",
                          permalink: nil),
            linear: .init(id: "sample", name: "Sample project", url: "https://linear.app"), language: "English")
    }

    private func create() {
        creating = true
        failure = nil
        let new = LinearClient.NewIssue(projectID: linear.id, title: title.trimmingCharacters(in: .whitespaces),
                                        description: IssueDraft.description(description, author: source.author, permalink: source.permalink),
                                        priority: priority)
        Task {
            do {
                _ = try await IssueStore.shared.create(new, app: app)
                dismiss()
            } catch {
                failure = "Linear did not create the issue. \(error.localizedDescription)"
                creating = false
            }
        }
    }
}
