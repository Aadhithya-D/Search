import Foundation

// Fork: what closing the last page leaves.
//
// Upstream replaces the last page with a blank tab, and closing that blank
// tab closes the window. Here the last open page closed lands on a new tab
// — not on a pin or a bookmark's page, which is where upstream's neighbour
// rule landed once the loose tabs were gone.
//
// Or, with Settings › Tabs › "Leave the window empty when the last page
// closes" (from Adithya Sakaray's PR #1), the window stays up with nothing
// in it. Pins stay in the grid, put down; ⌘T, New Tab or an address typed in
// the column opens a page.

extension Browser {
    /// `closed` was an ordinary tab, and no ordinary tab is left: only pins
    /// and bookmark pages, which are places kept rather than pages open.
    func closesLastPage(_ closed: Tab) -> Bool {
        guard closed.pin == nil, closed.bookmark == nil else { return false }
        return !tabs.contains { $0.pin == nil && $0.bookmark == nil }
    }

    /// A page still in the row that isn't a pin: a loose tab, or a bookmark
    /// whose page is still open.
    func openPage(besides id: Tab.ID) -> Tab? {
        tabs.filter { $0.id != id && $0.pin == nil && !($0.bookmark != nil && $0.asleep) }
            .max(by: { $0.touched < $1.touched })
    }

    /// Nothing left to show: an empty window, or a new tab — as Settings says.
    func afterLastPage() {
        guard prefs.emptiesWindow else { return newTab() }
        activeID = nil
        typed = ""
        editing = false
    }

    /// An address with no page up opens one; with a page up, it goes there.
    func show(_ url: URL) {
        if let tab = active {
            tab.go(to: url)
        } else {
            open(url, foreground: true)
        }
    }
}
