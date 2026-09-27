import SwiftUI
import AppKit

// Fork: the column wears its space's colour (Fork/SpaceThemes.swift), with
// Arc's fine grain over it, and the page beside it sits in that colour as a
// card with rounded corners. The rows' greys become white let through, so
// they take the colour's hue instead of sitting on it as grey.

extension SideBar {
    /// Where every row's icon starts, and the section's first letter.
    static let inset: CGFloat = 10
}

/// White on the space's colour: the tab you are on, and the row under the pointer.
enum SideTone {
    static func chip(_ scheme: ColorScheme, strong: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(strong ? 0.16 : 0.08)
        }
        return Color.white.opacity(strong ? 0.94 : 0.34)
    }
}

/// The fine grain Arc lays over its colour, so a flat fill reads as a
/// surface. One small tile of noise, made once and repeated.
struct Grain: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: Grain.tile)
            .resizable(resizingMode: .tile)
            .opacity(scheme == .dark ? 0.05 : 0.07)
            .blendMode(scheme == .dark ? .plusLighter : .multiply)
            .allowsHitTesting(false)
    }

    private static let tile: NSImage = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(side * side) {
            // xorshift: the same grain every launch, and no cost to make.
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: rgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return NSImage() }
        // Two pixels to the point: a grain, not a gravel.
        return NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
    }()
}

extension ContentView {
    /// The column's layout: the page is inset in the space's colour, a thin
    /// strip on every side the column isn't already filling.
    var framed: Bool {
        browser.prefs.sidebar && browser.active?.immersed != true
    }

    var gutter: CGFloat { framed ? 8 : 0 }

    var pageCorner: CGFloat { framed ? 10 : 0 }

    /// The frame round the page wears the space's own tone, as the column does.
    var groundScheme: ColorScheme {
        browser.space.wearsDark(on: windowScheme == .dark) ? .dark : .light
    }

    /// The frame's top edge over the page. The same inset as the other sides
    /// of the card, including when the column is on the right. The traffic
    /// lights there still wait for the pointer (see Fold.swift); they do not
    /// take this inset away.
    var gutterTop: CGFloat {
        framed ? 8 : 0
    }

    /// The card's corners are all the same. A square top read as a missing edge.
    var squareTop: Bool { false }

    var pageShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: squareTop ? 0 : pageCorner,
            bottomLeadingRadius: pageCorner,
            bottomTrailingRadius: pageCorner,
            topTrailingRadius: squareTop ? 0 : pageCorner,
            style: .continuous
        )
    }

    /// The column is on the right. The page then gives up its trailing edge.
    var sideRight: Bool { browser.prefs.sideRight && browser.prefs.sidebar }
}
