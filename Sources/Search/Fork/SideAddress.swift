import SwiftUI

// Fork: the column's first rows, as in Arc — the traffic lights with back,
// forward and reload at the end of their line, then the page's address as a
// pill: the host at rest, the whole address to type into, a link that copies
// it and the site's controls (reading mode, the site card, the extensions).
// Upstream's raised field stays for the strip across the top.

extension SideBar {
    /// The row the traffic lights and back, forward and reload share. The
    /// title bar is made this tall in the column's layout (Lights.retarget).
    static let topRow: CGFloat = 34
}

extension Preferences {
    /// The line an empty address field shows.
    var searchPrompt: String {
        "Search \(engine.name(custom: customEngine)) or type a URL"
    }
}

/// The address, in the column, above the pins. At rest it is the site's name.
/// The link copies it; the other door is the page's own controls.
struct SideAddress: View {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var controls = false

    static let height: CGFloat = 32
    /// The air under the pill before the pins: the pins' own gap and a
    /// little more, so the address reads as a row of its own.
    static let below: CGFloat = 8
    /// The pill, and the air under it before the pins.
    static let block: CGFloat = height + below

    var body: some View {
        pill
        .overlay(alignment: .top) {
            if browser.fieldShowing, browser.active?.isBlank != true, !browser.offers.isEmpty {
                OfferList(browser: browser)
                    .padding(.top, 40)
                    .zIndex(2)
            }
        }
    }

    private var pill: some View {
        HStack(spacing: 0) {
            if typingHere {
                if let name = browser.searchAlias?.name {
                    KeywordMark(name: name)
                        .padding(.trailing, 6)
                }
                AddressField(
                    browser: browser,
                    point: 12.5,
                    prompt: browser.searchAlias == nil ? browser.prefs.searchPrompt : "Enter search terms"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 16)
            } else {
                Text(shown)
                    .font(.system(size: 12.5))
                    .foregroundStyle(browser.active?.address == nil ? Palette.quiet : Palette.ink.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            if let url = browser.active?.address, !typingHere {
                // Clear of the host, however long it runs.
                Color.clear.frame(width: 6)
                PillKnob(symbol: copied ? "checkmark" : "link", help: copied ? "Copied" : "Copy Link") {
                    browser.copyAddress()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                PillKnob(symbol: "slider.horizontal.3", help: "Site Settings and Extensions", on: controls) {
                    controls = true
                }
                .background(ExtensionSiteAnchor())
                .popover(isPresented: $controls, arrowEdge: .bottom) {
                    SiteControls(browser: browser) { controls = false }.popGround()
                }
                .disabled(url.scheme == nil)
            }
        }
        // The host starts where the rows' titles do; the knobs' own squares
        // leave their symbols as far in from the other end.
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: SideAddress.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.45))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            guard !typingHere else { return }
            if browser.active?.isBlank == true { browser.askFocus() } else { browser.edit() }
        }
    }

    private var typingHere: Bool {
        browser.fieldShowing && browser.active?.isBlank != true
    }

    /// The host, as the column says it. The field, once open, has the rest.
    private var shown: String {
        guard let url = browser.active?.address else { return browser.prefs.searchPrompt }
        if let host = url.host(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return Address.pretty(url)
    }
}

/// One of the pill's two buttons: the symbol in a square of its own that
/// lights under the pointer, and stays lit while what it opened is open.
private struct PillKnob: View {
    let symbol: String
    let help: String
    var on = false
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(hovering || on ? 0.9 : 0.65))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.ink.opacity(hovering || on ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(Motion.quick, value: hovering)
    }
}

/// What Safari keeps behind the page menu: the article, the size, and how
/// the connection is doing. Copying the address is the link beside this.
struct SiteControls: View {
    @ObservedObject var browser: Browser
    let close: () -> Void

    var body: some View {
        // Drawn as one menu, on the same measures as the site card inside
        // it: every line's text from the same edge, one kind of separator.
        VStack(alignment: .leading, spacing: 0) {
            if let tab = browser.active, !tab.isBlank {
                SiteCard(browser: browser, tab: tab, padded: false, reader: true, close: close)
            }
            // The extensions, for a column with no room for their button —
            // where Arc keeps them too, behind the site's own menu.
            if #available(macOS 15.4, *), !Extensions.shared.installed.isEmpty {
                SiteCard.Separator()
                ExtensionsInline(close: close)
            }
        }
        .padding(.vertical, MenuMetrics.pad)
        // A menu's width, not the longest extension's. Names that don't fit
        // are cut (Fork/ExtensionsInline.swift).
        .frame(width: 260)
        .fixedSize(horizontal: true, vertical: true)
    }
}
