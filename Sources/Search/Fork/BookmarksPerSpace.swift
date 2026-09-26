import Foundation

// Fork: each space keeps its own bookmarks. The file holds one list per
// space, keyed by the space's id; `roots` is always the list on screen. An
// older file — one list for everybody — stays with the space that is on
// screen the first time it is read.

extension Bookmarks {
    /// The list a space keeps. The one on screen is `roots`.
    func nodes(in id: UUID) -> [Bookmark] {
        id == space ? roots : (trees[id] ?? [])
    }

    /// Another space is on screen. Its list comes up; the one leaving is kept.
    func use(_ id: UUID) {
        if carried {
            carried = false
            trees = [id: roots]
            space = id
            save()
            return
        }
        guard id != space else { return }
        trees[space] = roots
        space = id
        roots = trees[id] ?? []
    }

    /// A space is gone, and so is its list.
    func forget(_ id: UUID) {
        guard id != Space.firstID else { return }
        trees[id] = nil
        if space == id {
            space = Space.firstID
            roots = trees[space] ?? []
        }
        save()
    }

    /// Every id in the list on screen, so a page filed under a bookmark from
    /// another space can go back to being an ordinary tab.
    var identifiers: Set<Bookmark.ID> {
        var ids = Set<Bookmark.ID>()
        func walk(_ nodes: [Bookmark]) {
            for node in nodes {
                ids.insert(node.id)
                if let kids = node.children { walk(kids) }
            }
        }
        walk(roots)
        return ids
    }
}
