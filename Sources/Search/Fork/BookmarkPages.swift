import Foundation

// Fork: a bookmark in the column is its own page, as in Arc. A click opens
// it in a tab that belongs to the bookmark — drawn in the bookmark's row,
// never again among the tabs — and a second click comes back to that tab
// (Browser.openBookmark, which stays in Browser.swift for the row's private
// bookkeeping).
// Those tabs sit at the end of `tabs`, behind the row, so ⌘1–⌘9, the strip
// and every insertion keep to the row (`rowTabs`, `rowEnd`).

extension Browser {
    /// Tabs drawn in the row. A bookmark's page lives in that bookmark, so
    /// it is not also a tab underneath.
    var rowTabs: [Tab] { tabs.filter { $0.bookmark == nil } }

    /// Where the row ends and bookmark pages begin. A new tab belongs in the
    /// row, never after those pages.
    var rowEnd: Int { tabs.firstIndex { $0.bookmark != nil } ?? tabs.count }

    /// A bookmark's pages go at the end, behind the row, so the tabs you
    /// switch with ⌘1 keep their places.
    static func filedLast(_ row: [Tab]) -> [Tab] {
        row.filter { $0.bookmark == nil } + row.filter { $0.bookmark != nil }
    }

    /// A bookmark page belongs to the space whose list holds that bookmark.
    /// One filed under a list this space doesn't have is just a tab.
    func releaseForeignBookmarks() {
        let kept = bookmarks.identifiers
        for tab in tabs {
            guard let mark = tab.bookmark, !kept.contains(mark) else { continue }
            tab.bookmark = nil
        }
    }
}
