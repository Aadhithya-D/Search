import SwiftUI

// Fork: how far a page has come, said quietly — a hairline across the top of
// the page, and the tab's ring filling as the page does. Grey, never a
// colour of their own; both follow WebKit's
// own estimate of the load, eased so a jump in it reads as a glide.

/// The hairline over the top of the page while it loads.
struct LoadLine: View {
    @ObservedObject var tab: Tab
    @State private var shown: Double = 0
    @State private var visible = false

    var body: some View {
        GeometryReader { box in
            // A mid grey, not the chrome's ink: it lies on the page, which is
            // as often white under a dark window as the other way round.
            Capsule()
                .fill(Color(white: 0.5).opacity(0.6))
                .frame(width: box.size.width * shown, height: 2)
                .opacity(visible ? 1 : 0)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .onAppear { if tab.loading { start() } }
        .onChange(of: tab.loading) { _, loading in loading ? start() : finish() }
        .onChange(of: tab.progress) { _, now in
            guard tab.loading else { return }
            // Never back, and never quite the end until it is.
            let target = max(shown, min(0.94, now))
            withAnimation(.easeOut(duration: 0.4)) { shown = target }
        }
    }

    private func start() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { shown = 0 }
        visible = true
        withAnimation(.easeOut(duration: 0.4)) { shown = max(0.08, min(0.94, tab.progress)) }
    }

    /// Across to the end, then gone.
    private func finish() {
        guard visible else { return }
        withAnimation(.easeOut(duration: 0.2)) { shown = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(0.22)) { visible = false }
    }
}

/// The tab's ring: a faint track, and an arc that fills with the page,
/// turning slowly while it waits.
struct ProgressRing: View {
    @ObservedObject var tab: Tab
    var size: CGFloat = 11
    @State private var angle: Double = 0

    private var filled: Double { max(0.1, min(0.97, tab.progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.ink.opacity(0.1), lineWidth: 1.4)
            Circle()
                .trim(from: 0, to: filled)
                .stroke(Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90 + angle))
                .animation(.easeOut(duration: 0.4), value: filled)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}
