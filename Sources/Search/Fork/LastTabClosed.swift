import Foundation

// Fork: closing the last page you had open lands on a new tab. Upstream
// lands on the neighbour, which with the loose tabs gone is a pin or a
// bookmark's own page — the page closed a moment ago, as it looked.

extension Browser {
    /// `closed` was an ordinary tab, and no ordinary tab is left: only pins
    /// and bookmark pages, which are places kept rather than pages open.
    func closesLastPage(_ closed: Tab) -> Bool {
        guard closed.pin == nil, closed.bookmark == nil else { return false }
        return !tabs.contains { $0.pin == nil && $0.bookmark == nil }
    }
}
