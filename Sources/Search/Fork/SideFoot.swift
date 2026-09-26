import SwiftUI
import AppKit
import WebKit

// Fork: the column's foot, as in Arc — the library at the left (downloads,
// with a ring while one is coming, then history, bookmarks, passwords,
// extensions and settings), every space in the middle, and a new space at
// the right. The space on screen, pressed again, opens its theme.

/// A download still coming: its name once WebKit has one, and how far along.
@MainActor
final class Haul: ObservableObject, Identifiable {
    let id = UUID()
    let download: WKDownload
    @Published var name = "Download"
    @Published var fraction: Double = 0
    private var watch: NSKeyValueObservation?

    init(_ download: WKDownload) {
        self.download = download
        watch = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let through = progress.fractionCompleted
            Task { @MainActor in self?.fraction = through }
        }
    }

    func cancel() { download.cancel { _ in } }
}

extension Loot {
    func start(_ download: WKDownload) {
        guard !hauls.contains(where: { $0.download === download }) else { return }
        hauls.insert(Haul(download), at: 0)
    }

    func name(_ download: WKDownload, _ name: String) {
        hauls.first { $0.download === download }?.name = name
    }

    func end(_ download: WKDownload) {
        hauls.removeAll { $0.download === download }
    }
}

/// Every space, in the middle of the foot: its icon if it was given one,
/// otherwise a dot of its colour. The one on screen is lit; pressed again,
/// it opens the theme.
struct SpaceStrip: View {
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
struct ThemePicker: View {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var scheme
    @State private var emoji = ""

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6)
    private let iconColumns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 7)

    private var space: Space { browser.space }

    /// The swatches in the tone the column will actually wear.
    private var shownDepth: CGFloat { space.depth(on: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(space.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)

            // The app's own control, sharing the card's width evenly: the
            // system's segments are sized to their words, and five of them
            // ran past both edges of the card.
            Segmented(
                options: Space.Tone.allCases.map { ($0, $0.title) },
                selection: Binding(
                    get: { space.tone ?? .auto },
                    set: { browser.setSpaceTone(space.id, to: $0) }
                ),
                wide: true
            )
            .frame(maxWidth: .infinity)
            .help("Auto follows the window. Light and Dark keep the pastel or the deep colour whatever the window; Soft and Deep are the two in between.")

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(Spaces.tints.enumerated()), id: \.offset) { index, tint in
                    let on = Spaces.clamp(space.colour) == index
                    Circle()
                        .fill(Spaces.swatch(index, depth: shownDepth))
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
struct Library: View {
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
