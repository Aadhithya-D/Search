import AppKit

// Fork: a link's right-click menu starts with Open Link in New Tab. WebKit's
// Open Link only did what a click on the link already does, and Download
// Linked File, on every link, is gone too.

extension PageView {
    func dropOpenLink(_ menu: NSMenu) {
        guard menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }),
              let index = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLink" })
        else { return }
        menu.removeItem(at: index)
        menu.items.filter { $0.identifier?.rawValue == "WKMenuItemIdentifierDownloadLinkedFile" }.forEach(menu.removeItem)
    }
}
