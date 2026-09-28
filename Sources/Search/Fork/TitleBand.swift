import SwiftUI

// Fork: with the column on the right, the traffic lights wait at the top
// left until the pointer is there. They were three dots on the page. Zen
// brings the space's colour down with them, a row of it under the dots, and
// the page starts below that row. The pointer leaving takes the colour back
// up with the lights.

enum TitleBand {
    /// The row the lights are centred in. The page's top inset grows to this
    /// while they are down, so the window's own colour — the space's — fills
    /// it.
    static var height: CGFloat { SideBar.topRow }
}
