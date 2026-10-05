import SwiftUI
import UniformTypeIdentifiers

enum BookmarkLanding: Equatable {
    case before, inside, after
}

/// The edges of a row reorder; the middle of a folder files into it.
/// Keeping the destination until the drop also makes its insertion line stable.
struct BookmarkRowDrop: DropDelegate {
    let folder: Bool
    let height: CGFloat
    @Binding var landing: BookmarkLanding?
    let take: ([NSItemProvider], BookmarkLanding) -> Bool

    private func destination(_ info: DropInfo) -> BookmarkLanding {
        if folder && info.location.y >= height * 0.25 && info.location.y <= height * 0.75 { return .inside }
        return info.location.y < height * 0.5 ? .before : .after
    }

    func dropEntered(info: DropInfo) { landing = destination(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        landing = destination(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { landing = nil }
    func performDrop(info: DropInfo) -> Bool {
        let destination = destination(info)
        landing = nil
        return take(info.itemProviders(for: [.text]), destination)
    }
}
