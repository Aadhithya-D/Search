import SwiftUI

/// The right-hand column leaves the window controls on the left. Reveal
/// room in the browser's coloured frame along with those controls, using
/// the stage's existing slide-and-resize layout rather than covering a site.
enum RightSidebarTopBar {
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
        return max(0, SideBar.topRow - gutterTop)
    }
}
