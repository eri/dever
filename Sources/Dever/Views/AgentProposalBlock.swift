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
                            SootCheckbox(on: on).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
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

/// A checkbox in the app's look: an 18-point rounded square that fills lime and draws its check
/// when ticked, with a small spring; the change is only faded under Reduce Motion.
struct SootCheckbox: View {
    let on: Bool
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(on && enabled ? Soot.lime : Color.clear)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(on && enabled ? Color.clear : Soot.muted.opacity(enabled ? 0.8 : 0.4), lineWidth: 1.5)
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Soot.limeInk)
                .scaleEffect(on && enabled ? 1 : (reduceMotion ? 1 : 0.4))
                .opacity(on && enabled ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.62), value: on)
        .accessibilityHidden(true)
    }
}
