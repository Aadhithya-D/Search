import Foundation

// Fork: closing the last page leaves the window up with nothing open.
// Upstream replaces that page with a blank tab, and closing the blank tab
// closes the window. Pins stay in the grid, put down; they are not a page
// to land on, and they are not a reason to open a new tab.

extension Browser {
    /// A page still in the row that isn't a pin: a loose tab, or a bookmark's
    /// own page, asleep or not. Selecting it wakes it. A pin is not a place
    /// to land.
    func openPage(besides id: Tab.ID) -> Tab? {
        tabs.filter { $0.id != id && $0.pin == nil }
            .max(by: { $0.touched < $1.touched })
    }

    /// Nothing left to show. The window stays; ⌘T and New Tab open a page.
    func clearPage() {
        activeID = nil
        typed = ""
        editing = false
    }

    /// An address with no page up opens one. With a page up, that page goes
    /// there — including a bookmark's page, which `visit` would open beside.
    func show(_ url: URL) {
        if let tab = active {
            tab.go(to: url)
        } else {
            open(url, foreground: true)
        }
    }
}
