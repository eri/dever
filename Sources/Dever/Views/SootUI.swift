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
    static let fieldHeight: CGFloat = 40
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

// Button styles live in Buttons.swift (PrimaryButton, SecondaryButton, TertiaryButton, IconButton,
// DestructiveButton, ToolbarButton, ChipButton, RowButton, MenuTriggerButton).

/// A linked tool as a chip: its logo and its name; a click opens it in the tool.
/// Without a URL (the tool is linked but not connected yet) it stays a quiet label.
struct ToolChip: View {
    let service: ServiceKind
    let text: String
    var url: URL?

    var body: some View {
        if let url {
            HoverLink(destination: url, hoverTint: Soot.surface) { face }
                .help("Open \(text) in \(service.label)")
                .accessibilityLabel("Open \(text) in \(service.label)")
        } else {
            face.padding(.horizontal, 8).frame(height: 28)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(service.label): \(text), not connected")
        }
    }

    private var face: some View {
        HStack(spacing: 6) {
            BrandLogo(service: service, size: 12).accessibilityHidden(true)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.muted).lineLimit(1)
        }
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
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius)
                .strokeBorder(recommended && enabled ? Soot.lime.opacity(0.5) : .clear))
        }
        .buttonStyle(RowButton(lift: .tone, radius: Soot.radius))
        .disabled(!enabled)
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
                    .motion(Motion.quick, fade: true, value: focused)
            }
            .focused($focused)
            .onSubmit(onSubmit)
    }
}

/// A small set of mutually exclusive options as pills; the selected one is lime.
struct ChipPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                // The lime pill travels to the new choice; the words only change colour.
                Button { Motion.run(Motion.settle) { selection = option.value } } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Soot.limeInk : Soot.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if on { Capsule().fill(Soot.lime).matchedGeometryEffect(id: "pill", in: marker) }
                            else { Capsule().fill(Soot.surface) }
                        }
                }
                .buttonStyle(ChipButton(on: on, drawsFill: false))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A round check mark for selectable rows.
struct CheckCircle: View {
    let on: Bool
    /// A rounded square says "several can be on", a circle "one of these".
    var square = false
    var body: some View {
        ZStack {
            if square {
                RoundedRectangle(cornerRadius: 4).strokeBorder(on ? Soot.lime : Soot.muted, lineWidth: 1.5)
                if on { RoundedRectangle(cornerRadius: 4).fill(Soot.lime) }
            } else {
                Circle().strokeBorder(on ? Soot.lime : Soot.muted, lineWidth: 1.5)
                if on { Circle().fill(Soot.lime) }
            }
            if on {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.limeInk)
                    .transition(Motion.pop)
            }
        }
        .frame(width: 18, height: 18)
        .motion(Motion.ui, value: on)
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
            .modifier(SheetEntrance())
    }
}

/// The sheet's content rises into place as the system slides the sheet down: 200 ms ease-out,
/// fade only under Reduce Motion. The chrome itself is macOS's own animation.
struct SheetEntrance: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear { withAnimation(Motion.ui) { shown = true } }
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
            Text(title).font(.system(size: 22, weight: .semibold)).tracking(-0.5).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            GlyphButton(symbol: "xmark", label: "Close", action: close)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// A visible keyboard-focus ring for custom controls (WCAG 2.4.7): lime, 2px, 3px outside —
/// the same colour a focused text field shows, so focus looks the same everywhere.
struct FocusOutline: ViewModifier {
    var radius: CGFloat
    @Environment(\.isFocused) private var isFocused
    @Environment(\.buttonStateOverride) private var override

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius + 3)
                .strokeBorder(Soot.lime, lineWidth: 2)
                .padding(-3)
                .opacity((override?.focused ?? isFocused) ? 1 : 0)
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
                    if selected { Circle().fill(Soot.lime).padding(5).transition(Motion.pop) }
                }
                .frame(width: 18, height: 18)
                .motion(Motion.ui, value: selected)
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
            .padding(.horizontal, 8)
        }
        .buttonStyle(RowButton(lift: .tone, radius: 6))
        .padding(.horizontal, -8)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(detail ?? "")
    }
}

/// A label above a control, so no input relies on its placeholder (WCAG 3.3.2).
struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).tracking(0.2).foregroundStyle(Soot.ink)
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
            if !label.isEmpty { FieldLabel(text: label) }
            HStack(spacing: 10) {
                if let leadingSymbol {
                    Image(systemName: leadingSymbol).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Soot.muted).accessibilityHidden(true)
                }
                TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Soot.muted))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
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
            .motion(Motion.quick, fade: true, value: focused)
            .onTapGesture { focused = true }
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Soot.muted)
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
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Soot.lime)
                .controlSize(.small)
        }
        .frame(maxWidth: 420, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .handCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail ?? "")
    }
}

/// One way to do a thing, as a tile: a check ring, a title, one line, and what it needs once chosen.
/// Same language as the onboarding choices; the selected tile has a lime edge.
struct ChoiceCard<Nested: View>: View {
    let title: String
    var detail: String? = nil
    var tag: String? = nil
    let selected: Bool
    let select: () -> Void
    @ViewBuilder var nested: () -> Nested

    init(title: String, detail: String? = nil, tag: String? = nil, selected: Bool,
         select: @escaping () -> Void, @ViewBuilder nested: @escaping () -> Nested) {
        self.title = title; self.detail = detail; self.tag = tag
        self.selected = selected; self.select = select; self.nested = nested
    }

    init(title: String, detail: String? = nil, tag: String? = nil, selected: Bool,
         select: @escaping () -> Void) where Nested == EmptyView {
        self.init(title: title, detail: detail, tag: tag, selected: selected, select: select) { EmptyView() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The choice, its ring and what it reveals below move in one transaction, so the
            // tiles under it slide instead of jumping.
            Button { Motion.run(Motion.ui) { select() } } label: {
                HStack(spacing: 12) {
                    CheckCircle(on: selected).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Soot.ink)
                            if let tag {
                                Text(tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.lime)
                            }
                        }
                        if let detail {
                            Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
            }
            .buttonStyle(RowButton(lift: .tone, radius: Soot.fieldRadius))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if selected && !(Nested.self == EmptyView.self) {
                VStack(alignment: .leading, spacing: 12) { nested() }
                    .padding(.leading, 46)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(Motion.rise)
            }
        }
        .clipped()
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.fieldRadius))
        .overlay(RoundedRectangle(cornerRadius: Soot.fieldRadius)
            .strokeBorder(selected ? Soot.lime : .clear, lineWidth: 1.5))
    }
}

/// A small scene for a choice, in the Settings pictures' language: a card of three quiet rows
/// and one accent that says what the choice does.
struct ChoiceThumb: View {
    enum Scene {
        /// A new row appears: a lime plus.
        case create
        /// One of the rows is the one: a lime row with a check.
        case existing
        /// One row, named: the match that was found.
        case found
        /// Nothing picked: a dashed card.
        case none
        /// A symbol in a lime badge over the rows.
        case symbol(String)
    }
    let scene: Scene

    var body: some View {
        ZStack {
            switch scene {
            case .none:
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Soot.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 56, height: 36)
            case .create:
                rows(accent: nil)
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Soot.limeInk)
                    .frame(width: 22, height: 22).background(Soot.lime, in: Circle())
                    .offset(x: 24, y: 14)
            case .existing:
                rows(accent: 1)
            case .found:
                rows(accent: 1, check: true)
            case .symbol(let name):
                rows(accent: nil)
                Image(systemName: name).font(.system(size: 11, weight: .bold)).foregroundStyle(Soot.limeInk)
                    .frame(width: 22, height: 22).background(Soot.lime, in: Circle())
                    .offset(x: 24, y: 14)
            }
        }
        .frame(width: 116, height: 76)
        .background(Soot.ground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.edge))
        .accessibilityHidden(true)
    }

    private func rows(accent: Int?, check: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 6) {
                    Capsule().fill(i == accent ? Soot.lime : Soot.ink.opacity(0.35))
                        .frame(width: [40, 52, 34][i], height: 5)
                    if check && i == accent {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Soot.lime)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 72, alignment: .leading)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// One answer to a step's question: a picture, a title, one quiet line; the chosen one wears
/// the lime ring. Laid out in a row by `ChoiceTiles`.
struct ChoiceTile: View {
    let thumb: ChoiceThumb.Scene
    let title: String
    var detail: String? = nil
    var tag: String? = nil
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                ChoiceThumb(scene: thumb)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Soot.lime, lineWidth: 2).opacity(selected ? 1 : 0)
                    }
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Soot.ink : Soot.muted)
                        .multilineTextAlignment(.center).lineLimit(2)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                    if let tag {
                        Text(tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.lime)
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(width: 148)
        }
        .buttonStyle(RowButton(lift: .tone, radius: 8))
        .accessibilityLabel([title, tag ?? detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A step's page: the question, what answers it, the buttons. Same spacing on every page, so
/// the pages of a flow line up as one.
struct StepPage<Content: View, Buttons: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepTitle(text: title)
            content()
            HStack(spacing: 16) { buttons() }
        }
    }
}

/// The answers to a question, side by side; three fit the sheet.
struct ChoiceTiles<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 8) { content() }
            .accessibilityElement(children: .contain)
    }
}

/// A sheet that asks one thing at a time, in the onboarding's frame: a headline, one control,
/// one button; close top-right, back top-left, progress marks bottom-left. Same size every step.
struct StepSheet<Content: View>: View {
    var step: Int? = nil
    var count: Int = 0
    var back: (() -> Void)? = nil
    let close: () -> Void
    @ViewBuilder var content: () -> Content

    static var size: CGSize { CGSize(width: 600, height: 560) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    if let back { BackButton(action: back) }
                    Spacer()
                }
                .frame(height: 28)
                Spacer(minLength: 16)
                content()
                Spacer(minLength: 28)
                if let step, count > 1 {
                    StepMarks(count: count, current: step)
                }
            }
            .padding(40)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background(Soot.ground)
            .modifier(SheetEntrance())
            GlyphButton(symbol: "xmark", label: "Close", action: close)
                .keyboardShortcut(.cancelAction)
                .padding(40)
        }
    }
}

/// The step's one question, in the onboarding's voice but sized for a sheet.
struct StepTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .semibold))
            .tracking(-1)
            .foregroundStyle(Soot.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Where you are: marks in a row, the current one long (as in onboarding).
struct StepMarks: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Soot.ink : i < current ? Soot.muted : Soot.surface)
                    .frame(width: i == current ? 28 : 8, height: 8)
            }
        }
        .motion(Motion.settle, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Back to the previous step of a sheet.
struct BackButton: View {
    let action: () -> Void
    var body: some View {
        GlyphButton(symbol: "chevron.left", label: "Back", action: action)
    }
}

/// Controls that exist only because of the choice above them: hung off a thin left rule.
struct NestedGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 1).fill(Soot.edge).frame(width: 2)
            VStack(alignment: .leading, spacing: 16) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
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
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted)
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

    init(width: CGFloat, height: CGFloat? = nil,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.width = width; self.height = height
        self.header = header; self.content = content; self.footer = footer
    }

    /// A sheet without a footer: the choices in the content are the actions.
    init(width: CGFloat, height: CGFloat? = nil,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content) where Footer == EmptyView {
        self.init(width: width, height: height, header: header, content: content, footer: { EmptyView() })
    }

    private let side: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, side)
                .padding(.top, 28)
                .padding(.bottom, 24)
            if height != nil {
                ScrollView {
                    content().padding(.horizontal, side).padding(.bottom, 28)
                }
                .frame(maxHeight: .infinity)
            } else {
                content().padding(.horizontal, side).padding(.bottom, 28)
            }
            if !(Footer.self == EmptyView.self) {
                Rectangle().fill(Soot.line).frame(height: 1)
                footer()
                    .padding(.horizontal, side)
                    .padding(.vertical, 16)
            }
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
    /// A figure for the right edge of a row (a member count).
    var aside: String? = nil
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
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.muted)
                }
                Text(current?.title ?? placeholder)
                    .foregroundStyle(current == nil ? Soot.muted : Soot.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .frame(height: Soot.fieldHeight)
            .motion(Motion.quick, fade: true, value: open)
        }
        .buttonStyle(MenuTriggerButton(open: open, radius: Soot.fieldRadius))
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
                    .font(.system(size: 14))
                    .foregroundStyle(Soot.ink)
                    .focused($searchFocused)
                    .onSubmit { if let first = (query.isEmpty ? actions + filtered : filtered).first { choose(first) } }
                    .accessibilityLabel("Search \(label)")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Rectangle().fill(Soot.line).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty && !actions.isEmpty {
                        ForEach(actions) { row($0) }
                        Rectangle().fill(Soot.line).frame(height: 1).padding(.vertical, 6)
                    }
                    ForEach(filtered) { row($0) }
                    if filtered.isEmpty {
                        Text(query.isEmpty ? "Nothing to pick yet" : "No match for \u{201C}\(query)\u{201D}")
                            .font(.system(size: 14)).foregroundStyle(Soot.muted)
                            .padding(.horizontal, 12).padding(.vertical, 16)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 340)
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
                    Text(item.title).font(.system(size: 13, weight: isAction ? .medium : .regular))
                        .foregroundStyle(Soot.ink).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Soot.lime)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The sheet's action as one glyph: what the sheet does, not which app it belongs to.
struct ActionIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Soot.lime)
            .frame(width: 34, height: 34)
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
