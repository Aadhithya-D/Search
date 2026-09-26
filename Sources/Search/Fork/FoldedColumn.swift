import SwiftUI

// Fork: the folded column (Fold.swift) says where it is — a small handle
// fades in on its edge as the pointer comes near, and a click on it keeps
// the column out. Out over the page, the column is a card of its own, set
// in from the window's edges with the page's own corners.

extension Fold {
    /// The floating column's inset from the window, the same as the page's,
    /// and its corners, the same as the page's.
    static let inset: CGFloat = 8
    static let corner: CGFloat = 10
}

/// The handle on the column's edge, on whichever side the column is set to.
struct SideHandle: View {
    let right: Bool
    let near: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: right ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 22, height: 28)
                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(right ? .trailing : .leading, 6)
        .help("Show Sidebar")
        .opacity(near ? 1 : 0)
        .allowsHitTesting(near)
        .animation(Motion.quick, value: near)
    }
}
