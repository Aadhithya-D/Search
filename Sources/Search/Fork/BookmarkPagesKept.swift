import Foundation

// Fork: with Settings › Tabs › "Keep a bookmark's page when it is closed"
// (from Adithya Sakaray's PR #1), closing a bookmark's page puts it down
// rather than throwing it away: the next click on the bookmark comes back to
// where it was. The cross on its row becomes a minus while it is down, and
// the minus removes the bookmark. Off, a closed bookmark's page is gone and
// the next click opens the bookmarked address afresh.

extension Browser {
    /// Put down, and off it to a loose tab, or whatever the last page leaves.
    func putDown(bookmarkPage tab: Tab) {
        tab.rest()
        guard activeID == tab.id else { return }
        if let row = tabs.last(where: { $0.id != tab.id && $0.bookmark == nil && $0.pin == nil }) {
            select(row)
        } else {
            afterLastPage()
        }
    }
}
