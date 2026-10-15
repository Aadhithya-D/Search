import SwiftUI

// Fork: Arc's bar. With the tabs down the side, ⌘T, New Tab, ⌘L and ⌘K bring
// up one field floating over the window instead of a blank tab or the
// column's address: open tabs that match first, to switch to, then where you
// have been and a search. Nothing is made until something is chosen — an
// address or a search opens a new tab (⌘L's goes where the page is), a tab is
// switched to, and Escape or a click beside it leaves everything as it was.
// A window with nothing open is the space's colour alone, and opens with the
// bar up. Light or dark as the space's colour is. Settings › Tabs › Arc-style
// address bar, on.

enum BarMode {
    /// ⌘T, New Tab, ⌘K: what is chosen opens beside what is open.
    case new
    /// ⌘L: the page's address, to go somewhere else in its tab.
    case edit
}

extension Browser {
    /// The bar stands in for the field: the tabs down the side, and asked for.
    var usesBar: Bool { prefs.arcBar && prefs.sidebar }

    /// What closing the last page leaves: with the bar, always the empty
    /// window it opens over; otherwise as Settings › Tabs says
    /// (Fork/LastTabClosed.swift).
    var leavesWindowEmpty: Bool { usesBar || prefs.emptiesWindow }

    /// ⌘T, New Tab in the column or a menu.
    func askNewTab() {
        if usesBar, !extensionNewTab { openBar(.new) } else { newTab() }
    }

    /// An extension's new tab page, which ⌘T opens as a tab, as it was.
    private var extensionNewTab: Bool {
        if #available(macOS 15.4, *) { return Extensions.shared.newTabPage != nil }
        return false
    }

    func openBar(_ mode: BarMode, typing text: String = "") {
        cancelTabEdit()
        clearKeyword()
        siteChip = nil
        withAnimation(Motion.quick) { bar = mode }
        // After the mode, so the list it makes already has the open tabs.
        typed = text
        editing = true
        askFocus()
    }

    /// The bar's list: tabs that match, to switch to, ahead of the rest —
    /// without the same page twice. On an empty field, the tabs alone, the
    /// last looked at first.
    func barOffers(_ list: [Suggestion]) -> [Suggestion] {
        let open = Array(openPages(matching: typed).prefix(typed.isEmpty ? 5 : 3))
        let there = Set(open.map { History.identity(for: $0.url) })
        let rest = list.filter { $0.kind != .visited || !there.contains(History.identity(for: $0.url)) }
        return open + rest + engineOffers(besides: rest)
    }

    /// What the search engine itself suggests for what is typed, as its own
    /// field would, under the rest. Asked a moment after typing stops, of
    /// the engine you search with, never from a private window or tab;
    /// the list is made again when the answer comes.
    private func engineOffers(besides list: [Suggestion]) -> [Suggestion] {
        let words = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefs.engineSuggestions, !words.isEmpty, !isPrivate, active?.shy != true,
              let ask = prefs.engine.suggestions(for: words)
        else { return [] }
        let asked = EngineSuggest.shared
        guard asked.query == words else {
            asked.ask(words, at: ask) { [weak self] in
                guard let self, bar != nil, picked == nil,
                      typed.trimmingCharacters(in: .whitespacesAndNewlines) == words else { return }
                guess()
            }
            return []
        }
        let taken = Set(list.map { $0.key.lowercased() } + [words.lowercased()])
        return asked.words
            .filter { !taken.contains($0.lowercased()) }
            .prefix(4)
            .compactMap { word in searchURL(for: word).map { Suggestion(key: word, title: "", url: $0, kind: .search) } }
    }
}

extension Engine {
    /// Where the engine answers what it would suggest, in OpenSearch's
    /// shape: [what was typed, [suggestions…]]. Nil for one that has none
    /// open to ask.
    func suggestions(for words: String) -> URL? {
        let template: String
        switch self {
        case .google: template = "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        case .duckduckgo: template = "https://duckduckgo.com/ac/?q=%s&type=list"
        case .bing: template = "https://api.bing.com/osjson.aspx?query=%s"
        case .ecosia: template = "https://ac.ecosia.org/autocomplete?q=%s&type=list"
        case .startpage: template = "https://www.startpage.com/suggestions?q=%s&format=opensearch"
        case .brave: template = "https://search.brave.com/api/suggest?q=%s"
        case .kagi, .qwant, .custom: return nil
        }
        guard let encoded = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#")))
        else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }
}

/// The engine's suggestions for the last words asked: one question at a
/// time, a moment after typing stops, without cookies.
@MainActor
final class EngineSuggest {
    static let shared = EngineSuggest()
    private(set) var query = ""
    private(set) var words: [String] = []
    private var pending: Task<Void, Never>?
    private var asking = ""
    private let session = URLSession(configuration: .ephemeral)

    func ask(_ words: String, at url: URL, then: @escaping @MainActor () -> Void) {
        guard words != asking else { return }
        asking = words
        pending?.cancel()
        pending = Task { [session] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpShouldHandleCookies = false
            guard let (data, _) = try? await session.data(for: request), !Task.isCancelled,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count > 1,
                  let list = json[1] as? [String]
            else { return }
            self.query = words
            self.words = list
            self.asking = ""
            then()
        }
    }
}

/// How the bar is drawn (Settings › Tabs › Bar style).
enum BarLook: String, CaseIterable, Identifiable {
    /// Frosted, the page showing through, washed with the space's colour;
    /// light or dark as the space is.
    case glass
    /// Frosted and dark whatever the space, as Raycast's is.
    case darkGlass
    /// The space's own colour, a step lighter or darker.
    case tinted
    case white
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "Glass"
        case .darkGlass: return "Dark glass"
        case .tinted: return "Space colour"
        case .white: return "White"
        case .black: return "Black"
        }
    }

    /// Light or dark ink, for a space whose own is `space`.
    func scheme(space: ColorScheme) -> ColorScheme {
        switch self {
        case .glass, .tinted: return space
        case .darkGlass, .black: return .dark
        case .white: return .light
        }
    }

    /// The line the arrows are on wears the space's colour, with its own
    /// ink, where the bar is a neutral; on glass or the space's colour, a
    /// wash of the bar's own ink is what reads.
    var marksInColour: Bool { self == .white || self == .black }
}

/// The space's colour as this window shows it, fixed: drawn under a scheme
/// of the bar's own, a dynamic colour would answer for that scheme instead.
@MainActor
func spaceColour(_ space: Space, in window: ColorScheme) -> Color {
    let dynamic = Spaces.nsGround(space)
    var fixed = dynamic
    NSAppearance(named: window == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
        fixed = NSColor(cgColor: dynamic.cgColor) ?? dynamic
    }
    return Color(nsColor: fixed)
}

/// The bar over the window, about the middle, and a click anywhere else puts
/// it away.
struct ArcBar: View {
    @ObservedObject var browser: Browser
    /// The window's own light or dark, and the space's ink on its colour.
    let window: ColorScheme
    let space: ColorScheme

    var body: some View {
        let look = browser.prefs.barLook
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Nothing over the rest of the window: the page behind still
                // scrolls, and any click beside the bar — either button —
                // puts it away (see BarSpot) and goes on to what it was on.
                ArcBarPanel(browser: browser, look: look, colour: spaceColour(browser.space, in: window), space: space)
                    .environment(\.colorScheme, look.scheme(space: space))
                    .frame(width: min(660, max(320, geo.size.width - 96)))
                    // A full list sits about the window's middle; a short one
                    // a little above it.
                    .padding(.top, max(56, geo.size.height * 0.5 - 180))
            }
            // From the top: the stack is only as tall as the bar now, and
            // centred it would carry the bar down by half what is left.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
    }
}

private struct ArcBarPanel: View {
    @ObservedObject var browser: Browser
    let look: BarLook
    let colour: Color
    let space: ColorScheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.muted)
                if let site = browser.siteChip {
                    SiteChip(site: site)
                }
                if let name = browser.searchAlias?.name {
                    KeywordMark(name: name)
                }
                AddressField(
                    browser: browser,
                    point: 17,
                    prompt: browser.searchAlias == nil ? "Search or Enter URL…" : "Enter search terms"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)

            if browser.siteOffer != nil || !browser.offers.isEmpty {
                Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
                VStack(spacing: 2) {
                    if let site = browser.siteOffer {
                        SiteOfferRow(site: site)
                            .contentShape(Rectangle())
                            .onTapGesture { _ = browser.lockSiteOffer() }
                    }
                    ForEach(Array(browser.offers.enumerated()), id: \.element.id) { index, offer in
                        ArcBarRow(browser: browser, offer: offer, picked: browser.picked == index,
                                  look: look, colour: colour, space: space)
                            .contentShape(Rectangle())
                            .onTapGesture { browser.take(offer) }
                    }
                }
                .padding(8)
            }
        }
        .background { ground.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .background(BarSpot { browser.dismiss() })
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 34, y: 14)
        .animation(Motion.quick, value: browser.offers.map(\.id))
    }

    @ViewBuilder
    private var ground: some View {
        switch look {
        case .glass:
            ZStack {
                Rectangle().fill(.regularMaterial)
                colour.opacity(scheme == .dark ? 0.30 : 0.38)
            }
        case .darkGlass:
            ZStack {
                Rectangle().fill(.regularMaterial)
                Color.black.opacity(0.32)
            }
        case .tinted:
            ZStack {
                colour
                (scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.45))
            }
        case .white:
            Color.white
        case .black:
            Color(white: 0.11)
        }
    }
}

/// One line of the bar's list. A tab that is open says Switch to Tab; the
/// line the arrows are on wears the space's colour.
private struct ArcBarRow: View {
    @ObservedObject var browser: Browser
    let offer: Suggestion
    let picked: Bool
    let look: BarLook
    let colour: Color
    /// The ink the space's colour takes, for the line marked in it.
    let space: ColorScheme
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var tab: Tab? { offer.tab.flatMap { id in browser.tabs.first { $0.id == id } } }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 16, height: 16)
            Text(Address.withoutWWW(offer.key))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if !offer.title.isEmpty, tab == nil {
                Text(offer.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if tab != nil {
                Text("Switch to Tab")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        // Marked in the space's colour, the line takes that colour's ink, so
        // what is written on it stays readable whatever the colour.
        .environment(\.colorScheme, picked && look.marksInColour ? space : scheme)
        .background {
            if picked {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(look.marksInColour ? colour : Palette.ink.opacity(scheme == .dark ? 0.14 : 0.09))
            } else if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.ink.opacity(0.05))
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        if let tab {
            Mark(icon: tab.icon, letter: tab.monogram, size: 16)
        } else {
            switch offer.kind {
            case .search:
                if let site = Favicons.site(offer.url), let image = Favicons.shared.cached(site) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            case .command:
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
            default:
                if let site = Favicons.site(offer.url), let image = Favicons.shared.cached(site) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

/// Nothing open: the card the page would sit in, empty, in the space's own
/// colour a step lighter or darker.
struct EmptyCard: View {
    let colour: Color
    /// The ink the space's colour takes: a dark one is stepped darker.
    let space: ColorScheme

    var body: some View {
        ZStack {
            colour
            // A step darker than the frame round it, whatever the colour:
            // a light one only a little, or it reads as grey.
            Color.black.opacity(space == .dark ? 0.16 : 0.07)
            Grain()
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(CardEdge.edge), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(colour)
                .shadow(color: .black.opacity(CardEdge.shadow), radius: 6, y: 1)
        )
        .environment(\.colorScheme, space)
    }
}

/// Where the bar is, for a click anywhere else in its window to put it away.
/// The click goes on to what it was on; a scroll never comes here at all.
private struct BarSpot: NSViewRepresentable {
    let away: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.watch()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { context.coordinator.away = away }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    func makeCoordinator() -> Coordinator { Coordinator(away: away) }

    final class Coordinator {
        weak var view: NSView?
        var away: () -> Void
        private var monitor: Any?

        init(away: @escaping () -> Void) { self.away = away }

        func watch() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let view, let window = view.window, event.window === window else { return event }
                let spot = view.convert(event.locationInWindow, from: nil)
                if !view.bounds.contains(spot) {
                    let away = self.away
                    DispatchQueue.main.async { away() }
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}
