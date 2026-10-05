import SwiftUI

/// The right-hand column leaves the window controls on the left. Reveal
/// room in the browser's coloured frame along with those controls, using
/// the stage's existing slide-and-resize layout rather than covering a site.
enum RightSidebarTopBar {
    /// The bar from the window's top edge: the lights, and a little air
    /// round them — not the column's whole first row.
    static let height: CGFloat = 26
    /// How far the lights stand up from the middle of the column's first
    /// row, to sit in the middle of the bar instead.
    static let lift: CGFloat = (SideBar.topRow - height) / 2
    @MainActor
    static func reveal(_ on: Bool, in browser: Browser) {
        let shown = on && browser.prefs.sidebar && browser.prefs.sideRight
            && browser.active?.immersed != true
            && browser.window?.styleMask.contains(.fullScreen) != true
        guard browser.rightTopRevealed != shown else { return }
        withAnimation(Motion.glide) { browser.rightTopRevealed = shown }
    }
}

extension ContentView {
    var rightTopBarHeight: CGFloat {
        guard browser.rightTopRevealed, framed, browser.prefs.sideRight,
              browser.window?.styleMask.contains(.fullScreen) != true else { return 0 }
        // The page already leaves its normal eight-point inset above it.
        return max(0, RightSidebarTopBar.height - gutterTop)
    }
}
