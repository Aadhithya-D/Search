import SwiftUI
import WebKit

// Fork: a pin stays on its site, as in Arc. A plain click in a pinned tab on
// a link to another site opens that link in a peek over the pin (Peek.swift),
// and the pin stays the page it was pinned for. Links within the site go as
// they always have, so moving about Gmail or Notion stays in the pin. A link
// that asks for a new window (target="_blank", window.open on a click) peeks
// too; a window sized by its page — "Sign in with…" — is left alone, as is a
// click with a modifier held. Settings › Tabs › Pins stay on their site, on.
//
// From driceroland/Search#581 (Pins stay on their site), which upstream has
// not taken yet; there it is off unless asked for.
//
// And from every tab: a link that asks for a new tab or window opens in a
// peek too (Settings › Tabs › New tabs from links open in a peek, on).
// ⌘-click, the middle button and Open Link in New Tab still make a tab.

extension Browser {
    /// A link from the pin `tab`, on the page at `page`, would leave its site.
    func peeksFromPin(_ url: URL, in tab: Tab, on page: URL?) -> Bool {
        guard prefs.pinsPeek, tab.pin != nil, peekTab == nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let there = url.host()?.lowercased(),
              let here = page?.host()?.lowercased()
        else { return false }
        return there != here && Vault.registrable(there) != Vault.registrable(here)
    }

    /// A new window asked for by a page, plainly clicked: in the peek — from
    /// a pin with Pins stay on their site, from any tab with New tabs from
    /// links open in a peek. Built on the configuration WebKit hands over and
    /// given back to it, so the page loads into it and the page that asked
    /// keeps it as its opener.
    func peeksWindow(from source: Tab?, action: WKNavigationAction, popup: Bool) -> Bool {
        guard let source, source.pin != nil ? prefs.pinsPeek : prefs.linksPeek,
              !popup, peekTab == nil, !source.bench,
              [.linkActivated, .other].contains(action.navigationType),
              action.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty
        else { return false }
        return true
    }

    func peekWindow(_ configuration: WKWebViewConfiguration, from tab: Tab, going url: URL?) -> WKWebView {
        let page = Tab(shy: tab.shy, configuration: configuration)
        prepare(page)
        page.opener = tab.id
        if let url { page.setAddressOptimistically(url) }
        notePeek(url, from: tab)
        withAnimation(Motion.settle) { peekTab = page }
        return page.web
    }

    /// Which tab the peek came from, and for a pin, the site it went to: the
    /// pin's own script sending it there a moment later is turned away.
    func notePeek(_ url: URL?, from tab: Tab) {
        peekFrom = tab.id
        if tab.pin != nil, let host = url?.host()?.lowercased() { tab.peeked = (Vault.registrable(host), Date()) }
    }

    /// A pin's page going after a link it just peeked at, by script: Google's
    /// results do, when the click didn't take the page away by itself. The
    /// peek already has it, and the pin stays.
    func followsPeek(_ url: URL, in tab: Tab) -> Bool {
        guard prefs.pinsPeek, tab.pin != nil, let peeked = tab.peeked,
              Date().timeIntervalSince(peeked.at) < 3,
              let host = url.host()?.lowercased()
        else { return false }
        return Vault.registrable(host) == peeked.site
    }
}

/// The peek's icon, worn by the pin it was opened from while it is up: on a
/// square's corner, at the end of a row. The letter of its site until the
/// icon comes in.
struct PeekBadge: View {
    @ObservedObject var page: Tab
    var size: CGFloat = 16

    var body: some View {
        Mark(icon: page.icon, letter: page.monogram, size: size * 0.7)
            .frame(width: size, height: size)
            .background(Palette.ground, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
