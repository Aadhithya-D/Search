import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

// Fork: the library, as Zen has it. A rail of its own takes the column's
// place, wider than the column, and the page moves over for it: what was
// downloaded as pictures (Media) and as files (Downloads), every space side
// by side with its tabs (Spaces), and everywhere you have been (History).
// The door at the foot's left opens it; ← or Escape puts it away. While the
// tabs are down the side, ⌘Y and ⇧⌘J open it too, in place of their panels.

enum LibraryShelf: String, CaseIterable, Identifiable {
    case media, downloads, spaces, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media"
        case .downloads: return "Downloads"
        case .spaces: return "Spaces"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .media: return "photo.on.rectangle.angled"
        case .downloads: return "arrow.down.circle"
        case .spaces: return "square.on.square"
        case .history: return "clock"
        }
    }

    /// The shelf the library last showed, to open on again.
    static var last: LibraryShelf {
        get { Store.settings.string(forKey: "library.shelf").flatMap(LibraryShelf.init) ?? .downloads }
        set { Store.settings.set(newValue.rawValue, forKey: "library.shelf") }
    }
}

/// How wide the library is: the rail and a list, or, for the spaces, as many
/// cards as there are, short of crowding the page out.
enum LibraryRoom {
    static let rail: CGFloat = 76
    static let list: CGFloat = 300
    static let card: CGFloat = 212
    static let gap: CGFloat = 10
    /// The page keeps at least this much beside the spaces.
    private static let page: CGFloat = 420

    @MainActor
    static func width(_ browser: Browser) -> CGFloat {
        let narrow = rail + list
        guard browser.library == .spaces else { return narrow }
        let wanted = rail + 2 * gap + CGFloat(browser.spaces.count) * (card + gap) + 44
        let window = browser.window?.frame.width ?? 1200
        return max(narrow, min(wanted, window - page))
    }
}

extension Browser {
    /// Whether this window has the library: the tabs down the side, and not
    /// a private window, which keeps nothing.
    var hasLibrary: Bool { prefs.library && prefs.sidebar && !isPrivate }

    /// What the column takes from the page: the library's width while it is
    /// open, the column's own otherwise.
    var columnRoom: CGFloat {
        library != nil ? LibraryRoom.width(self) : prefs.sideWidth
    }

    func openLibrary(_ shelf: LibraryShelf? = nil) {
        guard hasLibrary else { return }
        var to = shelf ?? LibraryShelf.last
        if to == .spaces && !prefs.usesSpaces { to = .downloads }
        LibraryShelf.last = to
        if folded {
            peeking = false
            withAnimation(Motion.glide) { folded = false }
        }
        withAnimation(Motion.glide) { library = to }
    }

    func closeLibrary() {
        withAnimation(Motion.glide) { library = nil }
    }

    /// ⌘Y and ⇧⌘J: the library's shelf, or the library put away when that
    /// shelf is the one open.
    func toggleLibrary(_ shelf: LibraryShelf) {
        if library == shelf { closeLibrary() } else { openLibrary(shelf) }
    }

    /// History or Downloads asked for while the library stands in for their
    /// panels. The panel isn't drawn; LibraryCatches opens the shelf.
    func libraryCatches(_ shelf: LibraryShelf) -> Bool {
        guard hasLibrary else { return false }
        switch shelf {
        case .history: return recallMode == .history
        case .downloads: return hoarding
        default: return false
        }
    }

    /// A space's tabs as the library lists them: its pins, then the rest,
    /// without the bookmarks' pages, which are the bookmarks' own.
    func libraryTabs(of space: UUID) -> [Tab] {
        let row = space == spaceID ? tabs : (parked[space]?.tabs ?? [])
        return row.filter { $0.bookmark == nil && !$0.bench }
    }

    /// A tab in any space, brought to the front: its space first.
    func libraryGo(to tab: Tab, in space: UUID) {
        if space != spaceID { switchSpace(to: space) }
        if let here = tabs.first(where: { $0.id == tab.id }) { select(here) }
    }

    /// A tab dropped on another space's card. From the space on screen it
    /// goes as Move to Space takes it; from a space off screen, its row there
    /// gives it up and the other takes it, rehomed in that space's sign-ins.
    func libraryCarry(_ id: Tab.ID, to space: UUID) {
        guard prefs.usesSpaces, let destination = spaces.first(where: { $0.id == space }) else { return }
        if let tab = tabs.first(where: { $0.id == id }) {
            guard space != spaceID, tab.pin == nil else { return }
            move(tab, toSpace: space) { [weak self] in self?.objectWillChange.send() }
            return
        }
        guard let from = parked.first(where: { $0.value.tabs.contains { $0.id == id } })?.key, from != space,
              var row = parked[from], let at = row.tabs.firstIndex(where: { $0.id == id })
        else { return }
        let tab = row.tabs[at]
        guard tab.pin == nil, tab.bookmark == nil, !tab.bench else { return }
        row.tabs.remove(at: at)
        row.splits.removeAll { $0.contains(id) }
        if row.active == id { row.active = row.tabs.last(where: { $0.pin == nil })?.id ?? row.tabs.first?.id }
        parked[from] = row
        writeSession(now: true, space: from, row: row)
        // Its group stays behind, as Move to Space leaves it.
        tab.groupID = nil
        if space == spaceID {
            receive(tab)
        } else {
            tab.rehome(in: space)
            var into = parked[space] ?? loadRow(space)
            into.tabs.append(tab)
            if into.active == nil { into.active = tab.id }
            parked[space] = into
            writeSession(now: true, space: space, row: into)
        }
        announce("Moved to \(destination.name)")
        objectWillChange.send()
    }
}

/// History and Downloads, asked for from the menu, the keys or the strip's
/// button, open the library's shelf while the library stands in for them.
struct LibraryCatches: ViewModifier {
    @ObservedObject var browser: Browser

    func body(content: Content) -> some View {
        content
            .onChange(of: browser.hoarding) { _, now in
                guard now, browser.libraryCatches(.downloads) else { return }
                browser.hoarding = false
                browser.toggleLibrary(.downloads)
            }
            .onChange(of: browser.recallMode) { _, now in
                guard now == .history, browser.libraryCatches(.history) else { return }
                browser.recallMode = nil
                browser.toggleLibrary(.history)
            }
    }
}

// MARK: - the library

/// The rail down the window's edge, and the shelf beside it.
struct LibraryPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @Environment(\.colorScheme) private var windowScheme

    @State private var hunt = ""

    private var onRight: Bool { browser.prefs.sidePosition == .right }
    private var shelf: LibraryShelf { browser.library ?? .downloads }

    private var shelves: [LibraryShelf] {
        LibraryShelf.allCases.filter { $0 != .spaces || browser.prefs.usesSpaces }
    }

    var body: some View {
        HStack(spacing: 0) {
            if !onRight { rail }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if onRight { rail }
        }
        .frame(width: LibraryRoom.width(browser))
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Spaces.ground(browser.space)
                Grain()
            }
        }
        .overlay(alignment: onRight ? .leading : .trailing) {
            Rectangle().fill(Palette.ink.opacity(0.06)).frame(width: 1)
        }
        .environment(\.colorScheme, browser.space.wearsDark(on: windowScheme == .dark) ? .dark : .light)
        .onChange(of: browser.library) { _, _ in hunt = "" }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            // The lights' corner, which also moves the window.
            DragStrip()
                .frame(height: SideBar.topRow + 8)
            // Spread down the whole rail as Zen spreads them: the same gap
            // over the first, between each, and under the last, growing
            // with the window.
            ForEach(shelves) { item in
                Spacer(minLength: 6)
                RailItem(shelf: item, on: item == shelf) {
                    LibraryShelf.last = item
                    withAnimation(Motion.glide) { browser.library = item }
                }
            }
            Spacer(minLength: 6)
            Door(icon: onRight ? "arrow.right" : "arrow.left", help: "Close Library (Esc)") {
                browser.closeLibrary()
            }
            .padding(.bottom, 12)
        }
        .frame(width: LibraryRoom.rail)
    }

    @ViewBuilder
    private var content: some View {
        switch shelf {
        case .media:
            LibraryMedia(browser: browser, loot: loot, hunt: $hunt)
        case .downloads:
            LibraryDownloads(browser: browser, loot: loot, hunt: $hunt)
        case .spaces:
            LibrarySpaces(browser: browser, window: windowScheme)
        case .history:
            LibraryHistory(browser: browser, hunt: $hunt)
        }
    }

    private struct RailItem: View {
        let shelf: LibraryShelf
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                VStack(spacing: 5) {
                    Image(systemName: shelf.icon)
                        .font(.system(size: 17, weight: .medium))
                        .frame(height: 20)
                    Text(shelf.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.quiet))
                .frame(width: 64, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(on ? Palette.veilStrong : (hovering ? Palette.veil : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: on)
        }
    }
}

// MARK: - pieces the shelves share

/// The field at the top of a shelf, and the filter beside it.
private struct ShelfHead<Filter: View>: View {
    @Binding var hunt: String
    let prompt: String
    @ViewBuilder let filter: () -> Filter
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.quiet)
                ZStack(alignment: .leading) {
                    if hunt.isEmpty {
                        Text(prompt).foregroundStyle(Palette.quiet)
                    }
                    TextField("", text: $hunt)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: 12.5))
                if !hunt.isEmpty {
                    Button { hunt = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.quiet)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(SideTone.chip(scheme, strong: false), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            filter()
        }
        .padding(.horizontal, 10)
        .frame(height: SideBar.topRow)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// The filter's button: its name while one is chosen, Filter otherwise.
private struct FilterMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: () -> Items
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.ink.opacity(0.8))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(SideTone.chip(scheme, strong: false), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        // A plain button keeps the label as drawn: the borderless menu style
        // takes its ground away.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// What a shelf says when it has nothing to show.
private struct ShelfEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 40)
    }
}

/// A day's name over its lines.
private struct ShelfCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.quiet)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What kind of file a download is, for the filters and for Media.
enum LootKind: String, CaseIterable, Identifiable {
    case all, images, video, audio, documents, archives, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .images: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives and Installers"
        case .other: return "Other"
        }
    }

    static func of(_ path: String) -> LootKind {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage)
            || type.conforms(to: .applicationBundle) || ["pkg", "mpkg", "dmg", "zip"].contains(ext.lowercased()) {
            return .archives
        }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) {
            return .documents
        }
        return .other
    }

    var isMedia: Bool { self == .images || self == .video }
}

/// The files' pictures, made by Quick Look once and kept while Search runs.
@MainActor
final class LootThumbs {
    static let shared = LootThumbs()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ path: String, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(path, side))
    }

    func make(_ path: String, side: CGFloat, iconsToo: Bool) async -> NSImage? {
        if let hit = cached(path, side: side) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: iconsToo ? .all : .thumbnail
        )
        guard let made = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = made.nsImage
        cache.setObject(image, forKey: key(path, side))
        return image
    }

    private func key(_ path: String, _ side: CGFloat) -> NSString { "\(Int(side)) \(path)" as NSString }
}

/// A download's picture: its thumbnail, or the Finder's icon for it.
private struct LootThumb: View {
    let keep: Keep
    let side: CGFloat
    var iconsToo = true
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if iconsToo {
                Image(nsImage: NSWorkspace.shared.icon(forFile: keep.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: keep.path) {
            image = LootThumbs.shared.cached(keep.path, side: side)
            guard image == nil, keep.stillThere else { return }
            image = await LootThumbs.shared.make(keep.path, side: side, iconsToo: iconsToo)
        }
    }
}

/// A download's picture as a row shows it: one rounded square for every
/// kind. A picture or a video fills it; a page is shown whole on it; a file
/// with nothing to show wears the Finder's icon for its kind.
private struct LootTile: View {
    let keep: Keep
    var side: CGFloat = 32
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var scheme

    private var fills: Bool { LootKind.of(keep.path).isMedia }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SideTone.chip(scheme, strong: false))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .padding(fills ? 0 : 3)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: keep.stillThere ? keep.path : keep.name))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .task(id: keep.path) {
            image = LootThumbs.shared.cached(keep.path, side: side * 2)
            guard image == nil, keep.stillThere else { return }
            // Pictures alone: Quick Look's icons are white squares of
            // their own, a size apart from the Finder's.
            image = await LootThumbs.shared.make(keep.path, side: side * 2, iconsToo: false)
        }
    }
}

extension Keep {
    /// The file's size as the Finder writes it, while the file is there.
    var size: String? {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// When, as briefly as a line has room for: the time today, the day before.
    var when: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return When.clock(date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return (calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? Keep.dayMonth : Keep.dayMonthYear)
            .string(from: date)
    }

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let dayMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter
    }()

    /// The heading a download is listed under: Today, Yesterday, Earlier
    /// This Week, then its month.
    var period: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())), date >= week {
            return "Earlier This Week"
        }
        return (calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? Keep.month : Keep.monthYear)
            .string(from: date)
    }

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    func matches(_ hunt: String) -> Bool {
        let needle = hunt.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || name.localizedCaseInsensitiveContains(needle) || from.localizedCaseInsensitiveContains(needle)
    }
}

/// What a download's right-click offers, on both shelves.
private struct LootMenu: View {
    let keep: Keep
    let loot: Loot

    var body: some View {
        Button("Open") { loot.open(keep) }.disabled(!keep.stillThere)
        Button("Show in Finder") { loot.reveal(keep) }.disabled(!keep.stillThere)
        if LootKind.of(keep.path) == .images {
            Button("Copy Image") {
                guard let image = NSImage(contentsOf: keep.url) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            .disabled(!keep.stillThere)
        }
        Button("Copy File") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([keep.url as NSURL])
        }
        .disabled(!keep.stillThere)
        Divider()
        Button("Remove from Library") { withAnimation(Motion.settle) { loot.forget(keep) } }
    }
}

// MARK: - Media

/// The pictures and videos downloaded, two to a row. Dragged out, a file
/// goes as the file: into a page, a folder, another app.
private struct LibraryMedia: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @Binding var hunt: String
    @State private var kind: LootKind = .all

    private var shown: [Keep] {
        loot.kept.filter { keep in
            let of = LootKind.of(keep.path)
            return of.isMedia && (kind == .all || of == kind) && keep.matches(hunt)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ShelfHead(hunt: $hunt, prompt: "Search Media") {
                FilterMenu(title: kind == .all ? "Filter" : kind.title) {
                    Picker("Show", selection: $kind) {
                        ForEach([LootKind.all, .images, .video]) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            let items = shown
            if items.isEmpty {
                ShelfEmpty(text: hunt.isEmpty ? "Pictures and videos you download show up here." : "Nothing matches.")
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(items) { keep in
                            Tile(keep: keep, loot: loot)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private struct Tile: View {
        let keep: Keep
        let loot: Loot
        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SideTone.chip(scheme, strong: hovering))
                LootThumb(keep: keep, side: 240, iconsToo: false)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .padding(12)
                if LootKind.of(keep.path) == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 2)
                }
            }
            .frame(height: 120)
            .opacity(keep.stillThere ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { if keep.stillThere { loot.open(keep) } }
            .onHover { hovering = $0 }
            .onDrag { NSItemProvider(contentsOf: keep.url) ?? NSItemProvider() }
            .contextMenu { LootMenu(keep: keep, loot: loot) }
            .help(keep.name)
            .animation(Motion.quick, value: hovering)
        }
    }
}

// MARK: - Downloads

/// Everything downloaded, newest first, what is still coming above it.
private struct LibraryDownloads: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @Binding var hunt: String
    @State private var kind: LootKind = .all

    private var shown: [Keep] {
        loot.kept.filter { keep in (kind == .all || LootKind.of(keep.path) == kind) && keep.matches(hunt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ShelfHead(hunt: $hunt, prompt: "Search Downloads") {
                FilterMenu(title: kind == .all ? "Filter" : kind.title) {
                    Picker("Show", selection: $kind) {
                        ForEach(LootKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Open Downloads Folder") { NSWorkspace.shared.open(browser.downloadsFolder) }
                    Button("Clear List") { withAnimation(Motion.settle) { loot.forgetAll() } }
                        .disabled(loot.kept.isEmpty)
                }
            }
            let items = shown
            if items.isEmpty && loot.hauls.isEmpty {
                ShelfEmpty(text: hunt.isEmpty && kind == .all ? "Nothing downloaded yet." : "Nothing matches.")
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        if !loot.hauls.isEmpty {
                            ShelfCaption(text: "Downloading")
                            ForEach(loot.hauls) { haul in
                                Coming(haul: haul)
                            }
                        }
                        // Newest first already: each heading where its run starts.
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, keep in
                            if index == 0 || items[index - 1].period != keep.period {
                                ShelfCaption(text: keep.period)
                            }
                            Row(keep: keep, loot: loot)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private struct Coming: View {
        @ObservedObject var haul: Haul
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(width: 32, height: 32)
                    .background(Palette.veil, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(haul.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: haul.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(Palette.ink.opacity(0.7))
                }
                Button { haul.cancel() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.quiet)
                }
                .buttonStyle(.plain)
                .help("Stop")
            }
            .padding(.horizontal, 6)
            .frame(height: 46)
        }
    }

    private struct Row: View {
        let keep: Keep
        let loot: Loot
        @State private var hovering = false
        @State private var size: String?
        @Environment(\.colorScheme) private var scheme

        private var detail: String {
            let there = keep.stillThere
            return [there ? size : "Deleted", keep.from.isEmpty ? nil : keep.from, keep.when]
                .compactMap { $0 }
                .joined(separator: " — ")
        }

        var body: some View {
            HStack(spacing: 10) {
                LootTile(keep: keep)
                    .opacity(keep.stillThere ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keep.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(keep.stillThere ? Palette.ink : Palette.quiet)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if hovering, keep.stillThere {
                    Button { loot.reveal(keep) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.quiet)
                    .help("Show in Finder")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? SideTone.chip(scheme, strong: false) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { if keep.stillThere { loot.open(keep) } }
            .onHover { hovering = $0 }
            .onDrag { keep.stillThere ? (NSItemProvider(contentsOf: keep.url) ?? NSItemProvider()) : NSItemProvider() }
            .contextMenu { LootMenu(keep: keep, loot: loot) }
            .task(id: keep.path) { size = keep.size }
            .animation(Motion.quick, value: hovering)
        }
    }
}

// MARK: - History

/// Everywhere you have been, by day. A click opens the page in a new tab
/// beside the library; ⌘-click leaves it behind.
private struct LibraryHistory: View {
    @ObservedObject var browser: Browser
    @Binding var hunt: String
    @State private var since: Since = .always
    @State private var lines: [Line] = []

    enum Since: String, CaseIterable, Identifiable {
        case always, today, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .always: return "All Time"
            case .today: return "Today"
            case .week: return "Last 7 Days"
            case .month: return "Last 30 Days"
            }
        }
        var start: Date? {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            switch self {
            case .always: return nil
            case .today: return today
            case .week: return calendar.date(byAdding: .day, value: -6, to: today)
            case .month: return calendar.date(byAdding: .day, value: -29, to: today)
            }
        }
    }

    struct Line: Identifiable {
        let id: String
        let day: String?
        let trace: History.Trace?
    }

    var body: some View {
        VStack(spacing: 0) {
            ShelfHead(hunt: $hunt, prompt: "Search History") {
                FilterMenu(title: since == .always ? "Filter" : since.title) {
                    Picker("Show", selection: $since) {
                        ForEach(Since.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    // The panel's own sweeps: history, sign-ins and cache,
                    // each said apart.
                    Button("Clear History…") { browser.recallMode = .clearing }
                }
            }
            if lines.isEmpty {
                ShelfEmpty(text: hunt.isEmpty && since == .always ? "Nothing yet." : "Nothing matches.")
                Spacer(minLength: 0)
            } else {
                // Lazy: thousands of lines, only those in view made.
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(lines) { line in
                            if let day = line.day {
                                ShelfCaption(text: day)
                            } else if let trace = line.trace {
                                Row(trace: trace, browser: browser) {
                                    browser.history.forget(trace.key)
                                    refresh()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: hunt) { _, _ in refresh() }
        .onChange(of: since) { _, _ in refresh() }
    }

    private func refresh() {
        var traces = browser.history.everything(matching: hunt)
        if let start = since.start { traces = traces.filter { $0.last >= start } }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: traces) { calendar.startOfDay(for: $0.last) }
        var made: [Line] = []
        for day in grouped.keys.sorted(by: >) {
            made.append(Line(id: "day " + day.description, day: When.day(day), trace: nil))
            for trace in (grouped[day] ?? []).sorted(by: { $0.last > $1.last }) {
                made.append(Line(id: trace.id, day: nil, trace: trace))
            }
        }
        lines = made
    }

    private struct Row: View {
        let trace: History.Trace
        let browser: Browser
        let forget: () -> Void
        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        private var place: String { Address.withoutWWW(trace.address) }

        var body: some View {
            HStack(spacing: 10) {
                Mark(icon: Favicons.shared.cached(Favicons.site(trace.url) ?? ""),
                     letter: trace.address.first.map { String($0).uppercased() } ?? "•", size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trace.title.isEmpty ? place : trace.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(place)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if hovering {
                    Button(action: forget) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.quiet)
                    .help("Remove from History")
                } else {
                    Text(When.clock(trace.last))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.quiet)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? SideTone.chip(scheme, strong: false) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                let behind = NSEvent.modifierFlags.contains(.command)
                browser.open(trace.url, foreground: !behind)
            }
            .onHover { hovering = $0 }
            .onDrag { NSItemProvider(object: trace.url as NSURL) }
            .contextMenu {
                Button("Open in New Tab") { browser.open(trace.url, foreground: true) }
                Button("Open in Background") { browser.open(trace.url, foreground: false) }
                Button("Open Here") { browser.active?.go(to: trace.url) }
                    .disabled(browser.active == nil)
                Divider()
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trace.url.absoluteString, forType: .string)
                }
                Divider()
                Button("Remove from History", action: forget)
            }
            .animation(Motion.quick, value: hovering)
        }
    }
}

// MARK: - Spaces

/// Every space as a card in its own colour, with its tabs: drag a tab onto
/// another card to move it there, drag a card by its foot to put it
/// elsewhere in the order, and + for a new one.
private struct LibrarySpaces: View {
    @ObservedObject var browser: Browser
    /// The window's own light or dark, for the cards' colours: the library
    /// itself is drawn in the space on screen's.
    let window: ColorScheme

    /// The card being carried along the row, and how far.
    @State private var carrying: (id: UUID, by: CGFloat)?

    private static let tabPrefix = "search-library-tab:"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: LibraryRoom.gap) {
                ForEach(browser.spaces) { space in
                    SpaceCard(browser: browser, space: space, window: window, prefix: LibrarySpaces.tabPrefix,
                              carry: { by in carrying = (space.id, by) },
                              letGo: { letGo(space.id) })
                        .offset(x: carrying?.id == space.id ? carrying?.by ?? 0 : 0)
                        .zIndex(carrying?.id == space.id ? 1 : 0)
                }
                NewSpace(browser: browser)
            }
            .padding(.horizontal, LibraryRoom.gap)
            .padding(.top, SideBar.topRow + 8)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
        .onAppear { browser.preloadSpaces() }
    }

    private func letGo(_ id: UUID) {
        defer { withAnimation(Motion.settle) { carrying = nil } }
        guard let by = carrying?.by, let from = browser.spaces.firstIndex(where: { $0.id == id }) else { return }
        let steps = Int((by / (LibraryRoom.card + LibraryRoom.gap)).rounded())
        let to = min(max(0, from + steps), browser.spaces.count - 1)
        guard to != from else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            browser.moveSpace(id, to: to)
            carrying = nil
        }
    }

    /// The round + after the cards.
    private struct NewSpace: View {
        let browser: Browser
        @State private var hovering = false

        var body: some View {
            Button {
                Ask.newSpace(
                    then: { name, shared in browser.addSpace(named: name, sharesSignIns: shared) },
                    cancelled: {}
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(hovering ? 0.85 : 0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(hovering ? Palette.veilStrong : Palette.veil))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("New Space")
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// One space: its icon and name, its pins over a line, then its tabs.
private struct SpaceCard: View {
    @ObservedObject var browser: Browser
    let space: Space
    let window: ColorScheme
    let prefix: String
    let carry: (CGFloat) -> Void
    let letGo: () -> Void

    @State private var theming = false
    @State private var landing = false

    private var here: Bool { space.id == browser.spaceID }
    private var dark: Bool { space.wearsDark(on: window == .dark) }

    var body: some View {
        let tabs = browser.libraryTabs(of: space.id)
        let pins = tabs.filter { $0.pin != nil }
        let loose = tabs.filter { $0.pin == nil }

        VStack(alignment: .leading, spacing: 0) {
            head
            Rectangle()
                .fill(Palette.ink.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 10)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(pins) { tab in
                        TabLine(browser: browser, tab: tab, space: space.id, prefix: prefix, movable: false,
                                live: here && tab.id == browser.activeID)
                    }
                    if !pins.isEmpty && !loose.isEmpty {
                        Rectangle()
                            .fill(Palette.ink.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                    }
                    ForEach(loose) { tab in
                        TabLine(browser: browser, tab: tab, space: space.id, prefix: prefix, movable: browser.prefs.usesSpaces,
                                live: here && tab.id == browser.activeID)
                    }
                    if tabs.isEmpty {
                        Text("No tabs")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.quiet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            Spacer(minLength: 0)
            foot
        }
        .frame(width: LibraryRoom.card)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(spaceColour(space, in: window))
                .overlay {
                    // The space on screen is the library's own colour: an
                    // outline tells it apart from the ground it stands on.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(landing ? 0.45 : (here ? 0.18 : 0.06)), lineWidth: landing ? 2 : 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .onDrop(of: [.text], isTargeted: $landing) { providers in take(providers) }
        .animation(Motion.quick, value: landing)
    }

    private var head: some View {
        HStack(spacing: 7) {
            SpaceGlyph(space: space, size: 11)
                .foregroundStyle(Palette.ink.opacity(0.75))
                .frame(width: 16)
            Text(space.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Door(icon: "paintbrush.pointed", on: theming, help: "Theme and Icon") { theming = true }
                .popover(isPresented: $theming, arrowEdge: .bottom) {
                    ThemePicker(browser: browser, spaceID: space.id).popGround()
                }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { rename() }
    }

    private var foot: some View {
        HStack {
            // Six dots, two by three: the grip.
            VStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 2.5) {
                        Circle().frame(width: 2.5, height: 2.5)
                        Circle().frame(width: 2.5, height: 2.5)
                    }
                }
            }
                .foregroundStyle(Palette.quiet)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { carry($0.translation.width) }
                        .onEnded { _ in letGo() }
                )
                .help("Drag to reorder")
                .onHover { inside in
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
            Spacer()
            Menu {
                if !here {
                    Button("Switch to Space") { browser.switchSpace(to: space.id) }
                    Divider()
                }
                Button("Rename…") { rename() }
                Button("Theme and Icon…") { theming = true }
                if !space.isFirst {
                    Divider()
                    Button("Delete…") {
                        Ask.sure("Delete “\(space.name)”?", detail: "Its tabs close, and its bookmarks, cookies and sign-ins are erased from this Mac. History stays.", confirm: "Delete") {
                            browser.deleteSpace(space.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func rename() {
        Ask.name("Rename Space", placeholder: space.name, initial: space.name, confirm: "Rename") {
            browser.renameSpace(space.id, to: $0)
        }
    }

    private func take(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        let target = space.id
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix(prefix),
                  let id = UUID(uuidString: String(text.dropFirst(prefix.count)))
            else { return }
            DispatchQueue.main.async {
                withAnimation(Motion.settle) { browser.libraryCarry(id, to: target) }
            }
        }
        return true
    }
}

/// A tab on a space's card. A click goes to it, its space first.
private struct TabLine: View {
    let browser: Browser
    @ObservedObject var tab: Tab
    let space: UUID
    let prefix: String
    let movable: Bool
    /// The tab on screen. Said by the card, which redraws as it changes.
    let live: Bool

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let line = HStack(spacing: 8) {
            Mark(icon: tab.icon, letter: tab.label.first.map { String($0).uppercased() } ?? "•", size: 14)
                .saturation(tab.asleep ? 0.3 : 1)
            Text(tab.label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(tab.asleep && !live ? 0.7 : 1))
                .lineLimit(1)
            Spacer(minLength: 0)
            if tab.pin != nil {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.quiet)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(live ? SideTone.chip(scheme, strong: true) : (hovering ? SideTone.chip(scheme, strong: false) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { browser.libraryGo(to: tab, in: space) }
        .onHover { hovering = $0 }
        .help(tab.address.map { Address.pretty($0) } ?? tab.label)
        .animation(Motion.quick, value: hovering)

        if movable {
            line.onDrag { NSItemProvider(object: (prefix + tab.id.uuidString) as NSString) }
        } else {
            line
        }
    }
}

/// Zen's mark for its library: a tray, and a star, a dot and a play mark
/// rising out of it. Drawn rather than a symbol, so it is sharp at any size,
/// in whatever colour it is given. `lift` raises the three a little.
struct LibraryGlyph: View, Animatable {
    var lift: CGFloat = 0

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        Canvas { context, size in
            // Drawn on a grid of 16, scaled to the frame.
            let s = min(size.width, size.height) / 16
            let up = -lift
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            let tray = Path { path in
                let rect = CGRect(x: 2 * s, y: 7.6 * s, width: 12 * s, height: 7.6 * s)
                let top = 1.1 * s, bottom = 3.6 * s
                path.addRoundedRect(in: rect, cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom,
                                                                                bottomTrailing: bottom, topTrailing: top),
                                    style: .continuous)
                // The slot, cut out of it.
                path.addRoundedRect(in: CGRect(x: 5.6 * s, y: 9.5 * s, width: 4.8 * s, height: 1.5 * s),
                                    cornerSize: CGSize(width: 0.75 * s, height: 0.75 * s), style: .continuous)
            }
            context.fill(tray, with: .foreground, style: FillStyle(eoFill: true))

            let rounded = StrokeStyle(lineWidth: 0.7 * s, lineJoin: .round)
            var star = Path()
            let centre = p(4.7, 4.5 + up)
            for i in 0..<10 {
                let r = (i % 2 == 0 ? 2.5 : 1.1) * s
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5 - 0.12
                let point = CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            context.fill(star.union(star.strokedPath(rounded)), with: .foreground)

            context.fill(Path(ellipseIn: CGRect(x: 7.5 * s, y: (1.0 + up) * s, width: 2.3 * s, height: 2.3 * s)),
                         with: .foreground)

            var play = Path()
            play.move(to: p(11.0, 2.6 + up))
            play.addLine(to: p(14.4, 4.8 + up))
            play.addLine(to: p(11.2, 6.6 + up))
            play.closeSubpath()
            context.fill(play.union(play.strokedPath(rounded)), with: .foreground)
        }
    }
}
