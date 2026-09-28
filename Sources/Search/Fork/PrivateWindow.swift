import SwiftUI
import WebKit

// Fork: ⇧⌘N opens a private window, as Chrome's incognito one. Every tab in
// it is private and shares one store of its own, gone when the window
// closes; nothing of it is saved, reopened or pinned. Its column is black,
// with no bookmarks, pins or spaces: New Tab, the tabs, and one incognito
// mark at the foot. It keeps the space it was opened from for its settings,
// and the extensions run in it.

enum PrivateWindow {
    /// Read by the Browser being made (`Browser.isPrivate`).
    @MainActor static var opening = false

    /// Stands in for the space in a private window's column.
    static let spaceID = UUID(uuidString: "00000000-0000-0000-0000-00000000B1AC")!

    @MainActor static func open(from browser: Browser) {
        opening = true
        let fresh = Browser(record: WindowRecord(space: browser.spaceID))
        opening = false
        Browsers.open(fresh, frame: nil)
    }

    static func stands(for space: Space) -> Bool { space.id == spaceID }
}

extension Browser {
    /// The space as the column wears it: black, for a private window.
    var privateSpace: Space {
        var black = Space(id: PrivateWindow.spaceID, name: "Private", colour: 0, icon: nil, sharesSignIns: nil)
        black.tone = .dark
        return black
    }

    /// A private tab of this window: its store, and the extensions.
    func privateTab() -> Tab {
        Tab(shy: true, configuration: Web.configuration(shy: false, store: privateStore))
    }

    /// The window's first page, instead of a session.
    func startPrivate() {
        let tab = privateTab()
        prepare(tab)
        insert(tab, at: 0)
        activeID = tab.id
        editing = true
    }
}

/// The foot of a private window's column: its one mark.
struct PrivateFoot: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 14, weight: .medium))
            Text("Private")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity)
        .help("A private window: nothing in it is kept")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private window")
    }
}
