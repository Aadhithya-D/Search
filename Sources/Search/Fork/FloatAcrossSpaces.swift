import Foundation

// Fork: the floating video goes with you from space to space. Leaving a
// space was landing it, back into a tab that was then parked out of sight;
// now leaving one floats the video out as leaving a tab does (Settings ›
// General › Float the video when you switch tabs), and one already out
// stays out. It goes home when you come back to its tab, or press its
// return button, which brings its space back first.

extension Browser {
    /// The tab whose video is out, in the space on screen or a parked one.
    var floatingTab: Tab? {
        guard let id = floating else { return nil }
        return (tabs + parkedTabs).first { $0.id == id }
    }

    /// Its tab, in whichever space holds it.
    func goHome(to tab: Tab) {
        if !tabs.contains(where: { $0 === tab }),
           let space = parked.first(where: { $0.value.tabs.contains { $0 === tab } })?.key {
            switchSpace(to: space)
        }
        if let here = tabs.first(where: { $0 === tab }) { select(here) }
    }

    /// Back in a space on the tab whose video is out: it goes back in.
    func landIfHome() {
        if let id = floating, id == activeID { land() }
    }

    /// Tabs about to close: their video comes home first.
    func landIfIn(_ closing: [Tab]) {
        if let id = floating, closing.contains(where: { $0.id == id }) { land() }
    }
}
