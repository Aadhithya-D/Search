import SwiftUI
import UniformTypeIdentifiers

// Fork: bookmarks in the column, between the pins and the tabs, as Arc keeps
// them — under the space's name, in folders that open downward, each page
// its own tab when clicked (Fork/BookmarkPages.swift). A tab dragged over a
// folder files the page there; bookmarks are dragged among themselves.

/// Where a tab drag is hovering in the bookmarks, so the folder under the
/// hand can light up without the column redrawing the tab it is carrying.
@MainActor
final class DropAim: ObservableObject {
    struct Mark: Equatable {
        var folder: Bookmark.ID?
        var root = false
    }

    @Published var mark = Mark()
}

/// A bookmark row's place in the column, so a tab let go over it can be filed
/// there. A nil id is the list itself.
struct MarkSpot: Equatable {
    var id: Bookmark.ID?
    var folder: Bool
    var rect: CGRect
}

struct MarkSpotsKey: PreferenceKey {
    static var defaultValue: [MarkSpot] = []
    static func reduce(value: inout [MarkSpot], nextValue: () -> [MarkSpot]) {
        value.append(contentsOf: nextValue())
    }
}

extension SideBar {
    /// The space's name over its bookmarks.
    static let section: CGFloat = 26
    static let ruleHeight: CGFloat = 1 + 16

    /// The space's name over its bookmarks, with its icon when it has one.
    /// Its first letter lines up with the icons of the rows beneath it.
    func section(_ space: Space?) -> some View {
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

    /// The hairline between the space's bookmarks and its loose tabs, as Arc
    /// draws it.
    var rule: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, SideBar.inset)
            .padding(.vertical, 8)
    }

    func newFolder(into parent: Bookmark.ID?) {
        Ask.name("New Folder", placeholder: "Name", confirm: "Create") { title in
            let made = bookmarks.makeFolder(title, into: parent)
            if let parent { foldersOpen.insert(parent) }
            foldersOpen.insert(made.id)
        }
    }

    // MARK: - filing a tab into the bookmarks

    /// The folder under the pointer, or the list itself when the pointer is
    /// over the bookmarks but not inside a folder.
    func mark(at point: CGPoint) -> DropAim.Mark {
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

    static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    func filing(_ tab: Tab) -> some Gesture {
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
    func relocate(_ providers: [NSItemProvider], into folder: Bookmark.ID?) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { self.bookmarks.move(id, into: folder) }
        }
        return true
    }
}

/// Bookmarks, in the column: folders that open downward, and the pages filed
/// in them. The same tree as the menu and the manager, drawn as rows so it
/// can sit between the pins and the tabs.
struct SideMarks: View {
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
