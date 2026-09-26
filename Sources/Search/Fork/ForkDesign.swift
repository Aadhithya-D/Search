import SwiftUI
import AppKit

// Fork: the few colours and one modifier the fork's chrome is drawn with,
// kept out of Design.swift so upstream's palette merges untouched.

extension Palette {
    /// The greys again, as ink let through rather than mixed: on a space's
    /// colour they take on its hue instead of sitting on it as grey. On the
    /// plain ground they read the same as muted, faint, hover and wash.
    static let quiet = Color(nsColor: NS.quiet)
    static let hush = Color(nsColor: NS.hush)
    static let veil = Color(nsColor: NS.veil)
    static let veilStrong = Color(nsColor: NS.veilStrong)
}

extension Palette.NS {
    static let quiet = through(light: 0.52, dark: 0.60)
    static let hush = through(light: 0.32, dark: 0.36)
    static let veil = through(light: 0.045, dark: 0.07)
    static let veilStrong = through(light: 0.08, dark: 0.11)

    /// Black on a light window, white on a dark one, at an opacity.
    fileprivate static func through(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark)
                : NSColor(white: 0, alpha: light)
        }
    }
}

extension View {
    /// A pop-up's own ground under what it shows. The system's glass alone
    /// lets the page through so far that muted lines and icons were lost in
    /// it; this is the ground nearly solid, in the pop-up's own light or dark.
    /// It reaches past the content so the arrow is covered too — the pop-up's
    /// outline clips it.
    func popGround() -> some View {
        background {
            Palette.ground.opacity(0.96)
                .padding(-40)
                .allowsHitTesting(false)
        }
    }
}
