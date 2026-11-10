import SwiftUI

/// Settings › Overview: how the project list is ordered, grouped and drawn. The same view
/// serves the page's own View popover (`compact`), where the controls sit under their
/// labels so the whole thing fits 340px. Every change lands in `AppState.overview` and the
/// Overview follows at once. Pinned projects always come first: there is no switch for it.
struct OverviewSettingsView: View {
    @EnvironmentObject var app: AppState
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preferences.quietAfterDaysKey) private var quietAfter = 14

    private var settings: Binding<OverviewSettings> { $app.overview }
    private var isDefault: Bool { app.overview == OverviewSettings() && quietAfter == 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                Text("View").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 0) {
                    choices
                    row(title: "Columns") { ColumnChips(columns: settings.columns, alignment: .leading) }
                    hideFinished
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                SectionHead(title: "Overview")
                // The list in miniature: it follows every choice below, and its column
                // heads are the switches for the columns.
                ListMiniature(settings: settings)
                Text("Click a column to hide it · Pinned projects always come first")
                    .font(.system(size: 13)).foregroundStyle(Soot.muted)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                SettingRows {
                    choices
                    SettingRow(title: "Quiet after", detail: "Without a Slack message") {
                        SegmentPicker(label: "A project is quiet after",
                                      options: Preferences.quietChoices.map { (label: "\($0) days", value: $0) },
                                      selection: $quietAfter)
                    }
                    hideFinished
                }
                Button("Reset to defaults") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        app.overview = OverviewSettings()
                        quietAfter = 14
                    }
                }
                .buttonStyle(SecondaryButton())
                .padding(.top, 16)
                .disabled(isDefault)
            }
        }
    }

    @ViewBuilder private var choices: some View {
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
    }

    private var hideFinished: some View {
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

/// The project list drawn small: a pinned row on top, the groups, the row height and the
/// finished row follow the settings. Each column's head is a chip that shows or hides it;
/// a hidden column keeps its place, empty, so the heads never move under the pointer.
private struct ListMiniature: View {
    @Binding var settings: OverviewSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Line: Identifiable {
        let id: Int
        var pinned = false
        var finished = false
        let name: CGFloat      // width of the name bar
        let progress: CGFloat  // share of issues done
        let health: Color
    }

    private let lines = [
        Line(id: 0, pinned: true, name: 64, progress: 0.6, health: Soot.lime),
        Line(id: 1, name: 48, progress: 0.3, health: Theme.negative),
        Line(id: 2, name: 72, progress: 0.8, health: Soot.lime),
        Line(id: 3, finished: true, name: 56, progress: 1, health: Soot.muted),
    ]

    private var rowHeight: CGFloat { settings.density == .compact ? 16 : 24 }
    private var grouped: Bool { settings.group != .none }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 92, height: 1)
                ForEach(OverviewSettings.Column.allCases) { column in
                    head(column).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            ForEach(lines) { line in
                if grouped, line.id == 0 || line.id == 2 {
                    HStack {
                        Capsule().fill(Soot.muted).frame(width: line.id == 0 ? 40 : 30, height: 4)
                        Spacer()
                    }
                    .frame(height: 16)
                    .transition(.opacity)
                }
                if !(line.finished && settings.hideFinished) {
                    row(line).transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Columns")
    }

    private func head(_ column: OverviewSettings.Column) -> some View {
        let on = settings.columns.contains(column)
        return Button {
            if on { settings.columns.remove(column) } else { settings.columns.insert(column) }
        } label: {
            Text(column.chip)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Soot.limeInk : Soot.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .frame(height: 26)
        }
        .buttonStyle(ChipButton(on: on, fill: Soot.surface))
        .help(column.detail)
        .accessibilityLabel("\(column.chip) column")
        .accessibilityValue(on ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
    }

    private func row(_ line: Line) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Soot.lime)
                    .opacity(line.pinned ? 1 : 0)
                Capsule().fill(Soot.ink).frame(width: line.name, height: 5)
                Spacer(minLength: 0)
            }
            .frame(width: 92)
            ForEach(OverviewSettings.Column.allCases) { column in
                cell(column, line)
                    .frame(maxWidth: .infinity)
                    .opacity(settings.columns.contains(column) ? 1 : 0)
            }
        }
        .frame(height: rowHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func cell(_ column: OverviewSettings.Column, _ line: Line) -> some View {
        let quiet = Soot.muted.opacity(0.55)
        switch column {
        case .slack:
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(quiet).frame(width: 3, height: CGFloat(3 + (i * 5 + line.id * 3) % 8))
                }
            }
        case .linear:
            Capsule().fill(quiet).frame(width: 36, height: 4)
                .overlay(alignment: .leading) { Capsule().fill(Soot.lime).frame(width: 36 * line.progress, height: 4) }
        case .github:
            HStack(spacing: 4) {
                Circle().fill(quiet).frame(width: 6, height: 6)
                Capsule().fill(quiet).frame(width: 18, height: 4)
            }
        case .preview:
            RoundedRectangle(cornerRadius: 2).fill(quiet).frame(width: 14, height: 10)
        case .target:
            Capsule().fill(quiet).frame(width: 24, height: 4)
        case .health:
            HStack(spacing: 4) {
                Circle().fill(line.health).frame(width: 6, height: 6)
                Capsule().fill(quiet).frame(width: 22, height: 4)
            }
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
