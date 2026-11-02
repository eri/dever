import AppKit
import SwiftUI

// Visual system: "framed sheet". The chrome (sidebar and title bar) is one blue-grey
// frame; the work sits on a sheet inset 8px with a hairline edge and no shadow. Colour
// goes on data and status only (under ~3% of the screen); the chrome stays grey.
// Tokens follow the dealt sheet; dark values follow its true-neutral dark rules.

extension Color {
    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

enum Theme {
    // Surfaces
    static let frame = Color(light: 0xF1F4F6, dark: 0x0C0E10)    // blue-grey chrome: the product's face
    static let sheet = Color(light: 0xFFFFFF, dark: 0x151719)
    static let raised = Color(light: 0xF4F6F8, dark: 0x1D2023)
    static let active = Color(light: 0xE6E9EC, dark: 0x262A2E)   // selected nav row
    static let border = Color(light: 0xE8EAEC, dark: 0x272A2E)
    static let rule = Color(light: 0xF0F1F2, dark: 0x1F2225)
    static let control = Color(light: 0xCDCED1, dark: 0x44484D)

    // Text (every tier reaches 4.5:1 on its surface)
    static let text = Color(light: 0x131416, dark: 0xF5F6F7)
    static let muted = Color(light: 0x5D5F60, dark: 0xB4B6B8)

    // Data and status
    static let chart1 = Color(light: 0x1B6C80, dark: 0x4FB0C6)   // the main data element: shipped
    static let chart2 = Color(light: 0x2F70BB, dark: 0x6CA2E6)   // in review
    static let chart3 = Color(light: 0xA86F0C, dark: 0xD9A23F)   // merged but not closed: needs action
    static let idle = Color(light: 0x8A8D91, dark: 0x6E7277)     // in progress, no PR yet
    static let empty = Color(light: 0xE3E6E9, dark: 0x2A2E33)    // to do
    static let positive = Color(light: 0x1E7B4F, dark: 0x3FC07A)
    static let negative = Color(light: 0xC4242A, dark: 0xE5566F)

    // Pills: a pale tint with dark ink of the same hue
    static let pillPositive = (bg: Color(light: 0xDCFAE5, dark: 0x172A1D), ink: Color(light: 0x04250E, dark: 0x3FC07A))
    static let pillNegative = (bg: Color(light: 0xFFEDEA, dark: 0x2C1A20), ink: Color(light: 0x831C1E, dark: 0xF0798C))
    static let pillWarning = (bg: Color(light: 0xFFFBEB, dark: 0x2A2212), ink: Color(light: 0x92400E, dark: 0xE8B04F))
    static let pillNeutral = (bg: Color(light: 0xEBEDEE, dark: 0x24272A), ink: Color(light: 0x353736, dark: 0xC9CBCD))

    // Geometry
    static let radiusCard: CGFloat = 8
    static let radiusControl: CGFloat = 6
    static let radiusSheet: CGFloat = 16
    static let sheetInset: CGFloat = 8
    static let gap: CGFloat = 24
    static let pad: CGFloat = 24
    static let sidebarWidth: CGFloat = 228

    // Type: the system grotesk, one family; SF Mono for IDs only.
    static let title = Font.system(size: 22, weight: .semibold)
    static let section = Font.system(size: 16, weight: .semibold)
    static let kpi = Font.system(size: 28, weight: .regular)
    static let body = Font.system(size: 14)
    static let bodyStrong = Font.system(size: 14, weight: .medium)
    static let small = Font.system(size: 12)
    static let smallStrong = Font.system(size: 12, weight: .semibold)
    static let id = Font.system(size: 12, design: .monospaced)
}

// MARK: - Building blocks

/// The white sheet the work sits on, inside the tinted frame.
struct SheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.radiusSheet))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSheet).strokeBorder(Theme.border))
            .padding([.trailing, .bottom], Theme.sheetInset)
            .background(Theme.frame)
    }
}

/// A card inside the sheet: 1px edge, no shadow.
struct Panel: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border))
    }
}

extension View {
    func sheetBackground() -> some View { modifier(SheetBackground()) }
    func panel(padding: CGFloat = 20) -> some View { modifier(Panel(padding: padding)) }
}

/// Pale pill with same-hue ink. The text carries the meaning; the tint only reinforces it.
struct Pill: View {
    enum Tone { case positive, negative, warning, neutral }
    let text: String
    let tone: Tone

    var body: some View {
        let pair = switch tone {
        case .positive: Theme.pillPositive
        case .negative: Theme.pillNegative
        case .warning: Theme.pillWarning
        case .neutral: Theme.pillNeutral
        }
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(pair.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(pair.bg, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Section heading inside the sheet, with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.section).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(Theme.small).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

/// Flat near-black primary button (inverted on dark).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(Theme.sheet)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.text.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Quiet bordered button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(configuration.isPressed ? Theme.active : Theme.sheet,
                        in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.control))
    }
}
