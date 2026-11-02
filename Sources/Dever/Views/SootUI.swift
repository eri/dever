import SwiftUI

// The app's sheet and onboarding language, from the "product performs" direction:
// soot-black ground, white ink, one lime for actions; rows instead of forms; few words.
// Sheets use it through `sootSheet()`.

/// Soot and lime: black ground, one lime for actions and the stage behind the product.
enum Soot {
    static let ground = Color(red: 0.059, green: 0.059, blue: 0.059)     // #0f0f0f
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.102)    // #1a1a1a
    static let ink = Color.white
    static let muted = Color(red: 0.56, green: 0.56, blue: 0.56)         // #8f8f8f · 5.9:1 on ground, 5.4:1 on surface
    /// Control edges: 3.9:1 on ground, 3.5:1 on surface (WCAG 1.4.11 asks 3:1).
    static let edge = Color(red: 0.44, green: 0.44, blue: 0.44)          // #707070
    static let lime = Color(red: 0.855, green: 0.98, blue: 0.612)        // #dafa9c
    static let limeInk = ground
    static let radius: CGFloat = 8
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
            .environment(\.colorScheme, .dark)
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
        HStack(spacing: 12) {
            mark()
            Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.6).foregroundStyle(Soot.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.muted)
                    .frame(width: 28, height: 28).background(Soot.surface, in: Circle())
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
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soot.muted)
    }
}
