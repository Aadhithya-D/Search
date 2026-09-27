import SwiftUI

/// The tabs, down either side instead of across the top.
///
/// The same pieces as the strip — the grey that slides to the tab you picked,
/// the pinned squares, the cross that appears under the pointer — laid out the
/// other way. The traffic lights keep their corner; the column starts under
/// them and the page takes the whole height beside it.
struct SideBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var bookmarks: Bookmarks
    /// Out over the page from the window's edge, as a card of its own
    /// rather than the column beside the page (Fork/FoldedColumn.swift).
    var floating = false

    @Environment(\.colorScheme) private var windowScheme
    @Namespace private var pill

    @State private var landing = false
    @State private var onEdge = false

    /// A pin, picked up out of the grid — a separate state from the loose
    /// rows above, since the two gestures never happen at once but move on
    /// two different axes.
    /// The neighbouring spaces' own grey, apart from this one's.
    @Namespace private var before
    @Namespace private var after

    @State private var pinDragging: Tab.ID?
    @State private var groupFrames: [UUID: CGRect] = [:]
    @State private var pinFrom = 0
    @State private var pinTravel: CGSize = .zero

    // Fork: the bookmarks in the column (Fork/SideMarks.swift).
    /// Folders the column has opened.
    /// Kept by the bookmarks, not the view: the column that slides out
    /// over the page is a new view each time, and every space its own list.
    var foldersOpen: Set<Bookmark.ID> {
        get { bookmarks.opened }
        nonmutating set { bookmarks.opened = newValue }
    }
    var openFolders: Binding<Set<Bookmark.ID>> {
        Binding(get: { bookmarks.opened }, set: { bookmarks.opened = $0 })
    }
    /// Bookmark rows, measured in the column, for a tab dropped onto one.
    @State var spots: [MarkSpot] = []
    @State private var overSection = false
    /// Held as state, not observed here: the folder lighting up must not
    /// redraw the tab under the hand, or the drag would be dropped.
    @State var aim = DropAim()
    /// The neighbouring space's list is drawn too, and must not light up
    /// when this space's drag passes a folder.
    @State private var idleAim = DropAim()
    /// Fork: the spaces whose bookmarks are folded under their name.
    @State var marksFolded: Set<UUID> = SideBar.foldedMarks()
    /// The theme, open off the space on screen (Fork/SideFoot.swift).
    @State private var theming = false

    static let row: CGFloat = 28
    static let gap: CGFloat = 2
    private static let square: CGFloat = 34
    private static let pinGap: CGFloat = 6

    private var onRight: Bool { prefs.sidePosition == .right }
    private var innerEdge: Alignment { onRight ? .leading : .trailing }

    var body: some View {
        ZStack(alignment: .top) {
            // Not under the card for a new space: it isn't made of views that
            // would take the click first.
            DragStrip(reserved: 0, below: browser.makingSpace ? .greatestFiniteMagnitude : rowsEnd, onDoubleClick: browser.newTab)

            // The band the lights sit in is this mode's title bar: the window
            // is dragged by it and a double-click fills the screen with it.
            // The lights and the doors at the other end are views of their
            // own and answer first.
            HStack(spacing: 0) {
                DragStrip()
                    .frame(width: 10 + Metrics.sideLights)
                DragStrip()
            }
            .frame(height: SideBar.topRow)

            VStack(alignment: .leading, spacing: 0) {
                // Fork: the traffic lights' corner, with back, forward and
                // reload at the end of the same line, and the address as the
                // row under them (Fork/SideAddress.swift).
                HStack(spacing: 2) {
                    Color.clear.frame(width: Metrics.sideLights)
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
                .frame(width: prefs.sideWidth - 20, height: SideBar.topRow)

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
        // Fork: the space's own colour, grained (Fork/ColumnColour.swift).
        .background {
            ZStack {
                Spaces.ground(browser.space)
                Grain()
            }
        }
        .overlay(alignment: innerEdge) { if !floating { edge } }
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
        // Fork: the cursor, the drag and the double-click are a real view's
        // (Fork/ColumnEdge.swift); the hairline is drawn under it.
        Rectangle()
            .fill(Palette.ink.opacity(onEdge ? 0.18 : 0))
            .frame(width: onEdge ? 2 : 1)
            .frame(width: 10)
            .allowsHitTesting(false)
            .overlay {
                ColumnEdge(
                    right: onRight,
                    width: { prefs.sideWidth },
                    resize: { wanted in
                        // Pulled well past its narrowest, the column folds
                        // away, as ⌘S does, and keeps the width it had.
                        if wanted < Metrics.sideMin - 60 {
                            guard !browser.folded else { return }
                            browser.peeking = false
                            withAnimation(Motion.glide) { browser.folded = true }
                            return
                        }
                        prefs.sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, wanted))
                    },
                    reset: { withAnimation(Motion.settle) { prefs.sideWidth = Metrics.side } },
                    hover: { onEdge = $0 }
                )
            }
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
                    // A row too long for the window scrolls between the pins
                    // and the foot, rather than running under the lights at one
                    // end and the foot at the other. While it fits it stays a
                    // plain stack, and the space under it is still the
                    // window's to be dragged by. Inside the page: the swipe
                    // between spaces moves the page, scroll and all.
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
        let rest = row.tabs.filter { $0.pin == nil && $0.bookmark == nil }  // Fork: Fork/BookmarkPages.swift
        let cells = pinCells(pins.count)
        return VStack(alignment: .leading, spacing: 0) {
            if !pins.isEmpty {
                VStack(spacing: 0) {
                    PinGrid(cells: cells) {
                        ForEach(Array(pins.enumerated()), id: \.element.id) { index, tab in
                            PinSquare(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active,
                                      pill: pill, width: cells[index].width, height: cells[index].height)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            section(browser.spaces.first { $0.id == space }, live: false)
            if !marksFolded.contains(space) {
                SideMarks(
                    browser: browser, bookmarks: bookmarks, open: openFolders, aim: idleAim,
                    tree: bookmarks.nodes(in: space),
                    tabs: row.tabs, active: row.active,
                    colour: browser.spaces.first { $0.id == space }?.colour
                )
            }
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
        let pinBlock = pins == 0 ? 0 : (pinCells(pins).map(\.maxY).max() ?? 0) + 10
        let count = prefs.usesTabGroups
            ? browser.tabs(in: nil).count + browser.tabGroups.reduce(0) { $0 + browser.visibleTabs(in: $1).count }
            : browser.rowTabs.count - pins
        let headings = prefs.usesTabGroups ? CGFloat(browser.tabGroups.count) * (GroupHeading.height + SideBar.gap) : 0
        let loose = CGFloat(count) * (SideBar.row + SideBar.gap) + headings
        // Fork: the lights, the address, the space's name, the bookmark rows,
        // New Tab, and the loose tabs (Fork/SideAddress.swift, Fork/SideMarks.swift).
        let marks = marksFolded.contains(browser.spaceID) ? 0
            : CGFloat(SideMarks.count(bookmarks.roots, open: foldersOpen, empty: bookmarks.isEmpty)) * (SideBar.row + SideBar.gap)
        return SideBar.topRow + SideAddress.block + pinBlock + SideBar.section + marks + SideBar.ruleHeight + loose + (SideBar.row + SideBar.gap) + 16
    }

    // MARK: - the pinned squares

    private var pinnedTabs: [Tab] { browser.tabs.filter { $0.pin != nil } }
    private var looseTabs: [Tab] {
        // Fork: a bookmark's page isn't a loose tab (Fork/BookmarkPages.swift).
        browser.tabs.filter { $0.pin == nil && $0.bookmark == nil && (!prefs.usesTabGroups || browser.group(of: $0) == nil) }
    }

    /// How many squares go in each row: at most four — fewer only when the
    /// column is too narrow for four of the classic width — and as even as
    /// they go, the fuller rows first. Five are three and two, seven four
    /// and three, nine three, three and three, ten four, three and three.
    /// Up to three stay the one row of three places they always were, with
    /// a place or two empty rather than a lonely button the column's width.
    static func pinRows(_ count: Int, most: Int) -> [Int] {
        guard count > 0 else { return [] }
        let most = max(1, most)
        let rows = (count + most - 1) / most
        let base = count / rows
        let extra = count % rows
        return (0..<rows).map { $0 < extra ? base + 1 : base }
    }

    /// Where each square goes, in the order of the row. Each row splits the
    /// column's width between its own squares — the row fills edge to edge,
    /// not each cell on its own — and every row is as tall as the narrowest
    /// cell allows, never taller than the classic square: past that a cell
    /// turns into a wide, short button rather than a bigger icon.
    private func pinCells(_ count: Int) -> [CGRect] {
        let room = prefs.sideWidth - 20
        let gap = SideBar.pinGap
        let fits = Int((room + gap) / (SideBar.square + gap))
        let rows = SideBar.pinRows(count, most: min(4, max(1, fits)))
        // A row of fewer than three keeps three places.
        let slots = rows.map { rows.count == 1 ? max($0, min(3, fits)) : $0 }
        let widths = slots.map { max(20, (room - CGFloat($0 - 1) * gap) / CGFloat($0)) }
        let height = min(SideBar.square, widths.min() ?? SideBar.square)
        var cells: [CGRect] = []
        for (row, n) in rows.enumerated() {
            for col in 0..<n {
                cells.append(CGRect(x: CGFloat(col) * (widths[row] + gap),
                                    y: CGFloat(row) * (height + gap),
                                    width: widths[row], height: height))
            }
        }
        return cells
    }

    /// The grid itself: fixed-size cells, left-aligned, so a half-empty last
    /// row holds its ground rather than stretching to fill it.
    private var pinned: some View {
        let tabs = pinnedTabs
        let cells = pinCells(tabs.count)
        // Measured in the grid's own space, not the square's: a square that
        // has just been moved to a new cell would otherwise report the drag
        // from where it now is, the target would jump back, and the square
        // would shuttle between two cells for as long as the finger stayed.
        return VStack(spacing: 0) { PinGrid(cells: cells) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let held = pinDragging == tab.id
                PinSquare(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    width: cells[index].width,
                    height: cells[index].height
                )
                .offset(pinOffset(held: held, index: index, cells: cells))
                // Under the hand exactly, as a row is (see the rows below).
                .transaction { if held { $0.animation = nil } }
                .zIndex(held ? 1 : 0)
                .shadow(color: .black.opacity(held ? 0.16 : 0), radius: 10, y: 3)
                .gesture(pinReorder(tab: tab, index: index, cells: cells))
            }
        } }
        .coordinateSpace(name: "pins")
    }

    /// The one square actually held stays glued to the fingers; every other
    /// square is already exactly where it belongs, because `browser.move`
    /// put it there — this only cancels out the bit of that same movement
    /// the held square already got for free by changing index underneath
    /// its own drag.
    private func pinOffset(held: Bool, index: Int, cells: [CGRect]) -> CGSize {
        guard held, cells.indices.contains(pinFrom), cells.indices.contains(index) else { return .zero }
        let from = cells[pinFrom], now = cells[index]
        return CGSize(
            width: pinTravel.width - (now.midX - from.midX),
            height: pinTravel.height - (now.midY - from.midY)
        )
    }

    /// The cell the held square is over: the one whose centre is nearest to
    /// where the fingers have taken the square's own centre. Rows of
    /// different lengths have cells of different widths, so a count of
    /// steps along one axis would land in the wrong one.
    private func pinTarget(cells: [CGRect]) -> Int {
        guard cells.indices.contains(pinFrom) else { return 0 }
        let start = cells[pinFrom]
        let point = CGPoint(x: start.midX + pinTravel.width, y: start.midY + pinTravel.height)
        func distance(_ cell: CGRect) -> CGFloat { hypot(cell.midX - point.x, cell.midY - point.y) }
        return cells.indices.min { distance(cells[$0]) < distance(cells[$1]) } ?? pinFrom
    }

    /// Pick a square up and the others make way — across a row, and down
    /// into the next, exactly as far as the fingers actually moved.
    private func pinReorder(tab: Tab, index: Int, cells: [CGRect]) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("pins"))
            .onChanged { value in
                if pinDragging != tab.id {
                    pinDragging = tab.id
                    pinFrom = index
                }
                pinTravel = value.translation
                let target = pinTarget(cells: cells)
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

    // MARK: - the rows

    private var loose: some View {
        VStack(spacing: SideBar.gap) {
            if prefs.usesTabGroups {
                ForEach(browser.tabGroups) { group in
                    GroupHeading(browser: browser, group: group, dragSpace: "rows")
                    groupRows(group)
                }
            }
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
                .modifier(Carried(index: index, count: looseTabs.count, step: step, vertical: true,
                                  space: "rows", onDrop: { point in drop(tab, at: point) },
                                  outside: { browser.dragOut(tab) }) {
                    if prefs.usesTabGroups {
                        browser.move(tab, within: nil, to: $0)
                    } else {
                        browser.move(tab, to: $0 + browser.pinnedCount)
                    }
                })
                // The reorder above keeps the row under the hand. This one
                // only watches where the hand is, and files the page when
                // that place is a bookmark folder.
                .simultaneousGesture(filing(tab))
            }
        }
        .coordinateSpace(name: "rows")
        .onPreferenceChange(GroupDropFrames.self) { groupFrames = $0 }
    }

    private func drop(_ tab: Tab, at point: CGPoint) {
        guard prefs.usesTabGroups, tab.pin == nil else { return }
        if let id = groupFrames.first(where: { $0.value.contains(point) })?.key {
            browser.move(tab, toGroup: id)
        }
    }

    private func groupRows(_ group: TabGroup) -> some View {
        let members = browser.visibleTabs(in: group)
        return VStack(spacing: SideBar.gap) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, tab in
                SideRow(browser: browser, prefs: prefs, tab: tab,
                        live: tab.id == browser.activeID, pill: pill,
                        close: { browser.close(tab) })
                    .padding(.leading, 14)
                    .modifier(Carried(index: index, count: members.count,
                                      step: SideBar.row + SideBar.gap, vertical: true,
                                      space: "rows", onDrop: { point in drop(tab, at: point) },
                                      outside: { browser.dragOut(tab) }) {
                        browser.move(tab, within: group.id, to: $0)
                    })
            }
        }
    }

    /// Bookmarks, then the tabs, under the space's name. They scroll as one
    /// once the column is full; the pins stay above them.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            section(browser.space)
                .onDrop(of: [.text], isTargeted: $overSection) { providers in relocate(providers, into: nil) }
                .contextMenu {
                    Button("New Folder") { newFolder(into: nil) }
                    Button("Theme…") { theming = true }
                }
            if !marksFolded.contains(browser.spaceID) {
                SideMarks(browser: browser, bookmarks: bookmarks, open: openFolders, aim: aim)
                    .transition(.opacity)
            }
            rule
            newTab
            loose
        }
    }

    /// The foot's door and its margin beneath.
    private static let footHeight: CGFloat = 26 + 12

    private var newTab: some View {
        Quiet(icon: "plus", title: "New Tab", height: SideBar.row) { browser.newTab() }
            .padding(.top, SideBar.gap)
    }

    /// One small door at the bottom: the settings.
    private var foot: some View {
        // Fork: see Fork/SideFoot.swift.
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

/// The pinned squares' grid, every cell laid out at once. A lazy grid makes
/// its cells only once the column is on screen, where the column's slide
/// can't take them along: folded with ⌘S and brought back, the squares stood
/// in place while the column came in beneath them. A dozen squares need no
/// laziness.
private struct PinGrid: Layout {
    /// Each square's place, worked out by the column (see pinCells).
    let cells: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: cells.map(\.maxX).max() ?? 0, height: cells.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() where cells.indices.contains(index) {
            let cell = cells[index]
            subview.place(
                at: CGPoint(x: bounds.minX + cell.minX, y: bounds.minY + cell.minY),
                proposal: ProposedViewSize(width: cell.width, height: cell.height)
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
            } else if tab.loading {
                // Its page on the way, as a row's ring says.
                Ring(size: scale * 11 / 34)
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
                // Darker than the resting squares' grey by as much as a live
                // row is darker than the white it sits on (Drice: the live
                // pin barely showed among the others).
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
            if live { browser.goHome(tab) } else { browser.select(tab) }
        })
        // Put down, like ⌘W: close() is what knows a pin isn't removed.
        .overlay { MiddleClick { browser.close(tab) } }
        .onHover { hovering = $0; TabPreview.hover(tab, over: $0, in: browser) }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: { browser.close(tab) }) }
        // The preview names it (Fork/TabPreview.swift); a tooltip on top of it
        // said the same over the card.
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
        // Fork: the tab's preview beside the column (Fork/TabPreview.swift).
        .onHover { hovering = $0; TabPreview.hover(tab, over: $0, in: browser) }
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
                        ReadingFill(meter: tab.meter, width: geo.size.width)
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
