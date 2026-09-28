import SwiftUI

// Fork: an empty window, and a new tab, wear a lighter shade of the space.
//
// The page card is otherwise the ground — white, or near-black in a dark
// window — so closing the last tab left a black rectangle beside a coloured
// column. Zen fills that room with the space, only lighter. A new tab keeps
// its own page: the field in the middle, on that same lighter colour.

enum EmptyCanvas {
    /// The card's fill when nothing is loaded in it. A private window stays
    /// a shade of its black; every other space steps toward white from the
    /// colour the column is already wearing. A dark column needs a longer
    /// step, or the page is still black. A pastel only needs a short one.
    static func fill(_ space: Space, dark: Bool) -> Color {
        if PrivateWindow.stands(for: space) {
            return Color(red: 0.11, green: 0.11, blue: 0.12)
        }
        let c = Spaces.tints[Spaces.clamp(space.colour)].at(space.depth(on: dark))
        let y = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
        let lift = min(0.70, max(0.16, 0.58 - 0.46 * y))
        return Color(red: c.0 + (1 - c.0) * lift,
                     green: c.1 + (1 - c.1) * lift,
                     blue: c.2 + (1 - c.2) * lift)
    }
}

extension ContentView {
    /// Nothing loaded: the window was left empty, or the tab is a new one.
    var barePage: Bool { browser.active?.isBlank != false }

    /// What the card wears then. A real page keeps the ground. Beside the
    /// column, a bare card takes the space's lighter shade.
    var bareFill: Color {
        guard framed, barePage else { return Palette.ground }
        return EmptyCanvas.fill(browser.space, dark: groundScheme == .dark)
    }
}
