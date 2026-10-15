import AppKit

// Fork: a link's right-click menu starts with Open Link in New Tab. WebKit's
// Open Link only did what a click on the link already does, and Download
// Linked File, on every link, is gone too.
//
// Open Link in New Tab opens behind, as upstream has it, unless Settings ›
// Tabs › "Open Link in New Tab goes to it" says otherwise; ⌥ then turns it
// into the one that stays behind. Either way a tab asked for from the menu
// is a tab, never a peek (Fork/PinPeek.swift).

extension PageView {
    func dropOpenLink(_ menu: NSMenu) {
        guard menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }),
              let index = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLink" })
        else { return }
        menu.removeItem(at: index)
        menu.items.filter { $0.identifier?.rawValue == "WKMenuItemIdentifierDownloadLinkedFile" }.forEach(menu.removeItem)
    }

    /// Upstream's two items, Open Link in New Tab (behind) and, with ⌥, the
    /// one that goes to it: that one marked as the menu's, and with Settings
    /// asking for it, the two the other way round.
    func frontLinkMenu(_ menu: NSMenu, goesToIt: Bool) {
        guard let behind = menu.items.first(where: { $0.action == #selector(openLinkBehind(_:)) }),
              let index = menu.items.firstIndex(of: behind), menu.items.indices.contains(index + 1)
        else { return }
        let front = menu.items[index + 1]
        guard front.isAlternate else { return }
        front.target = self
        front.action = #selector(openLinkFront(_:))
        guard goesToIt else { return }
        behind.action = #selector(openLinkFront(_:))
        front.title = "Open Link in New Tab Behind"
        front.action = #selector(openLinkBehind(_:))
    }

    @objc func openLinkFront(_ item: NSMenuItem) {
        guard let action = openLink.action else { return }
        frontSince = Date()
        NSApp.sendAction(action, to: openLink.target, from: item)
    }

    /// Whether the tab being made now is the menu's, to go to.
    func takeFront() -> Bool {
        defer { frontSince = nil }
        return frontSince.map { Date().timeIntervalSince($0) < 1 } ?? false
    }
}
