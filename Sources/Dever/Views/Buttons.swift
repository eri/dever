import AppKit
import SwiftUI

// Dever's buttons, in one place. Nine roles, one `ButtonStyle` each, all drawn by the same
// chrome (`ButtonChrome`): it tracks hover, reads the gallery's state override, draws the
// 2px lime focus ring, answers a press with a 0.97 scale (off under Reduce Motion), shows the
// pointing hand while the button is enabled, and fades every tone change in 150 ms ease-out.
//
//   primary      lime fill, limeInk label            PrimaryButton      44 in sheets, 36 in panels
//   secondary    surface fill, edge, ink label        SecondaryButton    44 / 36
//   tertiary     text only: lime, ink or muted        TertiaryButton     28, surface pill on hover
//   icon         one glyph on a circle or a tile      IconButton         the label's own frame
//   destructive  surface fill, negative label         DestructiveButton  44 / 36
//   toolbar      glyph + verb on a surface tile       ToolbarButton      34
//   chip         a capsule; lime when `on`            ChipButton         30 (26–30)
//   row          a tile that opens something          RowButton          the row's own height
//   menu         a trigger with a chevron or "⋯"      MenuTriggerButton  30–40
//
// Disabled: surface fill, `Soot.edge` stroke at half, `Soot.muted` label (5.4:1), no hover,
// no hand. Nothing disabled is ever lime.

/// Sizes a filled button can take: `sheet` for the one action of a sheet or onboarding stage,
/// `panel` for actions inside a page.
enum ButtonSize {
    case sheet, panel
    var height: CGFloat { self == .sheet ? 44 : 36 }
    var fontSize: CGFloat { self == .sheet ? 15 : 14 }
    var padding: CGFloat { self == .sheet ? 20 : 16 }
}

/// Forces a button's visual state, for the gallery capture (hover and press cannot be driven
/// from a screenshot run). `nil` in the app.
struct ButtonStateOverride: Equatable {
    var hovered = false
    var pressed = false
    var focused = false
}

private struct ButtonStateOverrideKey: EnvironmentKey {
    static let defaultValue: ButtonStateOverride? = nil
}

extension EnvironmentValues {
    var buttonStateOverride: ButtonStateOverride? {
        get { self[ButtonStateOverrideKey.self] }
        set { self[ButtonStateOverrideKey.self] = newValue }
    }
}

enum Buttons {
    /// Every hover, press and disable tone fades at this pace (a dissolve: kept under Reduce Motion).
    static let hover: Animation = .easeOut(duration: 0.15)
    static let toolbarHeight: CGFloat = 34
    static let chipHeight: CGFloat = 30
    static let textHeight: CGFloat = 28
    /// The column every segment picker and chip grid in Settings fills, so their edges line up.
    static let controlWidth: CGFloat = 360
    /// The tone a hovered tile or chip takes: ink at 6 %, pressed 12 %. Reads on dark and light.
    static let hoverTone: Double = 0.06
    static let pressTone: Double = 0.12
}

/// What a role's face is told about its state.
struct ButtonFace {
    let hovering: Bool
    let pressed: Bool
    let enabled: Bool
    /// The tone to lay over a fill: 0 at rest, 6 % on hover, 12 % when pressed, nothing when disabled.
    var tone: Double { !enabled ? 0 : pressed ? Buttons.pressTone : hovering ? Buttons.hoverTone : 0 }
}

/// The chrome every role shares. `face` draws the label for a state; the chrome adds the rest.
private struct ButtonChrome<Face: View>: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    var scales = true
    @ViewBuilder let face: (ButtonFace) -> Face
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.buttonStateOverride) private var override

    var body: some View {
        let state = ButtonFace(hovering: override?.hovered ?? (hovering && isEnabled),
                               pressed: override?.pressed ?? configuration.isPressed,
                               enabled: isEnabled)
        face(state)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .modifier(FocusOutline(radius: radius))
            .pressScale(scales && state.pressed)
            .motion(Buttons.hover, fade: true, value: state.hovering)
            .motion(Buttons.hover, fade: true, value: state.pressed)
            .onHover { hovering = $0 }
            .handCursor(isEnabled)
    }
}

// MARK: - Primary

/// The one action of a view: lime fill. Hover and press darken it with the label's ink.
struct PrimaryButton: ButtonStyle {
    var size: ButtonSize = .panel
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: Soot.radius) { s in
            configuration.label
                .font(.system(size: size.fontSize, weight: .semibold))
                .foregroundStyle(s.enabled ? Soot.limeInk : Soot.muted)
                .padding(.horizontal, size.padding)
                .frame(height: size.height)
                .background(s.enabled ? Soot.lime : Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).fill(Soot.limeInk.opacity(s.tone * 1.3)))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(s.enabled ? Color.clear : Soot.edge.opacity(0.5)))
        }
    }
}

/// The name the sheets have used since the start; the same style.
typealias LimeButton = PrimaryButton

// MARK: - Secondary

/// A peer action beside the primary one: surface fill with a 3:1 edge.
struct SecondaryButton: ButtonStyle {
    var size: ButtonSize = .panel
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: Soot.radius) { s in
            configuration.label
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundStyle(s.enabled ? Soot.ink : Soot.muted)
                .padding(.horizontal, size.padding)
                .frame(height: size.height)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).fill(Soot.ink.opacity(s.tone)))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.edge.opacity(s.enabled ? 1 : 0.5)))
        }
    }
}

typealias QuietButton = SecondaryButton

// MARK: - Tertiary

/// A text link: "Show all 15", "Skip for now", "Open ↗". Hover shows a pill behind it (the tone
/// one step from the surface it sits on) and lifts a muted label to ink; the pressed pill is solid.
struct TertiaryButton: ButtonStyle {
    enum Tint { case lime, ink, muted }
    var tint: Tint = .lime
    /// The pill's colour: `Soot.ground` on a panel, `Soot.surface` on the page.
    var lift: Color = Soot.ground
    var font: Font = .system(size: 13, weight: .semibold)
    var height: CGFloat = Buttons.textHeight

    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: height / 2) { s in
            configuration.label
                .font(font)
                .foregroundStyle(colour(s))
                .padding(.horizontal, 8)
                .frame(minHeight: height)
                .background(lift.opacity(s.pressed ? 1 : s.hovering ? 0.85 : 0), in: Capsule())
        }
    }

    private func colour(_ s: ButtonFace) -> Color {
        guard s.enabled else { return Soot.muted }
        switch tint {
        case .lime: return Soot.lime
        case .ink: return Soot.ink
        case .muted: return s.hovering || s.pressed ? Soot.ink : Soot.muted
        }
    }
}

/// A link to a URL in the tertiary form, the arrow glyph added: "Open in Linear ↗".
struct ExternalLink<Label: View>: View {
    let destination: URL
    var tint: TertiaryButton.Tint = .lime
    var lift: Color = Soot.ground
    var font: Font = .system(size: 13, weight: .semibold)
    @ViewBuilder var label: () -> Label

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 4) {
                label()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
        }
        .buttonStyle(TertiaryButton(tint: tint, lift: lift, font: font))
    }
}

extension ExternalLink where Label == Text {
    init(_ title: String, destination: URL, tint: TertiaryButton.Tint = .lime, lift: Color = Soot.ground,
         font: Font = .system(size: 13, weight: .semibold)) {
        self.init(destination: destination, tint: tint, lift: lift, font: font) { Text(title) }
    }
}

/// A link whose label is given as is (a logo and a line, say), in the tertiary form.
/// `hoverTint` is the pill's colour: ground on a panel, surface on the page.
struct HoverLink<Label: View>: View {
    let destination: URL
    var hoverTint: Color = Soot.ground
    @ViewBuilder var label: () -> Label

    var body: some View {
        Link(destination: destination) { label() }
            .buttonStyle(TertiaryButton(tint: .ink, lift: hoverTint))
    }
}

// MARK: - Icon

/// One glyph: close, back, pin, zoom, expand. The label sets its own frame; the style fills
/// it (circle by default) and tones it on hover. Every icon button needs `.help` and an
/// accessible name at the call site, since the glyph says nothing to a screen reader.
struct IconButton: ButtonStyle {
    /// `nil` draws no fill (a glyph in a strip, a rail tile that paints itself).
    var fill: Color? = Soot.surface
    /// `nil` is a circle.
    var radius: CGFloat? = nil
    var edge = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: radius ?? 999) { s in
            configuration.label
                .foregroundStyle(s.enabled ? Soot.ink : Soot.muted)
                .background { if let fill { shape.fill(fill) } }
                .overlay(shape.fill(Soot.ink.opacity(s.tone)))
                .overlay(shape.strokeBorder(Soot.edge.opacity(edge ? (s.enabled ? 1 : 0.5) : 0)))
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius ?? 999) }
}

/// An icon-only button with the tooltip and the accessible name it must carry.
struct GlyphButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 28
    var glyphSize: CGFloat = 12
    var fill: Color? = Soot.surface
    var radius: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: glyphSize, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(IconButton(fill: fill, radius: radius))
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Destructive

/// An action that removes something, outside a system dialog or menu: the negative pill's
/// ink on a surface tile (6.5:1 dark, 9.8:1 light), a negative edge, a negative tint on hover.
struct DestructiveButton: ButtonStyle {
    var size: ButtonSize = .panel
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: Soot.radius) { s in
            configuration.label
                .font(.system(size: size.fontSize, weight: .semibold))
                .foregroundStyle(s.enabled ? Theme.pillNegative.ink : Soot.muted)
                .padding(.horizontal, size.padding)
                .frame(height: size.height)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).fill(Theme.negative.opacity(s.tone)))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius)
                    .strokeBorder(s.enabled ? Theme.negative : Soot.edge.opacity(0.5)))
        }
    }
}

// MARK: - Toolbar

/// A page-toolbar action: a glyph and a verb on a surface tile, 34px, no edge. `busy` runs
/// a lime line along its foot instead of a spinner.
struct ToolbarButton: ButtonStyle {
    var busy = false
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: Soot.radius) { s in
            configuration.label
                .labelStyle(ToolbarLabel())
                .foregroundStyle(s.enabled || busy ? Soot.ink : Soot.muted)
                .padding(.horizontal, 12)
                .frame(height: Buttons.toolbarHeight)
                .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
                .overlay(RoundedRectangle(cornerRadius: Soot.radius).fill(Soot.ink.opacity(s.tone)))
                .overlay(alignment: .bottom) {
                    if busy { WaitingLine().padding(.horizontal, 6).padding(.bottom, 1).transition(.opacity) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
                .motion(Motion.ui, fade: true, value: busy)
        }
    }
}

private struct ToolbarLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            configuration.title.font(.system(size: 13, weight: .semibold))
        }
    }
}

// MARK: - Chip

/// A capsule: a tab with a count, a column toggle, a pull request, a "Back". `on` paints it
/// lime; off, it sits on `fill` with a 3:1 edge. The label sets its own padding and height
/// (30 for tabs, 26 for small chips). `drawsFill: false` leaves the fill to the label, for
/// the pickers whose lime pill slides between choices.
struct ChipButton: ButtonStyle {
    var on = false
    var fill: Color = Soot.ground
    var drawsFill = true
    var edge = true

    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: 999) { s in
            configuration.label
                // Disabled while on: the fill turns muted (the label's limeInk reads 5.5:1 on it),
                // so nothing disabled is lime.
                .background {
                    if drawsFill { Capsule().fill(on ? (s.enabled ? Soot.lime : Soot.muted) : fill) }
                }
                .overlay(Capsule().fill((on ? Soot.limeInk : Soot.ink).opacity(s.tone * (on ? 1.3 : 1))))
                .overlay(Capsule().strokeBorder(Soot.edge.opacity(edge && !on ? (s.enabled ? 1 : 0.5) : 0)))
                .opacity(s.enabled || on ? 1 : 0.6)
        }
    }
}

/// One segment of a `SegmentPicker`: same hover tone as a chip, the focus ring drawn inside
/// it (ink on the lime pill, lime on the track) so it never crosses the picker's edge.
struct SegmentButton: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, on: on)
    }
}

private struct SegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.buttonStateOverride) private var override

    var body: some View {
        let hover = override?.hovered ?? (hovering && isEnabled)
        let pressed = override?.pressed ?? configuration.isPressed
        let focused = override?.focused ?? isFocused
        configuration.label
            .overlay(Capsule().fill((on ? Soot.limeInk : Soot.ink).opacity(pressed ? Buttons.pressTone : hover ? Buttons.hoverTone : 0)))
            .overlay(Capsule().strokeBorder(on ? Soot.limeInk : Soot.lime, lineWidth: 2).opacity(focused ? 1 : 0))
            .contentShape(Capsule())
            .motion(Buttons.hover, fade: true, value: hover)
            .onHover { hovering = $0 }
            .handCursor(isEnabled)
    }
}

// MARK: - Row

/// A row or tile that opens something: an issue, a project, a choice, a file. Hover lifts
/// it one tone; a press deepens the tone; nothing scales. `lift` says what the tone is:
/// `.ground` on a surface panel, `.surface` on the ground, `.tone` (ink at 6 %) on a row
/// that paints its own surface, `.none` when the row shows hover itself.
struct RowButton: ButtonStyle {
    enum Lift { case ground, surface, tone, none }
    var lift: Lift = .ground
    var radius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: radius, scales: false) { s in
            configuration.label
                .background {
                    switch lift {
                    case .ground: RoundedRectangle(cornerRadius: radius).fill(Soot.ground.opacity(s.pressed ? 1 : s.hovering ? 0.7 : 0))
                    case .surface: RoundedRectangle(cornerRadius: radius).fill(Soot.surface.opacity(s.pressed || s.hovering ? 1 : 0))
                    case .tone, .none: Color.clear
                    }
                }
                .overlay {
                    if lift == .tone { RoundedRectangle(cornerRadius: radius).fill(Soot.ink.opacity(s.tone)) }
                    else if lift == .surface, s.pressed { RoundedRectangle(cornerRadius: radius).fill(Soot.ink.opacity(Buttons.hoverTone)) }
                }
                .opacity(s.enabled ? 1 : 0.5)
        }
    }
}

// MARK: - Menu trigger

/// Opens a menu or a popover: a status glyph with a chevron, a "⋯", a select. Surface fill
/// (or `fill`), an edge that turns lime while `open`. The label sets its own padding and height.
struct MenuTriggerButton: ButtonStyle {
    var open = false
    var fill: Color = Soot.surface
    var radius: CGFloat = Soot.radius
    var edge = true

    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, radius: radius) { s in
            configuration.label
                .foregroundStyle(s.enabled ? Soot.ink : Soot.muted)
                .background(fill, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).fill(Soot.ink.opacity(open ? Buttons.hoverTone : s.tone)))
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(open ? Soot.lime : Soot.edge.opacity(edge ? (s.enabled ? 1 : 0.5) : 0), lineWidth: open ? 2 : 1))
        }
    }
}

/// One part of a split lime button (Add project | ⌄): a tone on hover and press, the focus
/// ring inside it so it never crosses the hairline.
struct PrimarySegment: ButtonStyle {
    var open = false
    func makeBody(configuration: Configuration) -> some View {
        PrimarySegmentBody(configuration: configuration, open: open)
    }
}

private struct PrimarySegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let open: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.buttonStateOverride) private var override

    var body: some View {
        let hover = override?.hovered ?? (hovering && isEnabled)
        let pressed = override?.pressed ?? configuration.isPressed
        let focused = override?.focused ?? isFocused
        configuration.label
            .frame(maxHeight: .infinity)
            .background(Soot.limeInk.opacity(pressed ? 0.16 : hover || open ? 0.08 : 0))
            .overlay(RoundedRectangle(cornerRadius: Soot.radius - 2).strokeBorder(Soot.limeInk, lineWidth: 2)
                .padding(2).opacity(focused ? 1 : 0))
            .contentShape(Rectangle())
            .motion(Buttons.hover, fade: true, value: hover)
            .motion(Buttons.hover, fade: true, value: open)
            .onHover { hovering = $0 }
            .handCursor(isEnabled)
    }
}

// MARK: - Cursor

/// The pointing hand over anything clickable that is not a system control. Applied by every
/// role's chrome; `active: false` (a disabled button) shows the arrow.
struct HandCursor: ViewModifier {
    var active = true
    func body(content: Content) -> some View {
        content.overlay { if active { CursorArea(cursor: .pointingHand) } }
    }
}

extension View {
    func handCursor(_ active: Bool = true) -> some View { modifier(HandCursor(active: active)) }
}

// MARK: - Gallery

/// Every role in every state, dark and light: captured by `DEVER_SNAPSHOT_GALLERY=1` to
/// `buttons-dark.png` and `buttons-light.png`, and the source of the contrast table in
/// docs/accessibility-review.md.
struct ButtonGallery: View {
    private let states: [(String, ButtonStateOverride?, Bool)] = [
        ("Normal", ButtonStateOverride(), true),
        ("Hover", ButtonStateOverride(hovered: true), true),
        ("Pressed", ButtonStateOverride(hovered: true, pressed: true), true),
        ("Focus", ButtonStateOverride(focused: true), true),
        ("Disabled", ButtonStateOverride(), false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Buttons").font(.system(size: 24, weight: .semibold)).tracking(-0.6).foregroundStyle(Soot.ink)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    Text("").frame(width: 120)
                    ForEach(states, id: \.0) { s in
                        Text(s.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted).frame(minWidth: 150, alignment: .leading)
                    }
                }
                row("Primary · sheet") { Button("Continue") {}.buttonStyle(PrimaryButton(size: .sheet)) }
                row("Primary") { Button("Add project") {}.buttonStyle(PrimaryButton()) }
                row("Secondary") { Button("Cancel") {}.buttonStyle(SecondaryButton()) }
                row("Tertiary · lime") { Button("Show all 15") {}.buttonStyle(TertiaryButton()) }
                row("Tertiary · muted") { Button("Skip for now") {}.buttonStyle(TertiaryButton(tint: .muted)) }
                row("External link") { ExternalLink("Open in Linear", destination: URL(string: "https://linear.app")!) }
                row("Icon") { GlyphButton(symbol: "xmark", label: "Close") {} }
                row("Icon · tile") { GlyphButton(symbol: "pin", label: "Pin", size: 28, fill: Soot.surface, radius: 8) {} }
                row("Destructive") { Button("Delete preview") {}.buttonStyle(DestructiveButton()) }
                row("Toolbar") { Button { } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(ToolbarButton()) }
                row("Toolbar · busy") { Button { } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(ToolbarButton(busy: true)) }
                row("Chip") { chip(on: false) }
                row("Chip · on") { chip(on: true) }
                row("Segment") {
                    HStack(spacing: 2) {
                        segment("Overview", on: true); segment("Last", on: false)
                    }
                    .padding(2).frame(height: 32).background(Soot.ground, in: Capsule())
                }
                row("Row") {
                    Button {} label: {
                        HStack(spacing: 10) {
                            Text("INA-1050").font(.system(size: 11, design: .monospaced)).foregroundStyle(Soot.muted)
                            Text("Sync tips").font(.system(size: 13)).foregroundStyle(Soot.ink)
                        }
                        .padding(.horizontal, 12).frame(width: 150, height: 40, alignment: .leading)
                    }
                    .buttonStyle(RowButton(lift: .surface))
                }
                row("Menu trigger") {
                    Button {} label: {
                        HStack(spacing: 6) {
                            Text("In progress").font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Soot.muted)
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                    }
                    .buttonStyle(MenuTriggerButton())
                }
                row("Menu trigger · ⋯") {
                    Button {} label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 34)
                    }
                    .buttonStyle(MenuTriggerButton())
                }
                row("Tooltip") { TipCard(title: "AI Tips", detail: "3 unread · 1 for you") }
                row("Menu row") {
                    MenuPanelRow(symbol: "pin", title: "Pin to top") {}
                        .frame(width: 210)
                        .padding(6).background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
                }
                row("Menu row · destructive") {
                    MenuPanelRow(symbol: "trash", title: "Remove from Dever…", destructive: true) {}
                        .frame(width: 210)
                        .padding(6).background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
                }
                row("Primary segment") {
                    HStack(spacing: 0) {
                        Button {} label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                                Text("Add project").font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(PrimarySegment())
                        Rectangle().fill(Soot.limeInk.opacity(0.28)).frame(width: 1, height: 18)
                        Button {} label: { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).frame(width: 32) }
                            .buttonStyle(PrimarySegment())
                    }
                    .foregroundStyle(Soot.limeInk)
                    .frame(height: 34)
                    .background(Soot.lime, in: RoundedRectangle(cornerRadius: Soot.radius))
                    .clipShape(RoundedRectangle(cornerRadius: Soot.radius))
                }
            }
        }
        .padding(32)
        .frame(width: 1080, alignment: .topLeading)
        .background(Soot.ground)
    }

    private func row<Content: View>(_ name: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GridRow {
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink).frame(width: 120, alignment: .leading)
            ForEach(states, id: \.0) { s in
                content()
                    .environment(\.buttonStateOverride, s.1)
                    .disabled(!s.2)
                    .frame(minWidth: 150, alignment: .leading)
            }
        }
    }

    private func chip(on: Bool) -> some View {
        Button {} label: {
            HStack(spacing: 6) {
                Text("In review")
                Text("4").monospacedDigit().foregroundStyle(on ? Soot.limeInk.opacity(0.8) : Soot.muted)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Soot.limeInk : Soot.ink)
            .padding(.horizontal, 12).frame(height: Buttons.chipHeight)
        }
        .buttonStyle(ChipButton(on: on))
    }

    private func segment(_ title: String, on: Bool) -> some View {
        Button {} label: {
            Text(title).font(.system(size: 13, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Soot.limeInk : Soot.muted)
                .padding(.horizontal, 10).frame(height: 28)
                .background { if on { Capsule().fill(Soot.lime) } }
        }
        .buttonStyle(SegmentButton(on: on))
    }
}

// MARK: - In-window menus

/// Frames (window coordinates) a click may land in without closing the menu that is open:
/// the trigger and the menu itself. Marked with `keepsMenuOpen()`, read by `closesOnOutsideClick`.
private struct MenuInsideFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

/// Closes an in-window menu (the Add project ⌄ menu, an account's status menu) on any click
/// outside it, wherever in the window the click lands, and swallows that click, like a system
/// menu would. Mark the trigger and the menu with `keepsMenuOpen()` so their own clicks pass.
private struct ClosesOnOutsideClick: ViewModifier {
    let isOpen: Bool
    let close: () -> Void
    @State private var inside: [CGRect] = []
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(MenuInsideFramesKey.self) { inside = $0 }
            .onChange(of: isOpen, initial: true) { _, open in open ? install() : remove() }
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard let window = event.window, window.isKeyWindow, let content = window.contentView else { return event }
            // SwiftUI's global space is the content view with a top-left origin; AppKit's is bottom-left.
            let local = content.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
            if inside.contains(where: { $0.contains(point) }) { return event }
            DispatchQueue.main.async(execute: close)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// While `isOpen`, a click anywhere else in the window runs `close` and goes no further.
    func closesOnOutsideClick(_ isOpen: Bool, close: @escaping () -> Void) -> some View {
        modifier(ClosesOnOutsideClick(isOpen: isOpen, close: close))
    }

    /// Part of an open menu (its trigger or its body): clicks here do not close it.
    func keepsMenuOpen() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: MenuInsideFramesKey.self, value: [geo.frame(in: .global)])
        })
    }
}

// MARK: - Tooltips in the app's own style

/// What a hovered view asks the window to show beside it.
struct TipRequest {
    let title: String
    let detail: String?
    let anchor: Anchor<CGRect>
}

private struct TipKey: PreferenceKey {
    static var defaultValue: TipRequest? = nil
    static func reduce(value: inout TipRequest?, nextValue: () -> TipRequest?) { value = nextValue() ?? value }
}

/// A tooltip beside the view after a short hover (300 ms), drawn by the nearest `tipHost()` in
/// the app's own style instead of the system's slow yellow one. `forced` shows it at once
/// (snapshots). The view keeps its accessible name: the tip is for the pointer.
private struct SootTip: ViewModifier {
    let title: String
    let detail: String?
    let forced: Bool
    @State private var hovering = false
    @State private var shown = false
    @State private var delay: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                delay?.cancel()
                if inside {
                    delay = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled, hovering { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .onDisappear { delay?.cancel(); shown = false }
            .anchorPreference(key: TipKey.self, value: .bounds) { anchor in
                shown || forced ? TipRequest(title: title, detail: detail, anchor: anchor) : nil
            }
    }
}

/// The tip itself: a surface card with a title and one quiet line.
struct TipCard: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Soot.ink)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Soot.surface, in: RoundedRectangle(cornerRadius: Soot.radius))
        .overlay(RoundedRectangle(cornerRadius: Soot.radius).strokeBorder(Soot.line))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

private struct TipHost: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TipKey.self) { request in
            GeometryReader { geo in
                if let request {
                    let bounds = geo[request.anchor]
                    // Beside the view, centred on it; the card may be taller than the view.
                    TipCard(title: request.title, detail: request.detail)
                        .frame(height: bounds.height)
                        .offset(x: bounds.maxX + 8, y: bounds.minY)
                        .transition(.opacity)
                }
            }
            .motion(Motion.ui, fade: true, value: request?.title)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// A tooltip in the app's style, shown beside the view by the enclosing `tipHost()`.
    func sootTip(_ title: String, detail: String? = nil, forced: Bool = false) -> some View {
        modifier(SootTip(title: title, detail: detail, forced: forced))
    }

    /// Draws the tips its descendants ask for, beside them, over everything in this view.
    func tipHost() -> some View { modifier(TipHost()) }
}

// MARK: - Right click

/// Runs `action` on a right click (or a control-click) inside the view, the way a context
/// menu opens; the click goes no further.
private struct RightClick: ViewModifier {
    let action: () -> Void
    @State private var frame: CGRect = .zero
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geo in
                Color.clear.onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
            })
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  let window = event.window, window.isKeyWindow, let content = window.contentView else { return event }
            let local = content.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
            guard frame.contains(point) else { return event }
            DispatchQueue.main.async(execute: action)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View { modifier(RightClick(action: action)) }
}

// MARK: - Menu panel

/// The frame of an in-window menu (the Add project menu, a tile's context menu): ground,
/// a hairline, a soft shadow. Pair with `closesOnOutsideClick` / `keepsMenuOpen`.
struct MenuPanel<Content: View>: View {
    var width: CGFloat = 260
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content() }
            .padding(6)
            .frame(width: width)
            .background(Soot.ground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Soot.line))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .keepsMenuOpen()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}

/// A heading inside a menu panel: what the menu is about, in two short lines.
struct MenuPanelHead: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(1)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Soot.muted).lineLimit(1) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A hairline between groups of a menu panel.
struct MenuPanelDivider: View {
    var body: some View { Rectangle().fill(Soot.line).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 3) }
}

/// One action of a menu panel: a glyph (or a tool's logo), a title, an optional quiet line.
/// `url` makes it a link that opens outside (↗); `destructive` paints it in the negative tone.
struct MenuPanelRow: View {
    var symbol: String? = nil
    var service: ServiceKind? = nil
    let title: String
    var detail: String? = nil
    var url: URL? = nil
    var destructive = false
    var action: () -> Void = {}

    var body: some View {
        if let url {
            Link(destination: url) { face }
                .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
                .accessibilityLabel(detail.map { "\(title). \($0)" } ?? title)
                .accessibilityHint("Opens outside Dever")
        } else {
            Button(action: action) { face }
                .buttonStyle(RowButton(lift: .surface, radius: Soot.radius))
                .accessibilityLabel(detail.map { "\(title). \($0)" } ?? title)
        }
    }

    private var tint: Color { destructive ? Theme.pillNegative.ink : Soot.ink }

    private var face: some View {
        HStack(spacing: 10) {
            Group {
                if let service { BrandLogo(service: service, size: 13).foregroundStyle(tint) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint) }
            }
            .frame(width: 26, height: 26)
            .background(Soot.surface, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(tint).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if url != nil {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Soot.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: detail == nil ? 36 : 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
