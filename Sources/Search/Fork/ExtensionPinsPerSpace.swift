import Foundation

// Fork: an extension pinned in one space is pinned in that space alone. Each
// space keeps its own list of pinned extensions; a space that has never had
// one changed shows what was pinned before there were lists per space (the
// installed list's own `pinned`), and the first pin or unpin there starts
// its list from that.

@available(macOS 15.4, *)
extension Extensions {
    private static let key = "extensions.pins.bySpace"

    private var pinsBySpace: [String: [String]] {
        get { Store.settings.dictionary(forKey: Self.key) as? [String: [String]] ?? [:] }
        set { Store.settings.set(newValue, forKey: Self.key) }
    }

    /// Pinned in the space of the window in front.
    func isPinned(_ item: Installed) -> Bool {
        if let list = pinsBySpace[Spaces.current.uuidString] { return list.contains(item.id) }
        return item.pinned ?? false
    }

    func isPinned(_ id: String) -> Bool {
        installed.first { $0.id == id }.map(isPinned) ?? false
    }

    /// Pinned or not in the space in front only.
    func pinHere(_ id: String, _ on: Bool) {
        let space = Spaces.current.uuidString
        var map = pinsBySpace
        var list = map[space] ?? installed.filter { $0.pinned ?? false }.map(\.id)
        list.removeAll { $0 == id }
        if on { list.append(id) }
        // Only what is still installed.
        map[space] = list.filter { id in installed.contains { $0.id == id } }
        pinsBySpace = map
    }
}
