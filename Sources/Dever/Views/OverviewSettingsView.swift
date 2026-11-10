import SwiftUI

/// Settings › Overview: how the project list is ordered, grouped and drawn. The same view
/// serves the page's own View popover (`compact`), where the controls sit under their
/// labels so the whole thing fits 340px. Every change lands in `AppState.overview` and the
/// Overview follows at once.
struct OverviewSettingsView: View {
    @EnvironmentObject var app: AppState
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: Binding<OverviewSettings> { $app.overview }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                Text("View").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                rows.padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                SectionHead(title: "Overview", detail: "How the project list reads")
                SettingRows { rows }
                Button("Reset to defaults") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { app.overview = OverviewSettings() }
                }
                .buttonStyle(SecondaryButton())
                .padding(.top, 16)
                .disabled(app.overview == OverviewSettings())
            }
        }
    }

    @ViewBuilder private var rows: some View {
        row(title: "Sort by") {
            SegmentPicker(label: "Sort projects by",
                          options: OverviewSettings.Sort.allCases.map { (label: $0.label, value: $0) },
                          selection: settings.sort)
        }
        row(title: "Group by") {
            SegmentPicker(label: "Group projects by",
                          options: OverviewSettings.Group.allCases.map { (label: $0.label, value: $0) },
                          selection: settings.group)
        }
        row(title: "Density") {
            SegmentPicker(label: "Row density",
                          options: OverviewSettings.Density.allCases.map { (label: $0.label, value: $0) },
                          selection: settings.density)
        }
        row(title: "Columns", detail: compact ? nil : "The project's name always shows") {
            ColumnChips(columns: settings.columns, alignment: compact ? .leading : .trailing)
        }
        row(title: "Pinned projects first", detail: compact ? nil : "Pin a project from its row", tap: { settings.pinFavourites.wrappedValue.toggle() }) {
            Toggle("Pinned projects first", isOn: settings.pinFavourites)
                .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
        }
        row(title: "Hide finished projects", detail: compact ? nil : "Every Linear issue done", divided: false,
            tap: { settings.hideFinished.wrappedValue.toggle() }) {
            Toggle("Hide finished projects", isOn: settings.hideFinished)
                .labelsHidden().toggleStyle(.switch).tint(Soot.lime).controlSize(.small)
        }
    }

    /// In Settings, a `SettingRow`; in the popover, the label above the control.
    @ViewBuilder
    private func row<Control: View>(title: String, detail: String? = nil, divided: Bool = true,
                                    tap: (() -> Void)? = nil, @ViewBuilder control: @escaping () -> Control) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                    if tap != nil { Spacer(minLength: 12); control() }
                }
                .contentShape(Rectangle())
                .onTapGesture { tap?() }
                .handCursor(tap != nil)
                if tap == nil { control() }
            }
            .padding(.vertical, 8)
        } else {
            SettingRow(title: title, detail: detail, divided: divided, tap: tap, control: control)
        }
    }
}

/// The columns as chips: lime when shown. Each is a toggle; the rest of the row keeps its place.
private struct ColumnChips: View {
    @Binding var columns: Set<OverviewSettings.Column>
    var alignment: HorizontalAlignment = .trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Two rows of three: the six chips do not fit a 56px row beside their label.
        VStack(alignment: alignment, spacing: 6) {
            ForEach([Array(OverviewSettings.Column.allCases.prefix(3)), Array(OverviewSettings.Column.allCases.suffix(3))], id: \.first) { line in
                HStack(spacing: 6) {
                    ForEach(line) { column in chip(column) }
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Columns")
    }

    private func chip(_ column: OverviewSettings.Column) -> some View {
        let on = columns.contains(column)
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                if on { columns.remove(column) } else { columns.insert(column) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.muted)
                    .accessibilityHidden(true)
                Text(column.chip)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? Soot.limeInk : Soot.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .buttonStyle(ChipButton(on: on))
        .help(column.detail)
        .accessibilityLabel("\(column.chip) column")
        .accessibilityValue(on ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
    }
}
