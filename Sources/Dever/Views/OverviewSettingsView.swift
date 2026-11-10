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
                    sorting
                    row(title: "Density") {
                        SegmentPicker(label: "Row density",
                                      options: OverviewSettings.Density.allCases.map { (label: $0.label, value: $0) },
                                      selection: settings.density, width: nil, track: Soot.surface)
                    }
                    row(title: "Columns") { ColumnChips(columns: settings.columns, alignment: .leading) }
                    hideFinished
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                SectionHead(title: "Overview")
                // Columns: the list in miniature. It follows every choice below, and its
                // column heads are the switches for the columns.
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Columns").font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                        Text("Click a column to show or hide it").font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                    ListMiniature(settings: settings)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 12)
                SettingRows {
                    SettingRow(title: "Density", detail: "The height of a row") {
                        DensityPicker(selection: settings.density)
                    }
                    sorting
                    SettingRow(title: "Quiet after", detail: "Without a Slack message") {
                        SegmentPicker(label: "A project is quiet after",
                                      options: Preferences.quietChoices.map { (label: "\($0) days", value: $0) },
                                      selection: $quietAfter, width: Buttons.controlWidth)
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

    @ViewBuilder private var sorting: some View {
        row(title: "Sort by") {
            SegmentPicker(label: "Sort projects by",
                          options: OverviewSettings.Sort.allCases.map { (label: $0.label, value: $0) },
                          selection: settings.sort, width: compact ? nil : Buttons.controlWidth,
                          track: compact ? Soot.surface : Soot.ground)
        }
        row(title: "Group by") {
            SegmentPicker(label: "Group projects by",
                          options: OverviewSettings.Group.allCases.map { (label: $0.label, value: $0) },
                          selection: settings.group, width: compact ? nil : Buttons.controlWidth,
                          track: compact ? Soot.surface : Soot.ground)
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

/// Density as two pictures of the list: a few tall rows, or more short ones. A lime ring
/// marks the choice and travels between them.
private struct DensityPicker: View {
    @Binding var selection: OverviewSettings.Density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OverviewSettings.Density.allCases) { option in
                let on = selection == option
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { selection = option }
                } label: {
                    VStack(spacing: 6) {
                        VStack(spacing: option == .compact ? 3 : 7) {
                            ForEach(0..<(option == .compact ? 5 : 3), id: \.self) { i in
                                HStack(spacing: 5) {
                                    Capsule().fill(Soot.ink).frame(width: [22, 16, 26, 18, 24][i], height: 3)
                                    Spacer(minLength: 0)
                                    Capsule().fill(Soot.muted.opacity(0.55)).frame(width: 14, height: 3)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 84, height: 40)
                        .background(Soot.ground, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.edge))
                        .overlay {
                            if on {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime, lineWidth: 2)
                                    .matchedGeometryEffect(id: "ring", in: ring)
                            }
                        }
                        Text(option.label).font(.system(size: 12, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Soot.ink : Soot.muted)
                    }
                    .padding(4)
                }
                .buttonStyle(RowButton(lift: .tone, radius: 8))
                .accessibilityLabel("\(option.label) rows")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Row density")
    }
}

/// The project list drawn small: a pinned row on top, the groups, the row height and the
/// finished row follow the settings. Each column is headed by a chip that shows or hides
/// it (a check when shown, a plus when hidden); a hidden column keeps its place, empty, so
/// the heads never move under the pointer.
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
        Line(id: 0, pinned: true, name: 52, progress: 0.6, health: Soot.lime),
        Line(id: 1, name: 40, progress: 0.3, health: Theme.negative),
        Line(id: 2, finished: true, name: 58, progress: 1, health: Soot.muted),
    ]

    private var rowHeight: CGFloat { settings.density == .compact ? 16 : 24 }
    private var grouped: Bool { settings.group != .none }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(width: 76, alignment: .leading) {
                Color.clear.frame(height: 26)
            } group: { line in
                Capsule().fill(Soot.muted).frame(width: line.id == 0 ? 40 : 30, height: 4)
            } cell: { line in
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Soot.lime)
                        .opacity(line.pinned ? 1 : 0)
                    Capsule().fill(Soot.ink).frame(width: line.name, height: 5)
                }
            }
            ForEach(OverviewSettings.Column.allCases) { kind in
                Spacer(minLength: 4)
                column(width: nil, alignment: .center) {
                    head(kind)
                } group: { _ in
                    Color.clear
                } cell: { line in
                    mark(kind, line).opacity(settings.columns.contains(kind) ? 1 : 0)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings)
    }

    /// One column: its head, then a cell per line, with the group labels' rows kept in step.
    private func column<Head: View, GroupMark: View, Cell: View>(
        width: CGFloat?, alignment: HorizontalAlignment,
        @ViewBuilder head: () -> Head,
        @ViewBuilder group: @escaping (Line) -> GroupMark,
        @ViewBuilder cell: @escaping (Line) -> Cell
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            head().padding(.bottom, 8)
            ForEach(lines) { line in
                if grouped, line.id != 1 {
                    group(line).frame(height: 16).transition(.opacity).accessibilityHidden(true)
                }
                if !(line.finished && settings.hideFinished) {
                    cell(line).frame(height: rowHeight).transition(.opacity).accessibilityHidden(true)
                }
            }
        }
        .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .top))
    }

    private func head(_ column: OverviewSettings.Column) -> some View {
        let on = settings.columns.contains(column)
        return Button {
            if on { settings.columns.remove(column) } else { settings.columns.insert(column) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.muted)
                    .accessibilityHidden(true)
                Text(column.chip)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.ink)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 26)
        }
        .buttonStyle(ColumnHead(on: on))
        .help(column.detail)
        .accessibilityLabel("\(column.chip) column")
        .accessibilityValue(on ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
    }

    @ViewBuilder private func mark(_ column: OverviewSettings.Column, _ line: Line) -> some View {
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
        }
    }
}

/// A column's head in the miniature: lime when the column shows, an outline when hidden.
/// Hover and press tint it with its label's ink, like every chip.
private struct ColumnHead: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, on: on) }

    private struct Face: View {
        let configuration: Configuration
        let on: Bool
        @State private var hovering = false

        var body: some View {
            let tone = configuration.isPressed ? 0.16 : hovering ? 0.08 : 0
            configuration.label
                .background(Capsule().fill(on ? Soot.lime : Color.clear))
                .overlay(Capsule().fill((on ? Soot.limeInk : Soot.ink).opacity(tone)))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(Soot.edge.opacity(on ? 0 : 1)))
                .contentShape(Capsule())
                .modifier(FocusOutline(radius: 13))
                .onHover { hovering = $0 }
                .handCursor()
                .animation(.easeOut(duration: 0.12), value: hovering)
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
