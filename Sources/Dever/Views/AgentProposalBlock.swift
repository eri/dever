import SwiftUI

/// The acceptance criteria of an issue whose agent finished, read from its description and ticked
/// by the developer while reviewing the work; the ticks are theirs and local.
struct AcceptanceChecklist: View {
    @ObservedObject private var proposals = ProposalStore.shared
    let identifier: String
    let description: String?

    var body: some View {
        let list = AcceptanceCriteria.parse(description)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Acceptance criteria").font(.system(size: 12, weight: .medium)).foregroundStyle(Soot.muted)
                    .padding(.bottom, 4)
                ForEach(list, id: \.self) { criterion in
                    let on = proposals.isTicked(criterion, of: identifier)
                    Button { proposals.toggle(criterion, of: identifier) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 13))
                                .foregroundStyle(on ? Soot.lime : Soot.muted)
                                .accessibilityHidden(true)
                            Text(MarkdownTheme.inline(criterion, size: 13)).font(.system(size: 13))
                                .foregroundStyle(on ? Soot.muted : Soot.ink).strikethrough(on, color: Soot.muted)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 4)
                    }
                    .buttonStyle(RowButton(lift: .ground, radius: 6))
                    .padding(.horizontal, -4)
                    .accessibilityLabel(criterion)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
