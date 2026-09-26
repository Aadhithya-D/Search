import SwiftUI
import WebKit

// Spaces: separate sets of tabs in the one window, each with its own
// cookies and sign-ins, and a downloads folder of its own if you like.
//
// Off unless turned on in Settings › Tabs. Until then there is one space,
// the first, and nothing about it shows: its tabs are the session there
// has always been and its sites use the store there has always been, so
// turning spaces on signs nobody out.
//
// A space's sites live in a WebKit store of their own, made by identifier,
// and so do its bookmarks. History, the passwords in the keychain, settings
// and extensions are shared by every space. Switching swaps the row of tabs:
// the ones left behind are parked, their sound paused, and they sleep
// after half an hour as any tab does. ⌃1–⌃9 switch, as in Arc.

struct Space: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Which of `Spaces.tints`. An older list's index still reads: the first
    /// of those colours is the rose a space wore when it had no choice yet.
    var colour: Int
    /// Its icon, one of `Spaces.icons`.
    var icon: String?
    /// Signed in wherever the first space is — the same cookies and
    /// sign-ins, only the tabs its own — rather than a store of its own.
    /// Chosen when it is made; nil, for a space from before the choice, is
    /// a store of its own.
    var sharesSignIns: Bool?
    /// Where this space's downloads go; nil for the folder in Settings.
    var downloads: String?
    /// Light, dark, or whichever the window is: the pastel can be worn on a
    /// dark window, and the deep colour on a light one. Nil is the window's.
    var tone: Tone?

    enum Tone: String, Codable, CaseIterable {
        case auto, light, dark
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    /// The first space: the session and the store there were before spaces.
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    var isFirst: Bool { id == Space.firstID }

    /// The icon it shows: its own, or a house for the first and a
    /// briefcase for any other that has none yet.
    var symbol: String { icon.flatMap { Spaces.icons.contains($0) ? $0 : nil } ?? (isFirst ? "house" : "briefcase") }

    /// An emoji chosen for its icon, in place of a symbol.
    var emoji: String? {
        guard let icon, !icon.isEmpty, !Spaces.icons.contains(icon) else { return nil }
        return icon
    }

    /// An icon was chosen, symbol or emoji. A space without one is a dot.
    var hasIcon: Bool { icon?.isEmpty == false }

    /// The colour's variant this space wears on a window that is `dark`.
    func wearsDark(on dark: Bool) -> Bool {
        switch tone ?? .auto {
        case .auto: return dark
        case .light: return false
        case .dark: return true
        }
    }
}

enum Spaces {
    /// A space's colour, light enough to be the column and the frame around
    /// the page, and a darker twin of the same hue for a dark window. The
    /// first is the rose Arc's own sidebar wears; the rest are the soft
    /// presets from its theme picker.
    struct Tint {
        var name: String
        var light: (CGFloat, CGFloat, CGFloat)
        var dark: (CGFloat, CGFloat, CGFloat)
    }

    // Light: the pastel Arc wears, the two strongest held back a little so
    // the frame round the page never outshouts the page. Dark: the same hue,
    // low and quiet — a tint on near-black, as Arc does it, not a colour.
    static let tints: [Tint] = [
        Tint(name: "Rose", light: (0.937, 0.656, 0.665), dark: (0.220, 0.150, 0.152)),
        Tint(name: "Pink", light: (1.00, 0.796, 0.824), dark: (0.228, 0.168, 0.180)),
        Tint(name: "Peach", light: (1.00, 0.878, 0.827), dark: (0.220, 0.170, 0.150)),
        Tint(name: "Butter", light: (1.00, 0.976, 0.898), dark: (0.220, 0.208, 0.167)),
        Tint(name: "Mint", light: (0.871, 0.992, 0.922), dark: (0.150, 0.220, 0.179)),
        Tint(name: "Sky", light: (0.863, 0.953, 0.988), dark: (0.150, 0.200, 0.220)),
        Tint(name: "Periwinkle", light: (0.773, 0.776, 0.898), dark: (0.150, 0.151, 0.220)),
        Tint(name: "Mauve", light: (0.945, 0.820, 0.925), dark: (0.220, 0.150, 0.209)),
        Tint(name: "Coral", light: (0.970, 0.729, 0.679), dark: (0.232, 0.160, 0.144)),
        Tint(name: "Sea", light: (0.627, 0.824, 0.745), dark: (0.150, 0.220, 0.192)),
        Tint(name: "Sand", light: (0.925, 0.886, 0.824), dark: (0.220, 0.200, 0.167)),
        Tint(name: "Lilac", light: (0.820, 0.733, 0.910), dark: (0.184, 0.150, 0.220)),
    ]

    static func clamp(_ index: Int) -> Int {
        let count = tints.count
        guard count > 0 else { return 0 }
        return ((index % count) + count) % count
    }

    /// The column, and the thin frame the page sits in.
    static func ground(_ space: Space) -> Color {
        Color(nsColor: nsGround(space))
    }

    static func nsGround(_ space: Space) -> NSColor {
        let tint = tints[clamp(space.colour)]
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = space.wearsDark(on: dark) ? tint.dark : tint.light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    /// The colour's own ink: its hue, strong enough to draw a folder in on
    /// the column — deeper on the pastel, brighter on the deep colour.
    static func accent(_ index: Int, dark: Bool) -> Color {
        let c = tints[clamp(index)].light
        let rgb = NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return dark
            ? Color(hue: hue, saturation: 0.42, brightness: 0.95)
            : Color(hue: hue, saturation: 0.62, brightness: 0.62)
    }

    /// The swatch of one tone of a colour, for the picker.
    static func swatch(_ index: Int, dark: Bool) -> Color {
        let c = dark ? tints[clamp(index)].dark : tints[clamp(index)].light
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// A space's icon as an image, for the menus: its symbol, or its emoji
    /// drawn into one.
    @MainActor static func image(for space: Space) -> NSImage? {
        guard let emoji = space.emoji else {
            return NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil)
        }
        let text = emoji as NSString
        let font = NSFont.systemFont(ofSize: 13)
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let drawn = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2), withAttributes: attrs)
            return true
        }
    }

    /// The swatch, always the light colour, so a dot reads the same on a
    /// dark window as on a light one.
    static func swatch(_ index: Int) -> Color {
        let c = tints[clamp(index)].light
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// The icons a space can wear: Apple's own symbols, drawn in one weight
    /// and one grey, grouped as work, thinking, leisure and life.
    static let icons = [
        "briefcase", "building.2", "desktopcomputer", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "terminal",
        "sparkles", "brain.head.profile", "lightbulb", "gamecontroller", "beach.umbrella", "cup.and.saucer",
        "music.note", "film", "paintpalette", "camera", "house", "book",
        "graduationcap", "cart", "airplane", "dumbbell", "leaf", "heart",
        "face.smiling", "person",
    ]
    static let iconNames = [
        "Work", "Office", "Desktop", "Laptop", "Code", "Terminal",
        "AI", "Thinking", "Ideas", "Games", "Leisure", "Café",
        "Music", "Film", "Art", "Photos", "Home", "Reading",
        "Studies", "Shopping", "Travel", "Sport", "Nature", "Love",
        "Personal", "Me",
    ]

    private static var file: URL { Store.file("spaces.json") }

    /// Every space, the first one first — made on the spot if there is no
    /// list yet.
    static func read() -> [Space] {
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Space].self, from: $0) } ?? []
        let first = saved.first(where: \.isFirst) ?? Space(id: Space.firstID, name: "Personal", colour: 0)
        return [first] + saved.filter { !$0.isFirst }
    }

    static func write(_ spaces: [Space]) {
        guard let data = try? JSONEncoder().encode(spaces) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The space new tabs are made in: the one on screen.
    @MainActor static var current = Space.firstID

    /// Each space's store, made once: WebKit shares processes between views
    /// that ask for the same store object.
    @MainActor private static var stores: [UUID: WKWebsiteDataStore] = [:]
    /// The spaces signed in wherever the first one is (see Space.sharesSignIns).
    @MainActor static var sharing: Set<UUID> = []

    @MainActor static func store(for id: UUID) -> WKWebsiteDataStore {
        if id == Space.firstID || sharing.contains(id) { return Store.websites }
        if let made = stores[id] { return made }
        let made = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = made
        return made
    }

    /// A space's store and everything in it, gone. What it holds — cookies,
    /// sign-ins, storage, caches — is emptied at once. The store itself
    /// WebKit won't remove while this run still holds on to it, however
    /// closed its tabs, so it is written down and removed at the next
    /// launch if the tries in between don't manage.
    @MainActor static func erase(_ id: UUID) {
        guard id != Space.firstID else { return }
        // And once more a moment later, for what its closing tabs were
        // still writing — the cache of the page on screen, for one.
        let store = store(for: id)
        let everything = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        }
        stores[id] = nil
        let pending = Set(Store.settings.stringArray(forKey: "spaces.erasing") ?? []).union([id.uuidString])
        Store.settings.set(pending.sorted(), forKey: "spaces.erasing")
        sweep()
        for delay in [3.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sweep() }
        }
    }

    /// Every store of a deleted space that is still there, tried again.
    @MainActor static func sweep() {
        for text in Store.settings.stringArray(forKey: "spaces.erasing") ?? [] {
            guard let id = UUID(uuidString: text) else { continue }
            Task { @MainActor in
                do { try await WKWebsiteDataStore.remove(forIdentifier: id) } catch {
                    // Gone already is as good as removed; anything else is
                    // tried again later.
                    let left = await WKWebsiteDataStore.allDataStoreIdentifiers
                    guard !left.contains(id) else { return }
                }
                let now = (Store.settings.stringArray(forKey: "spaces.erasing") ?? []).filter { $0 != text }
                Store.settings.set(now, forKey: "spaces.erasing")
            }
        }
    }
}

/// A space's row of tabs while another space is on screen.
struct Parked {
    var tabs: [Tab]
    var active: Tab.ID?
}

extension Browser {
    var space: Space { spaces.first { $0.id == spaceID } ?? spaces[0] }

    /// Every tab of the spaces not on screen, for the sleep timer.
    var parkedTabs: [Tab] { parked.values.flatMap(\.tabs) }

    /// Where a download lands: the space's folder, or the one in Settings.
    var downloadsFolder: URL {
        guard prefs.usesSpaces, let path = space.downloads else { return prefs.downloads }
        return URL(fileURLWithPath: path)
    }

    /// ⌃1–⌃9, and the menu on the space's dot.
    func switchSpace(to id: UUID) {
        guard prefs.usesSpaces else { return }
        enter(id)
    }

    private func enter(_ id: UUID) {
        guard id != spaceID, let to = spaces.firstIndex(where: { $0.id == id }) else { return }
        // Which way the icon at the foot turns over: the way the spaces lie.
        if !makingSpace { spaceStep = to > (spaces.firstIndex { $0.id == spaceID } ?? 0) ? 1 : -1 }
        cancelTabEdit()
        if floater.showing { land() }
        writeSession(now: true)

        // The row on screen is parked as it is, sound and all: music or a
        // stream keeps playing in the space you left, as it does in a tab
        // you left. ⌘⇧M, or its speaker, stops it.
        parked[spaceID] = Parked(tabs: tabs, active: activeID)

        spaceID = id
        Spaces.current = id
        bookmarks.use(id)
        Store.settings.set(id.uuidString, forKey: "space.current")
        if let back = parked.removeValue(forKey: id), !back.tabs.isEmpty {
            showRow(back.tabs, active: back.active)
            if let active, !active.wake() { active.revive() }
        } else {
            showRow([], active: nil)
            restoreSession()
        }
        editing = active?.isBlank ?? true
        typed = ""
        askFocus()
        announce(space.name)
    }

    /// Every other space's row, made ahead of time, so the column can show
    /// the next space beside this one while two fingers bring it in.
    func preloadSpaces() {
        for space in spaces where space.id != spaceID && parked[space.id] == nil {
            parked[space.id] = loadRow(space.id)
        }
    }

    func switchSpace(index: Int) {
        guard spaces.indices.contains(index) else { return }
        switchSpace(to: spaces[index].id)
    }

    /// The icon a new space gets unless told: the first no space wears yet.
    var freeIcon: String {
        let used = Set(spaces.map(\.symbol))
        return Spaces.icons.first { !used.contains($0) } ?? "briefcase"
    }

    /// A new space, empty, and on screen — signed in where the others are,
    /// or starting afresh with its own cookies and sign-ins.
    func addSpace(named name: String, icon: String? = nil, sharesSignIns: Bool = true) {
        makingSpace = false
        let made = Space(id: UUID(), name: name, colour: 0, icon: icon ?? freeIcon, sharesSignIns: sharesSignIns)
        spaces.append(made)
        Spaces.write(spaces)
        switchSpace(to: made.id)
    }

    /// Dragged to another place among the dots. ⌃1–⌃9 follow the order.
    func moveSpace(_ id: UUID, to index: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == id }), spaces.indices.contains(index), from != index else { return }
        spaces.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        Spaces.write(spaces)
    }

    /// "New Space…": the card for a new space, in the column or the bar.
    func askForSpace() {
        // In place, where the next space would come in, in the column or the
        // bar alike; a question only while the tabs are folded out of sight.
        if !folded || peeking {
            let here = spaces.firstIndex { $0.id == spaceID } ?? 0
            SpaceSwipe.shared.start(for: self)
            SpaceSwipe.shared.slide(self, to: spaces.count, from: here)
        } else {
            Ask.newSpace { name, shared in self.addSpace(named: name, sharesSignIns: shared) }
        }
    }

    func renameSpace(_ id: UUID, to name: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        spaces[at].name = name
        Spaces.write(spaces)
    }

    func setSpaceIcon(_ id: UUID, to icon: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].icon = icon
        Spaces.write(spaces)
    }

    /// An emoji for the icon; empty takes the icon away, back to a dot.
    func setSpaceEmoji(_ id: UUID, to text: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
        spaces[at].icon = first
        Spaces.write(spaces)
    }

    func setSpaceTone(_ id: UUID, to tone: Space.Tone) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].tone = tone == .auto ? nil : tone
        Spaces.write(spaces)
    }

    func setSpaceColour(_ id: UUID, to index: Int) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].colour = Spaces.clamp(index)
        Spaces.write(spaces)
    }

    func setSpaceDownloads(_ id: UUID, to folder: URL?) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].downloads = folder?.path
        Spaces.write(spaces)
    }

    /// A space, its tabs, and its cookies and sign-ins, gone. The first one
    /// stays: it is where everything was before there were spaces.
    func deleteSpace(_ id: UUID) {
        guard id != Space.firstID, let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        if spaceID == id { switchSpace(to: Space.firstID) }
        for tab in parked.removeValue(forKey: id)?.tabs ?? [] { tab.close() }
        let shared = spaces[at].sharesSignIns == true
        spaces.remove(at: at)
        Spaces.write(spaces)
        Session.erase(space: id)
        bookmarks.forget(id)
        // A space signed in with the others has nothing of its own to erase:
        // its cookies are theirs.
        if !shared { Spaces.erase(id) }
    }

    /// Spaces turned off: back to the first one. The others are kept, in
    /// case they are turned on again.
    func leaveSpaces() {
        enter(Space.firstID)
        for (_, row) in parked { for tab in row.tabs { tab.close() } }
        parked = [:]
    }
}

// MARK: - the dot

/// A space's icon: one of the symbols, or an emoji, drawn at one size.
struct SpaceGlyph: View {
    let space: Space
    var size: CGFloat = 12

    var body: some View {
        SpaceGlyph.drawn(space.emoji ?? space.symbol, size: size)
    }

    /// A symbol's name, or an emoji — anything not a symbol is text.
    @ViewBuilder
    static func drawn(_ icon: String, size: CGFloat) -> some View {
        if Spaces.icons.contains(icon) || icon == "plus" {
            Image(systemName: icon).font(.system(size: size, weight: .medium))
        } else {
            Text(icon).font(.system(size: size + 1))
        }
    }

    /// The emoji, asked for with the Mac's own picker open beside it.
    @MainActor static func askEmoji(for space: Space, browser: Browser) {
        Ask.name("Emoji for “\(space.name)”", placeholder: "🙂", initial: space.emoji ?? "", confirm: "Use") {
            browser.setSpaceEmoji(space.id, to: $0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

/// The space on screen, as its icon: at the column's foot, or before the
/// tabs in the row. One icon however many spaces there are; a click opens
/// the menu. When the space changes the icon turns over the way the spaces
/// went — out on one side, the next one in from the other.
struct SpaceDot: View {
    @ObservedObject var browser: Browser
    @State private var hovering = false
    /// What is drawn, a step behind the browser: the space changes in a
    /// frame with nothing animated (see SpaceSwipe.slide), and the icon
    /// turns over just after, on a change of its own.
    @State private var shown: (key: String, symbol: String)?

    static let width: CGFloat = 26

    private var symbol: String { browser.makingSpace ? "plus" : (browser.space.emoji ?? browser.space.symbol) }
    private var key: String { browser.makingSpace ? "new" : "\(browser.spaceID.uuidString)-\(symbol)" }

    var body: some View {
        Button { SpaceMenu.show(for: browser) } label: {
            ZStack {
                SpaceGlyph.drawn(shown?.symbol ?? symbol, size: 12)
                    .foregroundStyle(hovering ? Palette.ink : Palette.quiet)
                    .id(shown?.key ?? key)
                    // The way the tabs go: sideways in the column; in the bar
                    // across the top, up for the next space, down going back.
                    .transition(.push(from: browser.prefs.sidebar
                        ? (browser.spaceStep > 0 ? .trailing : .leading)
                        : (browser.spaceStep > 0 ? .bottom : .top)))
            }
            .frame(width: SpaceDot.width, height: 26)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Palette.veil : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(browser.space.name) — ⌃1–⌃9, or two fingers \(browser.prefs.sidebar ? "sideways" : "up or down") over the tabs, to switch")
        .onChange(of: key) { _, now in
            let symbol = symbol
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.22)) { shown = (now, symbol) }
            }
        }
        .animation(Motion.quick, value: hovering)
    }
}

/// The dot's menu: the spaces, then what can be done to the one on screen.
@MainActor
enum SpaceMenu {
    /// Menu items call back into Swift through this.
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static var actions: [Action] = []

    private static func item(_ title: String, key: String = "", checked: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = Action(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: key)
        item.target = action
        item.keyEquivalentModifierMask = key.isEmpty ? [] : .control
        item.state = checked ? .on : .off
        return item
    }

    static func show(for browser: Browser) {
        actions = []
        let menu = NSMenu()
        for (index, space) in browser.spaces.enumerated() {
            let entry = item(space.name, key: index < 9 ? "\(index + 1)" : "", checked: space.id == browser.spaceID) {
                browser.switchSpace(to: space.id)
            }
            entry.image = Spaces.image(for: space)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("New Space…") { browser.askForSpace() })
        menu.addItem(.separator())
        let here = browser.space
        menu.addItem(item("Rename “\(here.name)”…") {
            Ask.name("Rename Space", placeholder: here.name, initial: here.name, confirm: "Rename") { browser.renameSpace(here.id, to: $0) }
        })
        let icons = NSMenu()
        for (symbol, name) in zip(Spaces.icons, Spaces.iconNames) {
            let choice = item(name, checked: here.symbol == symbol) { browser.setSpaceIcon(here.id, to: symbol) }
            choice.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            icons.addItem(choice)
        }
        icons.addItem(.separator())
        icons.addItem(item("Emoji…") { SpaceGlyph.askEmoji(for: here, browser: browser) })
        if here.hasIcon {
            icons.addItem(item("No Icon") { browser.setSpaceEmoji(here.id, to: "") })
        }
        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        icon.submenu = icons
        menu.addItem(icon)
        // The order is the swipe's, and ⌃1–⌃9's.
        if let at = browser.spaces.firstIndex(where: { $0.id == here.id }) {
            if at > 0 { menu.addItem(item("Move Left") { browser.moveSpace(here.id, to: at - 1) }) }
            if at < browser.spaces.count - 1 { menu.addItem(item("Move Right") { browser.moveSpace(here.id, to: at + 1) }) }
        }
        let folder = here.downloads.map { URL(fileURLWithPath: $0).lastPathComponent }
        menu.addItem(item(folder.map { "Downloads to “\($0)”…" } ?? "Downloads Folder…") {
            Ask.folder { browser.setSpaceDownloads(here.id, to: $0) }
        })
        if folder != nil {
            menu.addItem(item("Downloads to the Folder in Settings") { browser.setSpaceDownloads(here.id, to: nil) })
        }
        if !here.isFirst {
            menu.addItem(.separator())
            menu.addItem(item("Delete “\(here.name)”…") {
                Ask.sure("Delete “\(here.name)”?", detail: "Its tabs close, and its bookmarks, cookies and sign-ins are erased from this Mac. History stays.", confirm: "Delete") {
                    browser.deleteSpace(here.id)
                }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// The few questions a space's menu asks, as sheets on the window.
@MainActor
enum Ask {
    static func name(_ title: String, placeholder: String, initial: String = "", confirm: String, then: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, !name.isEmpty { then(name) }
        }
    }

    /// A new space's name, and whether it keeps the sign-ins the others
    /// have — for when the column isn't there to hold the card.
    static func newSpace(then: @escaping (String, Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "New Space"
        alert.informativeText = "Its own tabs. Signed in where your other spaces are, unless it starts afresh."
        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        field.placeholderString = "Work"
        let fresh = NSButton(checkboxWithTitle: "Start signed out, with its own cookies", target: nil, action: nil)
        fresh.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(field)
        box.addSubview(fresh)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, !name.isEmpty { then(name, fresh.state != .on) }
        }
    }

    static func sure(_ title: String, detail: String, confirm: String, then: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: confirm).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        show(alert) { ok in if ok { then() } }
    }

    static func folder(then: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use for This Space"
        panel.message = "Downloads in this space go here. Cancel keeps the folder it has."
        guard let window = Links.window else { return }
        panel.beginSheetModal(for: window) { answer in
            if answer == .OK, let url = panel.url { then(url) }
        }
    }

    private static func show(_ alert: NSAlert, _ done: @escaping (Bool) -> Void) {
        guard let window = Links.window else {
            done(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }
}
