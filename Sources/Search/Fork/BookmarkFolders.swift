import Foundation

// Fork: folders you make, and pages filed into them — by a drag onto a
// folder in the column, by a page dropped on another page, or from a tab's
// right-click. The tree and its file are upstream's; this only adds ways of
// changing it.

extension Bookmarks {
    /// A folder with nothing in it yet, at the top level or inside another.
    /// The name is whatever was typed; a blank one is still a folder you
    /// can find, called Folder.
    @discardableResult
    func makeFolder(_ title: String, into parent: Bookmark.ID? = nil) -> Bookmark {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return insert(.folder(name.isEmpty ? "Folder" : name, []), into: parent)
    }

    /// The page, at the end of the list. Nothing is asked: the title is the

    /// Files a page into a folder, or at the top of the list when the folder
    /// is nil. A page already kept is moved there: dragging it onto a folder
    /// is how it leaves the general list.
    @discardableResult
    func file(_ url: URL, title: String, into folderID: Bookmark.ID?) -> String {
        let name = folderID.flatMap(title(of:)) ?? "Bookmarks"
        if let existing = id(matching: url) {
            let place = place(of: existing)
            if place.found, place.parent == folderID {
                if let folderID { reveal = folderID }
                return "Already a bookmark"
            }
            move(existing, into: folderID)
            if let folderID { reveal = folderID }
            return folderID == nil ? "Moved to Bookmarks" : "Moved to \(name)"
        }
        let site = Bookmark.site(title, url)
        if let folderID {
            var nodes = roots
            if Bookmarks.place(site, in: folderID, at: nil, nodes: &nodes) {
                roots = nodes
                save()
                reveal = folderID
                return "Bookmarked in \(name)"
            }
        }
        roots.append(site)
        save()
        return "Bookmarked"
    }

    fileprivate func id(matching url: URL) -> Bookmark.ID? {
        func walk(_ nodes: [Bookmark]) -> Bookmark.ID? {
            for node in nodes {
                if node.url == url.absoluteString { return node.id }
                if let kids = node.children, let found = walk(kids) { return found }
            }
            return nil
        }
        return walk(roots)
    }

    fileprivate func title(of id: Bookmark.ID) -> String? {
        func walk(_ nodes: [Bookmark]) -> String? {
            for node in nodes {
                if node.id == id { return node.title }
                if let kids = node.children, let found = walk(kids) { return found }
            }
            return nil
        }
        return walk(roots)
    }

    /// Where a bookmark sits. `found` is false when the id isn't in this list;
    /// a nil parent is the top level.
    fileprivate func place(of id: Bookmark.ID) -> (parent: Bookmark.ID?, found: Bool) {
        func walk(_ nodes: [Bookmark], parent: Bookmark.ID?) -> (Bookmark.ID?, Bool)? {
            for node in nodes {
                if node.id == id { return (parent, true) }
                if let kids = node.children, let found = walk(kids, parent: node.id) { return found }
            }
            return nil
        }
        if let found = walk(roots, parent: nil) { return found }
        return (nil, false)
    }

    /// The folders that contain this one, outermost first, so opening it
    /// also opens the ones it is filed under.
    func ancestors(of id: Bookmark.ID) -> [Bookmark.ID] {
        var chain: [Bookmark.ID] = []
        func walk(_ nodes: [Bookmark], parents: [Bookmark.ID]) -> Bool {
            for node in nodes {
                if node.id == id {
                    chain = parents
                    return true
                }
                if let kids = node.children, walk(kids, parents: parents + [node.id]) { return true }
            }
            return false
        }
        _ = walk(roots, parents: [])
        return chain
    }
    /// Puts a bookmark just before another one, in that one's folder — how a
    /// row dropped onto a row finds its place among the list.
    func move(_ id: Bookmark.ID, before sibling: Bookmark.ID) {
        guard id != sibling else { return }
        var working = roots
        guard let node = Bookmarks.detach(id, from: &working) else { return }
        guard Bookmarks.insert(node, before: sibling, nodes: &working) else { return }
        roots = working
        save()
    }

    /// Use the destination's siblings, so the same operation also takes a
    /// bookmark out of a folder or into another one without losing its tab.
    func move(_ id: Bookmark.ID, beside target: Bookmark.ID, after: Bool) {
        guard id != target, let place = path(to: target) else { return }
        let parent = place.last?.id
        let siblings = parent.flatMap { node($0)?.children } ?? roots
        guard let index = siblings.firstIndex(where: { $0.id == target }) else { return }
        move(id, into: parent, at: index + (after ? 1 : 0))
    }

    func adjacent(to id: Bookmark.ID, offset: Int) -> Bookmark.ID? {
        guard let place = path(to: id) else { return nil }
        let siblings = place.last?.children ?? roots
        guard let index = siblings.firstIndex(where: { $0.id == id }),
              siblings.indices.contains(index + offset) else { return nil }
        return siblings[index + offset].id
    }

    /// Two pages dropped one on the other become a folder, where the one
    /// underneath was sitting. A folder dropped on a page is not this: that
    /// one just moves.
    @discardableResult
    func combine(_ dragged: Bookmark.ID, onto target: Bookmark.ID) -> Bookmark.ID? {
        guard dragged != target else { return nil }
        guard let coming = node(dragged), !coming.isFolder,
              let kept = node(target), !kept.isFolder else { return nil }
        let parent = place(of: target).parent
        var working = roots
        guard Bookmarks.detach(dragged, from: &working) != nil,
              let index = Bookmarks.index(of: target, parent: parent, in: working),
              Bookmarks.detach(target, from: &working) != nil
        else { return nil }
        let folder = Bookmark.folder("Folder", [kept, coming])
        guard Bookmarks.insert(folder, into: parent, at: index, nodes: &working) else { return nil }
        roots = working
        save()
        reveal = folder.id
        return folder.id
    }

    func node(_ id: Bookmark.ID) -> Bookmark? {
        func walk(_ nodes: [Bookmark]) -> Bookmark? {
            for node in nodes {
                if node.id == id { return node }
                if let kids = node.children, let found = walk(kids) { return found }
            }
            return nil
        }
        return walk(roots)
    }

    // parent(of:) is upstream's, in Bookmarks.swift.

    /// Puts `node` at `index` among a folder's children, or at the top of the
    /// list when `parent` is nil.
    @discardableResult
    fileprivate static func insert(_ node: Bookmark, into parent: Bookmark.ID?, at index: Int, nodes: inout [Bookmark]) -> Bool {
        if parent == nil {
            nodes.insert(node, at: min(max(0, index), nodes.count))
            return true
        }
        for i in nodes.indices {
            if nodes[i].id == parent, nodes[i].isFolder {
                var kids = nodes[i].children ?? []
                kids.insert(node, at: min(max(0, index), kids.count))
                nodes[i].children = kids
                return true
            }
            guard nodes[i].children != nil else { continue }
            var kids = nodes[i].children!
            if insert(node, into: parent, at: index, nodes: &kids) {
                nodes[i].children = kids
                return true
            }
        }
        return false
    }

    fileprivate static func index(of id: Bookmark.ID, parent: Bookmark.ID?, in nodes: [Bookmark]) -> Int? {
        if parent == nil { return nodes.firstIndex { $0.id == id } }
        for node in nodes {
            if node.id == parent { return node.children?.firstIndex { $0.id == id } }
            if let kids = node.children, let found = index(of: id, parent: parent, in: kids) { return found }
        }
        return nil
    }

    /// Inserts `node` immediately before `sibling`. Fails when the sibling
    /// was inside `node` and left with it, which is also what keeps a folder
    /// from being dropped into itself.
    @discardableResult
    fileprivate static func insert(_ node: Bookmark, before sibling: Bookmark.ID, nodes: inout [Bookmark]) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == sibling {
                nodes.insert(node, at: i)
                return true
            }
            guard nodes[i].children != nil else { continue }
            var kids = nodes[i].children!
            if insert(node, before: sibling, nodes: &kids) {
                nodes[i].children = kids
                return true
            }
        }
        return false
    }
}

extension Browser {
    /// The page, filed into a folder — or at the top of the list when the
    /// folder is nil. One already kept is moved, so a drag onto a folder
    /// takes it out of the general list.
    func file(_ tab: Tab, into folder: Bookmark.ID?) {
        guard let url = tab.address, !tab.isBlank else { return }
        announce(bookmarks.file(url, title: tab.title, into: folder))
    }
}
