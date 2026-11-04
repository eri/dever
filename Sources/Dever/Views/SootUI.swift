import SwiftUI

// The app's sheet and onboarding language, from the "product performs" direction:
// soot-black ground, white ink, one lime for actions; rows instead of forms; few words.
// Sheets use it through `sootSheet()`.

/// Soot and lime: black ground, one lime for actions and the stage behind the product.
enum Soot {
    // Dark / light pairs. Every text pair passes 4.5:1, every edge 3:1 (measured).
    static let ground = Color(light: 0xF4F4F2, dark: 0x0F0F0F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let ink = Color(light: 0x111111, dark: 0xFFFFFF)
    /// Secondary text: 5.5 / 6.1:1 light, 5.9 / 5.4:1 dark.
    static let muted = Color(light: 0x5F6368, dark: 0x8F8F8F)
    /// Control edges: 3.1 / 3.5:1 light, 3.9 / 3.5:1 dark (WCAG 1.4.11 asks 3:1).
    static let edge = Color(light: 0x8A8A8A, dark: 0x707070)
    /// The one action colour: pale lime on dark, deep green on light (7:1 on white).
    static let lime = Color(light: 0x3F6212, dark: 0xDAFA9C)
    static let limeInk = Color(light: 0xFFFFFF, dark: 0x0F0F0F)
    /// Hairlines inside a sheet (decorative, below the 3:1 bar on purpose).
    static let line = Color(light: 0xE3E3E0, dark: 0x262626)
    static let radius: CGFloat = 8
    /// Inputs and selects: a little rounder than tiles so they read as controls.
    static let fieldRadius: CGFloat = 10
    static let fieldHeight: CGFloat = 44
    static let margin: CGFloat = 40
}

struct Headline: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 44, weight: .semibold))
            .tracking(-1.5)
            .foregroundStyle(Soot.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LimeButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Soot.limeInk)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Soot.lime.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3),
                        in: RoundedRectangle(cornerRadius: Soot.radius))
            .modifier(FocusOutline(radius: Soot.radius))
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Soot.ink)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Soot.surface.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge))
            .modifier(FocusOutline(radius: Soot.radius))
    }
}

/// A choice that is its own button: icon, title, one short line, and where it leads.
struct OptionRow: View {
    let icon: AnyView
    let title: String
    let detail: String
    let recommended: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon.frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Soot.ink)
                    Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(recommended ? Soot.limeInk : Soot.muted)
                    .frame(width: 28, height: 28)
                    .background(recommended ? Soot.lime : Color.clear, in: Circle())
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(hovering && enabled ? Soot.surface.opacity(0.7) : Soot.surface,
                        in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius)
                .strokeBorder(recommended && enabled ? Soot.lime.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

/// A text field drawn as a single underline, sized for the one input of a screen.
struct UnderlineField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 20
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Soot.muted))
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Soot.ink)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Soot.ink : Soot.muted).frame(height: focused ? 2 : 1)
            }
            .focused($focused)
            .onSubmit(onSubmit)
    }
}

/// A small set of mutually exclusive options as pills; the selected one is lime.
struct ChipPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button(option.label) { selection = option.value }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Soot.limeInk : Soot.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(on ? Soot.lime : Soot.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.clear : Soot.edge))
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A round check mark for selectable rows.
struct CheckCircle: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Soot.lime : Soot.muted, lineWidth: 1.5)
            if on {
                Circle().fill(Soot.lime)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.limeInk)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The frame every sheet shares: soot ground, dark appearance, generous padding.
struct SootSheet: ViewModifier {
    var width: CGFloat
    var height: CGFloat?
    func body(content: Content) -> some View {
        content
            .padding(32)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Soot.ground)
    }
}

extension View {
    func sootSheet(width: CGFloat, height: CGFloat? = nil) -> some View {
        modifier(SootSheet(width: width, height: height))
    }
}

/// Sheet title row: a mark, the title, and a close button.
struct SheetTitle<Mark: View>: View {
    let title: String
    @ViewBuilder var mark: () -> Mark
    let close: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            mark()
            Text(title).font(.system(size: 24, weight: .semibold)).tracking(-0.5).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
                    .frame(width: 32, height: 32).background(Soot.surface, in: Circle())
                    .modifier(FocusOutline(radius: 16))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
    }
}

/// A visible keyboard-focus ring for custom controls (WCAG 2.4.7): white, 2px, 3px outside.
struct FocusOutline: ViewModifier {
    var radius: CGFloat
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius + 3)
                .strokeBorder(Soot.ink, lineWidth: 2)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
        )
    }
}

/// One option of a radio group: a ring with a dot when chosen, a label, one short line.
struct RadioRow: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Soot.lime : Soot.muted, lineWidth: 1.5)
                    if selected { Circle().fill(Soot.lime).padding(5) }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Soot.ink)
                    if let detail {
                        Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .modifier(FocusOutline(radius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(detail ?? "")
    }
}

/// A label above a control, so no input relies on its placeholder (WCAG 3.3.2).
struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink)
    }
}

/// A filled text field with its label above it, sized for a sheet (44px, WCAG 2.5.8).
/// Idle: surface fill with a 3:1 edge. Focused: a 2px lime edge, no motion.
struct SootField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    var leadingSymbol: String? = nil
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 10) {
                if let leadingSymbol {
                    Image(systemName: leadingSymbol).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Soot.muted).accessibilityHidden(true)
                }
                TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Soot.muted))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Soot.ink)
                    .focused($focused)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(label)
            }
            .padding(.horizontal, 14)
            .frame(height: Soot.fieldHeight)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
                .strokeBorder(focused ? Soot.lime : Soot.edge, lineWidth: focused ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .onTapGesture { focused = true }
            if let hint {
                Text(hint).font(.system(size: 13)).foregroundStyle(Soot.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A switch with its sentence on the left; the whole row is the target.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Soot.lime)
                .controlSize(.regular)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail ?? "")
    }
}

/// A heading for a group of controls in a sheet: an optional mark and a title.
struct SectionHeading<Mark: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark().frame(width: 18, alignment: .center).accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soot.ink)
            if let detail {
                Text(detail).font(.system(size: 13)).foregroundStyle(Soot.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The frame of a sheet with three bands: a title, the content, and a footer behind a hairline.
/// Fixed `height` makes the content scroll; without it the sheet hugs its content.
struct SheetScaffold<Header: View, Content: View, Footer: View>: View {
    var width: CGFloat
    var height: CGFloat? = nil
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    private let side: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, side)
                .padding(.top, 32)
                .padding(.bottom, 28)
            if height != nil {
                ScrollView {
                    content().padding(.horizontal, side).padding(.bottom, 32)
                }
                .frame(maxHeight: .infinity)
            } else {
                content().padding(.horizontal, side).padding(.bottom, 32)
            }
            Rectangle().fill(Soot.line).frame(height: 1)
            footer()
                .padding(.horizontal, side)
                .padding(.vertical, 20)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Soot.ground)
    }
}

// MARK: - Search picker

/// One choice in a `SearchPicker`.
struct PickerItem: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
}

/// A field that opens a searchable list: type to filter, click or press Return to choose.
/// Replaces long system menus (hundreds of channels or repositories).
struct SearchPicker: View {
    let label: String                // accessible name, e.g. "Slack channel"
    let placeholder: String          // shown when nothing is chosen
    /// Short fixed choices shown above the list (Not linked, New channel…).
    var actions: [PickerItem] = []
    let items: [PickerItem]
    @Binding var selection: String?
    @State private var open = false

    private var current: PickerItem? {
        (actions + items).first { $0.id == selection }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 10) {
                if let symbol = current?.symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.muted)
                }
                Text(current?.title ?? placeholder)
                    .foregroundStyle(current == nil ? Soot.muted : Soot.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: Soot.fieldHeight)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
                .strokeBorder(open ? Soot.lime : Soot.edge, lineWidth: open ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Soot.fieldRadius))
            .modifier(FocusOutline(radius: Soot.fieldRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(current?.title ?? "None")
        .onAppear {
            // Snapshots: DEVER_SNAPSHOT_PICKER=<label> opens that picker.
            if ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_PICKER"] == label {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { open = true }
            }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            SearchPickerList(label: label, actions: actions, items: items, selection: $selection, open: $open)
        }
    }
}

private struct SearchPickerList: View {
    let label: String
    let actions: [PickerItem]
    let items: [PickerItem]
    @Binding var selection: String?
    @Binding var open: Bool
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Soot.muted).accessibilityHidden(true)
                TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(Soot.muted))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Soot.ink)
                    .focused($searchFocused)
                    .onSubmit { if let first = (query.isEmpty ? actions + filtered : filtered).first { choose(first) } }
                    .accessibilityLabel("Search \(label)")
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            Rectangle().fill(Soot.line).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty && !actions.isEmpty {
                        ForEach(actions) { row($0) }
                        Rectangle().fill(Soot.line).frame(height: 1).padding(.vertical, 6)
                    }
                    ForEach(filtered) { row($0) }
                    if filtered.isEmpty {
                        Text("No match for \u{201C}\(query)\u{201D}").font(.system(size: 14)).foregroundStyle(Soot.muted)
                            .padding(.horizontal, 12).padding(.vertical, 16)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 380)
        .background(Soot.ground)
        .onAppear { searchFocused = true }
    }

    private func row(_ item: PickerItem) -> some View {
        PickerRow(item: item, isAction: actions.contains(item), selected: item.id == selection) { choose(item) }
    }

    private func choose(_ item: PickerItem) {
        selection = item.id
        open = false
    }
}

private struct PickerRow: View {
    let item: PickerItem
    let isAction: Bool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // A fixed icon column keeps every title on one edge.
                Group {
                    if let symbol = item.symbol {
                        Image(systemName: symbol).foregroundStyle(isAction ? Soot.lime : Soot.muted)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 18)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 14, weight: isAction ? .medium : .regular))
                        .foregroundStyle(Soot.ink).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Soot.lime)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(hovering ? Soot.surface : Color.clear, in: RoundedRectangle(cornerRadius: Soot.radius))
            .contentShape(Rectangle())
            .modifier(FocusOutline(radius: Soot.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The sheet's action as one glyph: what the sheet does, not which app it belongs to.
struct ActionIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Soot.lime)
            .frame(width: 38, height: 38)
            .background(Soot.surface, in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    /// A block on a soot page: one tone step up from the ground, no border.
    func sootPanel() -> some View {
        self.padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
