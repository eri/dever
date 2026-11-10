import SwiftUI

/// A way back to the latest message of a long conversation: a small pill at the bottom of the
/// scroll view, shown once the reader has scrolled more than a screen's third above the end.
/// A click scrolls to `target` (the view closing the list) on the room's spring; instantly
/// under Reduce Motion. Before macOS 15 the scroll position cannot be read, so the pill stays.
struct JumpToLatest: ViewModifier {
    let proxy: ScrollViewProxy
    let target: AnyHashable
    @State private var away = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(DistanceFromEnd { distance, height in
                let far = distance > max(160, height / 3)
                if far != away { Motion.run(Motion.ui, fade: true) { away = far } }
            })
            .overlay(alignment: .bottom) {
                if away || !canRead {
                    JumpPill {
                        Motion.run(Motion.move) { proxy.scrollTo(target, anchor: .bottom) }
                    }
                    .padding(.bottom, 14)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
            }
    }

    private var canRead: Bool {
        if #available(macOS 15.0, *) { return true } else { return false }
    }
}

extension View {
    /// Adds the "Latest" pill to a scroll view (see `JumpToLatest`).
    func jumpToLatest(_ proxy: ScrollViewProxy, target: AnyHashable) -> some View {
        modifier(JumpToLatest(proxy: proxy, target: target))
    }
}

/// Reports how far the visible area is from the end of the content, and its height (macOS 15+).
private struct DistanceFromEnd: ViewModifier {
    let changed: (_ distance: CGFloat, _ height: CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: [CGFloat].self, of: { g in
                [g.contentSize.height - g.visibleRect.maxY, g.containerSize.height]
            }) { _, new in changed(new[0], new[1]) }
        } else {
            content
        }
    }
}

/// The pill itself: an arrow and "Latest" on a raised surface, lime arrow, 32 pt high.
private struct JumpPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Soot.lime)
                Text("Latest").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .buttonStyle(ChipButton(fill: Soot.surface))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .help("Jump to the latest message")
        .accessibilityLabel("Jump to the latest message")
    }
}
