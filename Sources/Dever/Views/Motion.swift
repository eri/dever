import AppKit
import SwiftUI

// Dever's motion vocabulary, in one place. Four curves, nothing linear:
//   quick   120 ms ease-out  — press and hover feedback, barely seen
//   ui      200 ms ease-out  — swaps, fades, tab changes, skeleton → content
//   exit    150 ms ease-in   — something leaving
//   move    spring ~350 ms   — a larger move that settles (the Slack room, a stage change)
//   settle  spring ~300 ms   — a marker travelling between choices
// Every animation is explicit (`Motion.run`, `.motion(value:)`) so none leaks into layout it
// was not meant for, and every movement is off under Reduce Motion: fades stay (Apple's
// guidance: dissolves are fine), moves, scales and springs go.

enum Motion {
    static let quick: Animation = .easeOut(duration: 0.12)
    static let ui: Animation = .easeOut(duration: 0.2)
    static let exit: Animation = .easeIn(duration: 0.15)
    static let move: Animation = .spring(response: 0.38, dampingFraction: 0.86)
    static let settle: Animation = .spring(response: 0.3, dampingFraction: 0.82)

    /// The system's Reduce Motion switch, readable outside a view body.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// `withAnimation`, off under Reduce Motion unless the change is a fade (`fade: true`).
    static func run<R>(_ animation: Animation, fade: Bool = false, _ body: () throws -> R) rethrows -> R {
        try withAnimation(reduced && !fade ? nil : animation, body)
    }

    /// A view enters with a fade and a small rise, leaves with a fade; fade only under Reduce Motion.
    static var rise: AnyTransition {
        reduced ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                         removal: .opacity.combined(with: .offset(y: -4)))
    }

    /// A surface pops from 0.97 to its size; fade only under Reduce Motion.
    static var pop: AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    /// A pane slides in from its edge; fade only under Reduce Motion.
    static func slide(from edge: Edge) -> AnyTransition {
        reduced ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

extension View {
    /// An explicit animation on one value, off under Reduce Motion unless it is a fade.
    func motion<V: Equatable>(_ animation: Animation, fade: Bool = false, value: V) -> some View {
        modifier(MotionModifier(animation: animation, fade: fade, value: value))
    }

    /// A number that rolls to its new value instead of swapping (counters that refresh).
    func rollingNumber<V: Equatable>(_ value: V) -> some View {
        modifier(RollingNumber(value: value))
    }

    /// A brief scale on press for custom-drawn buttons; off under Reduce Motion.
    func pressScale(_ pressed: Bool) -> some View {
        modifier(PressScale(pressed: pressed))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let fade: Bool
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion && !fade ? nil : animation, value: value)
    }
}

private struct RollingNumber<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(Motion.ui, value: value)
    }
}

private struct PressScale: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: pressed)
    }
}

/// A plain button that answers a press with a 0.97 scale: pills, tiles, chips.
struct PressButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressScale(configuration.isPressed)
    }
}

/// Shows `content(value)`; when `value` changes, what is shown fades out (150 ms ease-in), then
/// the new content rises in (200 ms ease-out). Built on opacity rather than on a transition: a
/// transition can stay unfinished when the leaving view held the focused field, and a leaving
/// stage of onboarding or of the project editor usually does.
struct FadeSwap<Value: Equatable, Content: View>: View {
    let value: Value
    @ViewBuilder let content: (Value) -> Content
    @State private var shown: Value?
    @State private var opacity = 1.0
    @State private var offset = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(shown ?? value)
            .opacity(opacity)
            .offset(y: offset)
            .onChange(of: value) { _, new in swap(to: new) }
    }

    private func swap(to new: Value) {
        withAnimation(Motion.exit) { opacity = 0; offset = reduceMotion ? 0 : -4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.keyWindow?.makeFirstResponder(nil)
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { shown = new; offset = reduceMotion ? 0 : 8 }
            withAnimation(Motion.ui) { opacity = 1; offset = 0 }
        }
    }
}
