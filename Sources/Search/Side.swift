import SwiftUI
import UniformTypeIdentifiers

/// Where a tab drag is hovering in the bookmarks, so the folder under the
/// hand can light up without the column redrawing the tab it is carrying.
@MainActor
private final class DropAim: ObservableObject {
    struct Mark: Equatable {
        var folder: Bookmark.ID?
        var root = false
    }

    @Published var mark = Mark()
}

/// A bookmark row's place in the column, so a tab let go over it can be filed
/// there. A nil id is the list itself.
private struct MarkSpot: Equatable {
    var id: Bookmark.ID?
    var folder: Bool
    var rect: CGRect
}

private struct MarkSpotsKey: PreferenceKey {
    static var defaultValue: [MarkSpot] = []
    static func reduce(value: inout [MarkSpot], nextValue: () -> [MarkSpot]) {
        value.append(contentsOf: nextValue())
    }
}

/// The column down the left: pinned pages, then bookmark folders, then the
/// tabs in a section of their own.
///
/// The same pieces as the strip — the grey that slides to the tab you picked,
/// the pinned squares, the cross that appears under the pointer — laid out the
/// other way. The traffic lights keep their corner; the column starts under
/// them and the page starts under the address bar beside it.
struct SideBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var bookmarks: Bookmarks
    /// Out over the page from the window's edge, as a card of its own
    /// rather than the column beside the page (see Fold.swift).
    var floating = false

    @Environment(\.colorScheme) private var windowScheme
    @Namespace private var pill

    @State private var landing = false
    /// The width the column had when the edge was picked up.
    @State private var grabbed: CGFloat?
    @State private var onEdge = false

    /// A pin, picked up out of the grid — a separate state from the loose
    /// rows above, since the two gestures never happen at once but move on
    /// two different axes.
    /// The neighbouring spaces' own grey, apart from this one's.
    @Namespace private var before
    @Namespace private var after

    @State private var pinDragging: Tab.ID?
    @State private var pinFrom = 0
    @State private var pinTravel: CGSize = .zero
    /// Folders the column has opened. The tree is the same in every space,
    /// so opening one stays open while the spaces slide past each other.
    @State private var foldersOpen: Set<Bookmark.ID> = []
    /// Bookmark rows, measured in the column, for a tab dropped onto one.
    @State private var spots: [MarkSpot] = []
    @State private var overSection = false
    /// The theme, open off the space on screen.
    @State private var theming = false
    /// Held as state, not observed here: the folder lighting up must not
    /// redraw the tab under the hand, or the drag would be dropped.
    @State private var aim = DropAim()
    /// The neighbouring space's list is drawn too, and must not light up
    /// when this space's drag passes a folder.
    @State private var idleAim = DropAim()

    fileprivate static let row: CGFloat = 28
    fileprivate static let gap: CGFloat = 2
    /// "Bookmarks" and "Tabs", the labels that split the column.
    private static let section: CGFloat = 26
    private static let square: CGFloat = 34
    private static let pinGap: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            // Not under the card for a new space: it isn't made of views that
            // would take the click first.
            DragStrip(reserved: 0, below: browser.makingSpace ? .greatestFiniteMagnitude : rowsEnd)

            // The band the lights sit in, on the left only: the window is
            // dragged by it and a double-click fills the screen with it.
            // The lights are the title bar's own and answer first. On the
            // right the column has no lights — they stay in the address bar.
            HStack(spacing: 0) {
                if !prefs.sideRight {
                    DragStrip()
                        .frame(width: 10 + Metrics.sideLights)
                }
                DragStrip()
            }
            .frame(height: URLBar.height)

            VStack(alignment: .leading, spacing: 0) {
                // The traffic lights' corner, when the column is on the left.
                // Back, forward and reload sit on that same line, and the
                // address is the row under them — the page beside has none.
                HStack(spacing: 2) {
                    if !prefs.sideRight {
                        Color.clear.frame(width: Metrics.sideLights)
                    }
                    Spacer(minLength: 4)
                    // Never wider than the column: a narrow one keeps the
                    // three doors and lets the extensions' button go — the
                    // same list is in the site's controls, under the address
                    // — rather than pushing the column out past its edges.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 2) {
                            ExtensionSlot(edge: .bottom)
                            Helm(browser: browser)
                        }
                        Helm(browser: browser)
                    }
                }
                // Out over the page the card starts its inset below the
                // window's top, and the lights come down into it by as much
                // (Lights.nudge), so the row is the same as docked.
                .frame(width: prefs.sideWidth - 20, height: URLBar.height)

                SideAddress(browser: browser)
                    .padding(.bottom, SideAddress.below)
                    .zIndex(2)

                // The spaces side by side, as pages: two fingers sideways move
                // the one on screen and the next one together, the next one
                // coming in as this one goes, with nothing between them.
                pages

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: prefs.sideWidth)
            // Clear of the foot, which sits over the column's bottom edge.
            .padding(.bottom, SideBar.footHeight)

            VStack {
                Spacer()
                foot
            }
        }
        .frame(width: prefs.sideWidth)
        .frame(maxHeight: .infinity)
        // Rows on their way to or from another space stay in the column.
        .clipped()
        .onAppear { SpaceSwipe.shared.start(for: browser) }
        .background {
            ZStack {
                Spaces.ground(browser.space)
                Grain()
            }
        }
        .overlay(alignment: prefs.sideRight ? .leading : .trailing) { if !floating { edge } }
        // A pastel worn on a dark window takes dark ink, and the other way
        // round: the column is drawn in its colour's own light or dark.
        .environment(\.colorScheme, browser.space.wearsDark(on: windowScheme == .dark) ? .dark : .light)
        .onDrop(of: [.url, .text], isTargeted: $landing) { providers in
            browser.take(providers)
        }
        .animation(Motion.quick, value: landing)
        .animation(Motion.glide, value: browser.activeID)
        .animation(Motion.glide, value: browser.editingTab)
        .animation(Motion.settle, value: browser.tabs.map(\.id))
        .animation(Motion.settle, value: browser.pinnedCount)
        .coordinateSpace(name: "column")
        .onPreferenceChange(MarkSpotsKey.self) { spots = $0 }
        .onChange(of: bookmarks.reveal) { _, id in
            guard let id else { return }
            var open = foldersOpen
            open.insert(id)
            for parent in bookmarks.ancestors(of: id) { open.insert(parent) }
            withAnimation(Motion.quick) { foldersOpen = open }
            DispatchQueue.main.async { bookmarks.reveal = nil }
        }
    }

    /// The column's edge: pull it to make the column wider or narrower,
    /// double-click it to put it back. The hairline darkens under the pointer
    /// so the edge says it can be taken before it is.
    private var edge: some View {
        Rectangle()
            .fill(Palette.ink.opacity(onEdge || grabbed != nil ? 0.18 : 0))
            .frame(width: onEdge || grabbed != nil ? 2 : 1)
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { over in
                onEdge = over
                if over { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if grabbed == nil { grabbed = prefs.sideWidth }
                        let delta = prefs.sideRight ? -value.translation.width : value.translation.width
                        let wanted = (grabbed ?? prefs.sideWidth) + delta
                        prefs.sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, wanted))
                    }
                    .onEnded { _ in grabbed = nil }
            )
            .modifier(OneClick(double: true) {
                withAnimation(Motion.settle) { prefs.sideWidth = Metrics.side }
            })
            .animation(Motion.quick, value: onEdge)
    }

    // MARK: - the spaces, as pages

    /// Where the space on screen sits among them: one past the last while
    /// the card for a new one is up.
    private var spaceAt: Int {
        browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
    }

    private var pages: some View {
        let width = prefs.sideWidth
        let swipe = browser.spaceSwipe
        let at = spaceAt
        return ZStack(alignment: .topLeading) {
            page(at, pill: pill)
                .offset(x: swipe)
            // Only while the fingers are bringing one in: the one they are
            // bringing, a page's width away.
            if swipe > 0, at > 0 {
                page(at - 1, pill: before)
                    .offset(x: swipe - width)
            }
            if swipe < 0, at < browser.spaces.count {
                page(at + 1, pill: after)
                    .offset(x: swipe + width)
            }
        }
        // The pages are the column's whole width, each with its own margin.
        .padding(.horizontal, -10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// One space's page: the rows on screen, another space's rows as they
    /// were left, or past the last the card for a new one.
    @ViewBuilder
    private func page(_ index: Int, pill: Namespace.ID) -> some View {
        Group {
            if index == browser.spaces.count {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NewSpaceCard(browser: browser)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else if browser.spaces[index].id == browser.spaceID {
                VStack(alignment: .leading, spacing: 0) {
                    if browser.pinnedCount > 0 {
                        pinned
                            .padding(.bottom, 8)
                    }
                    // Bookmarks and tabs scroll together once they pass the
                    // foot. The pins stay, the way the icons at the top of the
                    // column do. While it all fits, the stack stays plain and
                    // the space under it is still the window's to be dragged by.
                    ViewThatFits(in: .vertical) {
                        rows
                        ScrollViewReader { proxy in
                            // The scroll view reaches into the margin on
                            // the right and the rows keep it inside, so the
                            // system's bar lands in the margin beside them
                            // rather than over the cross on the tab under the
                            // pointer. The column's edge lies over that margin
                            // and answers first, so the bar never fights the
                            // resize; the wheel and the trackpad still scroll.
                            ScrollView(.vertical) {
                                rows.padding(.trailing, 10)
                            }
                            .padding(.trailing, -10)
                            // The tab you go to is the tab you see — ⌘1–⌘9,
                            // ⇧⌘], a link opening beside the one on screen.
                            .onChange(of: browser.activeID) { _, id in
                                guard let id else { return }
                                withAnimation(Motion.glide) { proxy.scrollTo(id) }
                            }
                            .onAppear {
                                if let id = browser.activeID { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                    }
                }
            } else {
                preview(browser.parked[browser.spaces[index].id] ?? Parked(tabs: [], active: nil), space: browser.spaces[index].id, pill: pill)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: prefs.sideWidth, alignment: .topLeading)
    }

    /// Another space's rows, drawn with the same pieces as this one's so the
    /// two read as one column while they pass — and nothing to press until
    /// it is the one on screen.
    private func preview(_ row: Parked, space: UUID, pill: Namespace.ID) -> some View {
        let pins = row.tabs.filter { $0.pin != nil }
        let rest = row.tabs.filter { $0.pin == nil && $0.bookmark == nil }
        let cols = SideBar.pinColumns(pins.count)
        let width = pinWidth(for: pins.count)
        let height = min(SideBar.square, width)
        return VStack(alignment: .leading, spacing: 0) {
            if !pins.isEmpty {
                VStack(spacing: 0) {
                    PinGrid(columns: cols, width: width, height: height, spacing: SideBar.pinGap) {
                        ForEach(pins) { tab in
                            PinSquare(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active,
                                      pill: pill, width: width, height: height)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            section(browser.spaces.first { $0.id == space })
            SideMarks(
                browser: browser, bookmarks: bookmarks, open: $foldersOpen, aim: idleAim,
                tree: bookmarks.nodes(in: space),
                tabs: row.tabs, active: row.active,
                colour: browser.spaces.first { $0.id == space }?.colour
            )
            rule
            newTab
            VStack(spacing: SideBar.gap) {
                ForEach(rest) { tab in
                    SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Where the rows stop and the window's own drag area starts. Added up
    /// from what was drawn rather than measured: a measurement would arrive a
    /// frame late, and for one frame the whole column would drag the window.
    private var rowsEnd: CGFloat {
        let pins = browser.pinnedCount
        let cols = SideBar.pinColumns(pins)
        let pinRows = pins == 0 ? 0 : (pins + cols - 1) / cols
        let pinBlock = pinRows == 0 ? 0
            : CGFloat(pinRows) * pinHeight + CGFloat(pinRows - 1) * SideBar.pinGap + 8
        let looseCount = browser.tabs.filter { $0.pin == nil && $0.bookmark == nil }.count
        let loose = CGFloat(looseCount) * (SideBar.row + SideBar.gap)
        let marks = CGFloat(SideMarks.count(bookmarks.roots, open: foldersOpen, empty: bookmarks.isEmpty))
            * (SideBar.row + SideBar.gap)
        // The lights, the address, the space's name, the bookmark rows, New Tab, and the loose tabs.
        return URLBar.height + SideAddress.block + pinBlock + SideBar.section + marks + SideBar.ruleHeight + loose + (SideBar.row + SideBar.gap) + 16
    }

    // MARK: - the pinned squares

    private var pinnedTabs: [Tab] { browser.tabs.filter { $0.pin != nil } }
    private var looseTabs: [Tab] { browser.tabs.filter { $0.pin == nil && $0.bookmark == nil } }

    /// Three columns is the block's own shape — up to six pins, that's two
    /// full rows, and one or two is just those same three places with a
    /// couple of them empty rather than a lonely row of its own width. Only
    /// past six does the block widen, one column at a time, to stay at two
    /// rows for as long as that's a reasonable shape at all.
    private static func pinColumns(_ count: Int) -> Int {
        max(3, (count + 1) / 2)
    }

    /// However many columns the count calls for, they split the row's own
    /// width between them — the row is what fills edge to edge, not each
    /// cell on its own, so this grows past 34 just as readily as it shrinks
    /// below it.
    private var pinWidth: CGFloat { pinWidth(for: browser.pinnedCount) }

    private func pinWidth(for count: Int) -> CGFloat {
        let cols = SideBar.pinColumns(count)
        guard cols > 0 else { return SideBar.square }
        let available = prefs.sideWidth - 20 - CGFloat(cols - 1) * SideBar.pinGap
        return max(20, available / CGFloat(cols))
    }

    /// The one dimension that doesn't chase the sidebar's width: past three
    /// columns' worth of room a cell would otherwise turn into a big square
    /// rather than the wide, short button pinned tabs actually look like
    /// everywhere else in this app. It only shrinks below 34 alongside the
    /// width, once a narrow column leaves no other choice.
    private var pinHeight: CGFloat {
        min(SideBar.square, pinWidth)
    }

    /// The grid itself: fixed-size cells, left-aligned, so a half-empty last
    /// row holds its ground rather than stretching to fill it.
    private var pinned: some View {
        let tabs = pinnedTabs
        let cols = SideBar.pinColumns(tabs.count)
        let width = pinWidth
        let height = pinHeight
        // Measured in the grid's own space, not the square's: a square that
        // has just been moved to a new cell would otherwise report the drag
        // from where it now is, the target would jump back, and the square
        // would shuttle between two cells for as long as the finger stayed.
        return VStack(spacing: 0) { PinGrid(columns: cols, width: width, height: height, spacing: SideBar.pinGap) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let held = pinDragging == tab.id
                PinSquare(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    width: width,
                    height: height
                )
                .offset(pinOffset(held: held, index: index, columns: cols))
                // Under the hand exactly, as a row is (see the rows below).
                .transaction { if held { $0.animation = nil } }
                .zIndex(held ? 1 : 0)
                .shadow(color: .black.opacity(held ? 0.16 : 0), radius: 10, y: 3)
                .gesture(pinReorder(tab: tab, index: index, columns: cols, width: width, height: height))
            }
        } }
        .coordinateSpace(name: "pins")
    }

    /// The one square actually held stays glued to the fingers; every other
    /// square is already exactly where it belongs, because `browser.move`
    /// put it there — this only cancels out the bit of that same movement
    /// the held square already got for free by changing index underneath
    /// its own drag.
    private func pinOffset(held: Bool, index: Int, columns: Int) -> CGSize {
        guard held else { return .zero }
        let stepX = pinWidth + SideBar.pinGap
        let stepY = pinHeight + SideBar.pinGap
        let from = (row: pinFrom / columns, col: pinFrom % columns)
        let now = (row: index / columns, col: index % columns)
        return CGSize(
            width: pinTravel.width - CGFloat(now.col - from.col) * stepX,
            height: pinTravel.height - CGFloat(now.row - from.row) * stepY
        )
    }

    /// How many cells the drag has moved, in the grid's own row-major order
    /// — a straight line through the array a column-major offset would get
    /// wrong the moment it crossed a row. Row and column travel each measure
    /// themselves against that axis's own step now that a cell's width and
    /// height aren't the same number.
    private func pinDelta(columns: Int, stepX: CGFloat, stepY: CGFloat) -> Int {
        let col = Int((pinTravel.width / stepX).rounded())
        let row = Int((pinTravel.height / stepY).rounded())
        return row * columns + col
    }

    private func pinTarget(from: Int, moved: Int) -> Int {
        min(max(0, from + moved), max(0, pinnedTabs.count - 1))
    }

    /// Pick a square up and the others make way — across a row, and down
    /// into the next, exactly as far as the fingers actually moved.
    private func pinReorder(tab: Tab, index: Int, columns: Int, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("pins"))
            .onChanged { value in
                if pinDragging != tab.id {
                    pinDragging = tab.id
                    pinFrom = index
                }
                pinTravel = value.translation
                let stepX = width + SideBar.pinGap
                let stepY = height + SideBar.pinGap
                let target = pinTarget(from: pinFrom, moved: pinDelta(columns: columns, stepX: stepX, stepY: stepY))
                if target != index {
                    withAnimation(Motion.settle) {
                        browser.move(tab, to: target)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    pinDragging = nil
                    pinTravel = .zero
                }
            }
    }

    // MARK: - filing a tab into the bookmarks

    /// The folder under the pointer, or the list itself when the pointer is
    /// over the bookmarks but not inside a folder.
    private func mark(at point: CGPoint) -> DropAim.Mark {
        let hits = spots.filter { $0.rect.contains(point) }
        // A folder sitting in the list is inside the list's own rectangle, so
        // the folder wins even when the two are the same size.
        let folders = hits.filter(\.folder)
        if let folder = folders.min(by: { Self.area($0.rect) < Self.area($1.rect) }), let id = folder.id {
            return DropAim.Mark(folder: id)
        }
        if hits.contains(where: { $0.id == nil }) { return DropAim.Mark(root: true) }
        return DropAim.Mark()
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private func filing(_ tab: Tab) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("column"))
            .onChanged { value in
                let next = mark(at: value.location)
                if next != aim.mark { aim.mark = next }
            }
            .onEnded { value in
                let next = mark(at: value.location)
                aim.mark = DropAim.Mark()
                guard next.folder != nil || next.root, let url = tab.address, !tab.isBlank else { return }
                browser.announce(bookmarks.file(url, title: tab.title, into: next.folder))
            }
    }

    /// A bookmark let go on the Bookmarks label goes back to the top of the list.
    private func relocate(_ providers: [NSItemProvider], into folder: Bookmark.ID?) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { self.bookmarks.move(id, into: folder) }
        }
        return true
    }

    // MARK: - the rows

    private var loose: some View {
        VStack(spacing: SideBar.gap) {
            // See the grid: the drag is measured in the column's space, not
            // the row's, so a row that has just moved keeps its bearings.
            ForEach(Array(looseTabs.enumerated()), id: \.element.id) { index, tab in
                let step = SideBar.row + SideBar.gap
                SideRow(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    close: { browser.close(tab) }
                )
                // Positions here are among the loose rows; the pinned block
                // sits in front of them in the real list.
                .modifier(Carried(index: index, count: looseTabs.count, step: step, vertical: true, space: "rows") {
                    browser.move(tab, to: $0 + browser.pinnedCount)
                })
                // The reorder above keeps the row under the hand. This one
                // only watches where the hand is, and files the page when
                // that place is a bookmark folder.
                .simultaneousGesture(filing(tab))
            }
        }
        .coordinateSpace(name: "rows")
    }

    /// Bookmarks, then the tabs, each under its own label. They scroll as one
    /// once the column is full; the pins stay above them.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            section(browser.space)
                .onDrop(of: [.text], isTargeted: $overSection) { providers in relocate(providers, into: nil) }
                .contextMenu {
                    Button("New Folder") { newFolder(into: nil) }
                    Button("Theme…") { theming = true }
                }
            SideMarks(browser: browser, bookmarks: bookmarks, open: $foldersOpen, aim: aim)
            rule
            newTab
            loose
        }
    }

    /// The space's name over its bookmarks, with its icon when it has one.
    /// Its first letter lines up with the icons of the rows beneath it.
    private func section(_ space: Space?) -> some View {
        HStack(spacing: 6) {
            if let space, space.hasIcon {
                SpaceGlyph(space: space, size: 10)
                    .foregroundStyle(Palette.quiet)
            }
            Text(space?.name ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.quiet)
        }
        .padding(.leading, SideBar.inset)
        .padding(.bottom, 4)
        .frame(height: SideBar.section, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where every row's icon starts, and the section's first letter.
    fileprivate static let inset: CGFloat = 10
    fileprivate static let ruleHeight: CGFloat = 1 + 16

    /// The hairline between the space's bookmarks and its loose tabs, as Arc
    /// draws it.
    private var rule: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, SideBar.inset)
            .padding(.vertical, 8)
    }

    /// The foot's doors and the margin beneath.
    private static let footHeight: CGFloat = 26 + 12

    private var newTab: some View {
        Quiet(icon: "plus", title: "New Tab", height: SideBar.row) { browser.newTab() }
            .padding(.top, SideBar.gap)
    }

    private func newFolder(into parent: Bookmark.ID?) {
        Ask.name("New Folder", placeholder: "Name", confirm: "Create") { title in
            let made = bookmarks.makeFolder(title, into: parent)
            if let parent { foldersOpen.insert(parent) }
            foldersOpen.insert(made.id)
        }
    }

    /// The spaces, as their colours. The one on screen opens the theme;
    /// any other is switched to. A bookmark list is a right-click away,
    /// not a door of its own.
    private var foot: some View {
        ZStack {
            SpaceStrip(browser: browser, theming: $theming)
            // One door either side, the same width, so the spaces between
            // them sit in the true middle of the column.
            HStack(spacing: 0) {
                Library(browser: browser, loot: browser.loot)
                Spacer(minLength: 0)
                Door(icon: "plus", help: "New Space") { browser.askForSpace() }
            }
        }
        .frame(height: 26)
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

}

/// Bookmarks, in the column: folders that open downward, and the pages filed
/// in them. The same tree as the menu and the manager, drawn as rows so it
/// can sit between the pins and the tabs.
private struct SideMarks: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    @Binding var open: Set<Bookmark.ID>
    @ObservedObject var aim: DropAim
    /// Another space's list and pages, while that space is sliding past.
    /// Absent, this is the space on screen.
    var tree: [Bookmark]? = nil
    var tabs: [Tab]? = nil
    var active: Tab.ID? = nil
    /// That space's colour, for its folders. Absent, the one on screen.
    var colour: Int? = nil

    @State private var overEmpty = false

    private var shown: [Bookmark] { tree ?? bookmarks.roots }
    /// The list sliding past belongs to another space. It is only a picture.
    private var live: Bool { tree == nil }

    var body: some View {
        Group {
            if shown.isEmpty {
                Text("No bookmarks yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.hush)
                    .padding(.leading, SideBar.inset)
                    .frame(maxWidth: .infinity, minHeight: SideBar.row, alignment: .leading)
                    .onDrop(of: [.text], isTargeted: $overEmpty) { providers in
                        guard live else { return false }
                        return take(providers, into: nil, before: nil)
                    }
            } else {
                VStack(alignment: .leading, spacing: SideBar.gap) {
                    rows(shown, depth: 0)
                }
            }
        }
        .background { spot(nil, folder: false) }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(live && aim.mark.root ? Palette.veil : Color.clear)
        )
    }

    /// How many rows are on screen, folders closed counted as one. The
    /// column's drag area stops where these stop.
    static func count(_ nodes: [Bookmark], open: Set<Bookmark.ID>, empty: Bool) -> Int {
        if empty { return 1 }
        return nodes.reduce(0) { total, node in
            guard node.isFolder, open.contains(node.id) else { return total + 1 }
            let kids = node.children ?? []
            if kids.isEmpty { return total + 2 }
            return total + 1 + count(kids, open: open, empty: false)
        }
    }

    @ViewBuilder
    private func rows(_ nodes: [Bookmark], depth: Int) -> some View {
        ForEach(nodes) { node in
            if node.isFolder {
                folder(node, depth: depth)
            } else {
                site(node, depth: depth)
            }
        }
    }

    private func folder(_ node: Bookmark, depth: Int) -> some View {
        let opened = open.contains(node.id)
        let kids = node.children ?? []
        return VStack(alignment: .leading, spacing: SideBar.gap) {
            line(node, depth: depth, folder: true, opened: opened, live: false, close: nil, newFolder: {
                Ask.name("New Folder", placeholder: "Name", confirm: "Create") { title in
                    let made = bookmarks.makeFolder(title, into: node.id)
                    open.insert(node.id)
                    open.insert(made.id)
                }
            }) {
                withAnimation(Motion.quick) {
                    if opened {
                        open.remove(node.id)
                    } else {
                        open.insert(node.id)
                    }
                }
            }
            if opened {
                if kids.isEmpty {
                    Text("Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.hush)
                        .padding(.leading, indent(depth + 1) + SideBar.inset + 23)
                        .frame(maxWidth: .infinity, minHeight: SideBar.row, alignment: .leading)
                } else {
                    // The rows call this folder back. AnyView is what lets a
                    // view mention itself without the compiler having to name
                    // the type it is still building.
                    AnyView(rows(kids, depth: depth + 1))
                }
            }
        }
        .padding(opened ? 2 : 0)
        .background { spot(node.id, folder: true) }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(live && aim.mark.folder == node.id ? Palette.veilStrong : (opened ? Palette.veil : Color.clear))
        )
    }

    private func site(_ node: Bookmark, depth: Int) -> some View {
        let pool = tabs ?? browser.tabs
        let openTab = pool.first { $0.bookmark == node.id }
        let liveID = tabs == nil ? browser.activeID : active
        return line(
            node, depth: depth, folder: false, opened: false,
            live: openTab?.id == liveID,
            close: openTab.map { tab in { browser.close(tab) } },
            newFolder: live ? {
                let parent = bookmarks.parent(of: node.id)
                Ask.name("New Folder", placeholder: "Name", confirm: "Create") { title in
                    let made = bookmarks.makeFolder(title, into: parent)
                    if let parent { open.insert(parent) }
                    open.insert(made.id)
                }
            } : nil
        ) {
            guard let text = node.url, let url = URL(string: text) else { return }
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                _ = browser.open(url, foreground: true)
            } else {
                browser.openBookmark(node.id, url)
            }
        }
    }

    private func line(
        _ node: Bookmark,
        depth: Int,
        folder: Bool,
        opened: Bool,
        live rowLive: Bool,
        close: (() -> Void)?,
        newFolder: (() -> Void)?,
        act: @escaping () -> Void
    ) -> some View {
        let targets = live
            ? Bookmarks.folders(bookmarks.roots).filter { !Bookmarks.holds($0.node.id, node) }
            : []
        return Line(
            node: node, depth: depth, folder: folder, opened: opened, live: rowLive,
            lit: folder && live && aim.mark.folder == node.id,
            act: act, close: close, newFolder: newFolder,
            addPage: folder && live ? { if let tab = browser.active { browser.file(tab, into: node.id) } } : nil,
            canAdd: browser.active?.isBlank == false,
            moveTargets: targets,
            moveTo: { bookmarks.move(node.id, into: $0) },
            tint: colour ?? browser.space.colour
        ) {
            if let close { close() }
            bookmarks.remove(node.id)
        } openNew: {
            guard let text = node.url, let url = URL(string: text) else { return }
            _ = browser.open(url, foreground: true)
        } dropped: { providers in
            take(providers, into: folder ? node.id : nil, before: folder ? nil : node.id)
        }
    }

    /// A bookmark row's place, in the column's own coordinates. The page
    /// sliding past reports nothing, or a drop there would file into this space.
    @ViewBuilder
    private func spot(_ id: Bookmark.ID?, folder: Bool) -> some View {
        if live {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MarkSpotsKey.self,
                    value: [MarkSpot(id: id, folder: folder, rect: geo.frame(in: .named("column")))]
                )
            }
        }
    }

    /// A bookmark dropped on a folder is filed into it; one dropped on a page
    /// is placed just before that page. A tab dragged up from the list is not
    /// this drop — that gesture files the page on its own.
    private func take(_ providers: [NSItemProvider], into folder: Bookmark.ID?, before sibling: Bookmark.ID?) -> Bool {
        guard live, let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async {
                if let sibling {
                    // A page dropped on a page becomes a folder. Anything
                    // else — a folder onto a page — takes that page's place.
                    if self.bookmarks.combine(id, onto: sibling) == nil {
                        self.bookmarks.move(id, before: sibling)
                    }
                } else {
                    self.bookmarks.move(id, into: folder)
                    if let folder {
                        self.open.insert(folder)
                        for parent in self.bookmarks.ancestors(of: folder) { self.open.insert(parent) }
                    }
                }
            }
        }
        return true
    }

    private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 14 }

    private struct Line: View {
        let node: Bookmark
        let depth: Int
        let folder: Bool
        let opened: Bool
        let live: Bool
        let lit: Bool
        let act: () -> Void
        let close: (() -> Void)?
        let newFolder: (() -> Void)?
        let addPage: (() -> Void)?
        let canAdd: Bool
        let moveTargets: [(node: Bookmark, depth: Int)]
        let moveTo: (Bookmark.ID?) -> Void
        /// The space's colour, which its folders are drawn in.
        let tint: Int
        let remove: () -> Void
        let openNew: () -> Void
        let dropped: ([NSItemProvider]) -> Bool

        @State private var hovering = false
        @State private var over = false
        @Environment(\.colorScheme) private var scheme

        /// The same quiet as a tab you are not on. A folder stays readable;
        /// a page does not, until it is the one open.
        private var title: Color {
            if folder { return hovering ? Palette.ink : Palette.ink.opacity(0.9) }
            if live { return Palette.ink }
            return hovering ? Palette.ink : Palette.ink.opacity(0.78)
        }

        var body: some View {
            HStack(spacing: 8) {
                if folder {
                    FolderIcon(open: opened, tint: tint)
                } else {
                    Mark(
                        icon: Favicons.shared.cached(node.host ?? ""),
                        letter: String((node.host ?? "•").prefix(1)).uppercased(),
                        size: 15
                    )
                    .opacity(live ? 1 : 0.72)
                }
                Text(node.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if folder {
                    Image(systemName: opened ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.hush)
                }
            }
            .padding(.leading, SideBar.inset + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .frame(height: SideBar.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(live || lit ? SideTone.chip(scheme, strong: true) : (over && !folder ? SideTone.chip(scheme, strong: true) : (hovering && !opened ? SideTone.chip(scheme, strong: false) : Color.clear)))
            )
            .overlay(alignment: .leading) {
                // Dropping a page here makes a folder of the two. The icon
                // arrives while the pointer is still deciding.
                if over, !folder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .padding(.leading, 10)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .scaleEffect(over && !folder ? 1.035 : 1)
            .shadow(color: .black.opacity(over && !folder ? 0.12 : 0), radius: 8, y: 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
            .onDrag { NSItemProvider(object: node.id.uuidString as NSString) }
            .onDrop(of: [.text], isTargeted: $over, perform: dropped)
            .overlay(alignment: .trailing) {
                // A real view, not a SwiftUI button: the row's own tap was
                // winning the click, so the cross reopened the page it had
                // just closed. The target is the whole end of the row.
                if let close, hovering {
                    ZStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.quiet)
                            .frame(width: 15, height: 15)
                            .background(Palette.ink.opacity(0.07), in: Circle())
                            .allowsHitTesting(false)
                        BookmarkClose(act: close)
                            .frame(width: 32, height: SideBar.row)
                    }
                    .padding(.trailing, 4)
                }
            }
            .overlay {
                if let close { MiddleClick(act: close) }
            }
            .contextMenu {
                if !folder {
                    Button("Open", action: act)
                    Button("Open in New Tab", action: openNew)
                    if let close {
                        Button("Close", action: close)
                    }
                }
                if let addPage {
                    Button("Add This Page", action: addPage)
                        .disabled(!canAdd)
                }
                if let newFolder {
                    Button("New Folder", action: newFolder)
                }
                Menu("Move to") {
                    Button("Top Level") { moveTo(nil) }
                    if !moveTargets.isEmpty {
                        Divider()
                        ForEach(moveTargets, id: \.node.id) { target in
                            Button(String(repeating: "   ", count: target.depth) + target.node.title) {
                                moveTo(target.node.id)
                            }
                        }
                    }
                }
                Button("Remove", role: .destructive, action: remove)
            }
            .help(node.url ?? node.title)
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: opened)
            .animation(Motion.settle, value: over)
        }
    }
}

/// The cross on an open bookmark. An AppKit view is asked before the row's
/// SwiftUI tap, so the click closes the page and does not also open it.
private struct BookmarkClose: NSViewRepresentable {
    let act: () -> Void

    func makeNSView(context: Context) -> NSView { Catch(act: act) }
    func updateNSView(_ view: NSView, context: Context) { (view as? Catch)?.act = act }

    private final class Catch: NSView {
        var act: () -> Void
        init(act: @escaping () -> Void) {
            self.act = act
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .leftMouseDown || event.type == .leftMouseUp
            else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) { act() }
    }
}

/// The pinned squares' grid, every cell laid out at once. A lazy grid makes
/// its cells only once the column is on screen, where the column's slide
/// can't take them along: folded with ⌘S and brought back, the squares stood
/// in place while the column came in beneath them. A dozen squares need no
/// laziness.
private struct PinGrid: Layout {
    let columns: Int
    let width: CGFloat
    let height: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(
            width: CGFloat(columns) * width + CGFloat(max(0, columns - 1)) * spacing,
            height: CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % columns) * (width + spacing),
                    y: bounds.minY + CGFloat(index / columns) * (height + spacing)
                ),
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }
}

/// A pinned tab as a cell in the block at the top of the column — as wide as
/// its row asks for, but never taller than the classic square, so a row with
/// room to spare turns into a wide, short button rather than a bigger icon.
private struct PinSquare: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    var width: CGFloat = 34
    var height: CGFloat = 34

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    /// Everything drawn inside scales off the shorter edge — the one that
    /// stays put — so the glyph sits at its usual size, centred, rather than
    /// stretching to chase the width.
    private var scale: CGFloat { min(width, height) }

    var body: some View {
        Group {
            if browser.editingPin == tab.id {
                PinField(browser: browser, tab: tab)
            } else if prefs.glyph == .icons, let icon = tab.icon {
                Mark(icon: icon, letter: tab.pin ?? "", size: scale * 16 / 34, dim: tab.asleep)
            } else {
                Text(tab.pin ?? "")
                    .font(.system(size: scale * 12 / 34, weight: .medium))
                    .foregroundStyle((live ? Palette.ink : Palette.quiet).opacity(tab.asleep ? 0.45 : 1))
            }
        }
        .frame(width: scale * 16 / 34, height: scale * 16 / 34)
        .frame(width: width, height: height)
        .background {
            if live {
                RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                    .fill(SideTone.chip(scheme, strong: true))
                    .matchedGeometryEffect(id: "live", in: pill)
            } else {
                RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                    .fill(SideTone.chip(scheme, strong: false).opacity(hovering ? 1 : 0.7))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous))
        .modifier(OneClick(double: live) {
            if live { browser.editLetter(tab) } else { browser.select(tab) }
        })
        // Put down, like ⌘W: close() is what knows a pin isn't removed.
        .overlay { MiddleClick { browser.close(tab) } }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: { browser.close(tab) }) }
        .help(tab.label)
        .animation(Motion.quick, value: hovering)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// One tab, as a line in the column.
private struct SideRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    @State private var shake: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    private var editing: Bool { browser.editingTab == tab.id }

    /// The ring or the speaker, which stay for as long as the page loads or
    /// plays (or is muted) and so keep a place of their own at the end of the
    /// row. The cross is only there under the pointer, and takes none.
    private var status: Bool { !editing && (tab.loading || speaker) }
    /// The speaker, which can be pressed, and so steps in beside the cross
    /// under the pointer rather than hiding beneath it as the ring does.
    private var speaker: Bool { !tab.loading && (tab.noisy || tab.muted) }

    var body: some View {
        HStack(spacing: 8) {
            if editing {
                TabAddressField(browser: browser)
                    .frame(height: 16)
            } else {
                if prefs.glyph == .icons {
                    if tab.isBlank {
                        // Nothing to show yet, but the title still starts
                        // where every other row's does.
                        Image(systemName: "globe")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.hush)
                            .frame(width: 15, height: 15)
                    } else {
                        Mark(icon: tab.icon, letter: tab.monogram, size: 15)
                    }
                }
                if tab.bench {
                    // A script's tab, not yours.
                    Image(systemName: "flask")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                if tab.shy {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                Text(tab.label)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(colour)
            }

            if status {
                Spacer(minLength: 2)

                ZStack {
                    if tab.loading {
                        Ring().transition(.opacity)
                    } else {
                        Speaker(tab: tab).transition(.opacity)
                    }
                }
                .frame(width: 15, height: 15)
                // The cross takes this place while the pointer is here; the
                // speaker moves one place in, clear of the cross's reach.
                .opacity(hovering && !speaker ? 0 : 1)
                .padding(.trailing, hovering && speaker ? 23 : 0)
            }
        }
        .padding(.leading, SideBar.inset)
        .padding(.trailing, status ? 7 : 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The title keeps its length under the pointer and fades out
        // beneath the cross, rather than being cut shorter, so its end
        // doesn't jump on each row the pointer passes.
        .mask {
            ZStack {
                Rectangle().opacity(hovering && !editing && !status ? 0 : 1)
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                    Color.clear.frame(width: 26)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !editing {
                ZStack {
                    if hovering {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.quiet)
                            .frame(width: 15, height: 15)
                            .background(Palette.ink.opacity(0.07), in: Circle())
                            .transition(.opacity)
                    }
                }
                .frame(width: 15, height: 15)
                .overlay {
                    Color.clear
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture { if hovering { close() } }
                }
                .padding(.trailing, 7)
            }
        }
        .animation(Motion.quick, value: tab.loading)
        .animation(Motion.quick, value: speaker)
        .background { ground }
        .modifier(Shake(travel: shake))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .modifier(OneClick(double: false) {
            browser.select(tab)
        })
        .overlay { MiddleClick(act: close) }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.glide, value: editing)
        .onChange(of: browser.refusals) { _, _ in
            guard editing else { return }
            shake = 0
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
        }
        .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var ground: some View {
        if live {
            ZStack(alignment: .leading) {
                Rectangle().fill(SideTone.chip(scheme, strong: true))
                if prefs.showsReading {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Palette.ink.opacity(0.055))
                            .frame(width: geo.size.width * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .matchedGeometryEffect(id: "live", in: pill)
        } else if hovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(SideTone.chip(scheme, strong: false))
        }
    }

    private var colour: Color {
        if live { return Palette.ink }
        return hovering ? Palette.ink : Palette.ink.opacity(0.78)
    }
}

/// White on the space's colour: the tab you are on, and the row under the pointer.
private enum SideTone {
    static func chip(_ scheme: ColorScheme, strong: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(strong ? 0.16 : 0.08)
        }
        return Color.white.opacity(strong ? 0.94 : 0.34)
    }
}

/// The address, in the column, above the pins. At rest it is the site's name.
/// The link copies it; the other door is the page's own controls.
private struct SideAddress: View {
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
                AddressField(browser: browser, point: 12.5, prompt: browser.prefs.searchPrompt)
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
        .frame(minWidth: 240)
        .fixedSize()
    }
}

/// Every space, in the middle of the foot: its icon if it was given one,
/// otherwise a dot of its colour. The one on screen is lit; pressed again,
/// it opens the theme.
private struct SpaceStrip: View {
    @ObservedObject var browser: Browser
    @Binding var theming: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(browser.spaces) { space in
                Chip(space: space, on: space.id == browser.spaceID) {
                    if space.id == browser.spaceID {
                        theming = true
                    } else {
                        browser.switchSpace(to: space.id)
                    }
                }
                .contextMenu {
                    Button("Theme and Icon…") {
                        if browser.spaceID != space.id { browser.switchSpace(to: space.id) }
                        theming = true
                    }
                    Button("Rename…") {
                        Ask.name("Rename Space", placeholder: space.name, initial: space.name, confirm: "Rename") {
                            browser.renameSpace(space.id, to: $0)
                        }
                    }
                    if !space.isFirst {
                        Button("Delete…") {
                            Ask.sure("Delete “\(space.name)”?", detail: "Its tabs close, and its bookmarks, cookies and sign-ins are erased from this Mac. History stays.", confirm: "Delete") {
                                browser.deleteSpace(space.id)
                            }
                        }
                    }
                }
            }
        }
        .popover(isPresented: $theming, arrowEdge: .top) {
            ThemePicker(browser: browser).popGround()
        }
    }

    private struct Chip: View {
        let space: Space
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Group {
                if space.hasIcon {
                    SpaceGlyph(space: space, size: 11)
                        .foregroundStyle(on ? Palette.ink : Palette.quiet)
                        .opacity(on || hovering ? 1 : 0.7)
                } else {
                    Circle()
                        .fill(on ? Palette.ink.opacity(0.85) : Palette.ink.opacity(hovering ? 0.5 : 0.28))
                        .frame(width: on ? 7 : 6, height: on ? 7 : 6)
                }
            }
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Palette.veil : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
            .help(on ? "\(space.name) — theme and icon" : space.name)
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: on)
        }
    }
}

/// The space's colour, light or dark, and its icon: a symbol or an emoji.
private struct ThemePicker: View {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var scheme
    @State private var emoji = ""

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6)
    private let iconColumns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 7)

    private var space: Space { browser.space }

    /// The swatches in the tone the column will actually wear.
    private var showsDark: Bool { space.wearsDark(on: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(space.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)

            Picker("", selection: Binding(
                get: { space.tone ?? .auto },
                set: { browser.setSpaceTone(space.id, to: $0) }
            )) {
                ForEach(Space.Tone.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Auto follows the window. Light keeps the pastel on a dark window; Dark keeps the deep colour on a light one.")

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(Spaces.tints.enumerated()), id: \.offset) { index, tint in
                    let on = Spaces.clamp(space.colour) == index
                    Circle()
                        .fill(Spaces.swatch(index, dark: showsDark))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(Color.primary.opacity(on ? 0.85 : 0.12), lineWidth: on ? 2 : 1)
                        }
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                        .onTapGesture { browser.setSpaceColour(space.id, to: index) }
                        .help(tint.name)
                }
            }

            Divider()

            HStack {
                Text("Icon")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .onSubmit { browser.setSpaceEmoji(space.id, to: emoji) }
                    .onChange(of: emoji) { _, now in
                        // One character, taken as soon as it is typed or picked.
                        guard let first = now.trimmingCharacters(in: .whitespaces).first else { return }
                        if String(first) != space.emoji { browser.setSpaceEmoji(space.id, to: String(first)) }
                        if now.count > 1 { emoji = String(first) }
                    }
                Button {
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(.borderless)
                .help("Emoji & Symbols")
            }

            LazyVGrid(columns: iconColumns, spacing: 4) {
                cell(on: !space.hasIcon, help: "None — a dot") {
                    browser.setSpaceEmoji(space.id, to: "")
                    emoji = ""
                } label: {
                    Circle().fill(Palette.ink.opacity(0.6)).frame(width: 6, height: 6)
                }
                ForEach(Array(zip(Spaces.icons, Spaces.iconNames)), id: \.0) { symbol, name in
                    cell(on: space.icon == symbol, help: name) {
                        browser.setSpaceIcon(space.id, to: symbol)
                        emoji = ""
                    } label: {
                        Image(systemName: symbol).font(.system(size: 11.5))
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 236)
        .onAppear { emoji = space.emoji ?? "" }
    }

    private func cell<Label: View>(on: Bool, help: String, act: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        label()
            .foregroundStyle(on ? Palette.ink : Palette.muted)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? Palette.wash : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .help(help)
    }
}

/// The door at the foot's left: everything that is a panel of its own, and
/// the downloads — a ring round it while one is coming, and the shelf of
/// them opening from it when one starts.
private struct Library: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @State private var shelf = false

    var body: some View {
        Door(icon: "books.vertical", on: shelf, help: "Library — downloads, history, bookmarks, passwords") {
            PopMenu.show([
                ("Downloads", "arrow.down.circle", { shelf = true }),
                ("History", "clock", { browser.recalling = true }),
                ("Bookmarks", "bookmark", { browser.bookmarking = true }),
                ("Passwords", "key", { browser.managing = true }),
                nil,
                ("Extensions…", "puzzlepiece.extension", {
                    Store.settings.set("extensions", forKey: "settings.page")
                    browser.tuning = true
                }),
                ("Settings…", "gearshape", { browser.tuning = true }),
            ])
        }
        .overlay {
            if let haul = loot.hauls.first {
                HaulRing(haul: haul)
                    .frame(width: 24, height: 24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: loot.hauls.isEmpty)
        .popover(isPresented: $shelf, arrowEdge: .top) {
            DownloadsShelf(browser: browser, loot: loot) { shelf = false }.popGround()
        }
        // A download arriving says so where it will be found.
        .onChange(of: loot.hauls.count) { old, now in
            if now > old { shelf = true }
        }
    }
}

/// How far the newest download has come, drawn round the library's door.
private struct HaulRing: View {
    @ObservedObject var haul: Haul
    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: max(0.03, haul.fraction))
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: haul.fraction)
        }
    }
}

/// A menu popped up under the pointer. Nil in the list is a separator.
@MainActor
enum PopMenu {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static var actions: [Action] = []

    static func show(_ items: [(String, String, () -> Void)?]) {
        actions = []
        let menu = NSMenu()
        for entry in items {
            guard let (title, symbol, run) = entry else {
                menu.addItem(.separator())
                continue
            }
            let action = Action(run)
            actions.append(action)
            let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
            item.target = action
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// The downloads' shelf: what is still coming, then the last few kept.
private struct DownloadsShelf: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if loot.hauls.isEmpty && loot.kept.isEmpty {
                Text("Nothing downloaded yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                    .padding(12)
            }
            ForEach(loot.hauls) { haul in
                Coming(haul: haul)
            }
            ForEach(loot.kept.prefix(6)) { keep in
                Kept(keep: keep, loot: loot)
            }
            Divider().padding(.vertical, 4)
            Button {
                close()
                browser.hoarding = true
            } label: {
                Text("Show All Downloads")
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 280)
    }

    private struct Coming: View {
        @ObservedObject var haul: Haul
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(haul.name)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: haul.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
                Button { haul.cancel() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Stop")
            }
            .padding(8)
        }
    }

    private struct Kept: View {
        let keep: Keep
        let loot: Loot
        @State private var hovering = false
        var body: some View {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: keep.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                    .opacity(keep.stillThere ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(keep.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(keep.stillThere ? Palette.ink : Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(keep.from.isEmpty ? When.said(keep.date) : "\(keep.from) · \(When.said(keep.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if hovering, keep.stillThere {
                    Button { loot.reveal(keep) } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .help("Show in Finder")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Palette.wash : .clear))
            .contentShape(Rectangle())
            .onTapGesture { if keep.stillThere { loot.open(keep) } }
            .onHover { hovering = $0 }
        }
    }
}

/// A folder in the column, as Arc draws one: the outline in the theme's
/// colour with a pale wash of the same inside.
private struct FolderIcon: View {
    let open: Bool
    let tint: Int
    @Environment(\.colorScheme) private var scheme

    private var blue: Color { Spaces.accent(tint, dark: scheme == .dark) }

    var body: some View {
        ZStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(blue.opacity(open ? 0.32 : 0.2))
            Image(systemName: "folder")
                .foregroundStyle(blue)
        }
        .font(.system(size: 12.5, weight: .medium))
        .frame(width: 15, height: 15)
    }
}

/// The fine grain Arc lays over its colour, so a flat fill reads as a
/// surface. One small tile of noise, made once and repeated.
struct Grain: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: Grain.tile)
            .resizable(resizingMode: .tile)
            .opacity(scheme == .dark ? 0.05 : 0.07)
            .blendMode(scheme == .dark ? .plusLighter : .multiply)
            .allowsHitTesting(false)
    }

    private static let tile: NSImage = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(side * side) {
            // xorshift: the same grain every launch, and no cost to make.
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: rgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return NSImage() }
        // Two pixels to the point: a grain, not a gravel.
        return NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
    }()
}

/// A row that is an action rather than a page. Quiet until the pointer is on it.
struct Quiet: View {
    let icon: String
    let title: String
    var height: CGFloat = 28
    let act: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Palette.ink.opacity(0.8) : Palette.quiet)
            .padding(.leading, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? SideTone.chip(scheme, strong: false) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// The speaker at the end of a tab that plays sound, or that was muted and
/// so says it is: a press mutes the tab or lets it be heard again. Drawn as
/// it was before it could be pressed, with the cross's faint disc behind
/// it only while the pointer is on it.
struct Speaker: View {
    @ObservedObject var tab: Tab

    @State private var hovering = false

    var body: some View {
        Button(action: tab.toggleMute) {
            Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.quiet)
                .frame(width: 15, height: 15)
                .background(Palette.ink.opacity(hovering ? 0.07 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.muted ? "Unmute Tab" : "Mute Tab")
        .animation(Motion.quick, value: hovering)
    }
}

/// A small square holding one symbol. Lit when what it opens is open.
struct Door: View {
    let icon: String
    var on = false
    var help = ""
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.7) : Palette.quiet))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.veilStrong : (hovering ? Palette.veil : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: on)
    }
}
